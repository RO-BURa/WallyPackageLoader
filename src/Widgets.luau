-- 플러그인 창 공용 UI 조각 (Studio 테마 색, 버튼, 입력창, 스크롤, 출처 아이콘)

const Icons = require(script.Parent.Icons)

const Widgets = {}

const ICON_SIZE = 16

-- 출처 로고 (Wally / pesde 는 이미지, GitHub / 가져온 것은 Builder Icons)
const SOURCE_IMAGES = {
	wally = "rbxassetid://84745302108730",
	pesde = "rbxassetid://107553028826404",
}
const SOURCE_ICONS = {
	github = "github",
	import = "file-box",
}
Widgets.SOURCE_NAMES = { wally = "Wally", pesde = "pesde", github = "GitHub", import = "Import" }

function Widgets.themeColor(color: Enum.StudioStyleGuideColor): Color3
	return settings().Studio.Theme:GetColor(color)
end

function Widgets.isDarkTheme(): boolean
	const background = Widgets.themeColor(Enum.StudioStyleGuideColor.MainBackground)
	return (background.R + background.G + background.B) / 3 < 0.5
end

function Widgets.make(className: string, props: { [string]: any }, children: { Instance }?): Instance
	const instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	return instance
end

function Widgets.textButton(props: { [string]: any }): TextButton
	const merged = {
		Font = Enum.Font.SourceSansSemibold,
		TextSize = 15,
		AutoButtonColor = true,
		BackgroundColor3 = Widgets.themeColor(Enum.StudioStyleGuideColor.Button),
		TextColor3 = Widgets.themeColor(Enum.StudioStyleGuideColor.ButtonText),
		BorderColor3 = Widgets.themeColor(Enum.StudioStyleGuideColor.ButtonBorder),
	}
	for key, value in props do
		merged[key] = value
	end
	return Widgets.make("TextButton", merged) :: TextButton
end

-- 아이콘 + 글자 버튼 (가로로 자동 크기)
function Widgets.iconButton(icon: string, text: string, props: { [string]: any }): (TextButton, TextLabel, TextLabel)
	const button = Widgets.textButton(props)
	button.Text = ""
	if not props.Size then
		button.Size = UDim2.new(0, 0, 0, 24)
		button.AutomaticSize = Enum.AutomaticSize.X
	end
	Widgets.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = if text == "" then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = button,
	})
	Widgets.make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = button })
	const iconLabel = Icons.label(icon, ICON_SIZE, false, {
		LayoutOrder = 1,
		TextColor3 = Widgets.themeColor(Enum.StudioStyleGuideColor.ButtonText),
		Parent = button,
	})
	const textLabel = Widgets.make("TextLabel", {
		LayoutOrder = 2,
		Visible = text ~= "",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text,
		Font = Enum.Font.SourceSansSemibold,
		TextSize = 15,
		TextColor3 = Widgets.themeColor(Enum.StudioStyleGuideColor.ButtonText),
		Parent = button,
	}) :: TextLabel
	return button, iconLabel, textLabel
end

function Widgets.inputBox(props: { [string]: any }): TextBox
	const merged = {
		Text = "",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.Code,
		TextSize = 14,
		BackgroundColor3 = Widgets.themeColor(Enum.StudioStyleGuideColor.InputFieldBackground),
		TextColor3 = Widgets.themeColor(Enum.StudioStyleGuideColor.MainText),
		PlaceholderColor3 = Widgets.themeColor(Enum.StudioStyleGuideColor.DimmedText),
		BorderColor3 = Widgets.themeColor(Enum.StudioStyleGuideColor.InputFieldBorder),
	}
	for key, value in props do
		merged[key] = value
	end
	return Widgets.make("TextBox", merged, {
		Widgets.make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	}) :: TextBox
end

function Widgets.scrollFrame(props: { [string]: any }): ScrollingFrame
	const merged = {
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Widgets.themeColor(Enum.StudioStyleGuideColor.ScrollBar),
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		BorderSizePixel = 1,
		BorderColor3 = Widgets.themeColor(Enum.StudioStyleGuideColor.Border),
		BackgroundColor3 = Widgets.themeColor(Enum.StudioStyleGuideColor.ScriptBackground),
	}
	for key, value in props do
		merged[key] = value
	end
	return Widgets.make("ScrollingFrame", merged) :: ScrollingFrame
end


-- 출처 아이콘 하나 (size 픽셀 정사각형)
function Widgets.sourceIcon(source: string, size: number, props: { [string]: any }?): GuiObject
	const image = SOURCE_IMAGES[source]
	local icon: GuiObject
	if image then
		icon = Widgets.make("ImageLabel", {
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(size, size),
		}) :: GuiObject
	else
		icon = Icons.label(SOURCE_ICONS[source] or "file-box", size, false, {
			TextColor3 = Widgets.themeColor(Enum.StudioStyleGuideColor.MainText),
		})
	end
	for key, value in props or {} do
		(icon :: any)[key] = value
	end
	return icon
end

return Widgets
