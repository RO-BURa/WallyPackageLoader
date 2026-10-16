-- GitHub 로그인
--   토큰은 기본적으로 메모리에만 (Studio 를 끄면 사라짐)
--   --remember 일 때만 비밀번호로 암호화해서 plugin:SetSetting 으로 이 컴퓨터에 저장 (unlock 으로 풂)
--   플레이스에는 절대 안 넣음
--   기기 로그인: wally login 과 같은 GitHub Device Flow (Wally 의 OAuth 앱) -> Wally 업로드 + GitHub 요청 한도
--   토큰 입력: 직접 만든 토큰 -> GitHub 요청 한도만 (Wally 서버는 Wally 앱 토큰만 받음)

const Crypto = require(script.Parent.Util.Crypto)
const Http = require(script.Parent.Http)

export type Kind = "device" | "token"

const Auth = {}

-- 비밀번호로 암호화한 토큰
const SEALED_SETTING = "GitHubTokenSealed"
-- 예전 버전이 암호화 없이 저장하던 키 (보이면 지움)
const LEGACY_SETTINGS = { "GitHubToken", "GitHubTokenKind" }
const WALLY_INDEX_CONFIG = "https://raw.githubusercontent.com/UpliftGames/wally-index/main/config.json"
-- Wally 인덱스 설정을 못 읽을 때 쓰는 값 (wally-index config.json 의 github_oauth_id)
const FALLBACK_CLIENT_ID = "7bd503594a0f9a9f7ed3"

-- 비밀번호 최소 길이
Auth.MIN_PASSWORD_LENGTH = 10
-- 키를 만드는 데 쓰는 시간(초)과 최소 반복 횟수
Auth.KDF = { seconds = 1, minIterations = 20_000 }

local pluginRef: Plugin? = nil
local legacyRemoved = false

const function setting(name: string): any
	return if pluginRef then pluginRef:GetSetting(name) else nil
end

const function setSetting(name: string, value: any)
	if pluginRef then
		pluginRef:SetSetting(name, value)
	end
end

function Auth.init(plugin: Plugin)
	pluginRef = plugin
	for _, name in LEGACY_SETTINGS do
		if setting(name) ~= nil then
			setSetting(name, nil)
			legacyRemoved = true
		end
	end
end

-- 예전 방식(암호화 없이)으로 저장돼 있던 토큰을 init 에서 지웠는지
function Auth.legacyRemoved(): boolean
	return legacyRemoved
end

-- 이번 Studio 세션 동안만 기억하는 토큰
local memoryToken: string? = nil
local memoryKind: Kind? = nil

function Auth.getToken(): string?
	return memoryToken
end

function Auth.kind(): Kind?
	return memoryKind
end

-- 암호화해서 저장한 토큰이 있는지 (--remember)
function Auth.hasSaved(): boolean
	return type(setting(SEALED_SETTING)) == "table"
end

function Auth.isRemembered(): boolean
	return Auth.hasSaved()
end

-- 이번 세션에 로그인. 저장돼 있던 것은 지움 (저장은 save 로 따로)
function Auth.setToken(token: string, kind: Kind)
	memoryToken = token
	memoryKind = kind
	setSetting(SEALED_SETTING, nil)
end

-- 지금 토큰을 비밀번호로 암호화해서 저장. 걸린 시간(초) 반환
function Auth.save(password: string): number
	if not memoryToken or not memoryKind then
		error("로그인 안 됨 (login)", 0)
	end
	if #password < Auth.MIN_PASSWORD_LENGTH then
		error(`비밀번호는 {Auth.MIN_PASSWORD_LENGTH}자 이상`, 0)
	end
	const started = os.clock()
	const sealed = Crypto.seal(`{memoryKind}:{memoryToken}`, password, Auth.KDF.seconds, Auth.KDF.minIterations)
	setSetting(SEALED_SETTING, sealed)
	return os.clock() - started
end

-- 저장한 토큰을 비밀번호로 풀어서 이번 세션에 로그인. 걸린 시간(초) 반환
function Auth.unlock(password: string): number
	const sealed = setting(SEALED_SETTING)
	if type(sealed) ~= "table" then
		error("저장된 로그인이 없음 (login --agree --remember)", 0)
	end
	const started = os.clock()
	const plain = Crypto.open(sealed, password)
	if not plain then
		error("비밀번호가 틀림", 0)
	end
	const kind, token = string.match(plain, "^(%a+):(.+)$")
	if (kind ~= "device" and kind ~= "token") or not token then
		error("저장된 로그인이 망가짐. logout 후 다시 login 해주세요", 0)
	end
	memoryToken = token
	memoryKind = kind :: Kind
	return os.clock() - started
end

function Auth.clear()
	memoryToken = nil
	memoryKind = nil
	setSetting(SEALED_SETTING, nil)
end

-- api.github.com 요청에 붙일 헤더
function Auth.githubHeaders(): { [string]: string }?
	const token = Auth.getToken()
	if not token then
		return nil
	end
	return { Authorization = `Bearer {token}`, Accept = "application/vnd.github+json" }
end

-- 토큰 주인 (GitHub 로그인 이름)
function Auth.whoami(): string
	const headers = Auth.githubHeaders()
	if not headers then
		error(if Auth.hasSaved() then "저장된 로그인이 잠겨 있음 (unlock)" else "로그인 안 됨 (login)", 0)
	end
	const info = Http.getJson("https://api.github.com/user", headers, true)
	return info.login
end

const function wallyClientId(): string
	const ok, config = pcall(Http.getJson, WALLY_INDEX_CONFIG)
	if ok and type(config) == "table" and type(config.github_oauth_id) == "string" then
		return config.github_oauth_id
	end
	return FALLBACK_CLIENT_ID
end

-- 기기 로그인 대기 중인지, 취소 요청
local loginInProgress = false
local cancelRequested = false

function Auth.isLoggingIn(): boolean
	return loginInProgress
end

-- 대기 중인 기기 로그인 취소. 취소할 게 있었으면 true
function Auth.cancelLogin(): boolean
	if loginInProgress then
		cancelRequested = true
		return true
	end
	return false
end

-- 취소되면 오류, 아니면 seconds 동안 기다림 (1초마다 취소 확인)
const function waitOrCancel(seconds: number)
	local waited = 0
	while waited < seconds do
		if cancelRequested then
			error("GitHub 로그인 취소됨", 0)
		end
		task.wait(1)
		waited += 1
	end
	if cancelRequested then
		error("GitHub 로그인 취소됨", 0)
	end
end

-- GitHub 기기 로그인. 코드를 보여주고 승인될 때까지 기다림 (cancel 로 취소)
function Auth.deviceLogin(log: (string) -> ())
	if loginInProgress then
		error("이미 로그인을 기다리는 중 (cancel 로 취소)", 0)
	end
	loginInProgress = true
	cancelRequested = false
	const ok, err = pcall(function()
		const clientId = wallyClientId()
		const device = Http.postJson("https://github.com/login/device/code", {
			client_id = clientId,
			scope = "read:user",
		})
		if type(device) ~= "table" or not device.device_code then
			error("GitHub 기기 로그인을 시작할 수 없음", 0)
		end

		log(`1. 브라우저에서 {device.verification_uri} 열기`)
		log(`2. 코드 입력: {device.user_code}`)
		log("승인될 때까지 기다리는 중... (취소: cancel)")

		local interval = device.interval or 5
		const deadline = os.time() + (device.expires_in or 900)
		while os.time() < deadline do
			waitOrCancel(interval)
			const result = Http.postJson("https://github.com/login/oauth/access_token", {
				client_id = clientId,
				device_code = device.device_code,
				grant_type = "urn:ietf:params:oauth:grant-type:device_code",
			})
			if result.access_token then
				Auth.setToken(result.access_token, "device")
				return
			elseif result.error == "slow_down" then
				interval += 5
			elseif result.error ~= "authorization_pending" then
				error(`GitHub 로그인 실패: {result.error_description or result.error}`, 0)
			end
		end
		error("GitHub 로그인 시간이 지남. 다시 login 해주세요", 0)
	end)
	loginInProgress = false
	cancelRequested = false
	if not ok then
		error(err, 0)
	end
end

return Auth
