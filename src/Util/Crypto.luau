--!native
--!optimize 2
-- 비밀번호로 짧은 글자(토큰)를 암호화 / 복호화
--   키: PBKDF2-HMAC-SHA256 (비밀번호 + 무작위 salt, 반복 횟수는 저장값에 같이 기록)
--   암호화: HMAC-SHA256 카운터 모드 키스트림과 XOR
--   위변조 / 틀린 비밀번호 검사: HMAC-SHA256 태그
-- Roblox 에 암호화 API 가 없어서 SHA-256 하나로 전부 처리

const HttpService = game:GetService("HttpService")

export type Sealed = {
	v: number,
	iterations: number,
	salt: string,
	data: string,
	tag: string,
}

const Crypto = {}

const band, bor, bxor, bnot, rrotate, rshift = bit32.band, bit32.bor, bit32.bxor, bit32.bnot, bit32.rrotate, bit32.rshift
const MOD = 4294967296

const K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
const IV = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }

const W = table.create(64, 0)

-- 64바이트 블록 하나 (w[1..16] 은 32비트 단어) 를 상태 H 에 반영
const function compress(H: { number }, w: { number })
	for i = 1, 16 do
		W[i] = w[i]
	end
	for i = 17, 64 do
		const x, y = W[i - 15], W[i - 2]
		const s0 = bxor(rrotate(x, 7), rrotate(x, 18), rshift(x, 3))
		const s1 = bxor(rrotate(y, 17), rrotate(y, 19), rshift(y, 10))
		W[i] = (W[i - 16] + s0 + W[i - 7] + s1) % MOD
	end
	local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
	for i = 1, 64 do
		const S1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
		const ch = bxor(band(e, f), band(bnot(e), g))
		const t1 = h + S1 + ch + K[i] + W[i]
		const S0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
		const maj = bxor(band(a, b), band(a, c), band(b, c))
		h, g, f, e, d, c, b, a = g, f, e, (d + t1) % MOD, c, b, a, (t1 + S0 + maj) % MOD
	end
	H[1] = (H[1] + a) % MOD
	H[2] = (H[2] + b) % MOD
	H[3] = (H[3] + c) % MOD
	H[4] = (H[4] + d) % MOD
	H[5] = (H[5] + e) % MOD
	H[6] = (H[6] + f) % MOD
	H[7] = (H[7] + g) % MOD
	H[8] = (H[8] + h) % MOD
end

const function toWords(text: string, from: number): { number }
	const w = table.create(16, 0)
	for i = 1, 16 do
		w[i] = string.unpack(">I4", text, from + (i - 1) * 4)
	end
	return w
end

const function fromWords(H: { number }): string
	return string.pack(">I4I4I4I4I4I4I4I4", H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8])
end

-- 이미 prefixLength 바이트를 처리한 상태 H 에 message 를 이어서 해시
const function finish(H: { number }, message: string, prefixLength: number): string
	const length = prefixLength + #message
	const padded = message .. "\128" .. string.rep("\0", (55 - #message) % 64) .. string.pack(">I8", length * 8)
	for i = 1, #padded, 64 do
		compress(H, toWords(padded, i))
	end
	return fromWords(H)
end

function Crypto.sha256(message: string): string
	return finish(table.clone(IV), message, 0)
end

-- HMAC 의 안쪽 / 바깥쪽 시작 상태 (키 하나로 여러 번 쓸 때 재사용)
const function hmacStates(key: string): ({ number }, { number })
	local block = if #key > 64 then Crypto.sha256(key) else key
	block ..= string.rep("\0", 64 - #block)
	const inner, outer = table.clone(IV), table.clone(IV)
	compress(inner, toWords(string.gsub(block, ".", function(c)
		return string.char(bxor(string.byte(c), 0x36))
	end), 1))
	compress(outer, toWords(string.gsub(block, ".", function(c)
		return string.char(bxor(string.byte(c), 0x5c))
	end), 1))
	return inner, outer
end

function Crypto.hmac(key: string, message: string): string
	const inner, outer = hmacStates(key)
	return finish(outer, finish(inner, message, 64), 64)
end

-- PBKDF2-HMAC-SHA256, 32바이트 결과 하나
--   iterations 만큼 돌리거나, seconds 가 있으면 그 시간(CPU) 동안 (최소 minIterations 번) 돌리고 돈 횟수를 같이 반환
--   중간중간 양보해서 Studio 가 멈추지 않게
const function derive(
	password: string,
	salt: string,
	iterations: number?,
	seconds: number?,
	minIterations: number?
): (string, number)
	const inner, outer = hmacStates(password)
	const first = finish(table.clone(outer), finish(table.clone(inner), salt .. "\0\0\0\1", 64), 64)

	-- 이후 반복은 32바이트 메시지라 패딩이 고정: 단어 8개 + 0x80000000 + 0... + 길이 (64+32)*8
	const block = { 0, 0, 0, 0, 0, 0, 0, 0, 0x80000000, 0, 0, 0, 0, 0, 0, (64 + 32) * 8 }
	const U = { string.unpack(">I4I4I4I4I4I4I4I4", first) }
	U[9] = nil
	const T = table.clone(U)
	local spent = 0
	local sliceStart = os.clock()
	local n = 1
	while if iterations then n < iterations else true do
		n += 1
		for i = 1, 8 do
			block[i] = U[i]
		end
		const s = table.clone(inner)
		compress(s, block)
		for i = 1, 8 do
			block[i] = s[i]
		end
		const o = table.clone(outer)
		compress(o, block)
		for i = 1, 8 do
			U[i] = o[i]
			T[i] = bxor(T[i], o[i])
		end
		if n % 256 == 0 then
			const slice = os.clock() - sliceStart
			if seconds and spent + slice >= seconds and n >= (minIterations or 0) then
				break
			end
			if slice > 0.03 then
				spent += slice
				task.wait()
				sliceStart = os.clock()
			end
		end
	end
	return fromWords(T), n
end

function Crypto.pbkdf2(password: string, salt: string, iterations: number): string
	return (derive(password, salt, iterations, nil, nil))
end

-- salt 용 무작위 바이트 (비밀일 필요는 없고 겹치지만 않으면 됨)
function Crypto.randomBytes(count: number): string
	const random = Random.new()
	local pool = ""
	local out = ""
	while #out < count do
		pool = Crypto.sha256(
			pool .. HttpService:GenerateGUID(false) .. tostring(os.clock()) .. tostring(random:NextInteger(0, 0x7fffffff))
		)
		out ..= pool
	end
	return string.sub(out, 1, count)
end

const function toHex(raw: string): string
	return (string.gsub(raw, ".", function(c)
		return string.format("%02x", string.byte(c))
	end))
end

const function fromHex(hex: string): string?
	if #hex % 2 ~= 0 or string.find(hex, "[^%x]") then
		return nil
	end
	return (string.gsub(hex, "%x%x", function(pair)
		return string.char(tonumber(pair, 16) :: number)
	end))
end

-- 키 하나에서 암호화용 / 검사용 키를 따로 뽑아 keystream 과 XOR
const function xorStream(key: string, data: string): string
	const encKey = Crypto.hmac(key, "encrypt")
	const out = table.create(#data)
	local stream = ""
	for i = 1, #data do
		const offset = (i - 1) % 32 + 1
		if offset == 1 then
			stream = Crypto.hmac(encKey, string.pack(">I4", (i - 1) // 32))
		end
		out[i] = string.char(bxor(string.byte(data, i), string.byte(stream, offset)))
	end
	return table.concat(out)
end

const function tagOf(key: string, iterations: number, salt: string, data: string): string
	return Crypto.hmac(Crypto.hmac(key, "verify"), `v1|{iterations}|{salt}|{data}`)
end

-- seconds: 키를 만드는 데 쓸 시간 (이 컴퓨터 속도에 맞춰 반복 횟수를 정함, 최소 minIterations)
function Crypto.seal(plaintext: string, password: string, seconds: number, minIterations: number?): Sealed
	const salt = Crypto.randomBytes(16)
	const key, iterations = derive(password, salt, nil, seconds, minIterations)
	const data = xorStream(key, plaintext)
	return {
		v = 1,
		iterations = iterations,
		salt = toHex(salt),
		data = toHex(data),
		tag = toHex(tagOf(key, iterations, salt, data)),
	}
end

-- 비밀번호가 틀렸거나 값이 망가졌으면 nil
function Crypto.open(sealed: any, password: string): string?
	if type(sealed) ~= "table" or sealed.v ~= 1 or type(sealed.iterations) ~= "number" then
		return nil
	end
	const salt = fromHex(tostring(sealed.salt))
	const data = fromHex(tostring(sealed.data))
	const tag = fromHex(tostring(sealed.tag))
	if not (salt and data and tag) or sealed.iterations < 1 or sealed.iterations > 10_000_000 then
		return nil
	end
	const key = Crypto.pbkdf2(password, salt, sealed.iterations)
	-- 끝까지 비교 (어디서 다른지 시간으로 드러나지 않게)
	const expected = tagOf(key, sealed.iterations, salt, data)
	local diff = #expected ~= #tag and 1 or 0
	for i = 1, math.min(#expected, #tag) do
		diff = bor(diff, bxor(string.byte(expected, i), string.byte(tag, i)))
	end
	if diff ~= 0 then
		return nil
	end
	return xorStream(key, data)
end

return Crypto
