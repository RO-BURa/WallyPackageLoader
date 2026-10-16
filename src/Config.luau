-- 플레이스에 저장되는 설정 (ServerStorage.PackageLoaderConfig ModuleScript)
-- 사람이 직접 고칠 수 있도록 wally.toml 과 비슷한 Luau 테이블로 저장
-- Team Create 로 함께 작업하는 사람도 같은 설정을 봄

const ServerStorage = game:GetService("ServerStorage")

const ConfigEditor = require(script.Parent.Util.ConfigEditor)
const LicenseText = require(script.Parent.LicenseText)

export type Data = {
	shared: string,
	server: string,
	dependencies: { [string]: string },
	serverDependencies: { [string]: string },
	-- 경로 -> { 별칭 -> 스펙 }
	custom: { [string]: { [string]: string } },
}

export type Entry = {
	alias: string,
	spec: string,
	location: string,
}

const Config = {}

const CONFIG_NAME = "PackageLoaderConfig"
const DEFAULT_SHARED = "ReplicatedStorage/Packages"
const DEFAULT_SERVER = "ServerScriptService/ServerPackages"

-- 처음 만들 때만 붙는 설명
const DOCS = [==[

--[[
	PackageLoaderConfig

	Keys with "-" must be written as ["vide-opinionated"] = "cayasde/vide-opinionated@0.4.3"

	shared             Folder for shared packages        e.g. "ReplicatedStorage/Packages"
	server             Folder for server packages        e.g. "ServerScriptService/ServerPackages"
	dependencies       Alias = spec, installed to `shared`
	serverDependencies Alias = spec, installed to `server`
	custom             ["Service/Folder"] = { Alias = spec }, installed to that folder

	Spec formats
		"sleitnick/signal@^2"       Wally package (^, ~, =, >=, <, *, "1.2.3" = ^1.2.3)
		"wally:sleitnick/signal@2"  Same as above
		"gh:owner/repo@^1.0"        GitHub, highest semver tag (v1.2.3 / 1.2.3)
		"gh:owner/repo#main"        GitHub branch, tag or commit
		"gh:owner/repo"             GitHub, latest semver tag or default branch

	Add only writes here; press "Install All" (or run `install`) to install.
	Add / Remove only edit the lines they need, so your comments are kept.
	If the file can no longer be understood (e.g. the table is built with code),
	Add / Remove fail and nothing is changed.
]]
]==]

const function defaultData(): Data
	return {
		shared = DEFAULT_SHARED,
		server = DEFAULT_SERVER,
		dependencies = {},
		serverDependencies = {},
		custom = {},
	}
end

const function isIdentifier(name: string): boolean
	return string.match(name, "^[%a_][%w_]*$") ~= nil
end

const function keyText(key: string): string
	return if isIdentifier(key) then key else `[{string.format("%q", key)}]`
end

const function sortedKeys(map: { [string]: any }): { string }
	const keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

const function writeMap(lines: { string }, map: { [string]: string }, indent: string)
	for _, key in sortedKeys(map) do
		table.insert(lines, `{indent}{keyText(key)} = {string.format("%q", map[key])},`)
	end
end

const function writeSection(lines: { string }, name: string, map: { [string]: string })
	if next(map) == nil then
		table.insert(lines, `\t{name} = \{},`)
		return
	end
	table.insert(lines, `\t{name} = \{`)
	writeMap(lines, map, "\t\t")
	table.insert(lines, "\t},")
end

const function serialize(data: Data, withDocs: boolean): string
	const lines = { "return {" }
	table.insert(lines, `\tshared = {string.format("%q", data.shared)},`)
	table.insert(lines, `\tserver = {string.format("%q", data.server)},`)
	table.insert(lines, "")
	writeSection(lines, "dependencies", data.dependencies)
	writeSection(lines, "serverDependencies", data.serverDependencies)

	const paths = {}
	for _, path in sortedKeys(data.custom) do
		if next(data.custom[path]) ~= nil then
			table.insert(paths, path)
		end
	end
	if #paths == 0 then
		table.insert(lines, "\tcustom = {},")
	else
		table.insert(lines, "\tcustom = {")
		for _, path in paths do
			table.insert(lines, `\t\t[{string.format("%q", path)}] = \{`)
			writeMap(lines, data.custom[path], "\t\t\t")
			table.insert(lines, "\t\t},")
		end
		table.insert(lines, "\t},")
	end
	table.insert(lines, "}")
	return table.concat(lines, "\n") .. "\n" .. (if withDocs then DOCS else "")
end

-- 이전 버전(Configuration + attribute)에서 옮겨옴
const function migrate(old: Instance): Data
	const HttpService = game:GetService("HttpService")
	const data = defaultData()
	data.shared = old:GetAttribute("SharedPackages") or DEFAULT_SHARED
	data.server = old:GetAttribute("ServerPackages") or DEFAULT_SERVER
	const ok, dependencies = pcall(HttpService.JSONDecode, HttpService, old:GetAttribute("Dependencies") or "{}")
	if ok and type(dependencies) == "table" then
		for alias, dependency in dependencies do
			if dependency.location then
				data.custom[dependency.location] = data.custom[dependency.location] or {}
				data.custom[dependency.location][alias] = dependency.spec
			elseif dependency.realm == "server" then
				data.serverDependencies[alias] = dependency.spec
			else
				data.dependencies[alias] = dependency.spec
			end
		end
	end
	return data
end

function Config.getModule(): ModuleScript
	const existing = ServerStorage:FindFirstChild(CONFIG_NAME)
	if existing and existing:IsA("ModuleScript") then
		return existing
	end

	const data = if existing then migrate(existing) else defaultData()
	if existing then
		existing:Destroy()
	end

	const module = Instance.new("ModuleScript")
	module.Name = CONFIG_NAME
	;(module :: any).Source = serialize(data, true)

	-- 처음 만들 때만 라이선스 고지를 같이 넣음 (지워도 다시 만들지 않음)
	const licenseModule = Instance.new("ModuleScript")
	licenseModule.Name = "LICENSE"
	;(licenseModule :: any).Source = `-- WallyPackageLoader license and third-party notices. You can delete this.\nreturn [==[\n{LicenseText.text()}\n]==]\n`
	licenseModule.Parent = module

	module.Parent = ServerStorage
	return module
end

-- 매번 복제해서 require (require 캐시 때문에 수정한 내용이 안 보이는 것 방지)
function Config.read(): Data
	const clone = Config.getModule():Clone()
	const ok, result = pcall(require, clone)
	clone:Destroy()
	if not ok then
		error(`{CONFIG_NAME} 를 읽을 수 없음: {result}`, 0)
	end
	if type(result) ~= "table" then
		error(`{CONFIG_NAME} 는 테이블을 return 해야 함`, 0)
	end

	const data = defaultData()
	if type(result.shared) == "string" then
		data.shared = result.shared
	end
	if type(result.server) == "string" then
		data.server = result.server
	end
	for _, field in { "dependencies", "serverDependencies" } do
		if type(result[field]) == "table" then
			for alias, spec in result[field] do
				if type(alias) == "string" and type(spec) == "string" then
					(data :: any)[field][alias] = spec
				end
			end
		end
	end
	if type(result.custom) == "table" then
		for path, map in result.custom do
			if type(path) == "string" and type(map) == "table" then
				data.custom[path] = {}
				for alias, spec in map do
					if type(alias) == "string" and type(spec) == "string" then
						data.custom[path][alias] = spec
					end
				end
			end
		end
	end
	return data
end

function Config.write(data: Data)
	const module: any = Config.getModule()
	module.Source = serialize(data, false)
end

-- 소스에서 바뀌는 부분만 고침 (주석, 순서 유지)
-- 구조를 알아볼 수 없거나 고친 결과를 읽을 수 없으면 아무것도 바꾸지 않고 오류
const function edit(apply: (source: string) -> string)
	const module: any = Config.getModule()
	const original = module.Source
	const ok, result = pcall(apply, original)
	if not ok then
		error(`{CONFIG_NAME} 를 고칠 수 없어서 취소함: {result}`, 0)
	end
	module.Source = result
	const readOk, readError = pcall(Config.read)
	if not readOk then
		module.Source = original
		error(`{CONFIG_NAME} 를 고친 결과를 읽을 수 없어서 취소함: {readError}`, 0)
	end
end

function Config.getSharedPath(): string
	return Config.read().shared
end

function Config.getServerPath(): string
	return Config.read().server
end

function Config.setSharedPath(path: string)
	edit(function(source)
		return ConfigEditor.set(source, {}, "shared", string.format("%q", path))
	end)
end

function Config.setServerPath(path: string)
	edit(function(source)
		return ConfigEditor.set(source, {}, "server", string.format("%q", path))
	end)
end

-- 설치 위치(path)에 맞는 Config 안의 테이블 경로
const function sectionFor(data: Data, location: string): { string }
	if location == data.shared then
		return { "dependencies" }
	elseif location == data.server then
		return { "serverDependencies" }
	end
	return { "custom", location }
end

const function mapFor(data: Data, section: { string }): { [string]: string }?
	if section[1] == "custom" then
		return data.custom[section[2]]
	end
	return (data :: any)[section[1]]
end

-- 이미 같은 별칭이 있었으면 이전 스펙 반환
function Config.addDependency(alias: string, spec: string, location: string): string?
	const data = Config.read()
	const section = sectionFor(data, location)
	const map = mapFor(data, section)
	const previous = map and map[alias]
	edit(function(source)
		return ConfigEditor.set(source, section, alias, string.format("%q", spec))
	end)
	return previous
end

function Config.removeDependency(alias: string, location: string)
	const data = Config.read()
	const section = sectionFor(data, location)
	const map = mapFor(data, section)
	if not map or not map[alias] then
		return
	end
	edit(function(source)
		local result = ConfigEditor.remove(source, section, alias)
		-- custom 안의 빈 경로 테이블은 지움
		if section[1] == "custom" and ConfigEditor.isEmpty(result, section) then
			result = ConfigEditor.remove(result, { "custom" }, section[2])
		end
		return result
	end)
end

-- 모든 의존성 (설치 위치 경로 포함)
function Config.entries(): { Entry }
	const data = Config.read()
	const result = {}
	const function add(map: { [string]: string }, location: string)
		for _, alias in sortedKeys(map) do
			table.insert(result, { alias = alias, spec = map[alias], location = location })
		end
	end
	add(data.dependencies, data.shared)
	add(data.serverDependencies, data.server)
	for _, path in sortedKeys(data.custom) do
		add(data.custom[path], path)
	end
	return result
end

-- "ReplicatedStorage/Packages" 같은 경로를 Instance 로 (없는 폴더는 create 일 때 만듦)
function Config.resolvePath(path: string, create: boolean?): Instance?
	const parts = string.split(path, "/")
	const ok, service = pcall(game.GetService, game, parts[1])
	if not ok or not service then
		error(`알 수 없는 서비스: {parts[1]}`, 0)
	end

	local current: Instance = service
	for i = 2, #parts do
		const name = parts[i]
		if name ~= "" then
			local child = current:FindFirstChild(name)
			if not child then
				if not create then
					return nil
				end
				child = Instance.new("Folder")
				child.Name = name
				child.Parent = current
			end
			current = child
		end
	end
	return current
end

-- Instance -> "Service/Folder/..." 경로
function Config.pathOf(instance: Instance): string
	const parts = {}
	local current: Instance? = instance
	while current and current ~= game do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	if current ~= game then
		error(`{instance:GetFullName()} 은(는) DataModel 안에 있지 않음`, 0)
	end
	return table.concat(parts, "/")
end

return Config
