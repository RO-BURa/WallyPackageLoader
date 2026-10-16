-- Wally 와 같은 _Index 구조, thunk 모듈 생성
--   Packages/
--     Signal                      <- thunk: require(script.Parent._Index["sleitnick_signal@2.0.1"]["signal"])
--     _Index/
--       sleitnick_signal@2.0.1/
--         signal                  <- 실제 패키지
--         Promise                 <- 의존성 thunk

const TypeExports = require(script.Parent.Util.TypeExports)

const Linker = {}

const INDEX_NAME = "_Index"
-- thunk 가 가리키는 엔트리 폴더 (prune 에서 사용)
const LINK_ATTRIBUTE = "PackageLoaderLink"
-- 이 플러그인이 만든 엔트리 표시
const ENTRY_ATTRIBUTE = "PackageLoaderEntry"

Linker.INDEX_NAME = INDEX_NAME
Linker.LINK_ATTRIBUTE = LINK_ATTRIBUTE
Linker.ENTRY_ATTRIBUTE = ENTRY_ATTRIBUTE
-- ModuleScript 가 아닌 Instance 를 설치 위치에 바로 복사한 것 표시
Linker.COPY_ATTRIBUTE = "PackageLoaderCopy"

-- 플러그인이 설치 위치에 만든 것 (thunk 또는 복사본)
function Linker.isManaged(instance: Instance): boolean
	return instance:GetAttribute(LINK_ATTRIBUTE) ~= nil or instance:GetAttribute(Linker.COPY_ATTRIBUTE) ~= nil
end

function Linker.entryName(scope: string, name: string, version: string): string
	return `{scope}_{name}@{version}`
end

function Linker.getIndex(root: Instance): Instance
	local index = root:FindFirstChild(INDEX_NAME)
	if not index then
		index = Instance.new("Folder")
		index.Name = INDEX_NAME
		index.Parent = root
	end
	return index
end

const function indexExpression(name: string): string
	if string.match(name, "^[%a_][%w_]*$") then
		return "." .. name
	end
	return `[{string.format("%q", name)}]`
end

-- from 위치(아직 그 안에 없더라도)에서 target 을 가리키는 require 식
--   같은 서비스 안이면 script.Parent... 상대 경로, 다르면 game:GetService(...) 절대 경로
function Linker.requireExpression(from: Instance, target: Instance): string
	local ancestor: Instance? = from
	local up = 1
	while ancestor and ancestor ~= game and not (target == ancestor or target:IsDescendantOf(ancestor)) do
		ancestor = ancestor.Parent
		up += 1
	end

	const down = {}
	local stop: Instance
	local expression: string
	if ancestor == nil or ancestor == game then
		-- 서비스부터 절대 경로
		local current = target
		while current.Parent ~= game do
			table.insert(down, 1, current.Name)
			current = current.Parent :: Instance
		end
		expression = `game:GetService({string.format("%q", current.ClassName)})`
		stop = current
	else
		expression = "script" .. string.rep(".Parent", up)
		stop = ancestor
		local current = target
		while current ~= stop do
			table.insert(down, 1, current.Name)
			current = current.Parent :: Instance
		end
	end

	for _, name in down do
		expression ..= indexExpression(name)
	end
	return expression
end

-- parent 안에 alias 이름으로 thunk 를 만들어 entry 안의 패키지를 가리킴
function Linker.createThunk(parent: Instance, alias: string, entry: Instance, packageInstance: Instance): ModuleScript
	const existing = parent:FindFirstChild(alias)
	if existing then
		existing:Destroy()
	end

	const source = if packageInstance:IsA("ModuleScript") then packageInstance.Source else nil
	const thunk = Instance.new("ModuleScript")
	thunk.Name = alias
	;(thunk :: any).Source = TypeExports.thunk(Linker.requireExpression(parent, packageInstance), source)
	thunk:SetAttribute(LINK_ATTRIBUTE, entry:GetFullName())
	thunk.Parent = parent
	return thunk
end

-- 이 플러그인이 만든 엔트리만 정리 대상 (Rojo 로 동기화한 Wally _Index 는 건드리지 않음)
-- 엔트리 밖에 있는 thunk 에서 출발해 닿지 않는 엔트리를 지움. 지운 이름 목록 반환
function Linker.prune(): { string }
	const entriesByPath: { [string]: Instance } = {}
	const seeds: { Instance } = {}

	for _, service in game:GetChildren() do
		const ok, descendants = pcall(service.GetDescendants, service)
		if ok then
			for _, instance in descendants do
				if instance:GetAttribute(ENTRY_ATTRIBUTE) then
					entriesByPath[instance:GetFullName()] = instance
				elseif instance:GetAttribute(LINK_ATTRIBUTE) then
					const parent = instance.Parent
					if not (parent and parent:GetAttribute(ENTRY_ATTRIBUTE)) then
						table.insert(seeds, instance)
					end
				end
			end
		end
	end

	const reachable: { [Instance]: boolean } = {}
	const queue: { Instance } = {}
	const function follow(thunk: Instance)
		const link = thunk:GetAttribute(LINK_ATTRIBUTE)
		const entry = if type(link) == "string" then entriesByPath[link] else nil
		if entry and not reachable[entry] then
			reachable[entry] = true
			table.insert(queue, entry)
		end
	end

	for _, seed in seeds do
		follow(seed)
	end
	while #queue > 0 do
		for _, child in (table.remove(queue) :: Instance):GetChildren() do
			follow(child)
		end
	end

	const removed = {}
	for _, entry in entriesByPath do
		if not reachable[entry] then
			const index = entry.Parent
			table.insert(removed, entry.Name)
			entry:Destroy()
			if index and index.Name == INDEX_NAME and #index:GetChildren() == 0 then
				index:Destroy()
			end
		end
	end
	table.sort(removed)
	return removed
end

return Linker
