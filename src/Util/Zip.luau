-- zip 아카이브 읽기 (stored / deflate 만 지원, zip64·암호화 미지원)

const Inflate = require(script.Parent.Inflate)

const Zip = {}

const EOCD_SIGNATURE = "PK\5\6"
const CENTRAL_SIGNATURE = 0x02014b50
const LOCAL_SIGNATURE = 0x04034b50

const function findEndOfCentralDirectory(data: string): number
	-- EOCD 는 끝에서 22 바이트 + 최대 65535 바이트 주석 안쪽에 있음
	const minPos = math.max(1, #data - 22 - 0xFFFF)
	for pos = #data - 21, minPos, -1 do
		if string.sub(data, pos, pos + 3) == EOCD_SIGNATURE then
			return pos
		end
	end
	error("Zip: zip 파일이 아님 (End of Central Directory 없음)")
end

-- 반환: { [경로] = 내용 } (디렉터리 엔트리는 제외)
function Zip.extract(data: string): { [string]: string }
	const eocd = findEndOfCentralDirectory(data)
	const entryCount = string.unpack("<I2", data, eocd + 10)
	local cursor = string.unpack("<I4", data, eocd + 16) + 1

	const files = {}
	for _ = 1, entryCount do
		const signature, _, _, _, method, _, _, _, compressedSize, size, nameLen, extraLen, commentLen =
			string.unpack("<I4 I2 I2 I2 I2 I2 I2 I4 I4 I4 I2 I2 I2", data, cursor)
		if signature ~= CENTRAL_SIGNATURE then
			error("Zip: 잘못된 central directory 엔트리")
		end
		const localOffset = string.unpack("<I4", data, cursor + 42)
		const name = string.sub(data, cursor + 46, cursor + 45 + nameLen)
		cursor += 46 + nameLen + extraLen + commentLen

		if string.sub(name, -1) ~= "/" then
			const localPos = localOffset + 1
			if string.unpack("<I4", data, localPos) ~= LOCAL_SIGNATURE then
				error(`Zip: 잘못된 local header ({name})`)
			end
			const localNameLen, localExtraLen = string.unpack("<I2 I2", data, localPos + 26)
			const dataPos = localPos + 30 + localNameLen + localExtraLen

			if method == 0 then
				files[name] = string.sub(data, dataPos, dataPos + compressedSize - 1)
			elseif method == 8 then
				files[name] = Inflate.raw(data, dataPos, size)
			else
				error(`Zip: 지원하지 않는 압축 방식 {method} ({name})`)
			end
		end
	end

	return files
end

return Zip
