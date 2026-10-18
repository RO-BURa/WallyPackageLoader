-- Roblox Builder Icons (Studio 에 들어 있는 아이콘 폰트, 이름을 글자로 쓰면 아이콘이 됨)
--   쓰는 것: square-check, square, square-minus, star, gear, magnifying-glass, chevron-large-left, chevron-small-down, plus-small, folder, file-box
--   Regular / Filled(굵게) 두 가지

const Icons = {}

const FAMILY = "rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/BuilderIcons.json"

function Icons.font(filled: boolean?): Font
	return Font.new(FAMILY, if filled then Enum.FontWeight.Bold else Enum.FontWeight.Regular)
end

-- 아이콘 하나짜리 TextLabel
function Icons.label(name: string, size: number, filled: boolean?, props: { [string]: any }?): TextLabel
	const label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = name
	label.FontFace = Icons.font(filled)
	label.TextSize = size
	label.Size = UDim2.fromOffset(size, size)
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	return label
end

-- RichText 글자 사이에 넣는 아이콘 (예: 별 + 숫자를 한 줄에)
function Icons.rich(name: string, filled: boolean?): string
	return `<font family="{FAMILY}" weight="{if filled then "bold" else "regular"}">{name}</font>`
end

-- 이미 만든 아이콘 라벨을 바꿈
function Icons.set(label: TextLabel, name: string, filled: boolean?)
	label.Text = name
	label.FontFace = Icons.font(filled)
end

return Icons
