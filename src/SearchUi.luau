-- 검색 창: Wally / GitHub 에서 패키지를 찾아서 Add (Config 에 추가)

const Commands = require(script.Parent.Commands)
const Log = require(script.Parent.Log)
const Search = require(script.Parent.Sources.Search)

const SearchUi = {}

const SETTINGS_KEY = "RO_BURa.WallyPackageLoader.Search"
const ROW_HEIGHT = 58

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

	-- 1줄: 검색어 + 설정 버튼
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
	const settingsButton = textButton({
		Text = "⚙",
		TextSize = 18,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -28, 0, 0),
		Parent = queryRow,
	})

	-- 체크 버튼 하나
	const function toggle(parent: Instance, order: number, label: string, get: () -> boolean, set: ((boolean) -> ())?): TextButton
		const button = textButton({
			LayoutOrder = order,
			Size = UDim2.new(0, 0, 0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = parent,
		})
		make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 8), Parent = button })
		const function refresh()
			button.Text = (if get() then "☑ " else "☐ ") .. label
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
			button.TextColor3 = themeColor(Enum.StudioStyleGuideColor.DimmedText)
		end
		return button
	end

	const function row(order: number): Frame
		return make("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = top,
		}, {
			make("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Wraps = true,
			}),
		}) :: Frame
	end

	-- 2줄: 레지스트리 선택 (여러 개 가능)
	const registries = row(2)
	toggle(registries, 1, "Wally", function()
		return current.wally
	end, function(value)
		current.wally = value
	end)
	-- pesde 는 중앙 레지스트리가 없어지는 중이고 설치도 아직 안 돼서 비활성
	toggle(registries, 2, "pesde (준비 중)", function()
		return false
	end, nil)
	toggle(registries, 3, "GitHub", function()
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
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
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

	-- 결과 목록 (남은 공간 전체)
	const list = make("ScrollingFrame", {
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = themeColor(Enum.StudioStyleGuideColor.ScrollBar),
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		BorderSizePixel = 1,
		BorderColor3 = themeColor(Enum.StudioStyleGuideColor.Border),
		BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.ScriptBackground),
		Parent = root,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	}) :: ScrollingFrame
	const function layout()
		const height = top.AbsoluteSize.Y
		list.Position = UDim2.fromOffset(8, height)
		list.Size = UDim2.new(1, -16, 1, -height - 8)
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

	const function clearResults()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	const function addRow(order: number, result: Search.Result)
		const item = make("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			BackgroundTransparency = 1,
			Parent = list,
		}, {
			make("UIPadding", {
				PaddingLeft = UDim.new(0, 6),
				PaddingRight = UDim.new(0, 6),
				PaddingTop = UDim.new(0, 4),
			}),
		})
		make("TextLabel", {
			Size = UDim2.new(1, -70, 0, 18),
			BackgroundTransparency = 1,
			RichText = true,
			Text = `<b>{result.id}</b>  <font transparency="0.4">{result.detail}</font>`,
			Font = Enum.Font.Code,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
			Parent = item,
		})
		make("TextLabel", {
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, -70, 0, 32),
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
		const add = textButton({
			Text = "Add",
			Size = UDim2.fromOffset(60, 24),
			Position = UDim2.new(1, -60, 0, 4),
			Parent = item,
		})
		add.Activated:Connect(function()
			add.Text = "..."
			task.spawn(function()
				const ok, err = pcall(Commands.add, result.spec, NO_FLAGS, addContext)
				if ok then
					add.Text = "Added"
					status.Text = `Config 에 추가함: {result.spec} (설치는 Install All)`
				else
					add.Text = "Add"
					status.Text = `오류: {err}`
					Log.write(`오류: {err}`)
				end
			end)
		end)
		-- 줄 사이 구분선
		make("Frame", {
			Position = UDim2.new(0, -6, 1, -5),
			Size = UDim2.new(1, 12, 0, 1),
			BorderSizePixel = 0,
			BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.Border),
			Parent = item,
		})
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
			status.Text = `{#results}개` .. (if #errors > 0 then "  오류: " .. table.concat(errors, " / ") else "")
		end)
	end
	query.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			runSearch()
		end
	end)

	settings().Studio.ThemeChanged:Connect(function()
		root.BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.MainBackground)
		list.BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.ScriptBackground)
	end)

	root.Parent = widget
end

return SearchUi
