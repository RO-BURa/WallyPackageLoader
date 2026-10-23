-- 업데이트 확인 / 적용, 라이선스 목록 (outdated, update, licenses, Manage 창)

const L = require(script.Parent.Locale).L
const Config = require(script.Parent.Config)
const Http = require(script.Parent.Http)
const Installer = require(script.Parent.Installer)
const Linker = require(script.Parent.Linker)
const Semver = require(script.Parent.Util.Semver)
const GitHub = require(script.Parent.Sources.GitHub)
const Pesde = require(script.Parent.Sources.Pesde)

export type Source = "wally" | "pesde" | "github" | "import"

-- Config 줄 하나의 상태
export type Status = {
	alias: string,
	location: string,
	-- Config 에 적힌 스펙 (Instance 면 nil)
	spec: string?,
	source: Source,
	-- "scope/name" 또는 "owner/repo" (Instance 면 Instance 이름)
	id: string,
	installed: boolean,
	-- 설치된 버전 (없으면 스펙에 적힌 버전)
	current: string?,
	-- 확인한 최신 버전 (확인 전 / 실패면 nil)
	latest: string?,
	-- 업데이트할 때 Config 에 적을 스펙 (업데이트가 없으면 nil)
	newSpec: string?,
	-- 메이저가 바뀌는 업데이트 (0.x 는 minor 가 바뀌어도)
	major: boolean,
	-- 확인 실패 이유
	error: string?,
	-- 브랜치 / 커밋으로 고정된 GitHub 처럼 확인하지 않는 것
	skipped: boolean,
}

export type License = {
	id: string,
	version: string,
	source: Source,
	license: string?,
}

const Updates = {}

const WALLY_API = "https://api.wally.run"
const WALLY_HEADERS = { ["Wally-Version"] = "0.3.2" }

type Parsed = {
	source: Source,
	-- 스펙에서 버전 앞부분 ("sleitnick/signal", "gh:owner/repo", "pesde:scope/name")
	prefix: string,
	owner: string,
	name: string,
	versionText: string?,
	-- GitHub #ref
	ref: string?,
}

const function parseSpec(spec: string): Parsed?
	const trimmed = string.match(spec, "^%s*(.-)%s*$") :: string
	const github = string.match(trimmed, "^gh:(.+)$") or string.match(trimmed, "^github:(.+)$")
	if github then
		const body, ref = string.match(github, "^([^#]+)#(.+)$")
		const path, version = string.match(body or github, "^([^@]+)@(.+)$")
		const owner, repo = string.match(path or body or github, "^([^/]+)/(.+)$")
		if not owner then
			return nil
		end
		return { source = "github", prefix = `gh:{owner}/{repo}`, owner = owner, name = repo, versionText = version, ref = ref }
	end
	const pesde = string.match(trimmed, "^pesde:(.+)$")
	const body = pesde or string.match(trimmed, "^wally:(.+)$") or trimmed
	const path, version = string.match(body, "^([^@]+)@(.+)$")
	const scope, name = string.match(path or body, "^([^/]+)/(.+)$")
	if not scope then
		return nil
	end
	const prefix = (if pesde then "pesde:" elseif string.match(trimmed, "^wally:") then "wally:" else "") .. `{scope}/{name}`
	return {
		source = if pesde then "pesde" else "wally",
		prefix = prefix,
		owner = scope,
		name = name,
		versionText = version,
	}
end

-- 설치된 엔트리의 버전 ("scope_name@1.2.3" -> "1.2.3")
const function installedVersion(location: string, alias: string): (boolean, string?)
	const folder = Config.resolvePath(location, false)
	const thunk = if folder then folder:FindFirstChild(alias) else nil
	if not thunk then
		return false, nil
	end
	const link = thunk:GetAttribute(Linker.LINK_ATTRIBUTE)
	if type(link) ~= "string" then
		-- 복사본 (Instance 로 적은 것)
		return thunk:GetAttribute(Linker.COPY_ATTRIBUTE) ~= nil, nil
	end
	const version = string.match(link, "@([^@]+)$")
	return true, version
end

-- 버전 목록에서 가장 높은 정식 버전 (정식이 없으면 프리릴리즈 포함)
const function highest(labels: { string }): string?
	local best, bestLabel = nil, nil
	local bestStable, bestStableLabel = nil, nil
	for _, label in labels do
		const version = Semver.parse(label)
		if version then
			if not best or Semver.compare(version, best) > 0 then
				best, bestLabel = version, label
			end
			if #version.prerelease == 0 and (not bestStable or Semver.compare(version, bestStable) > 0) then
				bestStable, bestStableLabel = version, label
			end
		end
	end
	return bestStableLabel or bestLabel
end

-- 레지스트리에서 최신 버전
const function latestOf(parsed: Parsed): string?
	if parsed.source == "wally" then
		const metadata = Http.getJson(
			`{WALLY_API}/v1/package-metadata/{string.lower(parsed.owner)}/{string.lower(parsed.name)}`,
			WALLY_HEADERS,
			true
		)
		const labels = {}
		for _, entry in if type(metadata) == "table" and type(metadata.versions) == "table" then metadata.versions else {} do
			if type(entry.package) == "table" and type(entry.package.version) == "string" then
				table.insert(labels, entry.package.version)
			end
		end
		return highest(labels)
	elseif parsed.source == "pesde" then
		const metadata = Pesde.metadata(parsed.owner, parsed.name)
		const labels = {}
		for label, info in if type(metadata) == "table" and type(metadata.versions) == "table" then metadata.versions else {} do
			if Pesde.robloxTarget(info) then
				table.insert(labels, label)
			end
		end
		return highest(labels)
	end
	const best = highest(GitHub.listTags(parsed.owner, parsed.name))
	return if best then Semver.toString(Semver.parse(best) :: any) else nil
end

const function isMajorChange(from: Semver.Version, to: Semver.Version): boolean
	if from.major ~= to.major then
		return true
	end
	return from.major == 0 and from.minor ~= to.minor
end

-- 스펙에서 버전만 바꿈 (^ / ~ 는 그대로)
const function withVersion(parsed: Parsed, versionText: string?, latest: string): string
	const operator = if versionText then string.match(versionText, "^%s*([%^~])") else nil
	return `{parsed.prefix}@{operator or ""}{latest}`
end

-- Config 줄들의 상태 (네트워크 없이, latest 는 nil)
function Updates.list(): { Status }
	const result: { Status } = {}
	for _, entry in Config.entries() do
		const installed, version = installedVersion(entry.location, entry.alias)
		if entry.source then
			table.insert(result, {
				alias = entry.alias,
				location = entry.location,
				source = "import",
				id = entry.source.Name,
				installed = installed,
				major = false,
				skipped = true,
			})
		else
			const spec = entry.spec :: string
			const parsed = parseSpec(spec)
			local current = version
			if not current and parsed and parsed.versionText then
				const exact = Semver.parse((string.gsub(parsed.versionText, "^[%^~=%s]+", "")))
				current = if exact then Semver.toString(exact) else nil
			end
			table.insert(result, {
				alias = entry.alias,
				location = entry.location,
				spec = spec,
				source = if parsed then parsed.source else "wally",
				id = if parsed then `{parsed.owner}/{parsed.name}` else spec,
				installed = installed,
				current = current,
				major = false,
				skipped = parsed == nil or parsed.ref ~= nil,
			})
		end
	end
	return result
end

-- 상태 하나의 최신 버전 확인
function Updates.checkOne(status: Status)
	status.latest, status.newSpec, status.error, status.major = nil, nil, nil, false
	if status.skipped or not status.spec then
		return
	end
	const parsed = parseSpec(status.spec :: string) :: Parsed
	const ok, latest = pcall(latestOf, parsed)
	if not ok then
		status.error = tostring(latest)
		return
	end
	if not latest then
		status.error = L("버전을 찾을 수 없음", "No versions found")
		return
	end
	status.latest = latest
	const latestVersion = Semver.parse(latest)
	const currentVersion = if status.current then Semver.parse(status.current :: string) else nil
	if latestVersion and (not currentVersion or Semver.compare(latestVersion, currentVersion) > 0) then
		status.newSpec = withVersion(parsed, parsed.versionText, latest)
		status.major = currentVersion ~= nil and isMajorChange(currentVersion, latestVersion)
	end
end

-- 전부 확인 (동시에 받고 다 끝날 때까지 기다림)
function Updates.check(statuses: { Status }?): { Status }
	const list = statuses or Updates.list()
	const thread = coroutine.running()
	local remaining = 0
	local waiting = false
	for _, status in list do
		if not status.skipped and status.spec then
			remaining += 1
			task.spawn(function()
				Updates.checkOne(status)
				remaining -= 1
				if remaining == 0 and waiting then
					task.spawn(thread)
				end
			end)
		end
	end
	if remaining > 0 then
		waiting = true
		coroutine.yield()
	end
	return list
end

-- 업데이트 적용: Config 의 스펙을 바꾸고 설치
function Updates.apply(status: Status, log: (string) -> ())
	if not status.newSpec then
		return
	end
	const newSpec = status.newSpec :: string
	Config.addDependency(status.alias, newSpec, status.location)
	log(L(`업데이트: {status.alias} {status.current or "?"} -> {status.latest}`, `Updated: {status.alias} {status.current or "?"} -> {status.latest}`))
	Installer.install(newSpec, {
		alias = status.alias,
		location = Config.resolvePath(status.location, true),
		log = log,
	})
	status.current = status.latest
	status.newSpec = nil
	status.major = false
	status.installed = true
end

-- 설치된 _Index 엔트리들의 라이선스 (의존성 포함, 같은 패키지@버전은 한 번)
function Updates.licenses(): { License }
	const seen: { [string]: boolean } = {}
	const result: { License } = {}
	const pending = {}
	for _, service in game:GetChildren() do
		const ok, descendants = pcall(service.GetDescendants, service)
		if ok then
			for _, entry in descendants do
				if entry:GetAttribute(Linker.ENTRY_ATTRIBUTE) and not seen[entry.Name] then
					seen[entry.Name] = true
					const pesdeScope, pesdeName, pesdeVersion = string.match(entry.Name, "^pesde%+([^_]+)_(.+)@(.+)$")
					const scope, name, version = string.match(entry.Name, "^([^_]+)_(.+)@(.+)$")
					const attribute = entry:GetAttribute(Linker.SOURCE_ATTRIBUTE)
					if pesdeScope then
						table.insert(pending, { id = `{pesdeScope}/{pesdeName}`, version = pesdeVersion, source = "pesde" })
					elseif scope and string.sub(entry.Name, 1, 7) ~= "custom_" then
						table.insert(pending, {
							id = `{scope}/{name}`,
							version = version,
							source = if attribute == "github" then "github" else "wally",
							guess = attribute == nil,
						})
					end
				end
			end
		end
	end

	const thread = coroutine.running()
	local remaining = #pending
	local waiting = false
	for _, item in pending do
		task.spawn(function()
			const owner, name = string.match(item.id, "^([^/]+)/(.+)$")
			local license: string? = nil
			local source: Source = item.source
			pcall(function()
				if item.source == "pesde" then
					const metadata = Pesde.metadata(owner :: string, name :: string)
					const info = metadata.versions[item.version]
					const _, target = Pesde.robloxTarget(info)
					license = target and target.license
				elseif item.source == "wally" then
					const metadata = Http.getJson(
						`{WALLY_API}/v1/package-metadata/{owner}/{name}`,
						WALLY_HEADERS
					)
					for _, entry in metadata.versions do
						if entry.package and entry.package.version == item.version then
							license = entry.package.license
						end
					end
				end
			end)
			-- 예전에 설치해서 출처 표시가 없고 Wally 에서 못 찾으면 GitHub 으로
			if not license and (item.source == "github" or item.guess) then
				pcall(function()
					const info = Http.getJson(`https://api.github.com/repos/{owner}/{name}`)
					license = if type(info.license) == "table" then info.license.spdx_id else nil
					source = "github"
				end)
			end
			table.insert(result, {
				id = item.id,
				version = item.version,
				source = source,
				license = if type(license) == "string" and license ~= "" then license else nil,
			})
			remaining -= 1
			if remaining == 0 and waiting then
				task.spawn(thread)
			end
		end)
	end
	if remaining > 0 then
		waiting = true
		coroutine.yield()
	end
	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

return Updates
