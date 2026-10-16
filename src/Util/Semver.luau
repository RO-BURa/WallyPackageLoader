-- 시맨틱 버전과 Cargo/Wally 스타일 버전 범위
-- 범위 문법: "1.2.3"(= ^1.2.3), "^1.2", "~1.2.3", "=1.2.3", ">=1.0, <2.0", "1.*", "*"

export type Version = {
	major: number,
	minor: number,
	patch: number,
	prerelease: { string | number },
}

type Comparator = {
	op: string,
	version: Version,
}

const Semver = {}

const function parsePrerelease(text: string?): { string | number }
	const result = {}
	if text and text ~= "" then
		for _, part in string.split(text, ".") do
			table.insert(result, if string.match(part, "^%d+$") then tonumber(part) :: number else part)
		end
	end
	return result
end

function Semver.parse(text: string): Version?
	const cleaned = string.gsub(string.gsub(text, "^%s*[vV]?", ""), "%s*$", "")
	const major, minor, patch, rest = string.match(cleaned, "^(%d+)%.(%d+)%.(%d+)(.*)$")
	if not major then
		return nil
	end
	-- 빌드 메타데이터(+...)는 무시
	const prerelease = string.match(rest, "^%-([%w%.%-]+)")
	if rest ~= "" and not prerelease and string.sub(rest, 1, 1) ~= "+" then
		return nil
	end
	return {
		major = tonumber(major) :: number,
		minor = tonumber(minor) :: number,
		patch = tonumber(patch) :: number,
		prerelease = parsePrerelease(prerelease),
	}
end

function Semver.toString(v: Version): string
	local text = `{v.major}.{v.minor}.{v.patch}`
	if #v.prerelease > 0 then
		const parts = {}
		for _, p in v.prerelease do
			table.insert(parts, tostring(p))
		end
		text ..= "-" .. table.concat(parts, ".")
	end
	return text
end

-- a < b 이면 음수, 같으면 0, a > b 이면 양수
function Semver.compare(a: Version, b: Version): number
	if a.major ~= b.major then
		return a.major - b.major
	elseif a.minor ~= b.minor then
		return a.minor - b.minor
	elseif a.patch ~= b.patch then
		return a.patch - b.patch
	end

	const pa, pb = a.prerelease, b.prerelease
	if #pa == 0 and #pb == 0 then
		return 0
	elseif #pa == 0 then
		return 1
	elseif #pb == 0 then
		return -1
	end

	for i = 1, math.max(#pa, #pb) do
		const x, y = pa[i], pb[i]
		if x == nil then
			return -1
		elseif y == nil then
			return 1
		elseif x ~= y then
			const xNum, yNum = type(x) == "number", type(y) == "number"
			if xNum and yNum then
				return (x :: number) - (y :: number)
			elseif xNum then
				return -1
			elseif yNum then
				return 1
			else
				return if (x :: string) < (y :: string) then -1 else 1
			end
		end
	end
	return 0
end

const function makeVersion(major: number, minor: number, patch: number): Version
	return { major = major, minor = minor, patch = patch, prerelease = {} }
end

-- 비교자 하나("^1.2", ">=1.0.0", "1.*" 등)를 하한/상한 비교자 목록으로 바꿈
const function expandComparator(text: string, out: { Comparator })
	const op, body = string.match(text, "^([%^~=<>]*)%s*(.-)$")
	if body == "" or body == "*" then
		return
	end

	const parts = string.split((string.gsub(body, "%-.*$", "")), ".")
	const prerelease = string.match(body, "%-([%w%.%-]+)$")
	const nums = {}
	for i = 1, 3 do
		const part = parts[i]
		if part == nil or part == "*" or part == "x" or part == "X" then
			break
		end
		const n = tonumber(part)
		if not n then
			error(`Semver: 잘못된 버전 범위 '{text}'`)
		end
		nums[i] = n
	end
	if #nums == 0 then
		return
	end

	const major, minor, patch = nums[1], nums[2] or 0, nums[3] or 0
	const base = makeVersion(major, minor, patch)
	base.prerelease = parsePrerelease(prerelease)

	-- 와일드카드나 생략된 자리가 있으면 그 자리만 고정
	const partial = #nums < 3
	const effectiveOp = if op == "" then (if partial then "=" else "^") else op

	if effectiveOp == "^" then
		table.insert(out, { op = ">=", version = base })
		local upper
		if major > 0 or #nums == 1 then
			upper = makeVersion(major + 1, 0, 0)
		elseif minor > 0 or #nums == 2 then
			upper = makeVersion(0, minor + 1, 0)
		else
			upper = makeVersion(0, 0, patch + 1)
		end
		table.insert(out, { op = "<", version = upper })
	elseif effectiveOp == "~" then
		table.insert(out, { op = ">=", version = base })
		table.insert(out, {
			op = "<",
			version = if #nums == 1 then makeVersion(major + 1, 0, 0) else makeVersion(major, minor + 1, 0),
		})
	elseif effectiveOp == "=" then
		if partial then
			table.insert(out, { op = ">=", version = base })
			table.insert(out, {
				op = "<",
				version = if #nums == 1 then makeVersion(major + 1, 0, 0) else makeVersion(major, minor + 1, 0),
			})
		else
			table.insert(out, { op = "=", version = base })
		end
	elseif effectiveOp == ">" and partial then
		-- ">1.2" 는 1.2.x 전체보다 큼
		table.insert(out, {
			op = ">=",
			version = if #nums == 1 then makeVersion(major + 1, 0, 0) else makeVersion(major, minor + 1, 0),
		})
	elseif effectiveOp == "<=" and partial then
		table.insert(out, {
			op = "<",
			version = if #nums == 1 then makeVersion(major + 1, 0, 0) else makeVersion(major, minor + 1, 0),
		})
	elseif effectiveOp == ">" or effectiveOp == ">=" or effectiveOp == "<" or effectiveOp == "<=" then
		table.insert(out, { op = effectiveOp, version = base })
	else
		error(`Semver: 알 수 없는 연산자 '{op}'`)
	end
end

export type Range = {
	comparators: { Comparator },
	allowPrerelease: boolean,
}

function Semver.parseRange(text: string?): Range
	const comparators = {}
	const source = text or "*"
	for _, piece in string.split(source, ",") do
		const trimmed = string.match(piece, "^%s*(.-)%s*$") :: string
		if trimmed ~= "" then
			expandComparator(trimmed, comparators)
		end
	end
	return {
		comparators = comparators,
		allowPrerelease = string.find(source, "-", 1, true) ~= nil,
	}
end

function Semver.satisfies(range: Range, v: Version): boolean
	if #v.prerelease > 0 and not range.allowPrerelease then
		return false
	end
	for _, c in range.comparators do
		const cmp = Semver.compare(v, c.version)
		const ok = if c.op == "=" then cmp == 0
			elseif c.op == ">" then cmp > 0
			elseif c.op == ">=" then cmp >= 0
			elseif c.op == "<" then cmp < 0
			else cmp <= 0
		if not ok then
			return false
		end
	end
	return true
end

-- 후보 중 범위를 만족하는 가장 높은 버전의 인덱스
function Semver.pickHighest(range: Range, candidates: { Version }): number?
	local best: number? = nil
	for i, v in candidates do
		if Semver.satisfies(range, v) and (best == nil or Semver.compare(v, candidates[best :: number]) > 0) then
			best = i
		end
	end
	return best
end

return Semver
