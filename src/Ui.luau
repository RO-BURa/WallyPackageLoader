-- DockWidget UI: 입력창(엔터로 명령 실행) + 버튼 + 로그

const Selection = game:GetService("Selection")
const TextService = game:GetService("TextService")

const Auth = require(script.Parent.Auth)
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
	-- 글자를 선택해서 복사할 수 있게 TextBox (고쳐도 바로 되돌림)
	const logLabel = make("TextBox", {
		Position = UDim2.fromOffset(LOG_PADDING_X, LOG_PADDING_Y),
		Size = UDim2.new(1, -LOG_PADDING_X * 2, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		RichText = true,
		ClearTextOnFocus = false,
		MultiLine = true,
		TextEditable = true,
		Font = LOG_FONT,
		TextSize = LOG_TEXT_SIZE,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
		Parent = logFrame,
	}) :: TextBox

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
	-- 같은 줄이 입력한 명령이면 그 명령 (클릭하면 입력창에 다시 넣음), 아니면 false
	const logCommands: { string | false } = {}
	-- 선택 / 복사 중에는 서식 없는 글자로 보여줌 (복사했을 때 태그가 같이 안 딸려오게)
	local plainText = ""
	local settingText = false

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
		plainText = Fmt.strip(markup)
		estimatedHeight = if #logLines == 0
			then 0
			else TextService:GetTextSize(plainText, LOG_TEXT_SIZE, LOG_FONT, Vector2.new(width, 1e6)).Y
		settingText = true
		if logLabel:IsFocused() then
			logLabel.RichText = false
			logLabel.Text = plainText
		else
			logLabel.RichText = true
			logLabel.Text = Fmt.resolve(markup, isDarkTheme())
		end
		settingText = false
		applyHeight()
	end
	logLabel:GetPropertyChangedSignal("TextBounds"):Connect(applyHeight)
	logFrame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(render)

	const function addLines(markup: string, command: string | false)
		for _, line in string.split(markup, "\n") do
			table.insert(logLines, line)
			table.insert(logCommands, command)
		end
		while #logLines > MAX_LOG_LINES do
			table.remove(logLines, 1)
			table.remove(logCommands, 1)
		end
		render()
	end
	const function rich(markup: string)
		addLines(markup, false)
	end
	-- 일반 글자: "오류:", "완료:" 같은 라벨에 색
	const function log(message: string)
		const lines = {}
		for _, line in string.split(message, "\n") do
			table.insert(lines, Fmt.line(line))
		end
		rich(table.concat(lines, "\n"))
	end
	-- 입력한 명령은 앞에 파란 원. reusable 이면 클릭해서 입력창에 다시 넣을 수 있음
	const function logCommand(line: string, reusable: boolean?)
		addLines(Fmt.color("blue", "●") .. " " .. Fmt.escape(line), if reusable then line else false)
	end
	const function clear()
		table.clear(logLines)
		table.clear(logCommands)
		followBottom = true
		render()
	end

	-- 로그: 포커스를 받으면 서식 없는 글자로 바꿔서 선택 / 복사, 고친 건 바로 되돌림
	logLabel.Focused:Connect(render)
	logLabel.FocusLost:Connect(render)
	logLabel:GetPropertyChangedSignal("Text"):Connect(function()
		if settingText or not logLabel:IsFocused() or logLabel.Text == plainText then
			return
		end
		const cursor = logLabel.CursorPosition
		settingText = true
		logLabel.Text = plainText
		logLabel.CursorPosition = math.min(cursor, #plainText + 1)
		settingText = false
	end)
	-- 입력한 명령 줄을 클릭하면 (드래그로 선택한 게 아니면) 그 명령을 입력창에 넣음
	logLabel:GetPropertyChangedSignal("CursorPosition"):Connect(function()
		if settingText then
			return
		end
		task.defer(function()
			const cursor = logLabel.CursorPosition
			if not logLabel:IsFocused() or cursor < 1 or logLabel.SelectionStart ~= -1 then
				return
			end
			const before = string.sub(plainText, 1, cursor - 1)
			const _, newlines = string.gsub(before, "\n", "")
			const command = logCommands[newlines + 1]
			if command then
				input.Text = command
				input.CursorPosition = #command + 1
			end
		end)
	end)

	-- Studio 테마가 바뀌면 색 다시 칠함
	settings().Studio.ThemeChanged:Connect(function()
		logFrame.BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.ScriptBackground)
		logLabel.TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText)
		render()
	end)
	Log.setSink(log)

	-- 비밀번호 입력 (입력창을 * 로 가림, 로그와 기록에 안 남김)
	local secretWaiter: thread? = nil
	local secretValue = ""
	local masking = false
	const PLACEHOLDER = input.PlaceholderText

	const function secret(prompt: string): string?
		log(prompt)
		secretValue = ""
		secretWaiter = coroutine.running()
		input.PlaceholderText = "비밀번호 (가려짐)"
		input.Text = ""
		task.defer(function()
			input:CaptureFocus()
		end)
		return coroutine.yield()
	end

	input:GetPropertyChangedSignal("Text"):Connect(function()
		if not secretWaiter or masking then
			return
		end
		-- 화면에는 * 만. 앞의 * 개수만큼은 원래 글자, 그 뒤는 새로 친 글자
		const text = input.Text
		const stars = #(string.match(text, "^%**") :: string)
		if stars > #secretValue then
			secretValue ..= string.rep("*", stars - #secretValue)
		end
		secretValue = string.sub(secretValue, 1, stars) .. string.sub(text, stars + 1)
		masking = true
		input.Text = string.rep("*", #secretValue)
		input.CursorPosition = #secretValue + 1
		masking = false
	end)

	const context: Commands.Context = { plugin = plugin, log = log, rich = rich, clear = clear, secret = secret }

	-- 작업은 하나씩만, 오류는 로그로
	local busy = false
	-- 로그인했을 때만 보이는 버튼 (Logout, Prepare Publish)
	const loginOnlyButtons: { TextButton } = {}
	const function refreshLoginButtons()
		const loggedIn = Auth.getToken() ~= nil
		for _, button in loginOnlyButtons do
			-- Logout 은 잠긴 저장 로그인을 지울 때도 필요
			button.Visible = loggedIn or (button.Text == "Logout" and Auth.hasSaved())
		end
	end

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
		refreshLoginButtons()
	end

	input.FocusLost:Connect(function(enterPressed)
		if not enterPressed then
			return
		end
		const waiter = secretWaiter
		if waiter then
			const value = secretValue
			secretWaiter = nil
			secretValue = ""
			masking = true
			input.Text = ""
			masking = false
			input.PlaceholderText = PLACEHOLDER
			logCommand(if value == "" then "(취소)" else "(비밀번호 입력됨)")
			task.spawn(waiter, if value == "" then nil else value)
			task.defer(function()
				input:CaptureFocus()
			end)
			return
		end
		const line = input.Text
		if string.match(line, "^%s*$") then
			return
		end
		-- 토큰 / 비밀번호는 로그에 **** 로 (그 줄은 클릭해서 다시 쓸 수 없음)
		--   login <토큰>, --password <비밀번호>, --r <비밀번호>
		local secret = false
		const words = string.split((string.gsub(line, "^%s+", "")), " ")
		const isLogin = string.lower(words[1] or "") == "login"
		const shownWords = {}
		for i, word in words do
			const previous = words[i - 1]
			if previous == "--password" or previous == "--r" then
				table.insert(shownWords, "****")
				secret = true
			elseif isLogin and i > 1 and word ~= "" and string.sub(word, 1, 2) ~= "--" then
				table.insert(shownWords, "****")
				secret = true
			else
				table.insert(shownWords, word)
			end
		end
		input.Text = ""
		logCommand(table.concat(shownWords, " "), not secret)
		-- cancel 은 다른 작업(로그인 대기)이 진행 중이어도 바로 실행
		if string.lower((string.gsub(line, "^%s*(.-)%s*$", "%1"))) == "cancel" then
			task.spawn(Commands.run, line, context)
		else
			task.spawn(run, function()
				Commands.run(line, context)
			end)
		end
		task.defer(function()
			input:CaptureFocus()
			-- 다시 포커스를 잡을 때 Enter 가 공백으로 들어가는 경우가 있어서 한 프레임 뒤 비움
			task.wait()
			if string.match(input.Text, "^%s*$") then
				input.Text = ""
			end
		end)
	end)


	local order = 0
	const function addButton(text: string, job: () -> ()): TextButton
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
		return button
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
	-- 선택한 곳(예: 방금 연 Config) 에 잘못 들어가지 않도록 버튼은 항상 shared 경로
	addButton("Import File", function()
		Commands.import(NO_FLAGS, context)
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

	-- 로그인하면 보임. Prepare Publish 는 선택한 패키지에 wally.toml 을 만들거나 미리보기 (업로드는 publish --yes)
	table.insert(loginOnlyButtons, addButton("Logout", function()
		Commands.run("logout", context)
	end))
	table.insert(loginOnlyButtons, addButton("Prepare Publish", function()
		Commands.run("publish", context)
	end))
	refreshLoginButtons()

	root.Parent = widget

	if Auth.hasSaved() then
		log("저장된 GitHub 로그인이 있음. login --password <비밀번호> 로 풀기")
	end

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
