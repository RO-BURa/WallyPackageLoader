-- 간단한 Luau 토크나이저 (주석/문자열 건너뛰기용)
-- TypeExports, ConfigEditor 에서 사용

export type Token = {
	kind: "name" | "symbol" | "string",
	text: string,
	first: number,
	last: number,
}

const Lexer = {}

-- [[ ]] / [==[ ]==] 형태의 긴 괄호 끝 위치
const function skipLongBracket(source: string, pos: number): number?
	const level = string.match(source, "^%[(=*)%[", pos)
	if not level then
		return nil
	end
	const close = string.find(source, "]" .. level .. "]", pos, true)
	return if close then close + #level + 1 else #source
end

const function skipQuoted(source: string, pos: number, quote: string): number
	local i = pos + 1
	while i <= #source do
		const c = string.sub(source, i, i)
		if c == "\\" then
			i += 2
		elseif c == quote then
			return i
		elseif c == "\n" and quote ~= "`" then
			return i - 1
		else
			i += 1
		end
	end
	return #source
end

-- 주석은 버리고 문자열은 토큰 하나로 묶음
function Lexer.tokenize(source: string): { Token }
	const tokens: { Token } = {}
	local pos = 1
	const len = #source

	while pos <= len do
		const c = string.sub(source, pos, pos)

		if string.find(c, "^%s") then
			pos += 1
		elseif string.sub(source, pos, pos + 1) == "--" then
			const longEnd = skipLongBracket(source, pos + 2)
			if longEnd then
				pos = longEnd + 1
			else
				pos = (string.find(source, "\n", pos, true) or len) + 1
			end
		elseif c == '"' or c == "'" or c == "`" then
			const last = skipQuoted(source, pos, c)
			table.insert(tokens, { kind = "string", text = string.sub(source, pos, last), first = pos, last = last })
			pos = last + 1
		elseif c == "[" and skipLongBracket(source, pos) then
			const last = skipLongBracket(source, pos) :: number
			table.insert(tokens, { kind = "string", text = string.sub(source, pos, last), first = pos, last = last })
			pos = last + 1
		elseif string.find(c, "^[%a_]") then
			const name = string.match(source, "^[%w_]+", pos) :: string
			table.insert(tokens, { kind = "name", text = name, first = pos, last = pos + #name - 1 })
			pos += #name
		elseif string.find(c, "^%d") then
			const num = string.match(source, "^[%w_%.]+", pos) :: string
			table.insert(tokens, { kind = "name", text = num, first = pos, last = pos + #num - 1 })
			pos += #num
		else
			-- 제네릭 안에서 의미 있는 두/세 글자 기호만 묶음
			const three = string.sub(source, pos, pos + 2)
			const two = string.sub(source, pos, pos + 1)
			const text = if three == "..." then three elseif two == "->" then two else c
			table.insert(tokens, { kind = "symbol", text = text, first = pos, last = pos + #text - 1 })
			pos += #text
		end
	end

	return tokens
end

return Lexer
