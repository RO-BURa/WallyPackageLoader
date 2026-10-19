--!native
-- DEFLATE (RFC 1951) 해제기
-- zzlib.luau (https://github.com/xhayper/zzlib.luau, WTFPL) 의 구조를 바탕으로
-- 출력을 buffer 로 쓰도록 다시 작성함

const band = bit32.band
const bxor = bit32.bxor
const lshift = bit32.lshift
const rshift = bit32.rshift

const Inflate = {}

const CODE_LENGTH_ORDER = { 17, 18, 19, 1, 9, 8, 10, 7, 11, 6, 12, 5, 13, 4, 14, 3, 15, 2, 16 }

-- depths[i] = (i - 1) 번 심볼의 코드 길이
-- 반환: (비트를 뒤집은 코드 -> 심볼 * 16 + 길이) 테이블, 최대 비트 수
const function buildHuffman(depths: { number }, count: number): ({ [number]: number }, number)
	local nbits = 1
	const blCount = {}
	for i = 1, count do
		const d = depths[i] or 0
		if d > nbits then
			nbits = d
		end
		blCount[d] = (blCount[d] or 0) + 1
	end

	const nextCode = {}
	local code = 0
	blCount[0] = 0
	for i = 1, nbits do
		code = (code + (blCount[i - 1] or 0)) * 2
		nextCode[i] = code
	end

	const huff = {}
	for i = 1, count do
		const len = depths[i] or 0
		if len > 0 then
			const entry = (i - 1) * 16 + len
			const c = nextCode[len]
			local reversed = 0
			for j = 1, len do
				reversed += lshift(band(1, rshift(c, j - 1)), len - j)
			end
			for j = 0, 2 ^ nbits - 1, 2 ^ len do
				huff[j + reversed] = entry
			end
			nextCode[len] += 1
		end
	end

	return huff, nbits
end

local staticLit, staticLitBits, staticDist, staticDistBits

const function getStaticTables()
	if not staticLit then
		const depths = {}
		for i = 1, 144 do
			depths[i] = 8
		end
		for i = 145, 256 do
			depths[i] = 9
		end
		for i = 257, 280 do
			depths[i] = 7
		end
		for i = 281, 288 do
			depths[i] = 8
		end
		staticLit, staticLitBits = buildHuffman(depths, 288)

		const distDepths = {}
		for i = 1, 32 do
			distDepths[i] = 5
		end
		staticDist, staticDistBits = buildHuffman(distDepths, 32)
	end
	return staticLit, staticLitBits, staticDist, staticDistBits
end

-- data 의 startPos(1부터 시작) 위치에서 raw deflate 스트림을 풀어 문자열로 반환
-- sizeHint 를 알면(zip 의 원본 크기) 버퍼를 한 번에 잡음
function Inflate.raw(data: string, startPos: number?, sizeHint: number?): string
	local pos = startPos or 1
	local bitBuf = 0
	local bitCount = 0

	local out = buffer.create(math.max(sizeHint or 0, 256))
	local outLen = 0

	const function ensure(extra: number)
		const needed = outLen + extra
		if needed > buffer.len(out) then
			const grown = buffer.create(math.max(buffer.len(out) * 2, needed))
			buffer.copy(grown, 0, out, 0, outLen)
			out = grown
		end
	end

	const function fill(n: number)
		while bitCount < n do
			bitBuf += lshift(string.byte(data, pos) or 0, bitCount)
			pos += 1
			bitCount += 8
		end
	end

	const function getBits(n: number): number
		if n == 0 then
			return 0
		end
		fill(n)
		const value = band(bitBuf, lshift(1, n) - 1)
		bitBuf = rshift(bitBuf, n)
		bitCount -= n
		return value
	end

	const function decode(huff: { [number]: number }, nbits: number): number
		fill(nbits)
		const entry = huff[band(bitBuf, lshift(1, nbits) - 1)]
		if not entry then
			error("Inflate: invalid Huffman code")
		end
		const len = band(entry, 15)
		bitBuf = rshift(bitBuf, len)
		bitCount -= len
		return rshift(entry, 4)
	end

	const function blockLoop(lit: { [number]: number }, litBits: number, dist: { [number]: number }, distBits: number)
		while true do
			const symbol = decode(lit, litBits)
			if symbol < 256 then
				ensure(1)
				buffer.writeu8(out, outLen, symbol)
				outLen += 1
			elseif symbol == 256 then
				return
			else
				local extraBits = 0
				local size = 3
				if symbol < 265 then
					size += symbol - 257
				elseif symbol < 285 then
					extraBits = rshift(symbol - 261, 2)
					size += lshift(band(symbol - 261, 3) + 4, extraBits)
				else
					size = 258
				end
				size += getBits(extraBits)

				const v = decode(dist, distBits)
				local distance = 1
				if v < 4 then
					distance += v
				else
					const distExtra = rshift(v - 2, 1)
					distance += lshift(band(v, 1) + 2, distExtra)
					distance += getBits(distExtra)
				end
				if distance > outLen then
					error("Inflate: distance out of range")
				end

				ensure(size)
				local from = outLen - distance
				for _ = 1, size do
					buffer.writeu8(out, outLen, buffer.readu8(out, from))
					outLen += 1
					from += 1
				end
			end
		end
	end

	const function blockDynamic()
		const hlit = 257 + getBits(5)
		const hdist = 1 + getBits(5)
		const hclen = 4 + getBits(4)

		const lengthDepths = {}
		for i = 1, 19 do
			lengthDepths[i] = 0
		end
		for i = 1, hclen do
			lengthDepths[CODE_LENGTH_ORDER[i]] = getBits(3)
		end
		const lengthHuff, lengthBits = buildHuffman(lengthDepths, 19)

		const depths = {}
		local i = 1
		while i <= hlit + hdist do
			const v = decode(lengthHuff, lengthBits)
			if v < 16 then
				depths[i] = v
				i += 1
			elseif v < 19 then
				local repeatValue = 0
				local repeatCount
				if v == 16 then
					if i == 1 then
						error("Inflate: no previous length to repeat")
					end
					repeatValue = depths[i - 1]
					repeatCount = 3 + getBits(2)
				elseif v == 17 then
					repeatCount = 3 + getBits(3)
				else
					repeatCount = 11 + getBits(7)
				end
				for _ = 1, repeatCount do
					depths[i] = repeatValue
					i += 1
				end
			else
				error(`Inflate: invalid length code {v}`)
			end
		end

		const litDepths = table.move(depths, 1, hlit, 1, {})
		const distDepths = table.move(depths, hlit + 1, hlit + hdist, 1, {})
		const litHuff, litBits = buildHuffman(litDepths, hlit)
		const distHuff, distBits = buildHuffman(distDepths, hdist)
		blockLoop(litHuff, litBits, distHuff, distBits)
	end

	const function blockStored()
		-- 바이트 경계로 맞춤
		const drop = bitCount % 8
		bitBuf = rshift(bitBuf, drop)
		bitCount -= drop

		const len = getBits(16)
		const nlen = getBits(16)
		if bxor(len, nlen) ~= 0xFFFF then
			error("Inflate: LEN/NLEN mismatch")
		end
		-- 이 시점에서 bitCount 는 항상 0
		ensure(len)
		buffer.writestring(out, outLen, string.sub(data, pos, pos + len - 1))
		outLen += len
		pos += len
	end

	repeat
		const last = getBits(1)
		const blockType = getBits(2)
		if blockType == 0 then
			blockStored()
		elseif blockType == 1 then
			blockLoop(getStaticTables())
		elseif blockType == 2 then
			blockDynamic()
		else
			error("Inflate: unsupported block type")
		end
	until last == 1

	return buffer.readstring(out, 0, outLen)
end

-- gzip(.gz) 해제
function Inflate.gunzip(data: string): string
	const id1, id2, method, flags = string.byte(data, 1, 4)
	if id1 ~= 31 or id2 ~= 139 then
		error("Inflate: not a gzip header")
	end
	if method ~= 8 then
		error("Inflate: gzip that is not deflate")
	end

	local pos = 11
	if band(flags, 4) ~= 0 then
		const xlen = string.unpack("<I2", data, pos)
		pos += 2 + xlen
	end
	if band(flags, 8) ~= 0 then
		pos = (string.find(data, "\0", pos, true) or pos) + 1
	end
	if band(flags, 16) ~= 0 then
		pos = (string.find(data, "\0", pos, true) or pos) + 1
	end
	if band(flags, 2) ~= 0 then
		pos += 2
	end

	const sizeHint = string.unpack("<I4", data, #data - 3)
	return Inflate.raw(data, pos, sizeHint)
end

return Inflate
