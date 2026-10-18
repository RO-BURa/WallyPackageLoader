-- Wally, GitHub(pesde 방식), 파일에서 패키지를 바로 불러오는 플러그인

const Auth = require(script.Auth)
const SearchUi = require(script.SearchUi)
const Ui = require(script.Ui)

const InsertService = game:GetService("InsertService")

-- 툴바 아이콘으로 올린 Decal 에셋. 툴바에는 그 안의 이미지(texture) ID 가 필요해서
-- 처음 한 번 InsertService 로 Decal 을 열어 Texture 를 읽고 이 컴퓨터에 저장해 둠
const PACKAGES_DECAL = 86460136593495
const SEARCH_DECAL = 132302594577680
const ICON_CACHE_KEY = "RO_BURa.WallyPackageLoader.IconTextures"

const function cachedTexture(decalId: number): string
	const cache = plugin:GetSetting(ICON_CACHE_KEY)
	const texture = if type(cache) == "table" then cache[tostring(decalId)] else nil
	return if type(texture) == "string" then texture else ""
end

-- Decal 에셋 ID -> 이미지 ID (실패하면 nil)
const function loadTexture(decalId: number): string?
	const ok, model = pcall(InsertService.LoadAsset, InsertService, decalId)
	if not ok or not model then
		return nil
	end
	const decal = model:FindFirstChildWhichIsA("Decal", true)
	const texture = if decal then decal.Texture else nil
	model:Destroy()
	if not texture or texture == "" then
		return nil
	end
	const cache = plugin:GetSetting(ICON_CACHE_KEY)
	const updated = if type(cache) == "table" then cache else {}
	updated[tostring(decalId)] = texture
	plugin:SetSetting(ICON_CACHE_KEY, updated)
	return texture
end

-- 저장해 둔 게 없으면 받아서 아이콘을 바꿈
const function applyIcon(button: PluginToolbarButton, decalId: number)
	if cachedTexture(decalId) ~= "" then
		return
	end
	task.spawn(function()
		const texture = loadTexture(decalId)
		if texture then
			button.Icon = texture
		end
	end)
end

Auth.init(plugin)

const toolbar = plugin:CreateToolbar("Package Loader")
const toggleButton = toolbar:CreateButton("Packages", "패키지 불러오기 창 열기", cachedTexture(PACKAGES_DECAL))
applyIcon(toggleButton, PACKAGES_DECAL)
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
const searchButton = toolbar:CreateButton("Search", "Wally / GitHub 패키지 검색", cachedTexture(SEARCH_DECAL))
applyIcon(searchButton, SEARCH_DECAL)
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
