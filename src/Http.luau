-- HttpService 래퍼 (같은 세션 동안 응답 캐시)

const HttpService = game:GetService("HttpService")

const Http = {}

-- 오류 메시지에는 전체 주소 대신 서버 이름만
const function hostOf(url: string): string
	return string.match(url, "^%a+://([^/]+)") or "server"
end

const cache: { [string]: string } = {}

-- fresh: 캐시를 쓰지 않음
function Http.get(url: string, headers: { [string]: string }?, fresh: boolean?): string
	const cached = cache[url]
	if cached and not fresh then
		return cached
	end

	const ok, response = pcall(HttpService.RequestAsync, HttpService, {
		Url = url,
		Method = "GET",
		Headers = headers,
	})
	if not ok then
		error(`HTTP 요청 실패 ({hostOf(url)}): {response}`, 0)
	end
	if not response.Success then
		error(`HTTP {response.StatusCode} {response.StatusMessage} ({hostOf(url)})`, 0)
	end

	cache[url] = response.Body
	return response.Body
end

function Http.getJson(url: string, headers: { [string]: string }?, fresh: boolean?): any
	return HttpService:JSONDecode(Http.get(url, headers, fresh))
end

-- POST (캐시 안 함). 실패해도 응답 본문을 같이 보여줌
function Http.post(url: string, body: string, headers: { [string]: string }?): string
	const ok, response = pcall(HttpService.RequestAsync, HttpService, {
		Url = url,
		Method = "POST",
		Headers = headers,
		Body = body,
	})
	if not ok then
		error(`HTTP 요청 실패 ({hostOf(url)}): {response}`, 0)
	end
	if not response.Success then
		const detail = if response.Body and response.Body ~= "" then `\n{string.sub(response.Body, 1, 500)}` else ""
		error(`HTTP {response.StatusCode} {response.StatusMessage} ({hostOf(url)}){detail}`, 0)
	end
	return response.Body
end

function Http.postJson(url: string, body: any, headers: { [string]: string }?): any
	const merged = table.clone(headers or {})
	merged["Content-Type"] = "application/json"
	merged["Accept"] = "application/json"
	return HttpService:JSONDecode(Http.post(url, HttpService:JSONEncode(body), merged))
end

function Http.clearCache()
	table.clear(cache)
end

return Http
