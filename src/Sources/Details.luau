-- 검색 창의 상세 화면에 쓸 정보 (버전 목록, 버전별 정보, 내부 구조)

const L = require(script.Parent.Parent.Locale).L
const Auth = require(script.Parent.Parent.Auth)
const Http = require(script.Parent.Parent.Http)
const Semver = require(script.Parent.Parent.Util.Semver)
const Toml = require(script.Parent.Parent.Util.Toml)
const Zip = require(script.Parent.Parent.Util.Zip)
const GitHub = require(script.Parent.GitHub)
const Pesde = require(script.Parent.Pesde)

-- 고를 수 있는 버전 하나
export type Version = {
	-- 화면에 보일 이름 ("2.0.1", "v1.2.0", "main (브랜치)")
	label: string,
	-- Config 에 적을 스펙 (정확히 이 버전)
	spec: string,
	-- ^ 범위 스펙 (없으면 nil)
	rangeSpec: string?,
	-- 1.0.0-rc.1 같은 프리릴리즈
	prerelease: boolean?,
}

-- 버전 하나의 정보
export type Info = {
	-- 제목 / 값 줄들
	fields: { { string } },
	dependencies: { [string]: string },
	serverDependencies: { [string]: string },
	-- 추가로 보여줄 글 (README 앞부분 등)
	extra: string?,
	-- 경고 (매니페스트 없음 등)
	warning: string?,
}

const Details = {}

const WALLY_API = "https://api.wally.run"
const WALLY_HEADERS = { ["Wally-Version"] = "0.3.2" }
const GITHUB_API = "https://api.github.com"
const RAW = "https://raw.githubusercontent.com"
const README_LINES = 25

const function list(value: any): string?
	if type(value) == "table" and #value > 0 then
		const parts = {}
		for _, item in value do
			table.insert(parts, tostring(item))
		end
		return table.concat(parts, ", ")
	end
	return if type(value) == "string" and value ~= "" then value else nil
end

-- 높은 버전부터
const function isPrerelease(label: string): boolean
	const version = Semver.parse(label)
	return version ~= nil and #version.prerelease > 0
end

const function sortVersions(labels: { string }): { string }
	const parsed = {}
	for _, label in labels do
		table.insert(parsed, { label = label, version = Semver.parse(label) })
	end
	table.sort(parsed, function(a, b)
		if a.version and b.version then
			return Semver.compare(a.version, b.version) > 0
		end
		return a.version ~= nil and b.version == nil
	end)
	const result = {}
	for _, item in parsed do
		table.insert(result, item.label)
	end
	return result
end

-- 처음에 보여줄 버전: 프리릴리즈가 아닌 것 중 가장 높은 것
function Details.defaultVersion(versions: { Version }): Version?
	for _, version in versions do
		if not version.prerelease then
			return version
		end
	end
	return versions[1]
end

--------------------------------------------------------------------------------
-- Wally

-- scope/name 의 버전 목록과 버전별 정보를 한 번에 (package-metadata)
function Details.wally(scope: string, name: string): { versions: { Version }, info: (Version) -> Info }
	const lowerScope, lowerName = string.lower(scope), string.lower(name)
	const metadata = Http.getJson(`{WALLY_API}/v1/package-metadata/{lowerScope}/{lowerName}`, WALLY_HEADERS)
	const byVersion: { [string]: any } = {}
	const labels = {}
	for _, entry in if type(metadata) == "table" and type(metadata.versions) == "table" then metadata.versions else {} do
		if type(entry.package) == "table" and type(entry.package.version) == "string" then
			byVersion[entry.package.version] = entry
			table.insert(labels, entry.package.version)
		end
	end

	const versions: { Version } = {}
	for _, label in sortVersions(labels) do
		table.insert(versions, {
			label = label,
			spec = `{lowerScope}/{lowerName}@{label}`,
			rangeSpec = `{lowerScope}/{lowerName}@^{label}`,
			prerelease = isPrerelease(label),
		})
	end

	return {
		versions = versions,
		info = function(version: Version): Info
			const entry = byVersion[version.label] or {}
			const package = entry.package or {}
			const fields = {}
			const function field(title: string, value: string?)
				if value then
					table.insert(fields, { title, value })
				end
			end
			field(L("설명", "description"), list(package.description))
			field("realm", list(package.realm) or "shared")
			field("license", list(package.license))
			field("authors", list(package.authors))
			field("homepage", list(package.homepage))
			field("repository", list(package.repository))
			return {
				fields = fields,
				dependencies = entry.dependencies or {},
				serverDependencies = entry["server-dependencies"] or {},
			}
		end,
	}
end

-- 파일 목록 + 내용 읽기
export type Files = {
	paths: { string },
	read: (path: string) -> string,
}

-- 이미 받은 파일들 (경로 -> 내용) 로
const function filesFromMap(files: { [string]: string }): Files
	const paths = {}
	for path in files do
		table.insert(paths, path)
	end
	table.sort(paths)
	return {
		paths = paths,
		read = function(path)
			return files[path] or ""
		end,
	}
end

-- 패키지 안의 파일 (zip 을 받아서)
function Details.wallyFiles(scope: string, name: string, version: string): Files
	const url = `{WALLY_API}/v1/package-contents/{string.lower(scope)}/{string.lower(name)}/{version}`
	return filesFromMap(Zip.extract(Http.get(url, WALLY_HEADERS)))
end

--------------------------------------------------------------------------------
-- pesde

function Details.pesde(scope: string, name: string): { versions: { Version }, info: (Version) -> Info }
	const lowerScope, lowerName = string.lower(scope), string.lower(name)
	const metadata = Pesde.metadata(lowerScope, lowerName)
	const byVersion = if type(metadata) == "table" and type(metadata.versions) == "table" then metadata.versions else {}
	const labels = {}
	for label, info in byVersion do
		if Pesde.robloxTarget(info) then
			table.insert(labels, label)
		end
	end
	const versions: { Version } = {}
	for _, label in sortVersions(labels) do
		table.insert(versions, {
			label = label,
			spec = `pesde:{lowerScope}/{lowerName}@{label}`,
			rangeSpec = `pesde:{lowerScope}/{lowerName}@^{label}`,
			prerelease = isPrerelease(label),
		})
	end

	return {
		versions = versions,
		info = function(version: Version): Info
			const versionInfo = byVersion[version.label] or {}
			const kind, target = Pesde.robloxTarget(versionInfo)
			const inner = target or {}
			const fields = {}
			const function field(title: string, value: string?)
				if value then
					table.insert(fields, { title, value })
				end
			end
			field(L("설명", "description"), list(versionInfo.description))
			field("target", kind)
			field("license", list(inner.license))
			field("authors", list(inner.authors))
			field("repository", list(inner.repository))
			field(L("올린 날", "published"), if type(inner.published_at) == "string" then string.sub(inner.published_at, 1, 10) else nil)
			if type(metadata) == "table" and type(metadata.deprecated) == "string" and metadata.deprecated ~= "" then
				field("deprecated", metadata.deprecated)
			end
			return {
				fields = fields,
				dependencies = Pesde.dependencySpecs(inner.dependencies),
				serverDependencies = {},
			}
		end,
	}
end

-- 패키지 안의 파일 (.tar.gz 를 받아서)
function Details.pesdeFiles(scope: string, name: string, version: string): Files
	const metadata = Pesde.metadata(scope, name)
	const versionInfo = if type(metadata) == "table" and type(metadata.versions) == "table" then metadata.versions[version] else nil
	const kind = Pesde.robloxTarget(versionInfo)
	if not kind then
		error(L("Roblox 용 target 이 없음", "No Roblox target"), 0)
	end
	return filesFromMap(Pesde.download(Pesde.archiveUrl(scope, name, version, kind :: string)))
end

--------------------------------------------------------------------------------
-- GitHub

export type Repo = {
	stars: number,
	-- 로그인했을 때만: 내가 별을 눌렀는지
	starred: boolean?,
	defaultBranch: string,
	fields: { { string } },
}

function Details.githubRepo(owner: string, repo: string): Repo
	const info = Http.getJson(`{GITHUB_API}/repos/{owner}/{repo}`, Auth.githubHeaders())
	const fields = {}
	const function field(title: string, value: string?)
		if value then
			table.insert(fields, { title, value })
		end
	end
	field(L("설명", "description"), list(info.description))
	field("license", if type(info.license) == "table" then list(info.license.spdx_id) else nil)
	field(L("주 언어", "language"), list(info.language))
	field("topics", list(info.topics))
	field(L("마지막 push", "last push"), if type(info.pushed_at) == "string" then string.sub(info.pushed_at, 1, 10) else nil)
	field(L("기본 브랜치", "default branch"), list(info.default_branch))

	-- 내가 별을 눌렀는지 (204 = 누름, 404 = 안 누름). 로그인 안 했거나 실패하면 모름
	local starred: boolean? = nil
	const headers = Auth.githubHeaders()
	if headers then
		const ok, err = pcall(Http.get, `{GITHUB_API}/user/starred/{owner}/{repo}`, headers, true)
		if ok then
			starred = true
		elseif string.find(tostring(err), "HTTP 404", 1, true) then
			starred = false
		end
	end

	return {
		stars = tonumber(info.stargazers_count) or 0,
		starred = starred,
		defaultBranch = if type(info.default_branch) == "string" then info.default_branch else "main",
		fields = fields,
	}
end

-- semver 태그 (높은 것부터) + 기본 브랜치
function Details.githubVersions(owner: string, repo: string, defaultBranch: string): { Version }
	const versions: { Version } = {}
	const tags = {}
	for _, tag in GitHub.listTags(owner, repo) do
		if Semver.parse(tag) then
			table.insert(tags, tag)
		end
	end
	for _, tag in sortVersions(tags) do
		const plain = Semver.toString(Semver.parse(tag) :: any)
		table.insert(versions, {
			label = tag,
			spec = `gh:{owner}/{repo}@{plain}`,
			rangeSpec = `gh:{owner}/{repo}@^{plain}`,
			prerelease = isPrerelease(tag),
		})
	end
	table.insert(versions, {
		label = L(`{defaultBranch} (브랜치)`, `{defaultBranch} (branch)`),
		spec = `gh:{owner}/{repo}#{defaultBranch}`,
	})
	return versions
end

const function refOf(version: Version): string
	const branch = string.match(version.spec, "#(.+)$")
	if branch then
		return branch
	end
	return version.label
end

-- 고른 버전의 매니페스트 (wally.toml / pesde.toml) 와 README 앞부분
function Details.githubInfo(owner: string, repo: string, version: Version): Info
	const ref = refOf(version)
	const fields = {}
	local dependencies, serverDependencies = {}, {}
	local warning: string? = nil

	const function raw(path: string): string?
		const ok, body = pcall(Http.get, `{RAW}/{owner}/{repo}/{ref}/{path}`)
		return if ok then body else nil
	end

	const wally = raw("wally.toml")
	const pesde = if wally then nil else raw("pesde.toml")
	if wally then
		const ok, data = pcall(Toml.decode, wally)
		if ok then
			const package = data.package or {}
			table.insert(fields, { L("매니페스트", "manifest"), `wally.toml ({tostring(package.name or "?")}@{tostring(package.version or "?")})` })
			if package.realm then
				table.insert(fields, { "realm", tostring(package.realm) })
			end
			dependencies = data.dependencies or {}
			serverDependencies = data["server-dependencies"] or {}
		else
			warning = L("wally.toml 을 읽을 수 없음", "Could not read wally.toml")
		end
	elseif pesde then
		const ok, data = pcall(Toml.decode, pesde)
		table.insert(fields, { L("매니페스트", "manifest"), `pesde.toml ({tostring(ok and data.name or "?")})` })
		if ok and type(data.dependencies) == "table" then
			for alias, dep in data.dependencies do
				dependencies[alias] = if type(dep) == "table" then (dep.wally or dep.repo or dep.name or "?") .. "@" .. tostring(dep.version or "*") else tostring(dep)
			end
		end
	else
		warning = L("wally.toml / pesde.toml 이 없음. 저장소 구조 그대로 가져옴 (default.project.json 이 있으면 그걸 따름)", "No wally.toml / pesde.toml. The repository is used as is (default.project.json is followed if present)")
	end

	-- README 앞부분 (글자만)
	local extra: string? = nil
	const readme = raw("README.md")
	if readme then
		const lines = {}
		for line in string.gmatch(readme .. "\n", "([^\n]*)\n") do
			if #lines >= README_LINES then
				table.insert(lines, "...")
				break
			end
			table.insert(lines, line)
		end
		extra = table.concat(lines, "\n")
	end

	return {
		fields = fields,
		dependencies = dependencies,
		serverDependencies = serverDependencies,
		extra = extra,
		warning = warning,
	}
end

-- 저장소 파일 (목록은 git tree, 내용은 누를 때 raw 로 받음)
function Details.githubFiles(owner: string, repo: string, version: Version): Files
	const data = Http.getJson(
		`{GITHUB_API}/repos/{owner}/{repo}/git/trees/{refOf(version)}?recursive=1`,
		Auth.githubHeaders()
	)
	const paths = {}
	for _, item in if type(data) == "table" and type(data.tree) == "table" then data.tree else {} do
		if item.type == "blob" and type(item.path) == "string" then
			table.insert(paths, item.path)
		end
	end
	table.sort(paths)
	const ref = refOf(version)
	return {
		paths = paths,
		read = function(path)
			return Http.get(`{RAW}/{owner}/{repo}/{ref}/{path}`)
		end,
	}
end

-- 경로 목록 -> 들여쓴 트리 줄 (파일 줄에는 path, 폴더 줄은 nil)
export type TreeLine = { text: string, path: string? }

function Details.pathTree(paths: { string }, limit: number?): { TreeLine }
	const lines: { TreeLine } = {}
	const shownDirs: { [string]: boolean } = {}
	const max = limit or 500
	for _, path in paths do
		if #lines >= max then
			table.insert(lines, { text = L(`... ({#paths} 개 중 일부)`, `... (part of {#paths})`) })
			break
		end
		const parts = string.split(path, "/")
		local dir = ""
		for i = 1, #parts - 1 do
			dir ..= parts[i] .. "/"
			if not shownDirs[dir] then
				shownDirs[dir] = true
				table.insert(lines, { text = string.rep("  ", i - 1) .. parts[i] .. "/" })
			end
		end
		table.insert(lines, { text = string.rep("  ", #parts - 1) .. parts[#parts], path = path })
	end
	return lines
end

return Details
