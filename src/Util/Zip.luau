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
	error("Zip: not a zip file (no End of Central Directory)")
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
			error("Zip: invalid central directory entry")
		end
		const localOffset = string.unpack("<I4", data, cursor + 42)
		const name = string.sub(data, cursor + 46, cursor + 45 + nameLen)
		cursor += 46 + nameLen + extraLen + commentLen

		if string.sub(name, -1) ~= "/" then
			const localPos = localOffset + 1
			if string.unpack("<I4", data, localPos) ~= LOCAL_SIGNATURE then
				error(`Zip: invalid local header ({name})`)
			end
			const localNameLen, localExtraLen = string.unpack("<I2 I2", data, localPos + 26)
			const dataPos = localPos + 30 + localNameLen + localExtraLen

			if method == 0 then
				files[name] = string.sub(data, dataPos, dataPos + compressedSize - 1)
			elseif method == 8 then
				files[name] = Inflate.raw(data, dataPos, size)
			else
				error(`Zip: unsupported compression method {method} ({name})`)
			end
		end
	end

	return files
end

-- CRC-32 (zip 용)
local crcTable: { number }? = nil
const function crc32(data: string): number
	if not crcTable then
		const t = {}
		for i = 0, 255 do
			local c = i
			for _ = 1, 8 do
				c = if bit32.band(c, 1) == 1 then bit32.bxor(0xEDB88320, bit32.rshift(c, 1)) else bit32.rshift(c, 1)
			end
			t[i] = c
		end
		crcTable = t
	end
	const t = crcTable :: { number }
	local crc = 0xFFFFFFFF
	for i = 1, #data do
		crc = bit32.bxor(t[bit32.band(bit32.bxor(crc, string.byte(data, i)), 0xFF)], bit32.rshift(crc, 8))
	end
	return bit32.bnot(crc)
end
Zip.crc32 = crc32

-- 파일들로 zip 만들기 (압축 없이 저장). paths 순서대로 넣음
function Zip.create(files: { [string]: string }, paths: { string }?): string
	const order = paths or (function()
		const list = {}
		for path in files do
			table.insert(list, path)
		end
		table.sort(list)
		return list
	end)()

	const parts = {}
	const central = {}
	local offset = 0
	for _, path in order do
		const content = files[path]
		const crc = crc32(content)
		const localHeader = string.pack("<I4 I2 I2 I2 I2 I2 I4 I4 I4 I2 I2", 0x04034b50, 20, 0x0800, 0, 0, 0x21, crc, #content, #content, #path, 0)
		table.insert(parts, localHeader)
		table.insert(parts, path)
		table.insert(parts, content)
		table.insert(
			central,
			string.pack("<I4 I2 I2 I2 I2 I2 I2 I4 I4 I4 I2 I2 I2 I2 I2 I4 I4", 0x02014b50, 20, 20, 0x0800, 0, 0, 0x21, crc, #content, #content, #path, 0, 0, 0, 0, 0, offset)
				.. path
		)
		offset += #localHeader + #path + #content
	end

	const centralData = table.concat(central)
	table.insert(parts, centralData)
	table.insert(parts, string.pack("<I4 I2 I2 I2 I2 I4 I4 I2", 0x06054b50, 0, 0, #order, #order, #centralData, offset, 0))
	return table.concat(parts)
end

return Zip
