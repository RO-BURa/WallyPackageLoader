-- 모듈 소스에서 export type 선언을 찾아 thunk 용 re-export 줄을 만듦
-- pesde 의 linking/generator.rs (MIT) 로직을 Luau 로 옮김
--   export type Foo<T, U = string> = ...   ->  export type Foo<T, U = string> = module.Foo<T, U>
--   export type function Bar(a, b) ...     ->  export type Bar<a, b> = module.Bar<a, b>

const Lexer = require(script.Parent.Lexer)

type Token = Lexer.Token

const TypeExports = {}

const OPENERS = { ["<"] = true, ["("] = true, ["{"] = true, ["["] = true }
const CLOSERS = { [">"] = true, [")"] = true, ["}"] = true, ["]"] = true }

const function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

-- tokens[index] 가 "<" 일 때 제네릭 목록을 읽음
-- 반환: 선언용 목록, 사용용 목록(기본값 제거), 닫는 ">" 다음 인덱스
const function readGenerics(source: string, tokens: { Token }, index: number): ({ string }, { string }, number)
	const declaration = {}
	const usage = {}

	local depth = 0
	local paramStart: number? = nil
	local paramEquals: number? = nil
	local i = index + 1

	const function finishParam(endToken: Token)
		if paramStart == nil then
			return
		end
		const firstToken = tokens[paramStart :: number]
		table.insert(declaration, trim(string.sub(source, firstToken.first, endToken.last)))
		if paramEquals then
			const beforeEquals = tokens[(paramEquals :: number) - 1]
			table.insert(usage, trim(string.sub(source, firstToken.first, beforeEquals.last)))
		else
			table.insert(usage, trim(string.sub(source, firstToken.first, endToken.last)))
		end
		paramStart = nil
		paramEquals = nil
	end

	while i <= #tokens do
		const token = tokens[i]
		const text = token.text
		if token.kind == "symbol" and depth == 0 and (text == ">" or text == ",") then
			finishParam(tokens[i - 1])
			if text == ">" then
				return declaration, usage, i + 1
			end
		else
			if paramStart == nil then
				paramStart = i
			end
			if token.kind == "symbol" then
				if OPENERS[text] then
					depth += 1
				elseif CLOSERS[text] then
					depth -= 1
				elseif text == "=" and depth == 0 and paramEquals == nil then
					paramEquals = i
				end
			end
		end
		i += 1
	end

	return declaration, usage, i
end

-- type function 의 매개변수 이름 목록
const function readFunctionParams(tokens: { Token }, index: number): { string }
	const params = {}
	local depth = 0
	local expectName = true
	for i = index + 1, #tokens do
		const token = tokens[i]
		if token.kind == "symbol" then
			if OPENERS[token.text] then
				depth += 1
			elseif CLOSERS[token.text] then
				if depth == 0 then
					break
				end
				depth -= 1
			elseif token.text == "," and depth == 0 then
				expectName = true
			end
		elseif expectName and depth == 0 and token.kind == "name" then
			table.insert(params, token.text)
			expectName = false
		end
	end
	return params
end

-- 소스에서 re-export 줄 목록을 만듦. moduleName 은 thunk 안의 지역 변수 이름
function TypeExports.collect(source: string, moduleName: string?): { string }
	const target = moduleName or "module"
	const tokens = Lexer.tokenize(source)
	const lines = {}

	for i = 1, #tokens - 2 do
		const a, b = tokens[i], tokens[i + 1]
		if a.kind == "name" and a.text == "export" and b.kind == "name" and b.text == "type" then
			local nameIndex = i + 2
			local isFunction = false
			if tokens[nameIndex].text == "function" and tokens[nameIndex + 1] and tokens[nameIndex + 1].kind == "name" then
				isFunction = true
				nameIndex += 1
			end

			const nameToken = tokens[nameIndex]
			if nameToken and nameToken.kind == "name" then
				const name = nameToken.text
				const nextToken = tokens[nameIndex + 1]

				if isFunction then
					-- 매개변수 없는 type function 은 type 선언으로 re-export 할 수 없음
					if nextToken and nextToken.text == "(" then
						const params = readFunctionParams(tokens, nameIndex + 1)
						if #params > 0 then
							const list = table.concat(params, ", ")
							table.insert(lines, `export type {name}<{list}> = {target}.{name}<{list}>`)
						end
					end
				elseif nextToken and nextToken.text == "<" then
					const declaration, usage = readGenerics(source, tokens, nameIndex + 1)
					table.insert(
						lines,
						`export type {name}<{table.concat(declaration, ", ")}> = {target}.{name}<{table.concat(usage, ", ")}>`
					)
				else
					table.insert(lines, `export type {name} = {target}.{name}`)
				end
			end
		end
	end

	return lines
end

-- thunk 모듈 소스 생성
function TypeExports.thunk(requireExpression: string, moduleSource: string?): string
	const lines = { `local module = require({requireExpression})` }
	if moduleSource then
		for _, line in TypeExports.collect(moduleSource, "module") do
			table.insert(lines, line)
		end
	end
	table.insert(lines, "return module")
	return table.concat(lines, "\n") .. "\n"
end

return TypeExports
