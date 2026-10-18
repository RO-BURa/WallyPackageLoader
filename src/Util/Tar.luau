-- tar 읽기 (pesde 패키지가 .tar.gz 라서)
--   ustar (name + prefix), pax 확장 헤더의 path, GNU 긴 이름 (././@LongLink) 지원

const Tar = {}

const BLOCK = 512

const function cString(data: string, from: number, length: number): string
	const raw = string.sub(data, from, from + length - 1)
	return (string.match(raw, "^[^%z]*")) :: string
end

const function octal(data: string, from: number, length: number): number
	const text = string.match(cString(data, from, length), "^%s*([0-7]+)")
	return if text then tonumber(text, 8) :: number else 0
end

-- pax 레코드 ("길이 키=값\n" 반복) 에서 path
const function paxPath(body: string): string?
	local pos = 1
	while pos <= #body do
		const lengthText = string.match(body, "^(%d+) ", pos)
		if not lengthText then
			break
		end
		const length = tonumber(lengthText) :: number
		const record = string.sub(body, pos + #lengthText + 1, pos + length - 2)
		const key, value = string.match(record, "^([^=]+)=(.*)$")
		if key == "path" then
			return value
		end
		pos += length
	end
	return nil
end

-- 경로 -> 내용 (파일만, 앞의 ./ 는 뗌)
function Tar.extract(data: string): { [string]: string }
	const files: { [string]: string } = {}
	local pos = 1
	local nextName: string? = nil
	while pos + BLOCK - 1 <= #data do
		const header = string.sub(data, pos, pos + BLOCK - 1)
		if not string.find(header, "[^%z]") then
			break
		end
		local name = cString(header, 1, 100)
		const size = octal(header, 125, 12)
		const kind = string.sub(header, 157, 157)
		if string.sub(header, 258, 262) == "ustar" then
			const prefix = cString(header, 346, 155)
			if prefix ~= "" then
				name = prefix .. "/" .. name
			end
		end
		const bodyStart = pos + BLOCK
		const body = string.sub(data, bodyStart, bodyStart + size - 1)
		pos = bodyStart + math.ceil(size / BLOCK) * BLOCK

		if kind == "x" then
			nextName = paxPath(body)
		elseif kind == "L" then
			nextName = (string.match(body, "^[^%z]*"))
		elseif kind == "g" then
			-- 전체 pax 헤더: 무시
		else
			const path = string.gsub(nextName or name, "^%./", "")
			nextName = nil
			if (kind == "0" or kind == "\0" or kind == "7") and path ~= "" and string.sub(path, -1) ~= "/" then
				files[path] = body
			end
		end
	end
	return files
end

return Tar
