-- wally.toml 을 읽기 위한 최소 TOML 파서
-- 지원: [테이블], [a.b], key = "문자열" | '문자열' | 숫자 | bool | [배열] | { 인라인 테이블 }, 주석

const Toml = {}

const function skipSpace(text: string, pos: number): number
	while true do
		const s = string.match(text, "^[ \t\r\n]+", pos)
		if s then
			pos += #s
		elseif string.sub(text, pos, pos) == "#" then
			pos = (string.find(text, "\n", pos, true) or #text) + 1
		else
			return pos
		end
	end
end

local parseValue: (text: string, pos: number) -> (any, number)

const function parseString(text: string, pos: number): (string, number)
	const quote = string.sub(text, pos, pos)
	if quote == "'" then
		const close = string.find(text, "'", pos + 1, true)
		if not close then
			error("Toml: 닫히지 않은 문자열")
		end
		return string.sub(text, pos + 1, close - 1), close + 1
	end

	const parts = {}
	local i = pos + 1
	while i <= #text do
		const c = string.sub(text, i, i)
		if c == '"' then
			return table.concat(parts), i + 1
		elseif c == "\\" then
			const nextChar = string.sub(text, i + 1, i + 1)
			const escapes = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\" }
			table.insert(parts, escapes[nextChar] or nextChar)
			i += 2
		else
			table.insert(parts, c)
			i += 1
		end
	end
	error("Toml: 닫히지 않은 문자열")
end

const function parseKey(text: string, pos: number): ({ string }, number)
	const keys = {}
	while true do
		pos = skipSpace(text, pos)
		const c = string.sub(text, pos, pos)
		if c == '"' or c == "'" then
			const key, nextPos = parseString(text, pos)
			table.insert(keys, key)
			pos = nextPos
		else
			const key = string.match(text, "^[%w_%-]+", pos)
			if not key then
				error(`Toml: 키를 읽을 수 없음 (위치 {pos})`)
			end
			table.insert(keys, key)
			pos += #key
		end
		pos = skipSpace(text, pos)
		if string.sub(text, pos, pos) ~= "." then
			return keys, pos
		end
		pos += 1
	end
end

const function setPath(root: { [string]: any }, keys: { string }, value: any)
	local node = root
	for i = 1, #keys - 1 do
		node[keys[i]] = node[keys[i]] or {}
		node = node[keys[i]]
	end
	node[keys[#keys]] = value
end

parseValue = function(text: string, pos: number): (any, number)
	pos = skipSpace(text, pos)
	const c = string.sub(text, pos, pos)
	if c == '"' or c == "'" then
		return parseString(text, pos)
	elseif c == "[" then
		const list = {}
		pos += 1
		while true do
			pos = skipSpace(text, pos)
			if string.sub(text, pos, pos) == "]" then
				return list, pos + 1
			end
			const value, nextPos = parseValue(text, pos)
			table.insert(list, value)
			pos = skipSpace(text, nextPos)
			if string.sub(text, pos, pos) == "," then
				pos += 1
			end
		end
	elseif c == "{" then
		const tbl = {}
		pos += 1
		while true do
			pos = skipSpace(text, pos)
			if string.sub(text, pos, pos) == "}" then
				return tbl, pos + 1
			end
			const keys, afterKey = parseKey(text, pos)
			pos = skipSpace(text, afterKey)
			if string.sub(text, pos, pos) ~= "=" then
				error("Toml: '=' 가 필요함")
			end
			const value, nextPos = parseValue(text, pos + 1)
			setPath(tbl, keys, value)
			pos = skipSpace(text, nextPos)
			if string.sub(text, pos, pos) == "," then
				pos += 1
			end
		end
	elseif string.sub(text, pos, pos + 3) == "true" then
		return true, pos + 4
	elseif string.sub(text, pos, pos + 4) == "false" then
		return false, pos + 5
	else
		const num = string.match(text, "^[%+%-]?[%d_%.eE%+%-]+", pos)
		if num then
			return tonumber((string.gsub(num, "_", ""))), pos + #num
		end
		error(`Toml: 값을 읽을 수 없음 (위치 {pos})`)
	end
end

function Toml.decode(text: string): { [string]: any }
	const root = {}
	local current = root
	local pos = 1

	while true do
		pos = skipSpace(text, pos)
		if pos > #text then
			return root
		end

		if string.sub(text, pos, pos) == "[" then
			const isArray = string.sub(text, pos, pos + 1) == "[["
			const keys, afterKey = parseKey(text, pos + (if isArray then 2 else 1))
			pos = skipSpace(text, afterKey)
			pos += if isArray then 2 else 1

			local node = root
			for i = 1, #keys - 1 do
				node[keys[i]] = node[keys[i]] or {}
				node = node[keys[i]]
			end
			const last = keys[#keys]
			if isArray then
				node[last] = node[last] or {}
				const item = {}
				table.insert(node[last], item)
				current = item
			else
				node[last] = node[last] or {}
				current = node[last]
			end
		else
			const keys, afterKey = parseKey(text, pos)
			pos = skipSpace(text, afterKey)
			if string.sub(text, pos, pos) ~= "=" then
				error(`Toml: '=' 가 필요함 (위치 {pos})`)
			end
			const value, nextPos = parseValue(text, pos + 1)
			setPath(current, keys, value)
			pos = nextPos
		end
	end
end

return Toml
