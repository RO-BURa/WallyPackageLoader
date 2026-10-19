-- 스펙 해석 -> 의존성 재귀 설치 -> thunk 연결 -> Config 저장

const HttpService = game:GetService("HttpService")

const L = require(script.Parent.Locale).L
const Builder = require(script.Parent.Builder)
const Config = require(script.Parent.Config)
const Linker = require(script.Parent.Linker)
const Log = require(script.Parent.Log)
const Semver = require(script.Parent.Util.Semver)
const Types = require(script.Parent.Sources.Types)
const Wally = require(script.Parent.Sources.Wally)
const GitHub = require(script.Parent.Sources.GitHub)
const Pesde = require(script.Parent.Sources.Pesde)
const File = require(script.Parent.Sources.File)

type Package = Types.Package

export type InstallOptions = {
	alias: string?,
	-- 설치할 폴더. 없으면 Config 의 shared 경로
	location: Instance?,
	log: ((message: string) -> ())?,
}

const Installer = {}

-- 별칭을 안 적으면 원래 패키지 이름 그대로 (cayasde/vide-opinionated -> vide-opinionated)
function Installer.defaultAlias(package: Package): string
	return package.displayName or package.name
end

-- 스펙 문자열 -> 패키지
--   scope/name@range, wally:scope/name@range, pesde:scope/name@range, gh:owner/repo@range, gh:owner/repo#ref
function Installer.resolve(spec: string): Package
	const trimmed = string.match(spec, "^%s*(.-)%s*$") :: string

	const github = string.match(trimmed, "^gh:(.+)$") or string.match(trimmed, "^github:(.+)$")
	if github then
		const body, ref = string.match(github, "^([^#]+)#(.+)$")
		const target = body or github
		const path, range = string.match(target, "^([^@]+)@(.+)$")
		const owner, repo = string.match(path or target, "^([%w_%-%.]+)/([%w_%-%.]+)$")
		if not owner then
			error(L(`잘못된 GitHub 스펙: {spec} (예: gh:owner/repo@^1.0)`, `Invalid GitHub spec: {spec} (e.g. gh:owner/repo@^1.0)`), 0)
		end
		return GitHub.resolve(owner, repo, range, ref)
	end

	const pesde = string.match(trimmed, "^pesde:(.+)$")
	if pesde then
		const path, range = string.match(pesde, "^([^@]+)@(.+)$")
		const scope, name = string.match(path or pesde, "^([%w_%-]+)/([%w_%-]+)$")
		if not scope then
			error(L(`잘못된 pesde 패키지: '{spec}' (예: pesde:scope/name@^1.0)`, `Invalid pesde package: '{spec}' (e.g. pesde:scope/name@^1.0)`), 0)
		end
		return Pesde.resolve(scope, name, range)
	end

	const body = string.match(trimmed, "^wally:(.+)$") or trimmed
	const path, range = string.match(body, "^([^@]+)@(.+)$")
	-- Wally 이름은 영문/숫자/-/_ 만 (공백 등이 있으면 요청 전에 막음)
	const scope, name = string.match(path or body, "^([%w_%-]+)/([%w_%-]+)$")
	if not scope then
		error(L(`잘못된 패키지: '{spec}' (예: sleitnick/signal@^2)`, `Invalid package: '{spec}' (e.g. sleitnick/signal@^2)`), 0)
	end
	return Wally.resolve(scope, name, range)
end

type Context = {
	-- 실제로 쓸 때 만듦 (설치할 게 없으면 폴더를 안 만들게)
	sharedRoot: () -> Instance,
	serverRoot: () -> Instance,
	log: (message: string) -> (),
	-- 이번 설치에서 새로 만든 엔트리 (실패하면 지움)
	created: { Instance },
	resolving: { [string]: Package },
}

local placePackage: (context: Context, package: Package, root: Instance) -> (Instance, Instance)
local storeAndInstall: (stored: Instance, alias: string, base: Instance, log: (string) -> ()) -> ()

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

		const dependencyRoot = if forceServer or dependency.realm == "server" then context.serverRoot() else root
		const _, packageInstance = placePackage(context, dependency, dependencyRoot)
		Linker.createThunk(entry, alias, packageInstance.Parent :: Instance, packageInstance)
	end
end

-- root/_Index 에 패키지를 놓고 (엔트리 폴더, 패키지 Instance) 반환
placePackage = function(context: Context, package: Package, root: Instance): (Instance, Instance)
	const index = Linker.getIndex(root)
	-- pesde 는 같은 이름의 Wally 패키지와 겹치지 않게 앞에 pesde+
	const entryName = (if package.source == "pesde" then "pesde+" else "")
		.. Linker.entryName(package.scope, package.name, package.version)

	const existing = index:FindFirstChild(entryName)
	if existing then
		const packageInstance = existing:FindFirstChild(package.name)
		if packageInstance then
			return existing, packageInstance
		end
		existing:Destroy()
	end

	context.log(L(`받는 중: {if package.source == "pesde" then "pesde:" else ""}{package.scope}/{package.name}@{package.version}`, `Fetching: {if package.source == "pesde" then "pesde:" else ""}{package.scope}/{package.name}@{package.version}`))
	const vfs = package.fetch()
	const packageInstance = Builder.buildPackage(vfs, package.name, package.entryPath)
	if not packageInstance then
		error(L(`{entryName}: 패키지 내용을 찾을 수 없음`, `{entryName}: package contents not found`), 0)
	end

	const entry = Instance.new("Folder")
	entry.Name = entryName
	entry:SetAttribute(Linker.ENTRY_ATTRIBUTE, true)
	packageInstance.Parent = entry
	entry.Parent = index
	table.insert(context.created, entry)

	linkDependencies(context, entry, root, package.dependencies, false)
	linkDependencies(context, entry, root, package.serverDependencies, true)

	context.log(L(`설치됨: {entryName}`, `Installed: {entryName}`))
	return entry, packageInstance
end

const function newContext(log: ((string) -> ())?): Context
	const data = Config.read()
	return {
		sharedRoot = function()
			return Config.resolvePath(data.shared, true) :: Instance
		end,
		serverRoot = function()
			return Config.resolvePath(data.server, true) :: Instance
		end,
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
function Installer.installPackage(package: Package, options: InstallOptions): string
	const context = newContext(options.log)
	const base = options.location or context.sharedRoot()
	const alias = options.alias or Installer.defaultAlias(package)

	const ok, err = pcall(function()
		const entry, packageInstance = placePackage(context, package, base)
		Linker.createThunk(base, alias, entry, packageInstance)
	end)
	if not ok then
		rollback(context)
		error(err, 0)
	end

	context.log(L(`완료: {alias} -> {package.scope}/{package.name}@{package.version} ({Config.pathOf(base)})`, `Done: {alias} -> {package.scope}/{package.name}@{package.version} ({Config.pathOf(base)})`))
	return alias
end

function Installer.install(spec: string, options: InstallOptions): string
	return Installer.installPackage(Installer.resolve(spec), options)
end

-- Import 한 패키지의 의존성 (wally.toml 에서 읽은 것) 을 보관하는 Attribute
const DEPENDENCIES_ATTRIBUTE = "PackageLoaderDependencies"

const function storedDependencies(source: Instance): ({ [string]: string }, { [string]: string })
	const raw = source:GetAttribute(DEPENDENCIES_ATTRIBUTE)
	if type(raw) ~= "string" then
		return {}, {}
	end
	const ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(decoded) ~= "table" then
		return {}, {}
	end
	return decoded.dependencies or {}, decoded.serverDependencies or {}
end

-- Config 에 Instance 로 적힌 패키지 설치 (원본은 그대로 두고 복사)
--   ModuleScript: _Index/custom_별칭 에 복사 + thunk (의존성도 설치)
--   그 외 (Folder 등): 설치 위치에 바로 복사
function Installer.installSource(alias: string, source: Instance, options: InstallOptions)
	const context = newContext(options.log)
	const base = options.location or context.sharedRoot()

	const ok, err = pcall(function()
		if source:IsA("ModuleScript") then
			const index = Linker.getIndex(base)
			const entryName = `custom_{alias}`
			const existing = index:FindFirstChild(entryName)
			if existing then
				existing:Destroy()
			end
			const entry = Instance.new("Folder")
			entry.Name = entryName
			entry:SetAttribute(Linker.ENTRY_ATTRIBUTE, true)
			entry.Parent = index
			table.insert(context.created, entry)

			const copy = source:Clone()
			copy:SetAttribute(DEPENDENCIES_ATTRIBUTE, nil)
			copy.Parent = entry

			const dependencies, serverDependencies = storedDependencies(source)
			linkDependencies(context, entry, base, dependencies, false)
			linkDependencies(context, entry, base, serverDependencies, true)
			Linker.createThunk(base, alias, entry, copy)
		else
			const existing = base:FindFirstChild(alias)
			if existing then
				existing:Destroy()
			end
			const copy = source:Clone()
			copy.Name = alias
			copy:SetAttribute(DEPENDENCIES_ATTRIBUTE, nil)
			copy:SetAttribute(Linker.COPY_ATTRIBUTE, true)
			copy.Parent = base
		end
	end)
	if not ok then
		rollback(context)
		error(err, 0)
	end
	context.log(L(`완료: {alias} -> {source.Name} ({Config.pathOf(base)})`, `Done: {alias} -> {source.Name} ({Config.pathOf(base)})`))
end

-- 버전을 안 적었으면 찾은 버전으로 고정 (wally add 처럼)
--   cayasde/vide-opinionated -> cayasde/vide-opinionated@0.4.3
const function pinVersion(spec: string, package: Package): string
	const trimmed = string.match(spec, "^%s*(.-)%s*$") :: string
	if string.find(trimmed, "[@#]") then
		return trimmed
	end
	if Semver.parse(package.version) then
		return `{trimmed}@{package.version}`
	end
	return trimmed
end

-- Config 에만 추가 (설치는 install). 패키지가 있는지 확인하고 버전을 고정함
-- 반환: 별칭, Config 에 적은 스펙
function Installer.add(spec: string, alias: string?, path: string, log: ((string) -> ())?): (string, string)
	const logger = log or Log.write
	logger(L(`확인 중: {spec}`, `Checking: {spec}`))
	const package = Installer.resolve(spec)
	const finalAlias = alias or Installer.defaultAlias(package)
	const pinned = pinVersion(spec, package)

	const previous = Config.addDependency(finalAlias, pinned, path)
	if previous and previous ~= pinned then
		logger(L(`추가됨: {finalAlias} = {pinned} (이전: {previous}) ({path})`, `Added: {finalAlias} = {pinned} (was: {previous}) ({path})`))
	else
		logger(L(`추가됨: {finalAlias} = {pinned} ({path})`, `Added: {finalAlias} = {pinned} ({path})`))
	end
	logger(L("install 로 설치", "Run install to install it"))
	return finalAlias, pinned
end

-- Config 대로 맞춤 (wally install 과 비슷)
--   1. 설치 위치에서 Config 에 없는 것 (플러그인이 만든 thunk / 복사본만) 삭제
--   2. Config 에 적힌 것 전부 설치
--   3. 안 쓰는 _Index 정리
function Installer.installAll(log: ((string) -> ())?)
	const logger = log or Log.write
	const data = Config.read()
	const entries = Config.entries()

	const expected: { [string]: { [string]: boolean } } = {
		[data.shared] = {},
		[data.server] = {},
	}
	for _, entry in entries do
		expected[entry.location] = expected[entry.location] or {}
		expected[entry.location][entry.alias] = true
	end
	for location, aliases in expected do
		const folder = Config.resolvePath(location, false)
		if folder then
			for _, child in folder:GetChildren() do
				const name = child.Name
				if Linker.isManaged(child) and not aliases[name] then
					child:Destroy()
					logger(L(`삭제됨: {name} ({location})`, `Removed: {name} ({location})`))
				end
			end
		end
	end

	if #entries == 0 then
		logger(L("Config 에 적힌 패키지가 없음", "No packages in the Config"))
	end
	for _, entry in entries do
		const ok, err = pcall(function()
			const options = {
				alias = entry.alias,
				location = Config.resolvePath(entry.location, true),
				log = logger,
			}
			if entry.source then
				Installer.installSource(entry.alias, entry.source, options)
			else
				Installer.install(entry.spec :: string, options)
			end
		end)
		if not ok then
			logger(L(`실패: {entry.alias} - {err}`, `Failed: {entry.alias} - {err}`))
		end
	end

	Installer.prune(logger)
end

-- Config.Imported 에 보관하고 "별칭 = script.Imported.별칭" 으로 Config 에 적은 뒤 설치
storeAndInstall = function(stored: Instance, alias: string, base: Instance, log: (string) -> ())
	const path = Config.pathOf(base)
	const storage = Config.storage()
	stored.Name = alias
	const existing = storage:FindFirstChild(alias)
	if existing then
		existing:Destroy()
	end
	stored.Parent = storage

	Config.addDependency(alias, stored, path)
	log(L(`가져옴: {alias} = {Config.childExpression(stored)} ({path})`, `Imported: {alias} = {Config.childExpression(stored)} ({path})`))
	Installer.installSource(alias, stored, { location = base, log = log })
end

-- Explorer 에서 선택한 것을 복제해서 가져오기 (Imported 폴더에 넣고 Config 에 추가, 설치)
function Installer.importInstance(source: Instance, options: InstallOptions)
	const context = newContext(options.log)
	if Linker.isManaged(source) then
		error(L(`{source.Name} 은 플러그인이 만든 thunk / 복사본이라 가져올 수 없음 (원본을 선택해주세요)`, `{source.Name} is a thunk / copy made by the plugin and cannot be imported (select the original)`), 0)
	end
	if source:IsDescendantOf(Config.storage()) then
		error(L(`{source.Name} 은 이미 가져온 것`, `{source.Name} is already imported`), 0)
	end
	if source:IsDescendantOf(Config.getModule()) then
		error(L("PackageLoaderConfig 안의 것은 가져올 수 없음", "Things inside PackageLoaderConfig cannot be imported"), 0)
	end
	const ok, copy = pcall(source.Clone, source)
	if not ok or not copy then
		error(L(`{source.Name} 을 복제할 수 없음 (Archivable 이 꺼져 있는지 확인)`, `Could not clone {source.Name} (check that Archivable is on)`), 0)
	end
	const base = options.location or context.sharedRoot()
	storeAndInstall(copy, options.alias or source.Name, base, context.log)
end

-- 파일에서 가져오기 (여러 개 선택 가능)
-- 가져온 것은 Config 모듈 아래에 보관하고 "이름 = script.이름" 으로 Config 에 적은 뒤 설치
function Installer.importFiles(options: InstallOptions)
	const context = newContext(options.log)
	const base = options.location or context.sharedRoot()
	const path = Config.pathOf(base)
	const files = File.prompt()
	if #files == 0 then
		context.log(L("선택한 파일이 없음", "No file selected"))
		return
	end
	for _, file in files do
		const ok, err = pcall(function()
			const imported = File.read(file)
			local stored: Instance
			local defaultAlias: string
			if imported.kind == "script" then
				const module = Instance.new("ModuleScript")
				module.Name = imported.name
				;(module :: any).Source = imported.source
				stored = module
				defaultAlias = imported.name
			elseif imported.kind == "package" then
				const package = imported.package
				const built = Builder.buildPackage(package.fetch(), package.name, package.entryPath)
				if not built then
					error(L("가져올 내용이 없음", "Nothing to import"), 0)
				end
				built:SetAttribute(DEPENDENCIES_ATTRIBUTE, HttpService:JSONEncode({
					dependencies = package.dependencies,
					serverDependencies = package.serverDependencies,
				}))
				stored = built
				defaultAlias = Installer.defaultAlias(package)
			else
				const built = Builder.buildPackage(imported.vfs, imported.name)
				if not built then
					error(L("가져올 내용이 없음", "Nothing to import"), 0)
				end
				stored = built
				defaultAlias = imported.name
			end

			storeAndInstall(stored, options.alias or defaultAlias, base, context.log)
		end)
		if not ok then
			context.log(L(`실패: {file.Name} - {err}`, `Failed: {file.Name} - {err}`))
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
			error(L(`Config 에 '{alias}' 가 없음`, `'{alias}' is not in the Config`), 0)
		elseif #matches > 1 then
			error(L(`'{alias}' 가 여러 곳에 있음 ({table.concat(matches, ", ")}). Explorer 에서 지울 것을 선택하고 Remove 를 눌러주세요`, `'{alias}' is in more than one place ({table.concat(matches, ", ")}). Select the one to remove in the Explorer and press Remove`), 0)
		end
		resolved = matches[1]
	end
	const path = resolved :: string

	-- Import 해서 Config 아래에 보관한 원본이면 같이 지움
	local stored: Instance? = nil
	for _, entry in Config.entries() do
		if entry.alias == alias and entry.location == path and entry.source then
			stored = entry.source
		end
	end

	const folder = Config.resolvePath(path, false)
	const thunk = folder and folder:FindFirstChild(alias)
	if thunk and Linker.isManaged(thunk) then
		thunk:Destroy()
	end
	Config.removeDependency(alias, path)
	-- Imported 폴더 또는 예전처럼 Config 바로 아래에 둔 것
	if stored and stored:IsDescendantOf(Config.getModule()) then
		stored:Destroy()
	end
	Installer.prune(logger)
	logger(L(`삭제됨: {alias} ({path})`, `Removed: {alias} ({path})`))
end

-- 어디서도 쓰이지 않는 _Index 엔트리 삭제
function Installer.prune(log: ((string) -> ())?)
	const logger = log or Log.write
	for _, name in Linker.prune() do
		logger(L(`정리됨: {name}`, `Pruned: {name}`))
	end
end

return Installer
