-- DockWidget UI: 입력창(엔터로 명령 실행) + 버튼 + 로그

const Selection = game:GetService("Selection")
const TextService = game:GetService("TextService")

const Commands = require(script.Parent.Commands)
const Config = require(script.Parent.Config)
const Fmt = require(script.Parent.Fmt)
const Installer = require(script.Parent.Installer)
const Log = require(script.Parent.Log)

const Ui = {}

const MAX_LOG_LINES = 300
const LOG_FONT = Enum.Font.Code
const LOG_TEXT_SIZE = 13
const LOG_PADDING_X = 6
const LOG_PADDING_Y = 4
const MAX_HISTORY = 50

const function themeColor(color: Enum.StudioStyleGuideColor): Color3
	return settings().Studio.Theme:GetColor(color)
end

const function make(className: string, props: { [string]: any }, children: { Instance }?): Instance
	const instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	return instance
end

const NO_FLAGS: Commands.Flags = { server = false, selected = false, to = nil }

function Ui.mount(widget: DockWidgetPluginGui, plugin: Plugin)
	-- 위: 입력창 + 버튼 (고정), 아래: 로그 (남은 공간 전체, 스크롤)
	const root = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.MainBackground),
	}) :: Frame

	const top = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		make("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
	}) :: Frame

	const input = make("TextBox", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 28),
		PlaceholderText = "asdf = ro-bura/signal  (Enter 로 실행, help)",
		Text = "",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.Code,
		TextSize = 14,
		BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.InputFieldBackground),
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
		PlaceholderColor3 = themeColor(Enum.StudioStyleGuideColor.DimmedText),
		BorderColor3 = themeColor(Enum.StudioStyleGuideColor.InputFieldBorder),
		Parent = top,
	}, {
		make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	}) :: TextBox

	const buttonGrid = make("Frame", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = top,
	}, {
		make("UIGridLayout", {
			CellSize = UDim2.new(0.5, -3, 0, 26),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	const logFrame = make("ScrollingFrame", {
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = themeColor(Enum.StudioStyleGuideColor.ScrollBar),
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		BorderSizePixel = 1,
		BorderColor3 = themeColor(Enum.StudioStyleGuideColor.Border),
		BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.ScriptBackground),
		Parent = root,
	}) :: ScrollingFrame

	-- 높이는 글자 크기로 직접 계산 (AutomaticSize 는 ScrollingFrame 안에서 안 늘어남)
	const logLabel = make("TextLabel", {
		Position = UDim2.fromOffset(LOG_PADDING_X, LOG_PADDING_Y),
		Size = UDim2.new(1, -LOG_PADDING_X * 2, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		RichText = true,
		Font = LOG_FONT,
		TextSize = LOG_TEXT_SIZE,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
		Parent = logFrame,
	}) :: TextLabel

	-- 로그 영역이 위쪽 고정 영역 아래 남은 공간을 채움
	const function layoutLog()
		const topHeight = top.AbsoluteSize.Y
		logFrame.Position = UDim2.fromOffset(8, topHeight)
		logFrame.Size = UDim2.new(1, -16, 1, -topHeight - 8)
	end
	top:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutLog)
	layoutLog()

	-- 줄마다 RichText 서식 (색은 Fmt 의 "$이름", 그릴 때 테마 색으로 바꿈)
	const logLines: { string } = {}

	-- 터미널처럼: 맨 아래에 있으면 새 로그를 따라 내려가고, 위로 스크롤해서 보고 있으면 그대로 둠
	local followBottom = true
	local canvasHeight = 0
	const function bottomY(): number
		return math.max(0, canvasHeight - logFrame.AbsoluteWindowSize.Y)
	end
	logFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		followBottom = logFrame.CanvasPosition.Y >= bottomY() - 4
	end)

	const function isDarkTheme(): boolean
		const background = themeColor(Enum.StudioStyleGuideColor.MainBackground)
		return (background.R + background.G + background.B) / 3 < 0.5
	end

	-- 높이: TextService 로 먼저 어림잡고, 실제로 그려진 TextBounds 가 더 크면 그걸 씀
	-- (RichText 굵은 글씨, 한글 대체 폰트는 GetTextSize 에 반영이 안 됨)
	local estimatedHeight = 0
	const function applyHeight()
		const textHeight = if #logLines == 0 then 0 else math.max(estimatedHeight, logLabel.TextBounds.Y)
		const wasFollowing = followBottom
		logLabel.Size = UDim2.new(1, -LOG_PADDING_X * 2, 0, textHeight + LOG_TEXT_SIZE)
		canvasHeight = textHeight + LOG_TEXT_SIZE + LOG_PADDING_Y * 2
		logFrame.CanvasSize = UDim2.fromOffset(0, canvasHeight)
		if wasFollowing then
			logFrame.CanvasPosition = Vector2.new(0, bottomY())
			followBottom = true
		end
	end

	const function render()
		const markup = table.concat(logLines, "\n")
		const width = math.max(1, logFrame.AbsoluteWindowSize.X - LOG_PADDING_X * 2)
		estimatedHeight = if #logLines == 0
			then 0
			else TextService:GetTextSize(Fmt.strip(markup), LOG_TEXT_SIZE, LOG_FONT, Vector2.new(width, 1e6)).Y
		logLabel.Text = Fmt.resolve(markup, isDarkTheme())
		applyHeight()
	end
	logLabel:GetPropertyChangedSignal("TextBounds"):Connect(applyHeight)
	logFrame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(render)

	const function rich(markup: string)
		for _, line in string.split(markup, "\n") do
			table.insert(logLines, line)
		end
		while #logLines > MAX_LOG_LINES do
			table.remove(logLines, 1)
		end
		render()
	end
	-- 일반 글자: "오류:", "완료:" 같은 라벨에 색
	const function log(message: string)
		const lines = {}
		for _, line in string.split(message, "\n") do
			table.insert(lines, Fmt.line(line))
		end
		rich(table.concat(lines, "\n"))
	end
	-- 입력한 명령은 앞에 파란 원
	const function logCommand(line: string)
		rich(Fmt.color("blue", "●") .. " " .. Fmt.escape(line))
	end
	const function clear()
		table.clear(logLines)
		followBottom = true
		render()
	end

	-- Studio 테마가 바뀌면 색 다시 칠함
	settings().Studio.ThemeChanged:Connect(function()
		logFrame.BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.ScriptBackground)
		logLabel.TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText)
		render()
	end)
	Log.setSink(log)

	const context: Commands.Context = { plugin = plugin, log = log, rich = rich, clear = clear }

	-- 작업은 하나씩만, 오류는 로그로
	local busy = false
	const function run(job: () -> ())
		if busy then
			log("이전 작업이 끝날 때까지 기다려주세요")
			return
		end
		busy = true
		const ok, err = pcall(job)
		if not ok then
			log(`오류: {err}`)
		end
		busy = false
	end

	-- 입력 기록 (↑ / ↓)
	const history: { string } = {}
	local historyIndex = 0

	input.FocusLost:Connect(function(enterPressed)
		if not enterPressed then
			return
		end
		const line = input.Text
		if string.match(line, "^%s*$") then
			return
		end
		if history[#history] ~= line then
			table.insert(history, line)
			if #history > MAX_HISTORY then
				table.remove(history, 1)
			end
		end
		historyIndex = #history + 1
		input.Text = ""
		logCommand(line)
		task.spawn(run, function()
			Commands.run(line, context)
		end)
		task.defer(function()
			input:CaptureFocus()
		end)
	end)

	input.InputBegan:Connect(function(inputObject)
		if inputObject.UserInputType ~= Enum.UserInputType.Keyboard or #history == 0 then
			return
		end
		if inputObject.KeyCode == Enum.KeyCode.Up then
			historyIndex = math.max(1, historyIndex - 1)
		elseif inputObject.KeyCode == Enum.KeyCode.Down then
			historyIndex = math.min(#history + 1, historyIndex + 1)
		else
			return
		end
		input.Text = history[historyIndex] or ""
		input.CursorPosition = #input.Text + 1
	end)

	local order = 0
	const function addButton(text: string, job: () -> ())
		order += 1
		const button = make("TextButton", {
			LayoutOrder = order,
			Text = text,
			Font = Enum.Font.SourceSansSemibold,
			TextSize = 15,
			AutoButtonColor = true,
			BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.Button),
			TextColor3 = themeColor(Enum.StudioStyleGuideColor.ButtonText),
			BorderColor3 = themeColor(Enum.StudioStyleGuideColor.ButtonBorder),
			Parent = buttonGrid,
		}) :: TextButton
		button.Activated:Connect(function()
			logCommand(`[{text}]`)
			task.spawn(run, job)
		end)
	end

	addButton("Add", function()
		Commands.add(input.Text, NO_FLAGS, context)
	end)
	addButton("Add to Server", function()
		Commands.add(input.Text, { server = true, selected = false, to = nil }, context)
	end)
	addButton("Add to Selected", function()
		Commands.add(input.Text, { server = false, selected = true, to = nil }, context)
	end)
	addButton("Remove", function()
		Commands.remove(input.Text, context)
	end)
	addButton("Install All", function()
		Installer.installAll(log)
	end)
	addButton("Prune", function()
		Installer.prune(log)
		log("정리 완료")
	end)
	addButton("Import File", function()
		Commands.import(NO_FLAGS, context, true)
	end)
	addButton("Open Config", function()
		Commands.openConfig(context)
	end)
	-- Explorer 에서 선택한 폴더 우선, 없으면 입력한 경로
	const function pathInput(): string?
		return if Selection:Get()[1] then nil else input.Text
	end
	addButton("Set Shared Path", function()
		Commands.setPath("shared", pathInput(), context)
	end)
	addButton("Set Server Path", function()
		Commands.setPath("server", pathInput(), context)
	end)
	addButton("List", function()
		Commands.list(context)
	end)
	addButton("Help", function()
		Commands.help(context)
	end)

	root.Parent = widget

	-- TODO: 임시 디버그용. 문제 확인되면 지울 것
	_G.PackageLoaderGui = {
		widget = widget,
		root = root,
		top = top,
		input = input,
		buttonGrid = buttonGrid,
		logFrame = logFrame,
		logLabel = logLabel,
		logLines = logLines,
		history = history,
		context = context,
		log = log,
		run = function(line: string)
			Commands.run(line, context)
		end,
		state = function()
			return {
				busy = busy,
				followBottom = followBottom,
				canvasHeight = canvasHeight,
				estimatedHeight = estimatedHeight,
				textBounds = logLabel.TextBounds,
				canvas = logFrame.AbsoluteCanvasSize,
				window = logFrame.AbsoluteWindowSize,
				position = logFrame.CanvasPosition,
			}
		end,
	}

	const ok, data = pcall(Config.read)
	if ok then
		log(`shared: {data.shared}`)
		log(`server: {data.server}`)
		log("help 를 입력하면 명령어 목록이 나옴")
	else
		log(`오류: {data}`)
	end
end

return Ui
