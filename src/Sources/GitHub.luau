-- GitHub 저장소를 패키지로 (pesde 의 Git 기반 패키지 방식과 같은 방향)
--   gh:owner/repo           최신 semver 태그, 없으면 기본 브랜치
--   gh:owner/repo@^1.2      범위를 만족하는 가장 높은 태그 (v1.2.3 / 1.2.3)
--   gh:owner/repo#main      브랜치, 태그, 커밋

const Auth = require(script.Parent.Parent.Auth)
const Http = require(script.Parent.Parent.Http)
const Semver = require(script.Parent.Parent.Util.Semver)
const Vfs = require(script.Parent.Parent.Util.Vfs)
const Zip = require(script.Parent.Parent.Util.Zip)
const Manifest = require(script.Parent.Manifest)
const Types = require(script.Parent.Types)

type Package = Types.Package

const GitHub = {}

const API = "https://api.github.com"
const CODELOAD = "https://codeload.github.com"

-- 엔트리 폴더 이름에 쓸 수 없는 문자를 바꿈
const function sanitize(text: string): string
	return (string.gsub(text, "[^%w%.%-_+]", "-"))
end

function GitHub.listTags(owner: string, repo: string): { string }
	const names = {}
	-- 태그가 많은 저장소를 위해 최대 3 페이지
	for page = 1, 3 do
		const tags = Http.getJson(`{API}/repos/{owner}/{repo}/tags?per_page=100&page={page}`, Auth.githubHeaders())
		for _, tag in tags do
			table.insert(names, tag.name)
		end
		if #tags < 100 then
			break
		end
	end
	return names
end

function GitHub.resolve(owner: string, repo: string, rangeText: string?, ref: string?): Package
	local version: string
	local downloadRef: string

	if ref then
		version = sanitize(ref)
		downloadRef = ref
	else
		const tags = GitHub.listTags(owner, repo)
		const candidates, tagNames = {}, {}
		for _, tag in tags do
			const parsed = Semver.parse(tag)
			if parsed then
				table.insert(candidates, parsed)
				table.insert(tagNames, tag)
			end
		end

		const index = Semver.pickHighest(Semver.parseRange(rangeText), candidates)
		if index then
			version = Semver.toString(candidates[index])
			downloadRef = `refs/tags/{tagNames[index]}`
		elseif rangeText then
			error(`GitHub: {owner}/{repo}@{rangeText} 를 만족하는 태그가 없음`, 0)
		else
			const info = Http.getJson(`{API}/repos/{owner}/{repo}`, Auth.githubHeaders())
			version = sanitize(info.default_branch)
			downloadRef = `refs/heads/{info.default_branch}`
		end
	end

	-- 의존성을 알려면 manifest 가 필요해서 미리 받음
	const vfs = Vfs.new(Zip.extract(Http.get(`{CODELOAD}/{owner}/{repo}/zip/{downloadRef}`))):stripSingleRoot()
	const manifest = Manifest.read(vfs)

	return {
		source = "github",
		scope = string.lower(owner),
		name = string.lower(repo),
		displayName = repo,
		version = version,
		realm = if manifest then manifest.realm else "shared",
		dependencies = if manifest then manifest.dependencies else {},
		serverDependencies = if manifest then manifest.serverDependencies else {},
		entryPath = if manifest then manifest.entryPath else nil,
		fetch = function()
			return vfs
		end,
	}
end

return GitHub
