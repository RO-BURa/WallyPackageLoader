-- HttpService 래퍼 (같은 세션 동안 응답 캐시)

const HttpService = game:GetService("HttpService")

const Http = {}

const cache: { [string]: string } = {}

function Http.get(url: string, headers: { [string]: string }?): string
	const cached = cache[url]
	if cached then
		return cached
	end

	const ok, response = pcall(HttpService.RequestAsync, HttpService, {
		Url = url,
		Method = "GET",
		Headers = headers,
	})
	if not ok then
		error(`HTTP 요청 실패: {url}\n{response}`, 0)
	end
	if not response.Success then
		error(`HTTP {response.StatusCode} {response.StatusMessage}: {url}`, 0)
	end

	cache[url] = response.Body
	return response.Body
end

function Http.getJson(url: string, headers: { [string]: string }?): any
	return HttpService:JSONDecode(Http.get(url, headers))
end

function Http.clearCache()
	table.clear(cache)
end

return Http
