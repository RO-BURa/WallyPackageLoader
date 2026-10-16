-- `return { ... }` 형태의 Luau 소스를 주석/순서/들여쓰기를 유지한 채 고침
-- 파일 전체를 다시 쓰지 않고 바뀌는 부분만 끼워 넣거나 지움
-- 구조를 알아볼 수 없으면 error (호출하는 쪽에서 전체 다시 쓰기로 대체)

const Lexer = require(script.Parent.Lexer)

type Token = Lexer.Token

type Field = {
	-- 이름 키나 ["문자열"] / [숫자] 키. 위치 기반 값이면 nil
	key: string?,
	firstToken: number,
	valueFirst: number,
	valueLast: number,
	separator: number?,
	node: Node?,
}

export type Node = {
	open: number,
	close: number,
	fields: { Field },
}

const ConfigEditor = {}

const OPENERS = { ["{"] = true, ["("] = true, ["["] = true }
const CLOSERS = { ["}"] = true, [")"] = true, ["]"] = true }

const function isSymbol(token: Token?, text: string): boolean
	return token ~= nil and token.kind == "symbol" and token.text == text
end

-- "abc" / 'abc' 토큰을 실제 문자열로
const function decodeString(text: string): string?
	const quote = string.sub(text, 1, 1)
	if quote ~= '"' and quote ~= "'" then
		return nil
	end
	const escapes = { n = "\n", t = "\t", r = "\r", ["\\"] = "\\", ['"'] = '"', ["'"] = "'" }
	return (string.gsub(string.sub(text, 2, -2), "\\(.)", function(c)
		return escapes[c] or c
	end))
end

local parseTable: (tokens: { Token }, open: number) -> Node

-- 값 하나의 끝 토큰 인덱스 (구분자/닫는 괄호 직전)
const function scanValue(tokens: { Token }, first: number): number
	local depth = 0
	local i = first
	while i <= #tokens do
		const token = tokens[i]
		if token.kind == "symbol" then
			if OPENERS[token.text] then
				depth += 1
			elseif CLOSERS[token.text] then
				if depth == 0 then
					return i - 1
				end
				depth -= 1
			elseif depth == 0 and (token.text == "," or token.text == ";") then
				return i - 1
			end
		end
		i += 1
	end
	error("ConfigEditor: 테이블이 닫히지 않음", 0)
end

parseTable = function(tokens: { Token }, open: number): Node
	const fields: { Field } = {}
	local i = open + 1

	while true do
		const token = tokens[i]
		if token == nil then
			error("ConfigEditor: 테이블이 닫히지 않음", 0)
		end
		if isSymbol(token, "}") then
			return { open = open, close = i, fields = fields }
		end

		local key: string? = nil
		local valueFirst = i
		if token.kind == "name" and isSymbol(tokens[i + 1], "=") then
			key = token.text
			valueFirst = i + 2
		elseif isSymbol(token, "[") and tokens[i + 1] and isSymbol(tokens[i + 2], "]") and isSymbol(tokens[i + 3], "=") then
			const keyToken = tokens[i + 1]
			key = if keyToken.kind == "string" then decodeString(keyToken.text) else keyToken.text
			valueFirst = i + 4
		end

		const valueLast = scanValue(tokens, valueFirst)
		if valueLast < valueFirst then
			error("ConfigEditor: 값이 비어 있음", 0)
		end

		local node: Node? = nil
		if isSymbol(tokens[valueFirst], "{") then
			const nested = parseTable(tokens, valueFirst)
			if nested.close == valueLast then
				node = nested
			end
		end

		local separator: number? = nil
		const after = tokens[valueLast + 1]
		if isSymbol(after, ",") or isSymbol(after, ";") then
			separator = valueLast + 1
		end

		table.insert(fields, {
			key = key,
			firstToken = i,
			valueFirst = valueFirst,
			valueLast = valueLast,
			separator = separator,
			node = node,
		})

		i = (separator or valueLast) + 1
	end
end

-- 마지막 `return {` 의 테이블
const function parseRoot(source: string): ({ Token }, Node)
	const tokens = Lexer.tokenize(source)
	for i = #tokens - 1, 1, -1 do
		if tokens[i].kind == "name" and tokens[i].text == "return" then
			if not isSymbol(tokens[i + 1], "{") then
				error("ConfigEditor: return 다음이 테이블 생성자가 아님", 0)
			end
			const root = parseTable(tokens, i + 1)
			if root.close ~= #tokens then
				error("ConfigEditor: return 테이블 뒤에 다른 코드가 있음", 0)
			end
			return tokens, root
		end
	end
	error("ConfigEditor: return 을 찾을 수 없음", 0)
end

const function findField(node: Node, key: string): Field?
	for _, field in node.fields do
		if field.key == key then
			return field
		end
	end
	return nil
end

const function lineStart(source: string, pos: number): number
	local i = pos
	while i > 1 and string.sub(source, i - 1, i - 1) ~= "\n" do
		i -= 1
	end
	return i
end

const function lineIndent(source: string, pos: number): string
	return string.match(source, "^[ \t]*", lineStart(source, pos)) :: string
end

-- pos 앞쪽이 그 줄의 공백뿐인지
const function startsLine(source: string, pos: number): boolean
	return string.match(string.sub(source, lineStart(source, pos), pos - 1), "^[ \t]*$") ~= nil
end

const function keyText(key: string): string
	if string.match(key, "^[%a_][%w_]*$") then
		return key
	end
	return `[{string.format("%q", key)}]`
end

const function splice(source: string, first: number, last: number, text: string): string
	return string.sub(source, 1, first - 1) .. text .. string.sub(source, last + 1)
end

-- segments[from] 필드에 들어갈 값: 남은 경로를 테이블로 감싸고 맨 안쪽에 key = value
const function nestedValue(segments: { string }, from: number, key: string, value: string, indent: string): string
	const inner = indent .. "\t"
	if from == #segments then
		return `\{\n{inner}{keyText(key)} = {value},\n{indent}}`
	end
	const body = nestedValue(segments, from + 1, key, value, inner)
	return `\{\n{inner}{keyText(segments[from + 1])} = {body},\n{indent}}`
end

-- node 에 key = value 필드를 추가 (value 는 fieldIndent 기준으로 만든 텍스트를 돌려주는 함수)
const function insertField(source: string, tokens: { Token }, node: Node, key: string, makeValue: (indent: string) -> string): string
	const openToken = tokens[node.open]
	const closeToken = tokens[node.close]
	const fields = node.fields
	const lastField = fields[#fields]

	const openIndent = lineIndent(source, openToken.first)
	local fieldIndent = openIndent .. "\t"
	if #fields > 0 and startsLine(source, tokens[fields[1].firstToken].first) then
		fieldIndent = lineIndent(source, tokens[fields[1].firstToken].first)
	end
	const entry = `{keyText(key)} = {makeValue(fieldIndent)}`

	const multiLine = string.find(string.sub(source, openToken.first, closeToken.first), "\n", 1, true) ~= nil

	if #fields == 0 then
		-- {} -> 여러 줄로 펼침
		const closeIndent = if multiLine and startsLine(source, closeToken.first)
			then lineIndent(source, closeToken.first)
			else openIndent
		return splice(source, openToken.first, closeToken.last, `\{\n{fieldIndent}{entry},\n{closeIndent}}`)
	end

	const lastEnd = tokens[lastField.separator or lastField.valueLast].last
	const comma = if lastField.separator then "" else ","

	if multiLine and startsLine(source, closeToken.first) then
		-- 닫는 } 줄 바로 앞에 한 줄 추가
		const at = lineStart(source, closeToken.first)
		local result = splice(source, at, at - 1, `{fieldIndent}{entry},\n`)
		if comma ~= "" then
			result = splice(result, lastEnd + 1, lastEnd, comma)
		end
		return result
	end

	-- 한 줄짜리 테이블: 마지막 필드 뒤에 이어 붙임
	return splice(source, lastEnd + 1, lastEnd, `{comma} {entry}`)
end

-- 경로를 따라 내려가며 테이블을 찾음. 없는 테이블은 만들어서 key = value 를 넣음
function ConfigEditor.set(source: string, path: { string }, key: string, value: string): string
	const tokens, root = parseRoot(source)
	local node = root
	for index, segment in path do
		const field = findField(node, segment)
		if not field then
			return insertField(source, tokens, node, segment, function(indent)
				return nestedValue(path, index, key, value, indent)
			end)
		end
		if not field.node then
			error(`ConfigEditor: '{segment}' 가 테이블이 아님`, 0)
		end
		node = field.node :: Node
	end

	const existing = findField(node, key)
	if existing then
		return splice(source, tokens[existing.valueFirst].first, tokens[existing.valueLast].last, value)
	end
	return insertField(source, tokens, node, key, function()
		return value
	end)
end

-- 필드를 지움. 그 필드가 줄 하나를 차지하면 줄째로 (같은 줄 뒤 주석 포함)
function ConfigEditor.remove(source: string, path: { string }, key: string): string
	const tokens, root = parseRoot(source)
	local node = root
	for _, segment in path do
		const field = findField(node, segment)
		if not field or not field.node then
			return source
		end
		node = field.node :: Node
	end

	const field = findField(node, key)
	if not field then
		return source
	end

	const first = tokens[field.firstToken].first
	const last = tokens[field.separator or field.valueLast].last
	const newline = string.find(source, "\n", last + 1, true)
	const rest = string.sub(source, last + 1, (newline or #source + 1) - 1)

	const isLineComment = string.match(rest, "^%s*%-%-") ~= nil and string.match(rest, "^%s*%-%-%[=*%[") == nil
	if startsLine(source, first) and (string.match(rest, "^%s*$") or isLineComment) then
		-- 다음 토큰이 같은 줄에 없을 때만 줄째로 지움
		const nextToken = tokens[(field.separator or field.valueLast) + 1]
		if not nextToken or not newline or nextToken.first > newline then
			return splice(source, lineStart(source, first), newline or #source, "")
		end
	end

	-- 같은 줄에 다른 것도 있으면 필드와 뒤 공백만 지움
	const trailing = string.match(source, "^[ \t]*", last + 1) :: string
	return splice(source, first, last + #trailing, "")
end

-- path 의 테이블이 비어 있는지 (없으면 nil)
function ConfigEditor.isEmpty(source: string, path: { string }): boolean?
	const _, root = parseRoot(source)
	local node = root
	for _, segment in path do
		const field = findField(node, segment)
		if not field or not field.node then
			return nil
		end
		node = field.node :: Node
	end
	return #node.fields == 0
end

return ConfigEditor
