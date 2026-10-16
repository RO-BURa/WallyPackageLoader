-- 플레이스에 저장되는 설정 (ServerStorage.PackageLoaderConfig ModuleScript)
-- 사람이 직접 고칠 수 있도록 wally.toml 과 비슷한 Luau 테이블로 저장
-- Team Create 로 함께 작업하는 사람도 같은 설정을 봄

const ServerStorage = game:GetService("ServerStorage")

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

	After editing this file by hand, press "Install All" in the plugin.
	Note: the plugin rewrites this file when you Add / Remove packages,
	so comments (including this one) are removed at that time.
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

function Config.getSharedPath(): string
	return Config.read().shared
end

function Config.getServerPath(): string
	return Config.read().server
end

function Config.setSharedPath(path: string)
	const data = Config.read()
	data.shared = path
	Config.write(data)
end

function Config.setServerPath(path: string)
	const data = Config.read()
	data.server = path
	Config.write(data)
end

-- 설치 위치(path)에 맞는 목록
const function mapFor(data: Data, path: string, create: boolean): { [string]: string }?
	if path == data.shared then
		return data.dependencies
	elseif path == data.server then
		return data.serverDependencies
	end
	if create and not data.custom[path] then
		data.custom[path] = {}
	end
	return data.custom[path]
end

function Config.addDependency(alias: string, spec: string, location: string)
	const data = Config.read()
	const map = mapFor(data, location, true) :: { [string]: string }
	map[alias] = spec
	Config.write(data)
end

function Config.removeDependency(alias: string, location: string)
	const data = Config.read()
	const map = mapFor(data, location, false)
	if map and map[alias] then
		map[alias] = nil
		if data.custom[location] and next(data.custom[location]) == nil then
			data.custom[location] = nil
		end
		Config.write(data)
	end
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
