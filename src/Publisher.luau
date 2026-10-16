-- Studio 의 Instance 를 Wally 패키지로 업로드 (wally publish 와 같은 형식)
--   패키지 안의 wally.toml (ModuleScript) 을 매니페스트로 씀
--   Instance -> Rojo 형식 파일 (src/...) + wally.toml + default.project.json -> zip -> api.wally.run/v1/publish

const HttpService = game:GetService("HttpService")
const SerializationService = game:GetService("SerializationService")

const Auth = require(script.Parent.Auth)
const Http = require(script.Parent.Http)
const Linker = require(script.Parent.Linker)
const Semver = require(script.Parent.Util.Semver)
const Toml = require(script.Parent.Util.Toml)
const Zip = require(script.Parent.Util.Zip)

export type Prepared = {
	source: Instance,
	name: string,
	version: string,
	files: { [string]: string },
	paths: { string },
	manifest: string,
	zip: string,
}

const Publisher = {}

const API = "https://api.wally.run"
const REGISTRY = "https://github.com/UpliftGames/wally-index"
const MAX_SIZE = 2 * 1024 * 1024
-- 패키지 안에 두는 매니페스트 ModuleScript (업로드할 때는 빠지고 zip 의 wally.toml 이 됨)
const MANIFEST_NAME = "wally.toml"
-- Import 한 패키지의 원래 의존성 (Installer 와 같은 Attribute)
const DEPENDENCIES_ATTRIBUTE = "PackageLoaderDependencies"

Publisher.MANIFEST_NAME = MANIFEST_NAME

const function tomlKey(key: string): string
	if string.match(key, "^[%w_%-]+$") then
		return key
	end
	return string.format("%q", key)
end

const function tomlSection(lines: { string }, title: string, map: { [string]: string })
	const keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	table.insert(lines, "")
	table.insert(lines, `[{title}]`)
	for _, key in keys do
		table.insert(lines, `{tomlKey(key)} = {string.format("%q", map[key])}`)
	end
end

-- 선택한 것 -> 올릴 패키지 (thunk 면 가리키는 진짜 모듈, wally.toml 이면 그 부모)
function Publisher.findSource(selected: Instance): Instance
	local source = selected
	if source.Name == MANIFEST_NAME and source:IsA("ModuleScript") and source.Parent then
		source = source.Parent
	end
	const link = source:GetAttribute(Linker.LINK_ATTRIBUTE)
	if type(link) == "string" then
		for _, service in game:GetChildren() do
			const ok, descendants = pcall(service.GetDescendants, service)
			if ok then
				for _, entry in descendants do
					if entry:GetAttribute(Linker.ENTRY_ATTRIBUTE) and entry:GetFullName() == link then
						for _, child in entry:GetChildren() do
							if child:GetAttribute(Linker.LINK_ATTRIBUTE) == nil then
								return child
							end
						end
					end
				end
			end
		end
		error(`{source.Name} 은 thunk 인데 가리키는 패키지를 찾을 수 없음`, 0)
	end
	return source
end

function Publisher.getManifest(source: Instance): ModuleScript?
	const manifest = source:FindFirstChild(MANIFEST_NAME)
	return if manifest and manifest:IsA("ModuleScript") then manifest else nil
end

-- 템플릿 wally.toml 을 만들어서 반환 (이미 있으면 그대로)
function Publisher.createManifest(source: Instance, scope: string?): ModuleScript
	const existing = Publisher.getManifest(source)
	if existing then
		return existing
	end

	const name = string.gsub(string.lower(source.Name), "[^a-z0-9_%-]", "-")
	const shared, server = {}, {}
	-- Import 한 패키지면 원래 wally.toml 의존성을 채워둠
	const raw = source:GetAttribute(DEPENDENCIES_ATTRIBUTE)
	if type(raw) == "string" then
		const ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(decoded) == "table" then
			for alias, spec in decoded.dependencies or {} do
				shared[alias] = spec
			end
			for alias, spec in decoded.serverDependencies or {} do
				server[alias] = spec
			end
		end
	end

	const lines = {
		"[package]",
		`name = "{if scope then string.lower(scope) else "scope"}/{name}"`,
		`version = "0.1.0"`,
		`registry = "{REGISTRY}"`,
		`realm = "{if source:IsDescendantOf(game:GetService("ServerScriptService")) or source:IsDescendantOf(game:GetService("ServerStorage")) then "server" else "shared"}"`,
		`description = ""`,
		`authors = []`,
		`license = ""`,
	}
	tomlSection(lines, "dependencies", shared)
	tomlSection(lines, "server-dependencies", server)

	const manifest = Instance.new("ModuleScript")
	manifest.Name = MANIFEST_NAME
	;(manifest :: any).Source = "-- publish 할 때 이 내용이 wally.toml 이 됨 (이 스크립트는 업로드에서 빠짐)\n"
		.. "-- 의존성은 코드에서 require(script.Parent.별칭) 으로 불러옴\n"
		.. "return [==[\n"
		.. table.concat(lines, "\n")
		.. "\n]==]\n"
	manifest.Parent = source
	return manifest
end

-- wally.toml ModuleScript 에서 TOML 글자 (return [[...]] 로 감싸져 있으면 안쪽만, 아니면 전체)
const function manifestText(manifest: ModuleScript): string
	const source = (manifest :: any).Source :: string
	const _, body = string.match(source, "return%s*%[(=*)%[\n?(.-)%]%1%]")
	return body or source
end

-- 의존성 하나 검사 (Wally 에는 Wally 패키지만 의존성으로 올릴 수 있음)
const function checkDependency(alias: string, spec: any)
	if type(spec) ~= "string" or not string.match(spec, "^[%w_%-]+/[%w_%-]+@.+$") then
		error(`의존성 {alias} = {tostring(spec)}: Wally 패키지 (scope/name@버전) 만 됨`, 0)
	end
end

-- Instance 하나를 Rojo 형식 파일로 (dir 안에)
const function addInstance(files: { [string]: string }, dir: string, instance: Instance, log: (string) -> ())
	const name = instance.Name
	if string.find(name, "[/\\]") then
		error(`이름에 / 나 \\ 가 있어서 파일로 만들 수 없음: {instance:GetFullName()}`, 0)
	end
	const path = `{dir}/{name}`
	const children = instance:GetChildren()

	if instance:IsA("LuaSourceContainer") and (instance:IsA("ModuleScript") or instance:IsA("Script")) then
		const suffix = if instance:IsA("LocalScript") then ".client" elseif instance:IsA("Script") then ".server" else ""
		const source = (instance :: any).Source
		if #children == 0 then
			files[`{path}{suffix}.luau`] = source
		else
			files[`{path}/init{suffix}.luau`] = source
			for _, child in children do
				addInstance(files, path, child, log)
			end
		end
	elseif instance.ClassName == "Folder" then
		if #children == 0 then
			files[`{path}/.gitkeep`] = ""
		end
		for _, child in children do
			addInstance(files, path, child, log)
		end
	elseif instance:IsA("StringValue") then
		files[`{path}.txt`] = (instance :: StringValue).Value
	else
		-- 그 외 (Part, UI 등) 는 .rbxm 으로
		const ok, result = pcall(function()
			return buffer.tostring(SerializationService:SerializeInstancesAsync({ instance }))
		end)
		if ok then
			files[`{path}.rbxm`] = result
		else
			log(`경고: {instance:GetFullName()} 을 .rbxm 으로 저장할 수 없어서 뺌 ({result})`)
		end
	end
end

-- 업로드할 내용 만들기 (업로드는 안 함). source 안의 wally.toml 을 씀
function Publisher.prepare(source: Instance, log: (string) -> ()): Prepared
	const manifestScript = Publisher.getManifest(source)
	if not manifestScript then
		error(`{source.Name} 안에 {MANIFEST_NAME} 이 없음 (publish 로 만들 수 있음)`, 0)
	end
	const manifest = manifestText(manifestScript)
	const ok, data = pcall(Toml.decode, manifest)
	if not ok then
		error(`{MANIFEST_NAME} 을 읽을 수 없음: {data}`, 0)
	end

	const package = data.package
	if type(package) ~= "table" then
		error(`{MANIFEST_NAME} 에 [package] 가 없음`, 0)
	end
	const name, version = package.name, package.version
	if type(name) ~= "string" or not string.match(name, "^[a-z0-9_%-]+/[a-z0-9_%-]+$") then
		error(`name 은 "scope/name" (소문자/숫자/-/_ 만): {tostring(name)}`, 0)
	end
	if string.match(name, "^scope/") then
		error(`{MANIFEST_NAME} 의 name 에 scope (GitHub 아이디) 를 적어주세요: {name}`, 0)
	end
	if type(version) ~= "string" or not Semver.parse(version) then
		error(`version 형식이 아님: {tostring(version)} (예: 1.0.0)`, 0)
	end
	if type(package.registry) ~= "string" then
		error(`registry 가 없음 (registry = "{REGISTRY}")`, 0)
	end
	if package.realm ~= "shared" and package.realm ~= "server" then
		error(`realm 은 "shared" 또는 "server": {tostring(package.realm)}`, 0)
	end
	for _, section in { "dependencies", "server-dependencies", "dev-dependencies" } do
		for alias, spec in data[section] or {} do
			checkDependency(alias, spec)
		end
	end
	if not source:IsA("ModuleScript") then
		log(`경고: {source.Name} 은 ModuleScript 가 아니라서 require 할 수 없는 패키지가 됨`)
	end

	const packageName = string.match(name, "/(.+)$") :: string
	const files: { [string]: string } = {}

	-- 루트: ModuleScript 면 src/init.luau, 그 외는 src/ 폴더. wally.toml 스크립트는 뺌
	if source:IsA("ModuleScript") then
		files["src/init.luau"] = (source :: any).Source
	end
	for _, child in source:GetChildren() do
		if child ~= manifestScript then
			addInstance(files, "src", child, log)
		end
	end

	files["default.project.json"] = HttpService:JSONEncode({
		name = packageName,
		tree = { ["$path"] = "src" },
	})
	files["wally.toml"] = manifest

	const paths = {}
	for path in files do
		table.insert(paths, path)
	end
	table.sort(paths)

	const zip = Zip.create(files, paths)
	if #zip > MAX_SIZE then
		error(`패키지가 2MB 를 넘음 ({math.ceil(#zip / 1024)}KB)`, 0)
	end

	return {
		source = source,
		name = name,
		version = version,
		files = files,
		paths = paths,
		manifest = manifest,
		zip = zip,
	}
end

-- 업로드 (Wally 는 같은 버전을 다시 올릴 수 없고, 올린 것은 지울 수 없음)
function Publisher.upload(prepared: Prepared)
	const token = Auth.getToken()
	if not token then
		error("로그인이 필요함 (login)", 0)
	end
	if Auth.kind() ~= "device" then
		error("Wally 업로드는 login (기기 로그인) 으로 받은 토큰만 됨. 직접 넣은 토큰은 Wally 서버가 받지 않음", 0)
	end

	Http.post(`{API}/v1/publish`, prepared.zip, {
		Authorization = `Bearer {token}`,
		["Wally-Version"] = "0.3.2",
		Accept = "application/json",
		["Content-Type"] = "application/octet-stream",
	})
	Http.clearCache()
end

return Publisher
