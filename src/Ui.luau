-- DockWidget UI: 입력창 하나 + 버튼 + 로그

const Selection = game:GetService("Selection")

const Config = require(script.Parent.Config)
const Installer = require(script.Parent.Installer)
const Linker = require(script.Parent.Linker)

const Ui = {}

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

const function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

-- "sleitnick/signal@^2 as Sig" -> ("sleitnick/signal@^2", "Sig")
const function parseSpec(text: string): (string, string?)
	const spec, alias = string.match(trim(text), "^(.-)%s+as%s+(%S+)$")
	if spec then
		return spec, alias
	end
	return trim(text), nil
end

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
	})

	const input = make("TextBox", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 28),
		PlaceholderText = "sleitnick/signal@^2 as Signal  |  gh:owner/repo@^1  |  path",
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
		print(`[PackageLoader] {message}`)
		table.insert(logLines, message)
		while #logLines > 60 do
			table.remove(logLines, 1)
		end
		logLabel.Text = table.concat(logLines, "\n")
	end

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
			task.spawn(run, job)
		end)
	end

	const function selected(): Instance?
		return Selection:Get()[1]
	end

	const function requireSpec(): (string, string?)
		const spec, alias = parseSpec(input.Text)
		if spec == "" then
			error("패키지를 입력해주세요 (예: sleitnick/signal@^2)", 0)
		end
		return spec, alias
	end

	const function install(location: Instance)
		const spec, alias = requireSpec()
		Installer.install(spec, { alias = alias, location = location, log = log })
	end

	addButton("Add", function()
		install(Installer.sharedRoot())
	end)

	addButton("Add to Server", function()
		install(Installer.serverRoot())
	end)

	addButton("Add to Selected", function()
		const target = selected()
		if not target then
			error("Explorer 에서 설치할 폴더를 선택해주세요", 0)
		end
		install(target)
	end)

	addButton("Remove", function()
		const alias = trim(input.Text)
		if alias ~= "" then
			Installer.remove(alias, nil, log)
			return
		end
		const target = selected()
		if target and target:GetAttribute(Linker.LINK_ATTRIBUTE) and target.Parent then
			Installer.remove(target.Name, target.Parent, log)
		else
			error("지울 별칭을 입력하거나 Explorer 에서 패키지를 선택해주세요", 0)
		end
	end)

	addButton("Install All", function()
		Installer.installAll(log)
	end)

	addButton("Prune", function()
		Installer.prune(log)
		log("정리 완료")
	end)

	addButton("Import File", function()
		Installer.importFiles({ location = selected(), log = log })
	end)

	const function readPath(): string
		const target = selected()
		if target then
			return Config.pathOf(target)
		end
		const text = trim(input.Text)
		if text == "" then
			error("Explorer 에서 폴더를 선택하거나 경로를 입력해주세요", 0)
		end
		Config.resolvePath(text, true)
		return text
	end

	addButton("Set Shared Path", function()
		const path = readPath()
		Config.setSharedPath(path)
		log(`shared 경로: {path}`)
	end)

	addButton("Set Server Path", function()
		const path = readPath()
		Config.setServerPath(path)
		log(`server 경로: {path}`)
	end)

	addButton("Open Config", function()
		plugin:OpenScript(Config.getModule())
	end)

	root.Parent = widget

	const ok, data = pcall(Config.read)
	if ok then
		log(`shared: {data.shared}`)
		log(`server: {data.server}`)
	else
		log(`오류: {data}`)
	end
end

return Ui
