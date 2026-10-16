-- Studio 의 Instance 를 Wally 패키지로 업로드 (wally publish 와 같은 형식)
--   Instance -> Rojo 형식 파일 (src/...) + wally.toml + default.project.json -> zip -> api.wally.run/v1/publish

const HttpService = game:GetService("HttpService")
const SerializationService = game:GetService("SerializationService")

const Auth = require(script.Parent.Auth)
const Config = require(script.Parent.Config)
const Http = require(script.Parent.Http)
const Semver = require(script.Parent.Util.Semver)
const Zip = require(script.Parent.Util.Zip)

export type Options = {
	-- "scope/name@1.0.0"
	spec: string,
	server: boolean,
	-- Config 의 dependencies / serverDependencies 를 의존성으로 넣음
	withConfigDependencies: boolean,
	log: (message: string) -> (),
}

export type Prepared = {
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
const DEPENDENCIES_ATTRIBUTE = "PackageLoaderDependencies"

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
	if #keys == 0 then
		return
	end
	table.insert(lines, "")
	table.insert(lines, `[{title}]`)
	for _, key in keys do
		table.insert(lines, `{tomlKey(key)} = {string.format("%q", map[key])}`)
	end
end

-- Config 스펙을 Wally 의존성으로 (Wally 패키지만, 버전이 있어야 함)
const function toWallyDependency(spec: string): string?
	const cleaned = string.gsub(spec, "^wally:", "")
	if string.match(cleaned, "^[%w_%-]+/[%w_%-]+@.+$") then
		return cleaned
	end
	return nil
end

const function collectDependencies(source: Instance, options: Options): ({ [string]: string }, { [string]: string })
	const shared, server = {}, {}

	-- Import 한 패키지면 원래 wally.toml 의존성
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

	if options.withConfigDependencies then
		const data = Config.read()
		for _, pair in { { data.dependencies, shared }, { data.serverDependencies, server } } do
			for alias, value in pair[1] do
				const dependency = if type(value) == "string" then toWallyDependency(value) else nil
				if dependency then
					pair[2][alias] = dependency
				else
					options.log(`경고: {alias} 는 Wally 패키지가 아니라서 의존성에서 뺌`)
				end
			end
		end
	end

	return shared, server
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

-- 업로드할 내용 만들기 (업로드는 안 함)
function Publisher.prepare(source: Instance, options: Options): Prepared
	const name, version = string.match(options.spec, "^%s*([^@%s]+)@(%S+)%s*$")
	if not name then
		error("publish <scope/name@버전> (예: publish ro-bura/signal@1.0.0)", 0)
	end
	if not string.match(name, "^[a-z0-9_%-]+/[a-z0-9_%-]+$") then
		error(`Wally 패키지 이름은 소문자/숫자/-/_ 만: {name}`, 0)
	end
	if not Semver.parse(version) then
		error(`버전 형식이 아님: {version} (예: 1.0.0)`, 0)
	end
	if not source:IsA("ModuleScript") then
		options.log(`경고: {source.Name} 은 ModuleScript 가 아니라서 require 할 수 없는 패키지가 됨`)
	end

	const packageName = string.match(name, "/(.+)$") :: string
	const files: { [string]: string } = {}

	-- 루트: ModuleScript 면 src/init.luau, 그 외는 src/ 폴더
	if source:IsA("ModuleScript") then
		files["src/init.luau"] = (source :: any).Source
	end
	for _, child in source:GetChildren() do
		addInstance(files, "src", child, options.log)
	end

	files["default.project.json"] = HttpService:JSONEncode({
		name = packageName,
		tree = { ["$path"] = "src" },
	})

	const shared, server = collectDependencies(source, options)
	const lines = {
		"[package]",
		`name = {string.format("%q", name)}`,
		`version = {string.format("%q", version)}`,
		`registry = {string.format("%q", REGISTRY)}`,
		`realm = "{if options.server then "server" else "shared"}"`,
	}
	tomlSection(lines, "dependencies", shared)
	tomlSection(lines, "server-dependencies", server)
	const manifest = table.concat(lines, "\n") .. "\n"
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

	return { name = name, version = version, files = files, paths = paths, manifest = manifest, zip = zip }
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
