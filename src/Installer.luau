-- 스펙 해석 -> 의존성 재귀 설치 -> thunk 연결 -> Config 저장

const Builder = require(script.Parent.Builder)
const Config = require(script.Parent.Config)
const Linker = require(script.Parent.Linker)
const Log = require(script.Parent.Log)
const Types = require(script.Parent.Sources.Types)
const Wally = require(script.Parent.Sources.Wally)
const GitHub = require(script.Parent.Sources.GitHub)
const File = require(script.Parent.Sources.File)

type Package = Types.Package

export type InstallOptions = {
	alias: string?,
	-- 설치할 폴더. 없으면 Config 의 shared 경로
	location: Instance?,
	-- Config 에 의존성으로 저장할지 (기본 true)
	save: boolean?,
	log: ((message: string) -> ())?,
}

const Installer = {}

-- "red-blox-util" -> "RedBloxUtil"
function Installer.defaultAlias(name: string): string
	const parts = {}
	for word in string.gmatch(name, "[%w]+") do
		table.insert(parts, string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2))
	end
	return if #parts > 0 then table.concat(parts) else name
end

-- 스펙 문자열 -> 패키지
--   scope/name@range, wally:scope/name@range, gh:owner/repo@range, gh:owner/repo#ref
function Installer.resolve(spec: string): Package
	const trimmed = string.match(spec, "^%s*(.-)%s*$") :: string

	const github = string.match(trimmed, "^gh:(.+)$") or string.match(trimmed, "^github:(.+)$")
	if github then
		const body, ref = string.match(github, "^([^#]+)#(.+)$")
		const target = body or github
		const path, range = string.match(target, "^([^@]+)@(.+)$")
		const owner, repo = string.match(path or target, "^([^/]+)/([^/]+)$")
		if not owner then
			error(`잘못된 GitHub 스펙: {spec} (예: gh:owner/repo@^1.0)`, 0)
		end
		return GitHub.resolve(owner, repo, range, ref)
	end

	const body = string.match(trimmed, "^wally:(.+)$") or trimmed
	const path, range = string.match(body, "^([^@]+)@(.+)$")
	const scope, name = string.match(path or body, "^([^/]+)/([^/]+)$")
	if not scope then
		error(`잘못된 스펙: {spec} (예: sleitnick/signal@^2)`, 0)
	end
	return Wally.resolve(scope, name, range)
end

type Context = {
	sharedRoot: Instance,
	serverRoot: Instance,
	log: (message: string) -> (),
	-- 이번 설치에서 새로 만든 엔트리 (실패하면 지움)
	created: { Instance },
	resolving: { [string]: Package },
}

local placePackage: (context: Context, package: Package, root: Instance) -> (Instance, Instance)

const function linkDependencies(
	context: Context,
	entry: Instance,
	root: Instance,
	dependencies: { [string]: string },
	forceServer: boolean
)
	for alias, spec in dependencies do
		const cached = context.resolving[spec]
		const dependency = cached or Installer.resolve(spec)
		context.resolving[spec] = dependency

		const dependencyRoot = if forceServer or dependency.realm == "server" then context.serverRoot else root
		const _, packageInstance = placePackage(context, dependency, dependencyRoot)
		Linker.createThunk(entry, alias, packageInstance.Parent :: Instance, packageInstance)
	end
end

-- root/_Index 에 패키지를 놓고 (엔트리 폴더, 패키지 Instance) 반환
placePackage = function(context: Context, package: Package, root: Instance): (Instance, Instance)
	const index = Linker.getIndex(root)
	const entryName = Linker.entryName(package.scope, package.name, package.version)

	const existing = index:FindFirstChild(entryName)
	if existing then
		const packageInstance = existing:FindFirstChild(package.name)
		if packageInstance then
			return existing, packageInstance
		end
		existing:Destroy()
	end

	context.log(`받는 중: {package.scope}/{package.name}@{package.version}`)
	const vfs = package.fetch()
	const packageInstance = Builder.buildPackage(vfs, package.name, package.entryPath)
	if not packageInstance then
		error(`{entryName}: 패키지 내용을 찾을 수 없음`, 0)
	end

	const entry = Instance.new("Folder")
	entry.Name = entryName
	entry:SetAttribute(Linker.ENTRY_ATTRIBUTE, true)
	packageInstance.Parent = entry
	entry.Parent = index
	table.insert(context.created, entry)

	linkDependencies(context, entry, root, package.dependencies, false)
	linkDependencies(context, entry, root, package.serverDependencies, true)

	context.log(`설치됨: {entryName}`)
	return entry, packageInstance
end

const function newContext(log: ((string) -> ())?): Context
	const data = Config.read()
	return {
		sharedRoot = Config.resolvePath(data.shared, true) :: Instance,
		serverRoot = Config.resolvePath(data.server, true) :: Instance,
		log = log or Log.write,
		created = {},
		resolving = {},
	}
end

const function rollback(context: Context)
	for i = #context.created, 1, -1 do
		context.created[i]:Destroy()
	end
end

function Installer.sharedRoot(): Instance
	return Config.resolvePath(Config.getSharedPath(), true) :: Instance
end

function Installer.serverRoot(): Instance
	return Config.resolvePath(Config.getServerPath(), true) :: Instance
end

-- 패키지 하나를 의존성까지 설치. 별칭 반환
function Installer.installPackage(package: Package, options: InstallOptions, spec: string?): string
	const context = newContext(options.log)
	const base = options.location or context.sharedRoot
	const alias = options.alias or Installer.defaultAlias(package.name)

	const ok, err = pcall(function()
		const entry, packageInstance = placePackage(context, package, base)
		Linker.createThunk(base, alias, entry, packageInstance)
	end)
	if not ok then
		rollback(context)
		error(err, 0)
	end

	if spec and options.save ~= false then
		Config.addDependency(alias, spec, Config.pathOf(base))
	end
	context.log(`완료: {alias} -> {package.scope}/{package.name}@{package.version} ({Config.pathOf(base)})`)
	return alias
end

function Installer.install(spec: string, options: InstallOptions): string
	return Installer.installPackage(Installer.resolve(spec), options, spec)
end

-- Config 에 적힌 의존성 전체 설치 (wally install 과 비슷)
function Installer.installAll(log: ((string) -> ())?)
	const logger = log or Log.write
	const entries = Config.entries()
	if #entries == 0 then
		logger("Config 에 적힌 패키지가 없음")
		return
	end
	for _, entry in entries do
		const ok, err = pcall(function()
			Installer.install(entry.spec, {
				alias = entry.alias,
				location = Config.resolvePath(entry.location, true),
				save = false,
				log = logger,
			})
		end)
		if not ok then
			logger(`실패: {entry.alias} ({entry.spec}) - {err}`)
		end
	end
end

-- 파일에서 가져오기 (여러 개 선택 가능)
function Installer.importFiles(options: InstallOptions)
	const context = newContext(options.log)
	const base = options.location or context.sharedRoot
	const files = File.prompt()
	if #files == 0 then
		context.log("선택한 파일이 없음")
		return
	end

	for _, file in files do
		const ok, err = pcall(function()
			const imported = File.read(file)
			if imported.kind == "script" then
				const existing = base:FindFirstChild(imported.name)
				if existing then
					existing:Destroy()
				end
				const module = Instance.new("ModuleScript")
				module.Name = imported.name
				;(module :: any).Source = imported.source
				module.Parent = base
				context.log(`가져옴: {imported.name} ({Config.pathOf(base)})`)
			elseif imported.kind == "package" then
				Installer.installPackage(imported.package, {
					alias = options.alias,
					location = base,
					log = context.log,
				}, nil)
			else
				const instance = Builder.buildPackage(imported.vfs, imported.name)
				if not instance then
					error("가져올 내용이 없음", 0)
				end
				const existing = base:FindFirstChild(imported.name)
				if existing then
					existing:Destroy()
				end
				instance.Parent = base
				context.log(`가져옴: {imported.name} ({Config.pathOf(base)})`)
			end
		end)
		if not ok then
			context.log(`실패: {file.Name} - {err}`)
		end
	end
end

-- thunk 를 지우고 Config 에서도 뺀 뒤 쓰이지 않는 엔트리 정리
-- location(경로) 이 없으면 Config 에서 별칭으로 찾음
function Installer.remove(alias: string, location: string?, log: ((string) -> ())?)
	const logger = log or Log.write
	local resolved = location
	if not resolved then
		const matches = {}
		for _, entry in Config.entries() do
			if entry.alias == alias then
				table.insert(matches, entry.location)
			end
		end
		if #matches == 0 then
			error(`Config 에 '{alias}' 가 없음`, 0)
		elseif #matches > 1 then
			error(`'{alias}' 가 여러 곳에 있음 ({table.concat(matches, ", ")}). Explorer 에서 지울 것을 선택하고 Remove 를 눌러주세요`, 0)
		end
		resolved = matches[1]
	end
	const path = resolved :: string

	const folder = Config.resolvePath(path, false)
	const thunk = folder and folder:FindFirstChild(alias)
	if thunk and thunk:GetAttribute(Linker.LINK_ATTRIBUTE) then
		thunk:Destroy()
	end
	Config.removeDependency(alias, path)
	Installer.prune(logger)
	logger(`삭제됨: {alias} ({path})`)
end

-- 어디서도 쓰이지 않는 _Index 엔트리 삭제
function Installer.prune(log: ((string) -> ())?)
	const logger = log or Log.write
	for _, name in Linker.prune() do
		logger(`정리됨: {name}`)
	end
end

return Installer
