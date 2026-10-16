-- 스펙 해석 -> 의존성 재귀 설치 -> thunk 연결 -> Config 저장

const Builder = require(script.Parent.Builder)
const Config = require(script.Parent.Config)
const Linker = require(script.Parent.Linker)
const Types = require(script.Parent.Sources.Types)
const Wally = require(script.Parent.Sources.Wally)
const GitHub = require(script.Parent.Sources.GitHub)
const File = require(script.Parent.Sources.File)

type Package = Types.Package

export type InstallOptions = {
	alias: string?,
	-- 설치할 폴더. 없으면 Config 의 Shared/Server 경로
	location: Instance?,
	server: boolean?,
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
	return {
		sharedRoot = Config.resolvePath(Config.getSharedPath(), true) :: Instance,
		serverRoot = Config.resolvePath(Config.getServerPath(), true) :: Instance,
		log = log or print,
		created = {},
		resolving = {},
	}
end

const function rollback(context: Context)
	for i = #context.created, 1, -1 do
		context.created[i]:Destroy()
	end
end

const function getBase(context: Context, options: InstallOptions): Instance
	if options.location then
		return options.location
	end
	return if options.server then context.serverRoot else context.sharedRoot
end

-- 패키지 하나를 의존성까지 설치. 별칭 반환
function Installer.installPackage(package: Package, options: InstallOptions, spec: string?): string
	const context = newContext(options.log)
	const base = getBase(context, options)
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
		Config.setDependency(alias, {
			spec = spec,
			realm = if options.server then "server" else "shared",
			location = if options.location then Config.pathOf(options.location) else nil,
		})
	end
	context.log(`완료: {alias} -> {package.scope}/{package.name}@{package.version}`)
	return alias
end

function Installer.install(spec: string, options: InstallOptions): string
	return Installer.installPackage(Installer.resolve(spec), options, spec)
end

-- Config 에 저장된 의존성 전체 설치 (wally install 과 비슷)
function Installer.installAll(log: ((string) -> ())?)
	const logger = log or print
	for alias, dependency in Config.getDependencies() do
		const location = if dependency.location then Config.resolvePath(dependency.location, true) else nil
		const ok, err = pcall(Installer.install, dependency.spec, {
			alias = alias,
			location = location,
			server = dependency.realm == "server",
			save = false,
			log = logger,
		})
		if not ok then
			logger(`실패: {alias} ({dependency.spec}) - {err}`)
		end
	end
end

-- 파일에서 가져오기
function Installer.importFiles(options: InstallOptions)
	const context = newContext(options.log)
	const base = getBase(context, options)

	for _, file in File.prompt() do
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
				context.log(`가져옴: {imported.name}`)
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
				context.log(`가져옴: {imported.name}`)
			end
		end)
		if not ok then
			context.log(`실패: {file.Name} - {err}`)
		end
	end
end

-- 루트에 있는 thunk 를 지우고 Config 에서도 뺀 뒤 쓰이지 않는 엔트리 정리
function Installer.remove(alias: string, log: ((string) -> ())?)
	const logger = log or print
	const dependency = Config.getDependencies()[alias]
	if dependency then
		const context = newContext(logger)
		const base = if dependency.location
			then Config.resolvePath(dependency.location, false)
			else (if dependency.realm == "server" then context.serverRoot else context.sharedRoot)
		const thunk = base and base:FindFirstChild(alias)
		if thunk and thunk:GetAttribute(Linker.LINK_ATTRIBUTE) then
			thunk:Destroy()
		end
		Config.setDependency(alias, nil)
	end
	Installer.prune(logger)
	logger(`삭제됨: {alias}`)
end

-- 어디서도 쓰이지 않는 _Index 엔트리 삭제
function Installer.prune(log: ((string) -> ())?)
	const logger = log or print
	for _, name in Linker.prune() do
		logger(`정리됨: {name}`)
	end
end

return Installer
