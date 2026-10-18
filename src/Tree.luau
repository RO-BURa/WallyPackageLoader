-- 의존성 트리 (tree 명령)
--   설치된 것: _Index 의 thunk 를 따라감 (인터넷 필요 없음)
--   설치 안 된 스펙 / wally.toml: 서버에서 버전을 찾아서 따라감

const Linker = require(script.Parent.Linker)

export type Node = {
	-- 별칭
	alias: string,
	-- "scope/name@1.0.0" 같은 설명
	label: string,
	-- (server), (설치 안 됨), (위와 같음) 같은 표시
	note: string?,
	-- 설명 (실패 이유 등)
	children: { Node },
}

-- 별칭 -> 스펙 ("scope/name@range") 을 Package 로 (Installer.resolve)
export type Resolver = (spec: string) -> any

const Tree = {}

const MAX_DEPTH = 12

const function sortedKeys(map: { [string]: any }): { string }
	const keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return string.lower(a) < string.lower(b)
	end)
	return keys
end

-- 플러그인이 만든 _Index 엔트리 (전체 경로 -> 엔트리)
const function entriesByPath(): { [string]: Instance }
	const result = {}
	for _, service in game:GetChildren() do
		const ok, descendants = pcall(service.GetDescendants, service)
		if ok then
			for _, instance in descendants do
				if instance:GetAttribute(Linker.ENTRY_ATTRIBUTE) then
					result[instance:GetFullName()] = instance
				end
			end
		end
	end
	return result
end

-- "ro-bura_signal@1.0.0" -> "ro-bura/signal@1.0.0", "custom_X" -> "직접 넣은 것"
const function entryLabel(entry: Instance): string
	const pesdeScope, pesdeRest = string.match(entry.Name, "^pesde%+([^_]+)_(.+@.+)$")
	if pesdeScope then
		return `pesde:{pesdeScope}/{pesdeRest}`
	end
	const scope, rest = string.match(entry.Name, "^([^_]+)_(.+@.+)$")
	if scope then
		return `{scope}/{rest}`
	end
	if string.match(entry.Name, "^custom_") then
		return "직접 넣은 것"
	end
	return entry.Name
end

-- 설치된 트리
--   thunk(LINK) 를 따라가서 엔트리 안의 thunk 들을 다시 따라감
function Tree.installed()
	const entries = entriesByPath()
	const seen: { [Instance]: boolean } = {}

	local fromThunk: (thunk: Instance, path: { [Instance]: boolean }, depth: number) -> Node
	const function fromEntry(alias: string, entry: Instance, path: { [Instance]: boolean }, depth: number): Node
		const node: Node = { alias = alias, label = entryLabel(entry), children = {} }
		if path[entry] then
			node.note = "(순환)"
			return node
		end
		if seen[entry] then
			node.note = "(위와 같음)"
			return node
		end
		seen[entry] = true
		if depth >= MAX_DEPTH then
			node.note = "(너무 깊음)"
			return node
		end
		path[entry] = true
		const thunks = {}
		for _, child in entry:GetChildren() do
			if child:GetAttribute(Linker.LINK_ATTRIBUTE) then
				table.insert(thunks, child)
			end
		end
		table.sort(thunks, function(a, b)
			return string.lower(a.Name) < string.lower(b.Name)
		end)
		for _, thunk in thunks do
			table.insert(node.children, fromThunk(thunk, path, depth + 1))
		end
		path[entry] = nil
		return node
	end

	fromThunk = function(thunk: Instance, path: { [Instance]: boolean }, depth: number): Node
		const link = thunk:GetAttribute(Linker.LINK_ATTRIBUTE)
		const entry = if type(link) == "string" then entries[link] else nil
		if not entry then
			return { alias = thunk.Name, label = "?", note = "(가리키는 패키지가 없음, install 필요)", children = {} }
		end
		return fromEntry(thunk.Name, entry, path, depth)
	end

	return {
		-- 설치 위치의 thunk 하나
		thunk = function(thunk: Instance): Node
			return fromThunk(thunk, {}, 0)
		end,
		-- _Index 엔트리 하나 (별칭은 엔트리 이름)
		entry = function(entry: Instance): Node
			return fromEntry(entry.Name, entry, {}, 0)
		end,
	}
end

-- 설치 안 된 스펙의 트리 (서버에서 찾음). 같은 스펙은 한 번만 찾음
function Tree.remote(resolve: Resolver)
	const cache: { [string]: any } = {}
	const seen: { [string]: boolean } = {}

	local fromSpec: (alias: string, spec: string, server: boolean, path: { [string]: boolean }, depth: number) -> Node
	const function children(node: Node, package: any, path: { [string]: boolean }, depth: number)
		for _, alias in sortedKeys(package.dependencies or {}) do
			table.insert(node.children, fromSpec(alias, package.dependencies[alias], false, path, depth + 1))
		end
		for _, alias in sortedKeys(package.serverDependencies or {}) do
			table.insert(node.children, fromSpec(alias, package.serverDependencies[alias], true, path, depth + 1))
		end
	end

	fromSpec = function(alias: string, spec: string, server: boolean, path: { [string]: boolean }, depth: number): Node
		const node: Node = { alias = alias, label = spec, children = {} }
		local package = cache[spec]
		if package == nil then
			const ok, result = pcall(resolve, spec)
			package = if ok then result else false
			cache[spec] = package
			if not ok then
				node.note = `(찾을 수 없음: {result})`
				return node
			end
		end
		if not package then
			node.note = "(찾을 수 없음)"
			return node
		end
		const id = (if package.source == "pesde" then "pesde:" else "") .. `{package.scope}/{package.name}@{package.version}`
		node.label = id
		if server or package.realm == "server" then
			node.note = "(server)"
		end
		if path[id] then
			node.note = "(순환)"
			return node
		end
		if seen[id] then
			node.note = (if node.note then node.note .. " " else "") .. "(위와 같음)"
			return node
		end
		seen[id] = true
		if depth >= MAX_DEPTH then
			node.note = "(너무 깊음)"
			return node
		end
		path[id] = true
		children(node, package, path, depth)
		path[id] = nil
		return node
	end

	return {
		spec = function(alias: string, spec: string, server: boolean?): Node
			return fromSpec(alias, spec, server == true, {}, 0)
		end,
		-- wally.toml 의 의존성 목록 (맨 위는 패키지 자신)
		manifest = function(alias: string, label: string, dependencies: { [string]: string }, serverDependencies: { [string]: string }): Node
			const node: Node = { alias = alias, label = label, children = {} }
			children(node, { dependencies = dependencies, serverDependencies = serverDependencies }, {}, 0)
			return node
		end,
	}
end

-- 트리를 줄 목록으로 (각 줄: 앞부분, 별칭, 설명, 표시)
export type Line = { prefix: string, alias: string, label: string, note: string? }

function Tree.lines(roots: { Node }): { Line }
	const result: { Line } = {}
	const function walk(node: Node, prefix: string, childPrefix: string)
		table.insert(result, { prefix = prefix, alias = node.alias, label = node.label, note = node.note })
		for i, child in node.children do
			const last = i == #node.children
			walk(child, childPrefix .. (if last then "└─ " else "├─ "), childPrefix .. (if last then "   " else "│  "))
		end
	end
	for _, root in roots do
		walk(root, "", "")
	end
	return result
end

return Tree
