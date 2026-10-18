-- pesde 레지스트리 (https://registry.pesde.daimond113.com/v1)
--   pesde:scope/name@^1.0
--   버전 목록: packages/{scope/name}, 받기: packages/{scope/name}/{버전}/{target}/archive (.tar.gz)
--   Roblox 용 target (roblox / roblox_server) 이 있는 버전만 고름

const HttpService = game:GetService("HttpService")

const Http = require(script.Parent.Parent.Http)
const Inflate = require(script.Parent.Parent.Util.Inflate)
const Log = require(script.Parent.Parent.Log)
const Semver = require(script.Parent.Parent.Util.Semver)
const Tar = require(script.Parent.Parent.Util.Tar)
const Vfs = require(script.Parent.Parent.Util.Vfs)
const Manifest = require(script.Parent.Manifest)
const Types = require(script.Parent.Types)

type Package = Types.Package

const Pesde = {}

const API = "https://registry.pesde.daimond113.com/v1"
-- shared 패키지는 roblox, 서버 전용은 roblox_server
const TARGETS = { "roblox", "roblox_server" }

Pesde.API = API

const function packagePath(scope: string, name: string): string
	return `{API}/packages/{HttpService:UrlEncode(`{scope}/{name}`)}`
end

-- 버전 목록 (packages/{name}) 그대로
function Pesde.metadata(scope: string, name: string): any
	return Http.getJson(packagePath(string.lower(scope), string.lower(name)))
end

-- 버전 하나에서 Roblox target 고르기 (없으면 nil)
function Pesde.robloxTarget(versionInfo: any): (string?, any)
	const targets = if type(versionInfo) == "table" and type(versionInfo.targets) == "table" then versionInfo.targets else {}
	for _, kind in TARGETS do
		const target = targets[kind]
		if type(target) == "table" and not target.yanked then
			return kind, target
		end
	end
	return nil, nil
end

-- 레지스트리의 의존성 목록 -> 이 플러그인 스펙 (dev 는 뺌)
--   { 별칭 = [ { name = "scope/name", version = "^1" } 또는 { wally = "scope/name", version = ... }, "standard" | "peer" | "dev" ] }
function Pesde.dependencySpecs(dependencies: any): { [string]: string }
	const result = {}
	for alias, entry in if type(dependencies) == "table" then dependencies else {} do
		const info = if type(entry) == "table" then entry[1] else nil
		const kind = if type(entry) == "table" then entry[2] else nil
		if type(info) == "table" and kind ~= "dev" then
			const version = if type(info.version) == "string" then info.version else nil
			if type(info.name) == "string" then
				result[alias] = `pesde:{info.name}` .. (if version then `@{version}` else "")
			elseif type(info.wally) == "string" then
				const wallyName = string.gsub(info.wally, "^.-#", "")
				result[alias] = wallyName .. (if version then `@{version}` else "")
			else
				Log.warn(`pesde 의존성 '{alias}' 는 지원하지 않는 형식이라 건너뜀`)
			end
		end
	end
	return result
end

function Pesde.archiveUrl(scope: string, name: string, version: string, target: string): string
	return `{packagePath(string.lower(scope), string.lower(name))}/{HttpService:UrlEncode(version)}/{target}/archive`
end

-- .tar.gz -> 경로 -> 내용
function Pesde.download(url: string): { [string]: string }
	return Tar.extract(Inflate.gunzip(Http.get(url)))
end

function Pesde.resolve(scope: string, name: string, rangeText: string?): Package
	const lowerScope, lowerName = string.lower(scope), string.lower(name)
	const metadata = Pesde.metadata(lowerScope, lowerName)
	if type(metadata) ~= "table" or type(metadata.versions) ~= "table" then
		error(`pesde: {lowerScope}/{lowerName} 정보를 읽을 수 없음`, 0)
	end

	const range = Semver.parseRange(rangeText)
	const candidates, labels = {}, {}
	for label, info in metadata.versions do
		const version = Semver.parse(label)
		if version and Pesde.robloxTarget(info) then
			table.insert(candidates, version)
			table.insert(labels, label)
		end
	end
	const index = Semver.pickHighest(range, candidates)
	if not index then
		error(`pesde: {lowerScope}/{lowerName}@{rangeText or "*"} 를 만족하는 Roblox 버전이 없음`, 0)
	end

	const label = labels[index]
	const kind, target = Pesde.robloxTarget(metadata.versions[label])
	const url = Pesde.archiveUrl(lowerScope, lowerName, label, kind :: string)

	const package: Package = {
		source = "pesde",
		scope = lowerScope,
		name = lowerName,
		version = Semver.toString(candidates[index]),
		realm = if kind == "roblox_server" then "server" else "shared",
		dependencies = Pesde.dependencySpecs(target.dependencies),
		serverDependencies = {},
		entryPath = nil,
		fetch = nil :: any,
	}
	package.fetch = function()
		const vfs = Vfs.new(Pesde.download(url)):stripSingleRoot()
		-- 진입 파일은 pesde.toml 의 target.lib
		const manifest = Manifest.read(vfs)
		if manifest and manifest.entryPath then
			package.entryPath = manifest.entryPath
		end
		return vfs
	end
	return package
end

return Pesde
