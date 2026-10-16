-- DockWidget UI: 입력창(엔터로 명령 실행) + 버튼 + 로그

const Selection = game:GetService("Selection")

const Commands = require(script.Parent.Commands)
const Config = require(script.Parent.Config)
const Installer = require(script.Parent.Installer)
const Log = require(script.Parent.Log)

const Ui = {}

const MAX_LOG_LINES = 80
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
	const root = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
		BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.MainBackground),
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		make("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
	}) :: ScrollingFrame

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
		Parent = root,
	}, {
		make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	}) :: TextBox

	const buttonGrid = make("Frame", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		make("UIGridLayout", {
			CellSize = UDim2.new(0.5, -3, 0, 26),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	const logLabel = make("TextLabel", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = "",
		Font = Enum.Font.Code,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
		Parent = root,
	}) :: TextLabel

	const logLines: { string } = {}
	const function log(message: string)
		for _, line in string.split(message, "\n") do
			table.insert(logLines, line)
		end
		while #logLines > MAX_LOG_LINES do
			table.remove(logLines, 1)
		end
		logLabel.Text = table.concat(logLines, "\n")
		root.CanvasPosition = Vector2.new(0, math.huge)
	end
	const function clear()
		table.clear(logLines)
		logLabel.Text = ""
	end
	Log.setSink(log)

	const context: Commands.Context = { plugin = plugin, log = log, clear = clear }

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
		log(`> {line}`)
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
			log(`> [{text}]`)
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
