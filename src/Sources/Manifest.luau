-- 패키지 안의 wally.toml / pesde.toml 읽기

const Log = require(script.Parent.Parent.Log)
const Toml = require(script.Parent.Parent.Util.Toml)
const Vfs = require(script.Parent.Parent.Util.Vfs)
const Types = require(script.Parent.Types)

type Manifest = Types.Manifest

const Manifest = {}

const function readWally(text: string): Manifest
	const data = Toml.decode(text)
	const package = data.package or {}
	local scope, name = nil, nil
	if type(package.name) == "string" then
		scope, name = string.match(package.name, "^([^/]+)/(.+)$")
	end
	return {
		scope = scope,
		name = name,
		version = package.version,
		realm = if package.realm == "server" then "server" else "shared",
		dependencies = data.dependencies or {},
		serverDependencies = data["server-dependencies"] or {},
		entryPath = nil,
	}
end

-- pesde 의존성 테이블 하나를 이 플러그인의 스펙 문자열로 바꿈
const function pesdeDependencyToSpec(alias: string, dep: any): string?
	if type(dep) ~= "table" then
		return nil
	end
	const versionText = if type(dep.version) == "string" then dep.version else nil

	if type(dep.wally) == "string" then
		-- "wally#scope/name" 또는 "scope/name"
		const name = string.gsub(dep.wally, "^.-#", "")
		return if versionText then `{name}@{versionText}` else name
	elseif type(dep.name) == "string" then
		-- pesde 레지스트리 패키지 ("scope/name")
		return if versionText then `pesde:{dep.name}@{versionText}` else `pesde:{dep.name}`
	elseif type(dep.repo) == "string" then
		local owner, repo = string.match(dep.repo, "github%.com[/:]([^/]+)/([^/%.]+)")
		if not owner then
			owner, repo = string.match(dep.repo, "^([%w%-_%.]+)/([%w%-_%.]+)$")
		end
		if owner then
			const ref = dep.rev or dep.tag or dep.branch
			if type(ref) == "string" then
				return `gh:{owner}/{repo}#{ref}`
			end
			return if versionText then `gh:{owner}/{repo}@{versionText}` else `gh:{owner}/{repo}`
		end
	end

	Log.warn(`pesde 의존성 '{alias}' 는 지원하지 않는 형식이라 건너뜀 (GitHub 외 Git 등)`)
	return nil
end

const function readPesde(text: string): Manifest
	const data = Toml.decode(text)
	local scope, name = nil, nil
	if type(data.name) == "string" then
		scope, name = string.match(data.name, "^([^/]+)/(.+)$")
	end

	const target = data.target or {}
	const realm = if target.environment == "roblox_server" then "server" else "shared"

	const dependencies = {}
	for alias, dep in data.dependencies or {} do
		const spec = pesdeDependencyToSpec(alias, dep)
		if spec then
			dependencies[alias] = spec
		end
	end

	return {
		scope = scope,
		name = name,
		version = data.version,
		realm = realm,
		dependencies = dependencies,
		serverDependencies = {},
		entryPath = if type(target.lib) == "string" then target.lib else nil,
	}
end

-- wally.toml 이 있으면 우선, 없으면 pesde.toml
function Manifest.read(vfs: Vfs.Vfs): Manifest?
	const wally = vfs:read("wally.toml")
	if wally then
		return readWally(wally)
	end
	const pesde = vfs:read("pesde.toml")
	if pesde then
		return readPesde(pesde)
	end
	return nil
end

return Manifest
