-- 검색 창: Wally / GitHub 에서 패키지를 찾고, 눌러서 상세 정보 (버전 선택, 의존성, 내부 구조) 를 보고 Add

const Auth = require(script.Parent.Auth)
const Commands = require(script.Parent.Commands)
const Fmt = require(script.Parent.Fmt)
const Icons = require(script.Parent.Icons)
const Log = require(script.Parent.Log)
const Details = require(script.Parent.Sources.Details)
const Search = require(script.Parent.Sources.Search)

const SearchUi = {}

const SETTINGS_KEY = "RO_BURa.WallyPackageLoader.Search"
const ROW_HEIGHT = 58
const ICON_SIZE = 16

type Settings = {
	wally: boolean,
	github: boolean,
	luauOnly: boolean,
	author: string,
}

const DEFAULT_SETTINGS: Settings = { wally = true, github = false, luauOnly = true, author = "" }

const function themeColor(color: Enum.StudioStyleGuideColor): Color3
	return settings().Studio.Theme:GetColor(color)
end

const function isDarkTheme(): boolean
	const background = themeColor(Enum.StudioStyleGuideColor.MainBackground)
	return (background.R + background.G + background.B) / 3 < 0.5
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

const function textButton(props: { [string]: any }): TextButton
	const merged = {
		Font = Enum.Font.SourceSansSemibold,
		TextSize = 15,
		AutoButtonColor = true,
		BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.Button),
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.ButtonText),
		BorderColor3 = themeColor(Enum.StudioStyleGuideColor.ButtonBorder),
	}
	for key, value in props do
		merged[key] = value
	end
	return make("TextButton", merged) :: TextButton
end

-- 아이콘 + 글자 버튼 (가로로 자동 크기)
const function iconButton(icon: string, text: string, props: { [string]: any }): (TextButton, TextLabel, TextLabel)
	const button = textButton(props)
	button.Text = ""
	if not props.Size then
		button.Size = UDim2.new(0, 0, 0, 24)
		button.AutomaticSize = Enum.AutomaticSize.X
	end
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = if text == "" then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = button,
	})
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = button })
	const iconLabel = Icons.label(icon, ICON_SIZE, false, {
		LayoutOrder = 1,
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.ButtonText),
		Parent = button,
	})
	const textLabel = make("TextLabel", {
		LayoutOrder = 2,
		Visible = text ~= "",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text,
		Font = Enum.Font.SourceSansSemibold,
		TextSize = 15,
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.ButtonText),
		Parent = button,
	}) :: TextLabel
	return button, iconLabel, textLabel
end

const function inputBox(props: { [string]: any }): TextBox
	const merged = {
		Text = "",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.Code,
		TextSize = 14,
		BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.InputFieldBackground),
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
		PlaceholderColor3 = themeColor(Enum.StudioStyleGuideColor.DimmedText),
		BorderColor3 = themeColor(Enum.StudioStyleGuideColor.InputFieldBorder),
	}
	for key, value in props do
		merged[key] = value
	end
	return make("TextBox", merged, {
		make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	}) :: TextBox
end

const function scrollFrame(props: { [string]: any }): ScrollingFrame
	const merged = {
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = themeColor(Enum.StudioStyleGuideColor.ScrollBar),
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		BorderSizePixel = 1,
		BorderColor3 = themeColor(Enum.StudioStyleGuideColor.Border),
		BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.ScriptBackground),
	}
	for key, value in props do
		merged[key] = value
	end
	return make("ScrollingFrame", merged) :: ScrollingFrame
end

function SearchUi.mount(widget: DockWidgetPluginGui, plugin: Plugin)
	-- 설정 (이 컴퓨터에 저장)
	const saved = plugin:GetSetting(SETTINGS_KEY)
	const current: Settings = table.clone(DEFAULT_SETTINGS)
	if type(saved) == "table" then
		for key, default in DEFAULT_SETTINGS do
			if type(saved[key]) == type(default) then
				(current :: any)[key] = saved[key]
			end
		end
	end
	const function save()
		plugin:SetSetting(SETTINGS_KEY, current)
	end

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

	-- 1줄: 검색어 + 검색 버튼 (Enter 도 됨)
	const queryRow = make("Frame", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Parent = top,
	})
	const query = inputBox({
		Size = UDim2.new(1, -34, 1, 0),
		PlaceholderText = "검색어 (Enter 로 검색)",
		Parent = queryRow,
	})
	const searchButton = iconButton("magnifying-glass", "", {
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -28, 0, 0),
		Parent = queryRow,
	})

	-- 2줄: 레지스트리 선택 (여러 개 가능) + 설정 버튼
	const registryRow = make("Frame", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Parent = top,
	})
	const toggles = make("Frame", {
		Size = UDim2.new(1, -34, 1, 0),
		BackgroundTransparency = 1,
		Parent = registryRow,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	const settingsButton = iconButton("gear", "", {
		Size = UDim2.fromOffset(28, 24),
		Position = UDim2.new(1, -28, 0, 0),
		Parent = registryRow,
	})

	-- 체크 버튼 (켜짐: square-check 굵게, 꺼짐: square, 못 씀: square-minus)
	const function toggle(parent: Instance, order: number, label: string, get: () -> boolean, set: ((boolean) -> ())?)
		const button, icon, text = iconButton("square", label, { LayoutOrder = order, Parent = parent })
		const function refresh()
			if not set then
				Icons.set(icon, "square-minus", false)
			elseif get() then
				Icons.set(icon, "square-check", true)
			else
				Icons.set(icon, "square", false)
			end
		end
		refresh()
		if set then
			button.Activated:Connect(function()
				set(not get())
				save()
				refresh()
			end)
		else
			button.AutoButtonColor = false
			icon.TextColor3 = themeColor(Enum.StudioStyleGuideColor.DimmedText)
			text.TextColor3 = themeColor(Enum.StudioStyleGuideColor.DimmedText)
		end
	end

	toggle(toggles, 1, "Wally", function()
		return current.wally
	end, function(value)
		current.wally = value
	end)
	-- pesde: 플러그인이 pesde 레지스트리 패키지를 아직 설치 못 함
	toggle(toggles, 2, "pesde", function()
		return false
	end, nil)
	toggle(toggles, 3, "GitHub", function()
		return current.github
	end, function(value)
		current.github = value
	end)

	-- 설정 (⚙ 로 열고 닫음)
	const settingsPanel = make("Frame", {
		LayoutOrder = 3,
		Visible = false,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = top,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	}) :: Frame
	const author = inputBox({
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 26),
		Text = current.author,
		PlaceholderText = "작성자: Wally scope / GitHub 사용자 (비우면 전체)",
		Parent = settingsPanel,
	})
	author.FocusLost:Connect(function()
		current.author = (string.gsub(author.Text, "%s", ""))
		author.Text = current.author
		save()
	end)
	const githubOptions = make("Frame", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Parent = settingsPanel,
	}, {
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	toggle(githubOptions, 1, "GitHub: Luau 저장소만", function()
		return current.luauOnly
	end, function(value)
		current.luauOnly = value
	end)
	settingsButton.Activated:Connect(function()
		settingsPanel.Visible = not settingsPanel.Visible
	end)

	const status = make("TextLabel", {
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Text = "",
		Font = Enum.Font.SourceSans,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.DimmedText),
		Parent = top,
	}) :: TextLabel

	-- 아래: 결과 목록 또는 상세 화면 (남은 공간 전체)
	const list = scrollFrame({ AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = root })
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	const detail = make("Frame", { Visible = false, BackgroundTransparency = 1, Parent = root }) :: Frame
	const function layout()
		const height = top.AbsoluteSize.Y
		for _, area in { list, detail } :: { GuiObject } do
			area.Position = UDim2.fromOffset(8, height)
			area.Size = UDim2.new(1, -16, 1, -height - 8)
		end
	end
	top:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

	-- Add: 메인 창의 add 와 같음 (Config 의 shared 에 추가, 결과는 메인 로그에도)
	const addContext: Commands.Context = {
		plugin = plugin,
		log = Log.write,
		rich = Log.write,
		clear = function() end,
		secret = function()
			return nil
		end,
	}
	const NO_FLAGS: Commands.Flags = { server = false, selected = false, to = nil }
	const function addSpec(spec: string, button: TextLabel?)
		task.spawn(function()
			const ok, err = pcall(Commands.add, spec, NO_FLAGS, addContext)
			if ok then
				status.Text = `Config 에 추가함: {spec} (설치는 Install All)`
				if button then
					button.Text = "Added"
				end
			else
				status.Text = `오류: {err}`
				Log.write(`오류: {err}`)
			end
		end)
	end

	----------------------------------------------------------------------------
	-- 상세 화면

	const header = make("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = detail })
	const backButton = iconButton("chevron-large-left", "Back", { Parent = header })
	const title = make("TextLabel", {
		Position = UDim2.fromOffset(80, 0),
		Size = UDim2.new(1, -80, 1, 0),
		BackgroundTransparency = 1,
		RichText = true,
		Text = "",
		Font = Enum.Font.Code,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
		Parent = header,
	}) :: TextLabel

	const controls = make("Frame", {
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Parent = detail,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	const versionButton, _, versionText = iconButton("chevron-small-down", "버전", { LayoutOrder = 1, Parent = controls })
	const addExact, _, addExactText = iconButton("plus-small", "Add", { LayoutOrder = 2, Parent = controls })
	const addRange, _, addRangeText = iconButton("plus-small", "Add ^", { LayoutOrder = 3, Parent = controls })
	const filesButton, filesIcon, filesText = iconButton("folder", "Files", { LayoutOrder = 4, Parent = controls })

	-- 본문: 글자 하나 (RichText), 높이는 TextBounds 로
	const body = scrollFrame({
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 1, -60),
		Parent = detail,
	})
	const bodyText = make("TextLabel", {
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(1, -12, 0, 0),
		BackgroundTransparency = 1,
		RichText = true,
		Text = "",
		Font = Enum.Font.Code,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
		Parent = body,
	}) :: TextLabel
	const function fitBody()
		const height = bodyText.TextBounds.Y + 16
		bodyText.Size = UDim2.new(1, -12, 0, height)
		body.CanvasSize = UDim2.fromOffset(0, height + 8)
	end
	bodyText:GetPropertyChangedSignal("TextBounds"):Connect(fitBody)
	local bodyMarkup = ""
	const function setBody(markup: string)
		bodyMarkup = markup
		bodyText.Text = Fmt.resolve(markup, isDarkTheme())
		body.CanvasPosition = Vector2.zero
		fitBody()
	end

	-- 버전 고르기 목록 (버전 버튼 아래에 뜸)
	const versionPopup = scrollFrame({
		Visible = false,
		ZIndex = 10,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(0.6, 0, 0, 200),
		BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.MainBackground),
		Parent = detail,
	})
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = versionPopup })

	-- 지금 보고 있는 패키지
	type View = {
		versions: { Details.Version },
		selected: Details.Version?,
		-- 고른 버전의 정보를 본문 글자로
		info: (version: Details.Version) -> string,
		files: ((version: Details.Version) -> { string })?,
		showingFiles: boolean,
	}
	local view: View? = nil
	local loadGeneration = 0

	const function line(title: string, value: string): string
		return Fmt.color("dim", Fmt.escape(title)) .. "  " .. Fmt.escape(value)
	end
	const function dependencyLines(lines: { string }, heading: string, map: { [string]: string })
		const keys = {}
		for key in map do
			table.insert(keys, key)
		end
		table.sort(keys)
		table.insert(lines, "")
		table.insert(lines, Fmt.color("yellow", Fmt.bold(heading)))
		if #keys == 0 then
			table.insert(lines, Fmt.color("dim", "  (없음)"))
		end
		for _, key in keys do
			table.insert(lines, "  " .. Fmt.bold(Fmt.escape(key)) .. "  " .. Fmt.color("dim", Fmt.escape(tostring(map[key]))))
		end
	end
	const function infoMarkup(info: Details.Info): string
		const lines = {}
		for _, field in info.fields do
			table.insert(lines, line(field[1], field[2]))
		end
		if info.warning then
			table.insert(lines, Fmt.color("yellow", "경고: " .. Fmt.escape(info.warning)))
		end
		dependencyLines(lines, "의존성", info.dependencies)
		if next(info.serverDependencies) then
			dependencyLines(lines, "server 의존성", info.serverDependencies)
		end
		if info.extra then
			table.insert(lines, "")
			table.insert(lines, Fmt.color("yellow", Fmt.bold("README")))
			table.insert(lines, Fmt.color("dim", Fmt.escape(info.extra)))
		end
		return table.concat(lines, "\n")
	end

	-- 고른 버전으로 본문 / 버튼 갱신
	const function showVersion(version: Details.Version)
		const current = view
		if not current then
			return
		end
		current.selected = version
		current.showingFiles = false
		versionText.Text = version.label
		addExactText.Text = "Add " .. version.label
		addExact.Visible = true
		addRange.Visible = version.rangeSpec ~= nil
		addRangeText.Text = "Add ^"
		Icons.set(filesIcon, "folder", false)
		filesText.Text = "Files"
		setBody(Fmt.color("dim", "불러오는 중..."))
		loadGeneration += 1
		const mine = loadGeneration
		task.spawn(function()
			const ok, result = pcall(current.info, version)
			if mine == loadGeneration and view == current then
				setBody(if ok then result else Fmt.color("red", "오류: " .. Fmt.escape(tostring(result))))
			end
		end)
	end

	versionButton.Activated:Connect(function()
		const current = view
		if not current or #current.versions == 0 then
			return
		end
		if versionPopup.Visible then
			versionPopup.Visible = false
			return
		end
		for _, child in versionPopup:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, version in current.versions do
			const option = textButton({
				LayoutOrder = i,
				ZIndex = 11,
				Size = UDim2.new(1, 0, 0, 22),
				Text = "  " .. version.label .. (if version.prerelease then "  (pre)" else ""),
				Font = Enum.Font.Code,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				BorderSizePixel = 0,
				BackgroundColor3 = if version == current.selected
					then themeColor(Enum.StudioStyleGuideColor.Item)
					else themeColor(Enum.StudioStyleGuideColor.MainBackground),
				Parent = versionPopup,
			})
			option.Activated:Connect(function()
				versionPopup.Visible = false
				showVersion(version)
			end)
		end
		versionPopup.Visible = true
	end)

	addExact.Activated:Connect(function()
		const current = view
		if current and current.selected then
			addSpec(current.selected.spec, addExactText)
		end
	end)
	addRange.Activated:Connect(function()
		const current = view
		if current and current.selected and current.selected.rangeSpec then
			addSpec(current.selected.rangeSpec :: string, addRangeText)
		end
	end)

	-- 내부 구조 보기 <-> 정보 보기
	filesButton.Activated:Connect(function()
		const current = view
		if not current or not current.selected or not current.files then
			return
		end
		if current.showingFiles then
			showVersion(current.selected)
			return
		end
		current.showingFiles = true
		Icons.set(filesIcon, "file-box", false)
		filesText.Text = "Info"
		setBody(Fmt.color("dim", "파일 목록을 받는 중..."))
		loadGeneration += 1
		const mine = loadGeneration
		const version = current.selected
		task.spawn(function()
			const ok, result = pcall(current.files :: any, version)
			if mine ~= loadGeneration or view ~= current then
				return
			end
			if not ok then
				setBody(Fmt.color("red", "오류: " .. Fmt.escape(tostring(result))))
				return
			end
			const lines = { Fmt.color("yellow", Fmt.bold(`내부 구조 ({version.label}, {#result}개 파일)`)) }
			for _, text in Details.pathTree(result) do
				table.insert(lines, Fmt.escape(text))
			end
			setBody(table.concat(lines, "\n"))
		end)
	end)

	const function closeDetail()
		view = nil
		loadGeneration += 1
		versionPopup.Visible = false
		detail.Visible = false
		list.Visible = true
	end
	backButton.Activated:Connect(closeDetail)

	-- 결과 하나 열기
	const function openDetail(result: Search.Result)
		list.Visible = false
		detail.Visible = true
		versionPopup.Visible = false
		addExact.Visible = false
		addRange.Visible = false
		versionText.Text = "버전"
		title.Text = Fmt.resolve(Fmt.bold(Fmt.escape(result.id)), isDarkTheme())
		setBody(Fmt.color("dim", "불러오는 중..."))
		loadGeneration += 1
		const mine = loadGeneration

		task.spawn(function()
			const ok, err = pcall(function()
				const owner, name = string.match(result.id, "^([^/]+)/(.+)$")
				if result.source == "wally" then
					const data = Details.wally(owner :: string, name :: string)
					const newView: View = {
						versions = data.versions,
						info = function(version)
							return infoMarkup(data.info(version))
						end,
						files = function(version)
							return Details.wallyFiles(owner :: string, name :: string, version.label)
						end,
						showingFiles = false,
					}
					if mine ~= loadGeneration then
						return
					end
					view = newView
				else
					const repo = Details.githubRepo(owner :: string, name :: string)
					const versions = Details.githubVersions(owner :: string, name :: string, repo.defaultBranch)
					-- 별: 1개 이상이면 굵게, 내가 눌렀으면 표시
					const starText = if repo.starred
						then Fmt.color("yellow", `★ {repo.stars} (내가 누름)`)
						else Fmt.color("dim", `★ {repo.stars}`)
					const newView: View = {
						versions = versions,
						info = function(version)
							const info = Details.githubInfo(owner :: string, name :: string, version)
							const fields = table.clone(repo.fields)
							for _, field in info.fields do
								table.insert(fields, field)
							end
							info.fields = fields
							return infoMarkup(info)
						end,
						files = function(version)
							return Details.githubFiles(owner :: string, name :: string, version)
						end,
						showingFiles = false,
					}
					if mine ~= loadGeneration then
						return
					end
					title.Text = Fmt.resolve(Fmt.bold(Fmt.escape(result.id)) .. "  " .. starText, isDarkTheme())
					view = newView
				end
				const newView = view :: View
				if #newView.versions == 0 then
					setBody(Fmt.color("yellow", "버전이 없음"))
					return
				end
				showVersion(Details.defaultVersion(newView.versions) :: Details.Version)
			end)
			if not ok and mine == loadGeneration then
				setBody(Fmt.color("red", "오류: " .. Fmt.escape(tostring(err))))
			end
		end)
	end

	----------------------------------------------------------------------------
	-- 결과 목록

	const function clearResults()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	const function addRow(order: number, result: Search.Result)
		-- 줄 전체가 버튼: 누르면 상세 화면, 올리면 제목에 밑줄
		const item = make("TextButton", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			Parent = list,
		}) :: TextButton
		const titleLabel = make("TextLabel", {
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(1, -80, 0, 18),
			BackgroundTransparency = 1,
			RichText = true,
			Font = Enum.Font.Code,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
			Parent = item,
		}) :: TextLabel
		-- GitHub 은 별 개수 (별 아이콘: 1개 이상이면 굵게), Wally 는 최신 버전
		const stars = if result.source == "github" then tonumber(string.match(result.detail, "%d+")) or 0 else nil
		const detailText = if stars then tostring(stars) else result.detail
		const function setTitle(underline: boolean)
			const name = if underline then `<u>{Fmt.escape(result.id)}</u>` else Fmt.escape(result.id)
			titleLabel.Text = `<b>{name}</b>  <font transparency="0.4">{Fmt.escape(detailText)}</font>`
		end
		setTitle(false)
		if stars then
			Icons.label("star", 13, stars > 0, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -72, 0, 6),
				TextColor3 = if stars > 0
					then Color3.fromRGB(229, 192, 123)
					else themeColor(Enum.StudioStyleGuideColor.DimmedText),
				Parent = item,
			})
		end
		make("TextLabel", {
			Position = UDim2.fromOffset(6, 22),
			Size = UDim2.new(1, -80, 0, 32),
			BackgroundTransparency = 1,
			Text = (if result.source == "github" then "[GitHub] " else "[Wally] ")
				.. (if result.description ~= "" then result.description else "(설명 없음)"),
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = themeColor(Enum.StudioStyleGuideColor.DimmedText),
			Parent = item,
		})
		const add, _, addText = iconButton("plus-small", "Add", {
			ZIndex = 2,
			Size = UDim2.fromOffset(64, 24),
			Position = UDim2.new(1, -66, 0, 4),
			Parent = item,
		})
		add.Activated:Connect(function()
			addText.Text = "..."
			addSpec(result.spec, addText)
		end)
		make("Frame", {
			Position = UDim2.new(0, 0, 1, -1),
			Size = UDim2.new(1, 0, 0, 1),
			BorderSizePixel = 0,
			BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.Border),
			Parent = item,
		})

		item.MouseEnter:Connect(function()
			setTitle(true)
			item.BackgroundTransparency = 0.85
			item.BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.Item)
		end)
		item.MouseLeave:Connect(function()
			setTitle(false)
			item.BackgroundTransparency = 1
		end)
		item.Activated:Connect(function()
			openDetail(result)
		end)
	end

	-- 검색 (새로 검색하면 이전 결과는 버림)
	local generation = 0
	const function runSearch()
		const text = string.match(query.Text, "^%s*(.-)%s*$") :: string
		if not current.wally and not current.github then
			status.Text = "검색할 곳을 하나 이상 선택해주세요"
			return
		end
		generation += 1
		const mine = generation
		closeDetail()
		clearResults()
		status.Text = "검색 중..."
		task.spawn(function()
			const options = { author = current.author, luauOnly = current.luauOnly }
			const results: { Search.Result } = {}
			const errors = {}
			for _, source in { "wally", "github" } do
				if (current :: any)[source] then
					const ok, found = pcall((Search :: any)[source], text, options)
					if ok then
						for _, result in found do
							table.insert(results, result)
						end
					else
						table.insert(errors, `{source}: {found}`)
					end
				end
			end
			if mine ~= generation then
				return
			end
			for i, result in results do
				addRow(i, result)
			end
			status.Text = `{#results}개`
				.. (if current.github and not Auth.getToken() then " (GitHub 은 로그인하면 요청 한도가 늘어남)" else "")
				.. (if #errors > 0 then "  오류: " .. table.concat(errors, " / ") else "")
		end)
	end
	query.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			runSearch()
		end
	end)
	searchButton.Activated:Connect(runSearch)

	settings().Studio.ThemeChanged:Connect(function()
		root.BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.MainBackground)
		list.BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.ScriptBackground)
		body.BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.ScriptBackground)
		bodyText.TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText)
		bodyText.Text = Fmt.resolve(bodyMarkup, isDarkTheme())
	end)

	root.Parent = widget
end

return SearchUi
