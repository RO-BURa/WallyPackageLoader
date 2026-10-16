-- 플러그인에 같이 빌드되는 LICENSE / THIRD_PARTY_NOTICES (StringValue) 읽기

const LicenseText = {}

const function readValue(name: string): string?
	const ok, value = pcall(function()
		const instance = script.Parent:FindFirstChild(name)
		return if instance and instance:IsA("StringValue") then instance.Value else nil
	end)
	return if ok then value else nil
end

-- 이 플러그인의 라이선스 + 참고한 프로젝트들의 고지
function LicenseText.text(): string
	const parts = {}
	for _, name in { "LICENSE", "THIRD_PARTY_NOTICES" } do
		const value = readValue(name)
		if value then
			table.insert(parts, (string.gsub(value, "%s+$", "")))
		end
	end
	if #parts == 0 then
		return "MIT License - https://github.com/RO-BURa/WallyPackageLoader"
	end
	return table.concat(parts, "\n\n")
end

return LicenseText
