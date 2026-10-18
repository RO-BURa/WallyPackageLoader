-- Wally, GitHub(pesde 방식), 파일에서 패키지를 바로 불러오는 플러그인

const Auth = require(script.Auth)
const SearchUi = require(script.SearchUi)
const Ui = require(script.Ui)

const PACKAGES_ICON = "rbxassetid://86460136593495"
const SEARCH_ICON = "rbxassetid://132302594577680"

Auth.init(plugin)

const toolbar = plugin:CreateToolbar("Package Loader")
const toggleButton = toolbar:CreateButton("Packages", "패키지 불러오기 창 열기", PACKAGES_ICON)
toggleButton.ClickableWhenViewportHidden = true

const widget = plugin:CreateDockWidgetPluginGui(
	"WallyPackageLoader",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 480, 260, 300)
)
widget.Title = "Package Loader"
widget.Name = "WallyPackageLoader"

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggleButton:SetActive(widget.Enabled)
end)

Ui.mount(widget, plugin)

-- 검색 창
const searchButton = toolbar:CreateButton("Search", "Wally / GitHub 패키지 검색", SEARCH_ICON)
searchButton.ClickableWhenViewportHidden = true

const searchWidget = plugin:CreateDockWidgetPluginGui(
	"WallyPackageLoaderSearch",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 480, 260, 300)
)
searchWidget.Title = "Package Search"
searchWidget.Name = "WallyPackageLoaderSearch"

searchButton.Click:Connect(function()
	searchWidget.Enabled = not searchWidget.Enabled
end)
searchWidget:GetPropertyChangedSignal("Enabled"):Connect(function()
	searchButton:SetActive(searchWidget.Enabled)
end)

SearchUi.mount(searchWidget, plugin)
