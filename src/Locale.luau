-- 한국어 / 영어
--   L("한국어", "English") 처럼 쓰는 곳에 두 문장을 같이 적고, 지금 언어에 맞는 쪽을 돌려줌
--   기본은 Studio 언어 (한국어면 ko, 그 외는 en). lang 명령으로 바꾸면 이 컴퓨터에 저장

export type Language = "ko" | "en"

const Locale = {}

const SETTING = "RO_BURa.WallyPackageLoader.Language"

local pluginRef: Plugin? = nil
local current: Language = "en"

-- Studio 언어 (StudioService.StudioLocaleId, 예: "ko-kr", "en-us")
const function studioLanguage(): Language
	const ok, localeId = pcall(function()
		return (game:GetService("StudioService") :: any).StudioLocaleId
	end)
	if ok and type(localeId) == "string" and string.sub(string.lower(localeId), 1, 2) == "ko" then
		return "ko"
	end
	return "en"
end

function Locale.init(plugin: Plugin)
	pluginRef = plugin
	const saved = plugin:GetSetting(SETTING)
	current = if saved == "ko" or saved == "en" then saved else studioLanguage()
end

function Locale.get(): Language
	return current
end

-- 언어를 정함. nil 이면 Studio 언어를 따라감 (저장한 것도 지움)
function Locale.set(language: Language?)
	current = language or studioLanguage()
	if pluginRef then
		pluginRef:SetSetting(SETTING, language)
	end
end

-- 저장해 둔 언어가 있는지 (없으면 Studio 언어를 따라가는 중)
function Locale.isAuto(): boolean
	return pluginRef == nil or pluginRef:GetSetting(SETTING) == nil
end

-- 지금 언어에 맞는 문장
function Locale.L(ko: string, en: string): string
	return if current == "ko" then ko else en
end

return Locale
