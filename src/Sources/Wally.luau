-- Wally 레지스트리 (https://api.wally.run)
-- 참고: roblox-package-manager 의 WallyApi (MIT)

const L = require(script.Parent.Parent.Locale).L
const Http = require(script.Parent.Parent.Http)
const Semver = require(script.Parent.Parent.Util.Semver)
const Vfs = require(script.Parent.Parent.Util.Vfs)
const Zip = require(script.Parent.Parent.Util.Zip)
const Types = require(script.Parent.Types)

type Package = Types.Package

const Wally = {}

const API = "https://api.wally.run"
const HEADERS = { ["Wally-Version"] = "0.3.2" }

function Wally.resolve(scope: string, name: string, rangeText: string?): Package
	const lowerScope, lowerName = string.lower(scope), string.lower(name)
	const metadata = Http.getJson(`{API}/v1/package-metadata/{lowerScope}/{lowerName}`, HEADERS)
	if type(metadata) ~= "table" or type(metadata.versions) ~= "table" then
		error(L(`Wally: {lowerScope}/{lowerName} 메타데이터를 읽을 수 없음`, `Wally: could not read metadata for {lowerScope}/{lowerName}`), 0)
	end

	const range = Semver.parseRange(rangeText)
	const candidates = {}
	const entries = {}
	for _, entry in metadata.versions do
		const version = entry.package and Semver.parse(entry.package.version)
		if version then
			table.insert(candidates, version)
			table.insert(entries, entry)
		end
	end

	const index = Semver.pickHighest(range, candidates)
	if not index then
		error(L(`Wally: {lowerScope}/{lowerName}@{rangeText or "*"} 를 만족하는 버전이 없음`, `Wally: no version matches {lowerScope}/{lowerName}@{rangeText or "*"}`), 0)
	end

	const entry = entries[index]
	const version = Semver.toString(candidates[index])
	const contentsUrl = `{API}/v1/package-contents/{lowerScope}/{lowerName}/{version}`

	return {
		source = "wally",
		scope = lowerScope,
		name = lowerName,
		version = version,
		realm = if entry.package.realm == "server" then "server" else "shared",
		dependencies = entry.dependencies or {},
		serverDependencies = entry["server-dependencies"] or {},
		entryPath = nil,
		fetch = function()
			return Vfs.new(Zip.extract(Http.get(contentsUrl, HEADERS)))
		end,
	}
end

return Wally
