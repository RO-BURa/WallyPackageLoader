-- 패키지 검색 (Wally 레지스트리, GitHub 저장소)

const HttpService = game:GetService("HttpService")

const L = require(script.Parent.Parent.Locale).L
const Auth = require(script.Parent.Parent.Auth)
const Http = require(script.Parent.Parent.Http)
const Semver = require(script.Parent.Parent.Util.Semver)
const Pesde = require(script.Parent.Pesde)

export type Result = {
	source: "wally" | "github" | "pesde",
	-- "scope/name" 또는 "owner/repo"
	id: string,
	-- 최신 버전 (GitHub 는 별 개수 등)
	detail: string,
	description: string,
	-- Config 에 적을 스펙
	spec: string,
}

export type Options = {
	-- Wally scope / GitHub 사용자로 좁힘 (없으면 전체)
	author: string?,
	-- GitHub: Luau 저장소만
	luauOnly: boolean?,
	limit: number?,
}

const Search = {}

const WALLY_API = "https://api.wally.run"
const GITHUB_API = "https://api.github.com"
const WALLY_HEADERS = { ["Wally-Version"] = "0.3.2" }
const DEFAULT_LIMIT = 30

-- 버전 목록에서 가장 높은 것 (프리릴리즈 포함)
const function latest(versions: { string }): string?
	local best, bestText = nil, nil
	for _, text in versions do
		const version = Semver.parse(text)
		if version and (not best or Semver.compare(version, best) > 0) then
			best, bestText = version, text
		end
	end
	return bestText
end

function Search.wally(query: string, options: Options): { Result }
	const author = if options.author and options.author ~= "" then string.lower(options.author) else nil
	-- scope 만 적고 검색어가 비면 scope 로 검색
	const text = if query ~= "" then query else (author or "")
	if text == "" then
		error(L("검색어를 입력해주세요", "Enter a search word"), 0)
	end
	const data = Http.getJson(
		`{WALLY_API}/v1/package-search?query={HttpService:UrlEncode(text)}`,
		WALLY_HEADERS,
		true
	)
	const results: { Result } = {}
	for _, item in if type(data) == "table" then data else {} do
		if type(item) == "table" and type(item.scope) == "string" and type(item.name) == "string" then
			if not author or string.lower(item.scope) == author then
				const version = latest(item.versions or {}) or "?"
				table.insert(results, {
					source = "wally",
					id = `{item.scope}/{item.name}`,
					detail = version,
					description = if type(item.description) == "string" then item.description else "",
					spec = if version ~= "?" then `{item.scope}/{item.name}@{version}` else `{item.scope}/{item.name}`,
				})
			end
		end
		if #results >= (options.limit or DEFAULT_LIMIT) then
			break
		end
	end
	return results
end

-- pesde: Roblox 용 target (roblox / roblox_server) 이 있는 패키지만
function Search.pesde(query: string, options: Options): { Result }
	const author = if options.author and options.author ~= "" then string.lower(options.author) else nil
	const text = if query ~= "" then query else (author or "")
	if text == "" then
		error(L("검색어를 입력해주세요", "Enter a search word"), 0)
	end
	const data = Http.getJson(`{Pesde.API}/search?query={HttpService:UrlEncode(text)}`, nil, true)
	const results: { Result } = {}
	for _, item in if type(data) == "table" and type(data.data) == "table" then data.data else {} do
		if type(item) == "table" and type(item.name) == "string" then
			local roblox = false
			for _, target in if type(item.targets) == "table" then item.targets else {} do
				if target.kind == "roblox" or target.kind == "roblox_server" then
					roblox = true
				end
			end
			const scope = string.match(item.name, "^([^/]+)/")
			if roblox and (not author or string.lower(scope or "") == author) then
				const version = if type(item.version) == "string" then item.version else "?"
				table.insert(results, {
					source = "pesde",
					id = item.name,
					detail = version,
					description = if type(item.description) == "string" then item.description else "",
					spec = if version ~= "?" then `pesde:{item.name}@{version}` else `pesde:{item.name}`,
				})
			end
		end
		if #results >= (options.limit or DEFAULT_LIMIT) then
			break
		end
	end
	return results
end

function Search.github(query: string, options: Options): { Result }
	const parts = {}
	if query ~= "" then
		table.insert(parts, query)
	end
	if options.author and options.author ~= "" then
		table.insert(parts, `user:{options.author}`)
	end
	if options.luauOnly then
		table.insert(parts, "language:Luau")
	end
	if #parts == 0 then
		error(L("검색어를 입력해주세요", "Enter a search word"), 0)
	end
	const limit = math.clamp(options.limit or DEFAULT_LIMIT, 1, 100)
	const data = Http.getJson(
		`{GITHUB_API}/search/repositories?q={HttpService:UrlEncode(table.concat(parts, " "))}&per_page={limit}`,
		Auth.githubHeaders(),
		true
	)
	const results: { Result } = {}
	for _, item in if type(data) == "table" and type(data.items) == "table" then data.items else {} do
		if type(item.full_name) == "string" then
			table.insert(results, {
				source = "github",
				id = item.full_name,
				detail = `★{item.stargazers_count or 0}`,
				description = if type(item.description) == "string" then item.description else "",
				spec = `gh:{item.full_name}`,
			})
		end
	end
	return results
end

return Search
