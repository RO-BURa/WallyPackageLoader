-- Wally, GitHub(pesde 방식), 파일에서 패키지를 바로 불러오는 플러그인

const Ui = require(script.Ui)

const toolbar = plugin:CreateToolbar("Package Loader")
const toggleButton = toolbar:CreateButton("Packages", "패키지 불러오기 창 열기", "")
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
