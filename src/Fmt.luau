-- 로그용 RichText 서식
-- 색은 "$이름" 으로 적어두고 그릴 때 Studio 테마에 맞는 색으로 바꿈

const Fmt = {}

const PALETTES = {
	dark = {
		yellow = "#E5C07B",
		green = "#98C379",
		red = "#E06C75",
		blue = "#61AFEF",
		cyan = "#56B6C2",
		dim = "#7F848E",
	},
	light = {
		yellow = "#A86E00",
		green = "#2E7D32",
		red = "#C62828",
		blue = "#1F63C9",
		cyan = "#00838F",
		dim = "#8A8A8A",
	},
}

function Fmt.escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- 태그를 지운 순수 글자 (높이 계산용)
function Fmt.strip(markup: string): string
	const text = string.gsub(markup, "<[^>]*>", "")
	return (string.gsub(string.gsub(string.gsub(text, "&lt;", "<"), "&gt;", ">"), "&amp;", "&"))
end

-- text 는 이미 이스케이프된 것
function Fmt.color(name: string, text: string): string
	return `<font color="${name}">{text}</font>`
end

function Fmt.bold(text: string): string
	return `<b>{text}</b>`
end

-- 오른쪽을 공백으로 채움 (ASCII 기준)
function Fmt.pad(text: string, width: number): string
	return text .. string.rep(" ", math.max(1, width - #text))
end

-- "$이름" 을 실제 색으로
function Fmt.resolve(markup: string, dark: boolean): string
	const palette = if dark then PALETTES.dark else PALETTES.light
	return (string.gsub(markup, 'color="%$(%a+)"', function(name)
		return `color="{palette[name] or "#FFFFFF"}"`
	end))
end

-- 일반 로그 한 줄: 앞쪽 라벨("오류:", "완료:" 등)과 끝의 (경로) 에 색
const LABEL_COLORS = {
	["오류"] = "red",
	["실패"] = "red",
	["경고"] = "yellow",
	["완료"] = "green",
	["추가됨"] = "green",
	["설치됨"] = "green",
	["삭제됨"] = "green",
	["가져옴"] = "green",
	["정리됨"] = "green",
	["받는 중"] = "dim",
	["확인 중"] = "dim",
	["shared"] = "cyan",
	["server"] = "cyan",
	["shared 경로"] = "cyan",
	["server 경로"] = "cyan",
	-- 영어
	["Error"] = "red",
	["Failed"] = "red",
	["Warning"] = "yellow",
	["Done"] = "green",
	["Added"] = "green",
	["Installed"] = "green",
	["Removed"] = "green",
	["Imported"] = "green",
	["Pruned"] = "green",
	["Fetching"] = "dim",
	["Checking"] = "dim",
	["shared path"] = "cyan",
	["server path"] = "cyan",
}

function Fmt.line(text: string): string
	const label, rest = string.match(text, "^([^:]+):(.*)$")
	const colorName = label and LABEL_COLORS[label]
	if not colorName then
		return Fmt.escape(text)
	end

	local body = Fmt.escape(rest :: string)
	if colorName == "dim" then
		return Fmt.color("dim", Fmt.escape(text))
	end
	-- 끝의 (경로) 는 흐리게
	body = string.gsub(body, "%(([^()]*)%)%s*$", function(inner)
		return Fmt.color("dim", `({inner})`)
	end)
	return Fmt.color(colorName, Fmt.bold(Fmt.escape(label :: string) .. ":")) .. body
end

return Fmt
