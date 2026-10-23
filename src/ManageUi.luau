-- 관리 창: 설치한 패키지 목록, 업데이트 (Major 표시), 의존성 트리, 라이선스

const L = require(script.Parent.Locale).L
const Commands = require(script.Parent.Commands)
const Config = require(script.Parent.Config)
const Fmt = require(script.Parent.Fmt)
const Icons = require(script.Parent.Icons)
const Installer = require(script.Parent.Installer)
const Log = require(script.Parent.Log)
const Updates = require(script.Parent.Updates)
const Widgets = require(script.Parent.Widgets)

const themeColor = Widgets.themeColor
const isDarkTheme = Widgets.isDarkTheme
const make = Widgets.make
const textButton = Widgets.textButton
const iconButton = Widgets.iconButton
const scrollFrame = Widgets.scrollFrame

const ManageUi = {}

const ROW_HEIGHT = 30
const HEADER_HEIGHT = 26
const ACTIONS_WIDTH = 104
-- 이보다 좁으면 Source 열을 숨기고 이름 앞 로고로만
const WIDE = 420

type Tab = "installed" | "updates" | "tree" | "licenses"

-- 검색 창 상세 화면을 여는 함수 (SearchUi.mount 가 돌려줌)
export type SearchController = {
	open: (result: any) -> (),
}

function ManageUi.mount(widget: DockWidgetPluginGui, plugin: Plugin, search: SearchController)
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
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
	}) :: Frame

	-- 1줄: 탭 + 새로고침
	const tabRow = make("Frame", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Parent = top,
	})
	const tabs = make("Frame", {
		Size = UDim2.new(1, -34, 1, 0),
		BackgroundTransparency = 1,
		Parent = tabRow,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	const refreshButton = iconButton("arrow-rotate-right", "", {
		Size = UDim2.fromOffset(28, 24),
		Position = UDim2.new(1, -28, 0, 0),
		Parent = tabRow,
	})

	-- 2줄: 업데이트 알림 (있을 때만)
	const banner = make("Frame", {
		LayoutOrder = 2,
		Visible = false,
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.Item),
		BorderSizePixel = 0,
		Parent = top,
	}, {
		make("UICorner", { CornerRadius = UDim.new(0, 4) }),
	}) :: Frame
	Icons.label("circle-i", 16, false, {
		Position = UDim2.fromOffset(8, 8),
		TextColor3 = Color3.fromRGB(97, 175, 239),
		Parent = banner,
	})
	const bannerText = make("TextLabel", {
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -130, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		Font = Enum.Font.SourceSans,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
		Parent = banner,
	}) :: TextLabel
	const updateAllButton = textButton({
		Text = L("Update all", "Update all"),
		Size = UDim2.fromOffset(90, 24),
		Position = UDim2.new(1, -96, 0, 4),
		Parent = banner,
	})

	const status = make("TextLabel", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = "",
		Font = Enum.Font.SourceSans,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = themeColor(Enum.StudioStyleGuideColor.DimmedText),
		Parent = top,
	}) :: TextLabel

	-- 아래: 목록 (Installed / Updates) 또는 글 (Tree / Licenses)
	const list = scrollFrame({ AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = root })
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	const textArea = scrollFrame({ Visible = false, Parent = root })
	const textLabel = make("TextLabel", {
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
		Parent = textArea,
	}) :: TextLabel
	textLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
		const height = textLabel.TextBounds.Y + 16
		textLabel.Size = UDim2.new(1, -12, 0, height)
		textArea.CanvasSize = UDim2.fromOffset(0, height + 8)
	end)
	local textMarkup = ""
	const function setText(markup: string)
		textMarkup = markup
		textLabel.Text = Fmt.resolve(markup, isDarkTheme())
	end

	const function layout()
		const height = top.AbsoluteSize.Y
		for _, area in { list, textArea } :: { GuiObject } do
			area.Position = UDim2.fromOffset(8, height)
			area.Size = UDim2.new(1, -16, 1, -height - 8)
		end
	end
	top:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

	----------------------------------------------------------------------------
	-- 상태

	local currentTab: Tab = "installed"
	local statuses: { Updates.Status } = {}
	local checked = false
	local busy = false
	local render: () -> ()

	const function logBoth(message: string)
		status.Text = message
		Log.write(message)
	end

	-- 오래 걸리는 작업 하나씩 (끝나면 목록을 다시 읽음)
	local refresh: (check: boolean) -> ()
	const function job(fn: () -> ())
		if busy then
			status.Text = L("이전 작업이 끝날 때까지 기다려주세요", "Wait for the previous job to finish")
			return
		end
		busy = true
		task.spawn(function()
			const ok, err = pcall(fn)
			busy = false
			if not ok then
				logBoth(L(`오류: {err}`, `Error: {err}`))
			end
			refresh(false)
		end)
	end

	const function updateCount(): (number, number)
		local all, safe = 0, 0
		for _, item in statuses do
			if item.newSpec then
				all += 1
				if not item.major then
					safe += 1
				end
			end
		end
		return all, safe
	end

	----------------------------------------------------------------------------
	-- 탭

	const tabButtons: { [Tab]: TextLabel } = {}
	const tabFrames: { [Tab]: TextButton } = {}
	const function tabButton(order: number, tab: Tab, icon: string, text: string)
		const button, _, label = iconButton(icon, text, { LayoutOrder = order, Parent = tabs })
		tabButtons[tab] = label
		tabFrames[tab] = button
		button.Activated:Connect(function()
			currentTab = tab
			render()
		end)
	end
	tabButton(1, "installed", "stackable-check", "Installed")
	tabButton(2, "updates", "arrow-rotate-right", "Updates")
	tabButton(3, "tree", "three-box-flowchart", "Tree")
	tabButton(4, "licenses", "document-list-heart", "Licenses")

	----------------------------------------------------------------------------
	-- 목록 줄

	-- ⋯ 메뉴 (한 번에 하나)
	local openMenu: Frame? = nil
	const function closeMenu()
		if openMenu then
			openMenu:Destroy()
			openMenu = nil
		end
	end

	const function menu(anchor: GuiObject, items: { { string } }, onPick: (string) -> ())
		closeMenu()
		const frame = make("Frame", {
			ZIndex = 20,
			Size = UDim2.fromOffset(130, #items * 24 + 4),
			Position = UDim2.fromOffset(
				anchor.AbsolutePosition.X - root.AbsolutePosition.X - 130 + anchor.AbsoluteSize.X,
				anchor.AbsolutePosition.Y - root.AbsolutePosition.Y + anchor.AbsoluteSize.Y + 2
			),
			BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.MainBackground),
			BorderColor3 = themeColor(Enum.StudioStyleGuideColor.Border),
			Parent = root,
		}, {
			make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
			make("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2) }),
		}) :: Frame
		for i, item in items do
			const option = textButton({
				LayoutOrder = i,
				ZIndex = 21,
				Size = UDim2.new(1, 0, 0, 24),
				Text = "  " .. item[2],
				TextXAlignment = Enum.TextXAlignment.Left,
				BorderSizePixel = 0,
				BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.MainBackground),
				Parent = frame,
			})
			option.Activated:Connect(function()
				closeMenu()
				onPick(item[1])
			end)
		end
		openMenu = frame
	end

	-- 검색 창에서 열 수 있는 형태로
	const function asSearchResult(item: Updates.Status): any
		return {
			source = item.source,
			id = item.id,
			detail = item.current or "",
			description = "",
			spec = item.spec or "",
		}
	end

	const function versionMarkup(item: Updates.Status): string
		if not item.installed then
			return Fmt.color("yellow", L("설치 안 됨", "not installed"))
		end
		if item.error then
			return Fmt.escape(item.current or "?") .. " " .. Fmt.color("red", L("확인 실패", "check failed"))
		end
		if item.newSpec then
			local text = `{Fmt.escape(item.current or "?")} → ` .. Fmt.bold(Fmt.escape(item.latest or "?"))
			if item.major then
				text ..= "  " .. Fmt.color("yellow", "● Major")
			end
			return text
		end
		return Fmt.escape(item.current or (if item.source == "import" then "—" else "?"))
	end

	const function row(order: number, item: Updates.Status, wide: boolean)
		const line = make("TextButton", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			Parent = list,
		}) :: TextButton
		Widgets.sourceIcon(item.source, 16, { Position = UDim2.fromOffset(8, 7), Parent = line })
		const nameLabel = make("TextLabel", {
			Position = UDim2.fromOffset(30, 0),
			Size = UDim2.new(0.4, -30, 1, 0),
			BackgroundTransparency = 1,
			RichText = true,
			Text = Fmt.escape(item.alias),
			Font = Enum.Font.SourceSans,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
			Parent = line,
		}) :: TextLabel
		make("TextLabel", {
			Position = UDim2.fromScale(0.4, 0),
			Size = if wide then UDim2.new(0.35, 0, 1, 0) else UDim2.new(0.6, -ACTIONS_WIDTH, 1, 0),
			BackgroundTransparency = 1,
			RichText = true,
			Text = Fmt.resolve(versionMarkup(item), isDarkTheme()),
			Font = Enum.Font.Code,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
			Parent = line,
		})
		if wide then
			make("TextLabel", {
				Position = UDim2.fromScale(0.75, 0),
				Size = UDim2.new(0.25, -ACTIONS_WIDTH, 1, 0),
				BackgroundTransparency = 1,
				Text = Widgets.SOURCE_NAMES[item.source] or item.source,
				Font = Enum.Font.SourceSans,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = themeColor(Enum.StudioStyleGuideColor.DimmedText),
				Parent = line,
			})
		end

		-- 오른쪽: Update + ⋯
		if item.newSpec then
			const update = textButton({
				Text = "Update",
				Size = UDim2.fromOffset(64, 22),
				Position = UDim2.new(1, -ACTIONS_WIDTH + 4, 0, 4),
				Parent = line,
			})
			update.Activated:Connect(function()
				job(function()
					Updates.apply(item, logBoth)
					Installer.prune(logBoth)
				end)
			end)
		end
		const more = iconButton("three-dots-horizontal", "", {
			Size = UDim2.fromOffset(28, 22),
			Position = UDim2.new(1, -32, 0, 4),
			Parent = line,
		})
		more.Activated:Connect(function()
			const items = {}
			if item.spec then
				table.insert(items, { "view", "View" })
				table.insert(items, { "reinstall", "Reinstall" })
			end
			table.insert(items, { "remove", "Remove" })
			menu(more, items, function(choice)
				if choice == "view" then
					search.open(asSearchResult(item))
				elseif choice == "reinstall" then
					job(function()
						Installer.install(item.spec :: string, {
							alias = item.alias,
							location = Config.resolvePath(item.location, true),
							log = logBoth,
						})
					end)
				elseif choice == "remove" then
					job(function()
						Installer.remove(item.alias, item.location, logBoth)
					end)
				end
			end)
		end)

		-- 줄 구분선, 마우스를 올리면 밑줄, 누르면 검색 창 상세
		make("Frame", {
			Position = UDim2.new(0, 0, 1, -1),
			Size = UDim2.new(1, 0, 0, 1),
			BorderSizePixel = 0,
			BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.Border),
			Parent = line,
		})
		line.MouseEnter:Connect(function()
			line.BackgroundTransparency = 0.85
			line.BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.Item)
			if item.spec then
				nameLabel.Text = "<u>" .. Fmt.escape(item.alias) .. "</u>"
			end
		end)
		line.MouseLeave:Connect(function()
			line.BackgroundTransparency = 1
			nameLabel.Text = Fmt.escape(item.alias)
		end)
		line.Activated:Connect(function()
			closeMenu()
			if item.spec then
				search.open(asSearchResult(item))
			end
		end)
	end

	const function groupHeader(order: number, title: string, path: string?)
		make("TextLabel", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
			BackgroundTransparency = 1,
			RichText = true,
			Text = Fmt.resolve(
				"  " .. Fmt.bold(Fmt.escape(title)) .. (if path then "  " .. Fmt.color("dim", Fmt.escape(path)) else ""),
				isDarkTheme()
			),
			Font = Enum.Font.SourceSans,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = themeColor(Enum.StudioStyleGuideColor.MainText),
			Parent = list,
		})
	end

	const function columnHeader(order: number, wide: boolean)
		const header = make("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Parent = list,
		})
		const function column(text: string, position: UDim2, size: UDim2)
			make("TextLabel", {
				Position = position,
				Size = size,
				BackgroundTransparency = 1,
				Text = text,
				Font = Enum.Font.SourceSans,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = themeColor(Enum.StudioStyleGuideColor.DimmedText),
				Parent = header,
			})
		end
		column("Name", UDim2.fromOffset(30, 0), UDim2.new(0.4, -30, 1, 0))
		column("Version", UDim2.fromScale(0.4, 0), UDim2.fromScale(0.35, 1))
		if wide then
			column("Source", UDim2.fromScale(0.75, 0), UDim2.fromScale(0.25, 1))
		end
		make("Frame", {
			Position = UDim2.new(0, 0, 1, -1),
			Size = UDim2.new(1, 0, 0, 1),
			BorderSizePixel = 0,
			BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.Border),
			Parent = header,
		})
	end

	----------------------------------------------------------------------------
	-- 그리기

	const function renderList(onlyUpdates: boolean)
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		const wide = list.AbsoluteSize.X >= WIDE
		columnHeader(0, wide)

		-- 위치별로 묶음 (shared, server, 나머지 경로 순)
		const ok, data = pcall(Config.read)
		const shared = if ok then data.shared else ""
		const server = if ok then data.server else ""
		const groups: { [string]: { Updates.Status } } = {}
		const order: { string } = {}
		for _, item in statuses do
			if not onlyUpdates or item.newSpec then
				if not groups[item.location] then
					groups[item.location] = {}
					table.insert(order, item.location)
				end
				table.insert(groups[item.location], item)
			end
		end
		table.sort(order, function(a, b)
			const rank = function(path: string): number
				return if path == shared then 0 elseif path == server then 1 else 2
			end
			if rank(a) ~= rank(b) then
				return rank(a) < rank(b)
			end
			return a < b
		end)

		local index = 1
		for _, location in order do
			const title = if location == shared then "Shared" elseif location == server then "Server" else location
			groupHeader(index, title, if title ~= location then location else nil)
			index += 1
			for _, item in groups[location] do
				row(index, item, wide)
				index += 1
			end
		end
		if #order == 0 then
			make("TextLabel", {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundTransparency = 1,
				Text = if onlyUpdates
					then (if checked then L("모두 최신", "Everything is up to date") else L("확인 중...", "Checking..."))
					else L("Config 에 적힌 패키지가 없음 (Search 창에서 Add)", "No packages in the Config (Add from the Search window)"),
				Font = Enum.Font.SourceSans,
				TextSize = 15,
				TextColor3 = themeColor(Enum.StudioStyleGuideColor.DimmedText),
				Parent = list,
			})
		end
	end

	-- Tree / Licenses: 명령 결과를 글로
	const function renderCommand(name: string)
		setText(Fmt.color("dim", L("불러오는 중...", "Loading...")))
		task.spawn(function()
			const lines = {}
			const context: Commands.Context = {
				plugin = plugin,
				log = function(message)
					table.insert(lines, Fmt.line(message))
				end,
				rich = function(markup)
					table.insert(lines, markup)
				end,
				clear = function() end,
				secret = function()
					return nil
				end,
			}
			const ok, err = pcall(function()
				if name == "tree" then
					Commands.tree({ server = false, selected = false, to = nil }, context)
				else
					Commands.licenses(context)
				end
			end)
			if not ok then
				table.insert(lines, Fmt.color("red", Fmt.escape(L(`오류: {err}`, `Error: {err}`))))
			end
			if currentTab == name then
				setText(table.concat(lines, "\n"))
			end
		end)
	end

	render = function()
		closeMenu()
		const all, safe = updateCount()
		tabButtons.updates.Text = if all > 0 then `Updates ({all})` else "Updates"
		for tab, button in tabFrames do
			button.BackgroundColor3 = if tab == currentTab
				then themeColor(Enum.StudioStyleGuideColor.ButtonBorder)
				else themeColor(Enum.StudioStyleGuideColor.Button)
		end
		const isList = currentTab == "installed" or currentTab == "updates"
		banner.Visible = isList and all > 0
		bannerText.Text = L(`업데이트 {all}개` .. (if all > safe then ` (Major {all - safe})` else ""), `{all} updates available` .. (if all > safe then ` ({all - safe} major)` else ""))
		updateAllButton.Visible = safe > 0
		list.Visible = isList
		textArea.Visible = not isList
		if isList then
			renderList(currentTab == "updates")
		else
			renderCommand(currentTab)
		end
	end

	-- 목록을 다시 읽고 (check 면) 최신 버전도 확인
	refresh = function(check: boolean)
		const ok, fresh = pcall(Updates.list)
		if not ok then
			status.Text = L(`오류: {fresh}`, `Error: {fresh}`)
			return
		end
		-- 이미 확인한 최신 버전은 이어서 씀
		const previous: { [string]: Updates.Status } = {}
		for _, item in statuses do
			previous[item.location .. "\0" .. item.alias] = item
		end
		for _, item in fresh do
			const old = previous[item.location .. "\0" .. item.alias]
			if old and old.spec == item.spec and not check then
				item.latest, item.error = old.latest, old.error
				if old.latest and old.newSpec and item.current ~= old.latest then
					item.newSpec, item.major = old.newSpec, old.major
				end
			end
		end
		statuses = fresh
		render()
		if not check then
			return
		end
		status.Text = L("확인 중: 최신 버전", "Checking: latest versions")
		task.spawn(function()
			Updates.check(statuses)
			checked = true
			const all = updateCount()
			status.Text = if all > 0
				then L(`업데이트 {all}개`, `{all} updates`)
				else L("모두 최신", "Everything is up to date")
			render()
		end)
	end

	refreshButton.Activated:Connect(function()
		if not busy then
			refresh(true)
		end
	end)
	updateAllButton.Activated:Connect(function()
		job(function()
			for _, item in statuses do
				if item.newSpec and not item.major then
					Updates.apply(item, logBoth)
				end
			end
			Installer.prune(logBoth)
		end)
	end)

	-- 창을 열 때마다 확인, 폭이 바뀌면 열 다시 배치
	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if widget.Enabled and not busy then
			refresh(true)
		end
	end)
	local lastWide: boolean? = nil
	list:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		const wide = list.AbsoluteSize.X >= WIDE
		if wide ~= lastWide then
			lastWide = wide
			if list.Visible then
				render()
			end
		end
	end)

	settings().Studio.ThemeChanged:Connect(function()
		root.BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.MainBackground)
		list.BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.ScriptBackground)
		textArea.BackgroundColor3 = themeColor(Enum.StudioStyleGuideColor.ScriptBackground)
		textLabel.Text = Fmt.resolve(textMarkup, isDarkTheme())
		render()
	end)

	root.Parent = widget
	if widget.Enabled then
		refresh(true)
	end
end

return ManageUi
