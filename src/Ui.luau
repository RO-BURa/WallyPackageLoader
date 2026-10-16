-- DockWidget UI (기본 Instance 로만 구성)

const Selection = game:GetService("Selection")

const Config = require(script.Parent.Config)
const Installer = require(script.Parent.Installer)

const Ui = {}

const function themeColor(color: Enum.StudioStyleGuideColor, modifier: Enum.StudioStyleGuideModifier?): Color3
	return settings().Studio.Theme:GetColor(color, modifier)
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

const function textBox(placeholder: string, order: number): TextBox
	return make("TextBox", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 26),
		PlaceholderText = placeholder,
		Text = "",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.SourceSans,
		TextSize = 15,
		BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.InputFieldBackground),
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
		PlaceholderColor3 = themeColor(Enum.StudioStyleGuideColor.DimmedText),
		BorderColor3 = themeColor(Enum.StudioStyleGuideColor.InputFieldBorder),
	}, {
		make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	}) :: TextBox
end

const function button(text: string, order: number, width: UDim?): TextButton
	return make("TextButton", {
		LayoutOrder = order,
		Size = UDim2.new(width or UDim.new(1, 0), UDim.new(0, 26)),
		Text = text,
		Font = Enum.Font.SourceSansSemibold,
		TextSize = 15,
		AutoButtonColor = true,
		BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.Button),
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.ButtonText),
		BorderColor3 = themeColor(Enum.StudioStyleGuideColor.ButtonBorder),
	}) :: TextButton
end

const function label(text: string, order: number): TextLabel
	return make("TextLabel", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.SourceSansSemibold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.DimmedText),
	}) :: TextLabel
end

const function row(order: number, children: { Instance }): Frame
	return make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		table.unpack(children),
	}) :: Frame
end

function Ui.mount(widget: DockWidgetPluginGui)
	const root = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
		BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.MainBackground),
		Parent = widget,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		make("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
	})

	-- 설치 입력
	label("패키지", 1).Parent = root
	const specBox = textBox("sleitnick/signal@^2  /  gh:owner/repo@^1  /  gh:owner/repo#main", 2)
	specBox.Parent = root
	const aliasBox = textBox("별칭 (비우면 자동)", 3)
	aliasBox.Parent = root

	label("설치 위치 (비우면 Config 경로)", 4).Parent = root
	const locationBox = textBox("예: ReplicatedStorage/Packages", 1)
	locationBox.Size = UDim2.new(1, -94, 0, 26)
	const pickButton = button("선택한 폴더", 2, UDim.new(0, 90))
	row(5, { locationBox, pickButton }).Parent = root

	local server = false
	const serverButton = button("Realm: shared", 6)
	serverButton.Parent = root

	const installButton = button("설치", 1, UDim.new(0.5, -2))
	const fileButton = button("파일에서 가져오기", 2, UDim.new(0.5, -2))
	row(7, { installButton, fileButton }).Parent = root

	const installAllButton = button("Config 전체 설치", 1, UDim.new(0.5, -2))
	const pruneButton = button("안 쓰는 패키지 정리", 2, UDim.new(0.5, -2))
	row(8, { installAllButton, pruneButton }).Parent = root

	-- 설정
	label("Config 경로 (ServerStorage.PackageLoaderConfig)", 9).Parent = root
	const sharedBox = textBox("Shared 경로", 10)
	sharedBox.Parent = root
	const serverPathBox = textBox("Server 경로", 11)
	serverPathBox.Parent = root

	-- 설치된 의존성
	label("의존성", 12).Parent = root
	const listFrame = make("Frame", {
		LayoutOrder = 13,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	-- 로그
	label("로그", 14).Parent = root
	const logLabel = make("TextLabel", {
		LayoutOrder = 15,
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
		print(`[PackageLoader] {message}`)
		table.insert(logLines, message)
		while #logLines > 40 do
			table.remove(logLines, 1)
		end
		logLabel.Text = table.concat(logLines, "\n")
	end

	local busy = false
	local refreshList: () -> ()

	-- 작업은 하나씩만, 오류는 로그로
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
		refreshList()
	end

	const function readLocation(): Instance?
		const text = string.match(locationBox.Text, "^%s*(.-)%s*$") :: string
		if text == "" then
			return nil
		end
		const location = Config.resolvePath(text, true)
		if not location then
			error(`설치 위치를 찾을 수 없음: {text}`, 0)
		end
		return location
	end

	refreshList = function()
		for _, child in listFrame:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		const dependencies = Config.getDependencies()
		const aliases = {}
		for alias in dependencies do
			table.insert(aliases, alias)
		end
		table.sort(aliases)

		for i, alias in aliases do
			const dependency = dependencies[alias]
			const where = dependency.location or dependency.realm
			const text = make("TextLabel", {
				LayoutOrder = 1,
				Size = UDim2.new(1, -64, 1, 0),
				BackgroundTransparency = 1,
				Text = `{alias} = {dependency.spec}  ({where})`,
				Font = Enum.Font.SourceSans,
				TextSize = 14,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
			})
			const removeButton = button("삭제", 2, UDim.new(0, 60))
			removeButton.Activated:Connect(function()
				task.spawn(run, function()
					Installer.remove(alias, log)
				end)
			end)
			row(i, { text, removeButton }).Parent = listFrame
		end
	end

	const function refreshConfig()
		sharedBox.Text = Config.getSharedPath()
		serverPathBox.Text = Config.getServerPath()
		refreshList()
	end

	pickButton.Activated:Connect(function()
		const selected = Selection:Get()[1]
		if selected then
			locationBox.Text = Config.pathOf(selected)
		else
			log("Explorer 에서 폴더를 먼저 선택해주세요")
		end
	end)

	serverButton.Activated:Connect(function()
		server = not server
		serverButton.Text = if server then "Realm: server" else "Realm: shared"
	end)

	installButton.Activated:Connect(function()
		task.spawn(run, function()
			const spec = specBox.Text
			if string.match(spec, "^%s*$") then
				error("패키지를 입력해주세요", 0)
			end
			const alias = string.match(aliasBox.Text, "^%s*(.-)%s*$")
			Installer.install(spec, {
				alias = if alias ~= "" then alias else nil,
				location = readLocation(),
				server = server,
				log = log,
			})
		end)
	end)

	fileButton.Activated:Connect(function()
		task.spawn(run, function()
			const alias = string.match(aliasBox.Text, "^%s*(.-)%s*$")
			Installer.importFiles({
				alias = if alias ~= "" then alias else nil,
				location = readLocation(),
				server = server,
				log = log,
			})
		end)
	end)

	installAllButton.Activated:Connect(function()
		task.spawn(run, function()
			Installer.installAll(log)
		end)
	end)

	pruneButton.Activated:Connect(function()
		task.spawn(run, function()
			Installer.prune(log)
		end)
	end)

	sharedBox.FocusLost:Connect(function()
		Config.setSharedPath(sharedBox.Text)
	end)
	serverPathBox.FocusLost:Connect(function()
		Config.setServerPath(serverPathBox.Text)
	end)

	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if widget.Enabled then
			refreshConfig()
		end
	end)
	refreshConfig()
end

return Ui
