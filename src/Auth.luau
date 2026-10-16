-- GitHub 로그인
--   토큰은 기본적으로 메모리에만 (Studio 를 끄면 사라짐)
--   --remember 일 때만 plugin:SetSetting 으로 이 컴퓨터에 저장 (다른 로컬 플러그인이 읽을 수 있음)
--   플레이스에는 절대 안 넣음
--   기기 로그인: wally login 과 같은 GitHub Device Flow (Wally 의 OAuth 앱) -> Wally 업로드 + GitHub 요청 한도
--   토큰 입력: 직접 만든 토큰 -> GitHub 요청 한도만 (Wally 서버는 Wally 앱 토큰만 받음)

const Http = require(script.Parent.Http)

export type Kind = "device" | "token"

const Auth = {}

const TOKEN_SETTING = "GitHubToken"
const KIND_SETTING = "GitHubTokenKind"
const WALLY_INDEX_CONFIG = "https://raw.githubusercontent.com/UpliftGames/wally-index/main/config.json"
-- Wally 인덱스 설정을 못 읽을 때 쓰는 값 (wally-index config.json 의 github_oauth_id)
const FALLBACK_CLIENT_ID = "7bd503594a0f9a9f7ed3"

local pluginRef: Plugin? = nil

function Auth.init(plugin: Plugin)
	pluginRef = plugin
end

const function setting(name: string): any
	return if pluginRef then pluginRef:GetSetting(name) else nil
end

const function setSetting(name: string, value: any)
	if pluginRef then
		pluginRef:SetSetting(name, value)
	end
end

-- 이번 Studio 세션 동안만 기억하는 토큰
local memoryToken: string? = nil
local memoryKind: Kind? = nil

function Auth.getToken(): string?
	if memoryToken then
		return memoryToken
	end
	const token = setting(TOKEN_SETTING)
	return if type(token) == "string" and token ~= "" then token else nil
end

function Auth.kind(): Kind?
	if memoryToken then
		return memoryKind
	end
	return if Auth.getToken() then setting(KIND_SETTING) else nil
end

-- 저장된 토큰인지 (--remember)
function Auth.isRemembered(): boolean
	const token = setting(TOKEN_SETTING)
	return type(token) == "string" and token ~= ""
end

-- remember 가 true 일 때만 Studio 설정에 저장, 아니면 저장돼 있던 것도 지움
function Auth.setToken(token: string, kind: Kind, remember: boolean?)
	memoryToken = token
	memoryKind = kind
	if remember then
		setSetting(TOKEN_SETTING, token)
		setSetting(KIND_SETTING, kind)
	else
		setSetting(TOKEN_SETTING, nil)
		setSetting(KIND_SETTING, nil)
	end
end

function Auth.clear()
	memoryToken = nil
	memoryKind = nil
	setSetting(TOKEN_SETTING, nil)
	setSetting(KIND_SETTING, nil)
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
		error("로그인 안 됨 (login)", 0)
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

-- GitHub 기기 로그인. 코드를 보여주고 승인될 때까지 기다림
function Auth.deviceLogin(log: (string) -> (), remember: boolean?)
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
	log("승인될 때까지 기다리는 중...")

	local interval = device.interval or 5
	const deadline = os.time() + (device.expires_in or 900)
	while os.time() < deadline do
		task.wait(interval)
		const result = Http.postJson("https://github.com/login/oauth/access_token", {
			client_id = clientId,
			device_code = device.device_code,
			grant_type = "urn:ietf:params:oauth:grant-type:device_code",
		})
		if result.access_token then
			Auth.setToken(result.access_token, "device", remember)
			return
		elseif result.error == "slow_down" then
			interval += 5
		elseif result.error ~= "authorization_pending" then
			error(`GitHub 로그인 실패: {result.error_description or result.error}`, 0)
		end
	end
	error("GitHub 로그인 시간이 지남. 다시 login 해주세요", 0)
end

return Auth
