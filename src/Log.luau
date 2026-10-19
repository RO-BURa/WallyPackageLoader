-- 플러그인 창 로그로 메시지를 보냄 (Output 창에는 찍지 않음)

const L = require(script.Parent.Locale).L

const Log = {}

local sink: ((message: string) -> ())? = nil

function Log.setSink(fn: ((message: string) -> ())?)
	sink = fn
end

function Log.write(message: string)
	if sink then
		sink(message)
	end
end

function Log.warn(message: string)
	Log.write(L(`경고: {message}`, `Warning: {message}`))
end

return Log
