-- Wally, pesde, GitHub, 파일에서 패키지를 바로 불러오는 플러그인

const Auth = require(script.Auth)
const Locale = require(script.Locale)
const ManageUi = require(script.ManageUi)
const SearchUi = require(script.SearchUi)
const Ui = require(script.Ui)

const L = Locale.L

-- 툴바 아이콘 (업로드한 Decal 86460136593495 / 132302594577680 의 이미지 ID)
const PACKAGES_ICON = "rbxassetid://94108074565091"
const SEARCH_ICON = "rbxassetid://118685771787843"
const MANAGE_ICON = "rbxassetid://92487039142919"

Locale.init(plugin)
Auth.init(plugin)

const toolbar = plugin:CreateToolbar("Package Loader")
const toggleButton = toolbar:CreateButton("Packages", L("패키지 불러오기 창 열기", "Open the package loader"), PACKAGES_ICON)
toggleButton.ClickableWhenViewportHidden = true

const widget = plugin:CreateDockWidgetPluginGui(
	"WallyPackageLoader",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 480, 260, 300)
)
widget.Title = "Package Loader"
-- 자식이 부모 위에 그려지게 (버튼 안의 글자가 버튼 배경에 가려지지 않게)
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
widget.Name = "WallyPackageLoader"

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggleButton:SetActive(widget.Enabled)
end)

Ui.mount(widget, plugin)

-- 검색 창
const searchButton = toolbar:CreateButton("Search", L("Wally / pesde / GitHub 패키지 검색", "Search Wally / pesde / GitHub packages"), SEARCH_ICON)
searchButton.ClickableWhenViewportHidden = true

const searchWidget = plugin:CreateDockWidgetPluginGui(
	"WallyPackageLoaderSearch",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 480, 260, 300)
)
searchWidget.Title = "Package Search"
searchWidget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
searchWidget.Name = "WallyPackageLoaderSearch"

searchButton.Click:Connect(function()
	searchWidget.Enabled = not searchWidget.Enabled
end)
searchWidget:GetPropertyChangedSignal("Enabled"):Connect(function()
	searchButton:SetActive(searchWidget.Enabled)
end)

const search = SearchUi.mount(searchWidget, plugin)

-- 관리 창 (설치한 패키지, 업데이트, 트리, 라이선스)
const manageButton = toolbar:CreateButton("Manage", L("설치한 패키지 관리, 업데이트", "Manage installed packages and updates"), MANAGE_ICON)
manageButton.ClickableWhenViewportHidden = true

const manageWidget = plugin:CreateDockWidgetPluginGui(
	"WallyPackageLoaderManage",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 420, 480, 300, 300)
)
manageWidget.Title = "Package Manager"
manageWidget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
manageWidget.Name = "WallyPackageLoaderManage"

manageButton.Click:Connect(function()
	manageWidget.Enabled = not manageWidget.Enabled
end)
manageWidget:GetPropertyChangedSignal("Enabled"):Connect(function()
	manageButton:SetActive(manageWidget.Enabled)
end)

ManageUi.mount(manageWidget, plugin, search)
