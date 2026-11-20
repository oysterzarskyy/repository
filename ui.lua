-- // lua ui lib for scripts

--[[
    TbUI - Standalone Retained-Mode Roblox Luau UI Library
    Designed for remote execution via loadstring(game:HttpGet("URL"))()
    Features:
      - Custom Loading Title API (`TbUI:config.CustomTLtitle("...")`)
      - Safe cross-environment GUI parenting & anti-duplicate cleanup
      - Animated sharp-square loading screen with dynamic status & progress bar
      - Unified Mouse & Touch input support + responsive UIScale + draggable mobile toggle
      - Sharp square containers paired with subtly rounded (4px) interactive controls
      - Live multi-theme dark system (Obsidian, Midnight, Carbon, Emerald Dark)
      - Full Window -> Tab -> Section -> Element hierarchy with :Set() / :Get() & cleanup
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

--// Root Table
local TbUI = {}
TbUI.__index = TbUI

--// 1. Custom Loading Title API (`TbUI:config.CustomTLtitle("example")`)
-- In Luau, `TbUI:config.CustomTLtitle("example")` parses as `(TbUI.config).CustomTLtitle(TbUI.config, "example")`.
-- Using a callable table with `__call` handles both colon (`:`) and dot (`.`) invocations seamlessly.
local CustomTLtitleHandler = setmetatable({}, {
	__call = function(self, arg1, arg2)
		local titleText = (arg1 == self) and arg2 or arg1
		if titleText ~= nil then
			TbUI.config._customTitle = tostring(titleText)
		end
		return TbUI.config._customTitle
	end
})

TbUI.config = {
	_customTitle = nil,
	CustomTLtitle = CustomTLtitleHandler
}

--// 2. Dark Theme Presets
local Themes = {
	Obsidian = {
		Background       = Color3.fromHex("#0F0F12"),
		Secondary        = Color3.fromHex("#16161B"),
		Tertiary         = Color3.fromHex("#1E1E24"),
		Accent           = Color3.fromHex("#3B82F6"),
		AccentHover      = Color3.fromHex("#60A5FA"),
		TextPrimary      = Color3.fromHex("#F3F4F6"),
		TextSecondary    = Color3.fromHex("#9CA3AF"),
		Border           = Color3.fromHex("#272730"),
		ControlBg        = Color3.fromHex("#22222A"),
		ToggleOff        = Color3.fromHex("#2D2D37"),
		Knob             = Color3.fromHex("#FFFFFF")
	},
	Midnight = {
		Background       = Color3.fromHex("#11131A"),
		Secondary        = Color3.fromHex("#181B24"),
		Tertiary         = Color3.fromHex("#202430"),
		Accent           = Color3.fromHex("#8B5CF6"),
		AccentHover      = Color3.fromHex("#A78BFA"),
		TextPrimary      = Color3.fromHex("#F8FAFC"),
		TextSecondary    = Color3.fromHex("#94A3B8"),
		Border           = Color3.fromHex("#2A2F3D"),
		ControlBg        = Color3.fromHex("#232836"),
		ToggleOff        = Color3.fromHex("#2E3445"),
		Knob             = Color3.fromHex("#FFFFFF")
	},
	Carbon = {
		Background       = Color3.fromHex("#121212"),
		Secondary        = Color3.fromHex("#181818"),
		Tertiary         = Color3.fromHex("#202020"),
		Accent           = Color3.fromHex("#EF4444"),
		AccentHover      = Color3.fromHex("#F87171"),
		TextPrimary      = Color3.fromHex("#FAFAFA"),
		TextSecondary    = Color3.fromHex("#A1A1AA"),
		Border           = Color3.fromHex("#2B2B2B"),
		ControlBg        = Color3.fromHex("#242424"),
		ToggleOff        = Color3.fromHex("#303030"),
		Knob             = Color3.fromHex("#FFFFFF")
	},
	["Emerald Dark"] = {
		Background       = Color3.fromHex("#101413"),
		Secondary        = Color3.fromHex("#161C1A"),
		Tertiary         = Color3.fromHex("#1D2522"),
		Accent           = Color3.fromHex("#10B981"),
		AccentHover      = Color3.fromHex("#34D399"),
		TextPrimary      = Color3.fromHex("#ECFDF5"),
		TextSecondary    = Color3.fromHex("#9CA3AF"),
		Border           = Color3.fromHex("#26322E"),
		ControlBg        = Color3.fromHex("#1F2926"),
		ToggleOff        = Color3.fromHex("#2A3632"),
		Knob             = Color3.fromHex("#FFFFFF")
	}
}

TbUI.Themes = Themes
TbUI._currentThemeName = "Obsidian"
TbUI._currentTheme = Themes.Obsidian
TbUI._themeRegistry = {} -- { { Instance = obj, Property = prop, Role = role, CustomEval = fn } }

--// Standard Tween Configuration
local DEFAULT_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LOADING_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--// Internal Utility Helpers
local function Create(className, props, children)
	local inst = Instance.new(className)
	if props then
		for k, v in pairs(props) do
			inst[k] = v
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	return inst
end

local function Tween(instance, props, info)
	if not instance or not instance.Parent then return end
	local t = TweenService:Create(instance, info or DEFAULT_TWEEN, props)
	t:Play()
	return t
end

local function RegisterTheme(instance, property, role, customEval)
	table.insert(TbUI._themeRegistry, {
		Instance = instance,
		Property = property,
		Role = role,
		CustomEval = customEval
	})
	if customEval then
		instance[property] = customEval(TbUI._currentTheme)
	else
		instance[property] = TbUI._currentTheme[role]
	end
end

local function ApplyCorner(instance, radiusPx)
	return Create("UICorner", {
		CornerRadius = UDim.new(0, radiusPx or 0),
		Parent = instance
	})
end

local function ApplyStroke(instance, role, thickness)
	local stroke = Create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = thickness or 1,
		Parent = instance
	})
	RegisterTheme(stroke, "Color", role or "Border")
	return stroke
end

--// Live Theme Switcher
function TbUI:SetTheme(themeName)
	local target = Themes[themeName]
	if not target then
		warn("[TbUI] Unknown theme:", tostring(themeName))
		return
	end
	self._currentThemeName = themeName
	self._currentTheme = target

	for i = #self._themeRegistry, 1, -1 do
		local entry = self._themeRegistry[i]
		if not entry.Instance or not entry.Instance.Parent then
			table.remove(self._themeRegistry, i)
		else
			local targetColor = entry.CustomEval and entry.CustomEval(target) or target[entry.Role]
			if targetColor then
				Tween(entry.Instance, { [entry.Property] = targetColor }, DEFAULT_TWEEN)
			end
		end
	end
end

--// Safe GUI Parenting & Anti-Duplicate Check
local GUI_NAME = "TbUI_Interface_Root"

local function GetSafeGuiParent()
	if typeof(gethui) == "function" then
		local ok, hiddenUi = pcall(gethui)
		if ok and hiddenUi then
			return hiddenUi
		end
	end
	local okCore, _ = pcall(function()
		return CoreGui.Name
	end)
	if okCore then
		return CoreGui
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function DestroyExistingInstances(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == GUI_NAME then
			child:Destroy()
		end
	end
	-- Also check PlayerGui just in case a fallback ran earlier
	if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
		for _, child in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
			if child.Name == GUI_NAME then
				child:Destroy()
			end
		end
	end
end

--// Unified Mouse & Touch Drag Helper
local function MakeDraggable(dragHandle, moveTarget, connections)
	local dragging = false
	local dragInput = nil
	local dragStart = nil
	local startPos = nil

	table.insert(connections, dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragInput = input
			dragStart = input.Position
			startPos = moveTarget.Position

			local endConn
			endConn = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					dragInput = nil
					if endConn then
						endConn:Disconnect()
					end
				end
			end)
			table.insert(connections, endConn)
		end
	end))

	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			if dragStart and startPos then
				local delta = input.Position - dragStart
				moveTarget.Position = UDim2.new(
					startPos.X.Scale,
					startPos.X.Offset + delta.X,
					startPos.Y.Scale,
					startPos.Y.Offset + delta.Y
				)
			end
		end
	end))
end

--// Main Window Constructor
function TbUI:CreateWindow(config)
	config = config or {}
	local windowTitle    = config.Title or "TbUI"
	local windowSubtitle = config.Subtitle or "v1.0"
	local initialTheme   = config.Theme or "Obsidian"
	local toggleKey      = config.ToggleKey or Enum.KeyCode.RightShift
	local showLoading    = (config.LoadingScreen ~= false)
	local isTouchDevice  = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local showMobileBtn  = (config.MobileButton ~= nil) and config.MobileButton or UserInputService.TouchEnabled

	-- Reset registry for fresh window instance
	self._themeRegistry = {}
	if Themes[initialTheme] then
		self._currentThemeName = initialTheme
		self._currentTheme = Themes[initialTheme]
	else
		self._currentThemeName = "Obsidian"
		self._currentTheme = Themes.Obsidian
	end

	local guiParent = GetSafeGuiParent()
	DestroyExistingInstances(guiParent)

	local Connections = {}

	local ScreenGui = Create("ScreenGui", {
		Name = GUI_NAME,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Parent = guiParent
	})

	--// Responsive Viewport UIScale Manager
	local UIScaleObj = Create("UIScale", {
		Scale = 1,
		Parent = ScreenGui
	})

	local BASE_WIDTH = 580
	local BASE_HEIGHT = 400

	local function UpdateViewportScale()
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local vp = cam.ViewportSize
		local scaleX = (vp.X - 32) / BASE_WIDTH
		local scaleY = (vp.Y - 48) / BASE_HEIGHT
		local minScale = math.min(scaleX, scaleY, 1)
		UIScaleObj.Scale = math.clamp(minScale, 0.55, 1)
	end

	UpdateViewportScale()
	if Workspace.CurrentCamera then
		table.insert(Connections, Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(UpdateViewportScale))
	end
	table.insert(Connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if Workspace.CurrentCamera then
			UpdateViewportScale()
			table.insert(Connections, Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(UpdateViewportScale))
		end
	end))

	--// Main Window Container (Strictly Square: CornerRadius = 0)
	local MainFrame = Create("Frame", {
		Name = "MainWindow",
		Size = UDim2.fromOffset(BASE_WIDTH, BASE_HEIGHT),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = not showLoading,
		Parent = ScreenGui
	})
	RegisterTheme(MainFrame, "BackgroundColor3", "Background")
	ApplyCorner(MainFrame, 0)
	ApplyStroke(MainFrame, "Border", 1)

	--// Top Header Bar (Sharp Square)
	local TopBar = Create("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, 42),
		BorderSizePixel = 0,
		Parent = MainFrame
	})
	RegisterTheme(TopBar, "BackgroundColor3", "Secondary")
	ApplyCorner(TopBar, 0)

	local TopBarDivider = Create("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		BorderSizePixel = 0,
		Parent = TopBar
	})
	RegisterTheme(TopBarDivider, "BackgroundColor3", "Border")

	-- Accent indicator bar on top-left
	local TopAccent = Create("Frame", {
		Name = "TopAccent",
		Size = UDim2.new(0, 3, 1, 0),
		BorderSizePixel = 0,
		Parent = TopBar
	})
	RegisterTheme(TopAccent, "BackgroundColor3", "Accent")

	local TitleLabel = Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(0, 0, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = windowTitle,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = TopBar
	})
	RegisterTheme(TitleLabel, "TextColor3", "TextPrimary")

	local SubtitleBadge = Create("TextLabel", {
		Name = "Subtitle",
		Size = UDim2.fromOffset(0, 20),
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = "  " .. windowSubtitle .. "  ",
		TextSize = 11,
		Parent = TopBar
	})
	RegisterTheme(SubtitleBadge, "BackgroundColor3", "Tertiary")
	RegisterTheme(SubtitleBadge, "TextColor3", "Accent")
	ApplyCorner(SubtitleBadge, 0)
	ApplyStroke(SubtitleBadge, "Border", 1)

	-- Keep subtitle aligned dynamically after title
	local function AlignSubtitle()
		SubtitleBadge.Position = UDim2.new(0, TitleLabel.AbsoluteSize.X + 22, 0.5, 0)
	end
	TitleLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(AlignSubtitle)
	task.defer(AlignSubtitle)

	-- Window Action Buttons (Minimize & Close - Subtly Rounded 4px)
	local CloseBtn = Create("TextButton", {
		Name = "CloseButton",
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, -34, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		Text = "X",
		TextSize = 12,
		Parent = TopBar
	})
	RegisterTheme(CloseBtn, "BackgroundColor3", "Tertiary")
	RegisterTheme(CloseBtn, "TextColor3", "TextSecondary")
	ApplyCorner(CloseBtn, 4)
	ApplyStroke(CloseBtn, "Border", 1)

	local MinBtn = Create("TextButton", {
		Name = "MinimizeButton",
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, -66, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		Text = "-",
		TextSize = 14,
		Parent = TopBar
	})
	RegisterTheme(MinBtn, "BackgroundColor3", "Tertiary")
	RegisterTheme(MinBtn, "TextColor3", "TextSecondary")
	ApplyCorner(MinBtn, 4)
	ApplyStroke(MinBtn, "Border", 1)

	MakeDraggable(TopBar, MainFrame, Connections)

	--// Body Area (Sidebar + Content Canvas)
	local BodyFrame = Create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -42),
		Position = UDim2.fromOffset(0, 42),
		BackgroundTransparency = 1,
		Parent = MainFrame
	})

	--// Left Sidebar (Strictly Square)
	local Sidebar = Create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, 148, 1, 0),
		BorderSizePixel = 0,
		Parent = BodyFrame
	})
	RegisterTheme(Sidebar, "BackgroundColor3", "Secondary")
	ApplyCorner(Sidebar, 0)

	local SidebarBorder = Create("Frame", {
		Name = "RightBorder",
		Size = UDim2.new(0, 1, 1, 0),
		Position = UDim2.new(1, -1, 0, 0),
		BorderSizePixel = 0,
		Parent = Sidebar
	})
	RegisterTheme(SidebarBorder, "BackgroundColor3", "Border")

	local TabList = Create("ScrollingFrame", {
		Name = "TabList",
		Size = UDim2.new(1, -1, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Parent = Sidebar
	})
	RegisterTheme(TabList, "ScrollBarImageColor3", "Accent")

	Create("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = TabList
	})

	Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = TabList
	})

	--// Right Content Container
	local ContentContainer = Create("Frame", {
		Name = "ContentContainer",
		Size = UDim2.new(1, -148, 1, 0),
		Position = UDim2.fromOffset(148, 0),
		BackgroundTransparency = 1,
		Parent = BodyFrame
	})

	--// Window Object & State
	local WindowObj = {
		_screenGui = ScreenGui,
		_mainFrame = MainFrame,
		_connections = Connections,
		_tabs = {},
		_activeTab = nil,
		_visible = true
	}

	function WindowObj:SetVisible(state)
		self._visible = state
		MainFrame.Visible = state
	end

	function WindowObj:Toggle()
		self:SetVisible(not self._visible)
	end

	function WindowObj:Destroy()
		for _, conn in ipairs(self._connections) do
			if conn and conn.Connected then
				conn:Disconnect()
			end
		end
		table.clear(self._connections)
		table.clear(TbUI._themeRegistry)
		if ScreenGui and ScreenGui.Parent then
			ScreenGui:Destroy()
		end
	end

	-- TopBar Button Events
	table.insert(Connections, CloseBtn.MouseEnter:Connect(function()
		Tween(CloseBtn, { BackgroundColor3 = Color3.fromHex("#DC2626"), TextColor3 = Color3.fromHex("#FFFFFF") })
	end))
	table.insert(Connections, CloseBtn.MouseLeave:Connect(function()
		Tween(CloseBtn, { BackgroundColor3 = TbUI._currentTheme.Tertiary, TextColor3 = TbUI._currentTheme.TextSecondary })
	end))
	table.insert(Connections, CloseBtn.Activated:Connect(function()
		WindowObj:Destroy()
	end))

	table.insert(Connections, MinBtn.MouseEnter:Connect(function()
		Tween(MinBtn, { BackgroundColor3 = TbUI._currentTheme.ControlBg, TextColor3 = TbUI._currentTheme.TextPrimary })
	end))
	table.insert(Connections, MinBtn.MouseLeave:Connect(function()
		Tween(MinBtn, { BackgroundColor3 = TbUI._currentTheme.Tertiary, TextColor3 = TbUI._currentTheme.TextSecondary })
	end))
	table.insert(Connections, MinBtn.Activated:Connect(function()
		WindowObj:Toggle()
	end))

	-- Keyboard Toggle Key
	table.insert(Connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == toggleKey then
			WindowObj:Toggle()
		end
	end))

	--// Floating Mobile Toggle Button (Subtly Rounded 4px, Draggable)
	if showMobileBtn then
		local MobileBtn = Create("TextButton", {
			Name = "MobileToggleButton",
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.new(0, 18, 0.5, -22),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Enum.Font.GothamBold,
			Text = "UI",
			TextSize = 13,
			ZIndex = 50,
			Parent = ScreenGui
		})
		RegisterTheme(MobileBtn, "BackgroundColor3", "Secondary")
		RegisterTheme(MobileBtn, "TextColor3", "Accent")
		ApplyCorner(MobileBtn, 4)
		ApplyStroke(MobileBtn, "Accent", 1)

		local dragMoved = false
		local pressStart = nil
		table.insert(Connections, MobileBtn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragMoved = false
				pressStart = input.Position
			end
		end))
		table.insert(Connections, UserInputService.InputChanged:Connect(function(input)
			if pressStart and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				if (input.Position - pressStart).Magnitude > 6 then
					dragMoved = true
				end
			end
		end))
		table.insert(Connections, MobileBtn.Activated:Connect(function()
			if not dragMoved then
				WindowObj:Toggle()
				Tween(MobileBtn, { BackgroundColor3 = TbUI._currentTheme.Tertiary })
				task.delay(0.15, function()
					if MobileBtn and MobileBtn.Parent then
						Tween(MobileBtn, { BackgroundColor3 = TbUI._currentTheme.Secondary })
					end
				end)
			end
		end))

		MakeDraggable(MobileBtn, MobileBtn, Connections)
	end

	--// Tab Constructor
	function WindowObj:CreateTab(tabName)
		tabName = tabName or "Tab"

		-- Square Tab Button in Sidebar
		local TabBtn = Create("TextButton", {
			Name = tabName .. "_TabButton",
			Size = UDim2.new(1, 0, 0, 32),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Enum.Font.GothamMedium,
			Text = "",
			Parent = TabList
		})
		ApplyCorner(TabBtn, 0)
		local tabStroke = ApplyStroke(TabBtn, "Border", 1)

		local TabIndicator = Create("Frame", {
			Name = "Indicator",
			Size = UDim2.new(0, 3, 1, 0),
			BorderSizePixel = 0,
			Visible = false,
			Parent = TabBtn
		})
		RegisterTheme(TabIndicator, "BackgroundColor3", "Accent")

		local TabLabel = Create("TextLabel", {
			Name = "Label",
			Size = UDim2.new(1, -14, 1, 0),
			Position = UDim2.fromOffset(10, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = tabName,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = TabBtn
		})

		-- Scrollable Tab Page
		local TabPage = Create("ScrollingFrame", {
			Name = tabName .. "_Page",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			Visible = false,
			Parent = ContentContainer
		})
		RegisterTheme(TabPage, "ScrollBarImageColor3", "Accent")

		Create("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 12),
			Parent = TabPage
		})

		Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
			Parent = TabPage
		})

		local TabObj = {
			_button = TabBtn,
			_indicator = TabIndicator,
			_label = TabLabel,
			_stroke = tabStroke,
			_page = TabPage,
			_active = false
		}

		RegisterTheme(TabBtn, "BackgroundColor3", "Tertiary", function(theme)
			return TabObj._active and theme.Tertiary or theme.Background
		end)
		RegisterTheme(TabLabel, "TextColor3", "TextPrimary", function(theme)
			return TabObj._active and theme.TextPrimary or theme.TextSecondary
		end)
		RegisterTheme(tabStroke, "Color", "Border", function(theme)
			return TabObj._active and theme.Accent or theme.Border
		end)

		local function SelectTab()
			for _, t in ipairs(WindowObj._tabs) do
				t._active = false
				t._page.Visible = false
				t._indicator.Visible = false
				Tween(t._button, { BackgroundColor3 = TbUI._currentTheme.Background })
				Tween(t._label, { TextColor3 = TbUI._currentTheme.TextSecondary })
				Tween(t._stroke, { Color = TbUI._currentTheme.Border })
			end
			TabObj._active = true
			TabPage.Visible = true
			TabIndicator.Visible = true
			Tween(TabBtn, { BackgroundColor3 = TbUI._currentTheme.Tertiary })
			Tween(TabLabel, { TextColor3 = TbUI._currentTheme.TextPrimary })
			Tween(tabStroke, { Color = TbUI._currentTheme.Accent })
			WindowObj._activeTab = TabObj
		end

		table.insert(Connections, TabBtn.Activated:Connect(SelectTab))
		table.insert(Connections, TabBtn.MouseEnter:Connect(function()
			if not TabObj._active then
				Tween(TabBtn, { BackgroundColor3 = TbUI._currentTheme.Tertiary })
			end
		end))
		table.insert(Connections, TabBtn.MouseLeave:Connect(function()
			if not TabObj._active then
				Tween(TabBtn, { BackgroundColor3 = TbUI._currentTheme.Background })
			end
		end))

		table.insert(WindowObj._tabs, TabObj)
		if #WindowObj._tabs == 1 then
			SelectTab()
		end

		--// Section Constructor inside Tab
		function TabObj:CreateSection(sectionTitle)
			sectionTitle = sectionTitle or "Section"

			-- Strictly Square Section Container
			local SectionFrame = Create("Frame", {
				Name = sectionTitle .. "_Section",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BorderSizePixel = 0,
				Parent = TabPage
			})
			RegisterTheme(SectionFrame, "BackgroundColor3", "Secondary")
			ApplyCorner(SectionFrame, 0)
			ApplyStroke(SectionFrame, "Border", 1)

			local SectionHeader = Create("Frame", {
				Name = "Header",
				Size = UDim2.new(1, 0, 0, 28),
				BorderSizePixel = 0,
				Parent = SectionFrame
			})
			RegisterTheme(SectionHeader, "BackgroundColor3", "Tertiary")
			ApplyCorner(SectionHeader, 0)

			local HeaderLine = Create("Frame", {
				Name = "BottomLine",
				Size = UDim2.new(1, 0, 0, 1),
				Position = UDim2.new(0, 0, 1, -1),
				BorderSizePixel = 0,
				Parent = SectionHeader
			})
			RegisterTheme(HeaderLine, "BackgroundColor3", "Border")

			local HeaderTitle = Create("TextLabel", {
				Name = "Title",
				Size = UDim2.new(1, -16, 1, 0),
				Position = UDim2.fromOffset(10, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Text = string.upper(sectionTitle),
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = SectionHeader
			})
			RegisterTheme(HeaderTitle, "TextColor3", "TextSecondary")

			local ElementHolder = Create("Frame", {
				Name = "Elements",
				Size = UDim2.new(1, 0, 0, 0),
				Position = UDim2.fromOffset(0, 28),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Parent = SectionFrame
			})

			Create("UIPadding", {
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
				Parent = ElementHolder
			})

			Create("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 8),
				Parent = ElementHolder
			})

			local SectionObj = {}

			--// 1. BUTTON (Subtly Rounded 4px)
			function SectionObj:CreateButton(opts, legacyDefault, legacyCallback)
				local name, callback
				if typeof(opts) == "table" then
					name = opts.Name or "Button"
					callback = opts.Callback
				else
					name = tostring(opts or "Button")
					callback = typeof(legacyDefault) == "function" and legacyDefault or legacyCallback
				end

				local Btn = Create("TextButton", {
					Name = name .. "_Button",
					Size = UDim2.new(1, 0, 0, 32),
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Font = Enum.Font.GothamMedium,
					Text = name,
					TextSize = 13,
					Parent = ElementHolder
				})
				RegisterTheme(Btn, "BackgroundColor3", "ControlBg")
				RegisterTheme(Btn, "TextColor3", "TextPrimary")
				ApplyCorner(Btn, 4)
				local stroke = ApplyStroke(Btn, "Border", 1)

				table.insert(Connections, Btn.MouseEnter:Connect(function()
					Tween(Btn, { BackgroundColor3 = TbUI._currentTheme.Tertiary })
					Tween(stroke, { Color = TbUI._currentTheme.Accent })
				end))
				table.insert(Connections, Btn.MouseLeave:Connect(function()
					Tween(Btn, { BackgroundColor3 = TbUI._currentTheme.ControlBg })
					Tween(stroke, { Color = TbUI._currentTheme.Border })
				end))
				table.insert(Connections, Btn.Activated:Connect(function()
					Tween(Btn, { BackgroundColor3 = TbUI._currentTheme.Accent })
					task.delay(0.12, function()
						if Btn and Btn.Parent then
							Tween(Btn, { BackgroundColor3 = TbUI._currentTheme.ControlBg })
						end
					end)
					if callback then
						task.spawn(callback)
					end
				end))

				local ElementAPI = { _text = name }
				function ElementAPI:Set(newText)
					self._text = tostring(newText)
					Btn.Text = self._text
				end
				function ElementAPI:Get()
					return self._text
				end
				return ElementAPI
			end

			--// 2. TOGGLE (Subtly Rounded 4px Track & Knob)
			function SectionObj:CreateToggle(opts, legacyDefault, legacyCallback)
				local name, defaultVal, callback
				if typeof(opts) == "table" then
					name = opts.Name or "Toggle"
					defaultVal = opts.Default or false
					callback = opts.Callback
				else
					name = tostring(opts or "Toggle")
					defaultVal = legacyDefault or false
					callback = legacyCallback
				end

				local state = (defaultVal == true)

				local Row = Create("TextButton", {
					Name = name .. "_Toggle",
					Size = UDim2.new(1, 0, 0, 32),
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					Parent = ElementHolder
				})

				local Label = Create("TextLabel", {
					Name = "Label",
					Size = UDim2.new(1, -54, 1, 0),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamMedium,
					Text = name,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = Row
				})
				RegisterTheme(Label, "TextColor3", "TextPrimary")

				local Track = Create("Frame", {
					Name = "Track",
					Size = UDim2.fromOffset(40, 20),
					Position = UDim2.new(1, -40, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					BorderSizePixel = 0,
					Parent = Row
				})
				ApplyCorner(Track, 4)
				local trackStroke = ApplyStroke(Track, "Border", 1)

				local Knob = Create("Frame", {
					Name = "Knob",
					Size = UDim2.fromOffset(14, 14),
					Position = state and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					BorderSizePixel = 0,
					Parent = Track
				})
				RegisterTheme(Knob, "BackgroundColor3", "Knob")
				ApplyCorner(Knob, 4)

				RegisterTheme(Track, "BackgroundColor3", "Accent", function(theme)
					return state and theme.Accent or theme.ToggleOff
				end)
				RegisterTheme(trackStroke, "Color", "Accent", function(theme)
					return state and theme.Accent or theme.Border
				end)

				local function UpdateToggle(newState, fireCallback)
					state = (newState == true)
					Tween(Track, {
						BackgroundColor3 = state and TbUI._currentTheme.Accent or TbUI._currentTheme.ToggleOff
					})
					Tween(trackStroke, {
						Color = state and TbUI._currentTheme.Accent or TbUI._currentTheme.Border
					})
					Tween(Knob, {
						Position = state and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
					})
					if fireCallback and callback then
						task.spawn(callback, state)
					end
				end

				table.insert(Connections, Row.Activated:Connect(function()
					UpdateToggle(not state, true)
				end))

				local ElementAPI = {}
				function ElementAPI:Set(val)
					UpdateToggle(val, true)
				end
				function ElementAPI:Get()
					return state
				end
				return ElementAPI
			end

			--// 3. SLIDER (Square Track + Subtly Rounded 4px Fill & Knob, Mouse & Touch Drag)
			function SectionObj:CreateSlider(opts, legacyDefault, legacyCallback)
				local name, minVal, maxVal, increment, defaultVal, callback
				if typeof(opts) == "table" then
					name = opts.Name or "Slider"
					minVal = opts.Min or 0
					maxVal = opts.Max or 100
					increment = opts.Increment or 1
					defaultVal = opts.Default ~= nil and opts.Default or minVal
					callback = opts.Callback
				else
					name = tostring(opts or "Slider")
					minVal = 0
					maxVal = 100
					increment = 1
					defaultVal = legacyDefault or 0
					callback = legacyCallback
				end

				local function SnapValue(val)
					val = math.clamp(val, minVal, maxVal)
					local steps = math.floor(((val - minVal) / increment) + 0.5)
					local snapped = minVal + (steps * increment)
					-- Avoid floating point artifacts
					local decimals = 0
					local strInc = tostring(increment)
					local dotIdx = string.find(strInc, "%.")
					if dotIdx then
						decimals = #strInc - dotIdx
					end
					local mult = 10 ^ decimals
					return math.clamp(math.floor(snapped * mult + 0.5) / mult, minVal, maxVal)
				end

				local currentValue = SnapValue(defaultVal)

				local Container = Create("Frame", {
					Name = name .. "_Slider",
					Size = UDim2.new(1, 0, 0, 44),
					BackgroundTransparency = 1,
					Parent = ElementHolder
				})

				local NameLabel = Create("TextLabel", {
					Name = "Label",
					Size = UDim2.new(1, -60, 0, 20),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamMedium,
					Text = name,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = Container
				})
				RegisterTheme(NameLabel, "TextColor3", "TextPrimary")

				local ValueLabel = Create("TextLabel", {
					Name = "Value",
					Size = UDim2.new(0, 60, 0, 20),
					Position = UDim2.new(1, -60, 0, 0),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					Text = tostring(currentValue),
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Right,
					Parent = Container
				})
				RegisterTheme(ValueLabel, "TextColor3", "Accent")

				-- Hitbox for comfortable touch & mouse dragging
				local Hitbox = Create("TextButton", {
					Name = "Hitbox",
					Size = UDim2.new(1, 0, 0, 22),
					Position = UDim2.fromOffset(0, 21),
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					Parent = Container
				})

				-- Square Slider Track
				local Track = Create("Frame", {
					Name = "Track",
					Size = UDim2.new(1, 0, 0, 8),
					Position = UDim2.fromScale(0, 0.5),
					AnchorPoint = Vector2.new(0, 0.5),
					BorderSizePixel = 0,
					Parent = Hitbox
				})
				RegisterTheme(Track, "BackgroundColor3", "ControlBg")
				ApplyCorner(Track, 0)
				ApplyStroke(Track, "Border", 1)

				local initAlpha = (maxVal > minVal) and ((currentValue - minVal) / (maxVal - minVal)) or 0

				-- Subtly Rounded Fill (4px)
				local Fill = Create("Frame", {
					Name = "Fill",
					Size = UDim2.new(initAlpha, 0, 1, 0),
					BorderSizePixel = 0,
					Parent = Track
				})
				RegisterTheme(Fill, "BackgroundColor3", "Accent")
				ApplyCorner(Fill, 4)

				-- Subtly Rounded Knob (4px)
				local Knob = Create("Frame", {
					Name = "Knob",
					Size = UDim2.fromOffset(12, 16),
					Position = UDim2.new(initAlpha, 0, 0.5, 0),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BorderSizePixel = 0,
					Parent = Track
				})
				RegisterTheme(Knob, "BackgroundColor3", "Knob")
				ApplyCorner(Knob, 4)
				ApplyStroke(Knob, "Accent", 1)

				local function SetSliderValue(newVal, fireCallback)
					currentValue = SnapValue(newVal)
					local alpha = (maxVal > minVal) and ((currentValue - minVal) / (maxVal - minVal)) or 0
					ValueLabel.Text = tostring(currentValue)
					Tween(Fill, { Size = UDim2.new(alpha, 0, 1, 0) }, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
					Tween(Knob, { Position = UDim2.new(alpha, 0, 0.5, 0) }, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
					if fireCallback and callback then
						task.spawn(callback, currentValue)
					end
				end

				local function UpdateFromInputPosition(posX)
					local absPos = Track.AbsolutePosition.X
					local absSize = Track.AbsoluteSize.X
					if absSize <= 0 then return end
					local alpha = math.clamp((posX - absPos) / absSize, 0, 1)
					local rawVal = minVal + (alpha * (maxVal - minVal))
					SetSliderValue(rawVal, true)
				end

				local sliding = false
				table.insert(Connections, Hitbox.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						sliding = true
						UpdateFromInputPosition(input.Position.X)

						local endConn
						endConn = input.Changed:Connect(function()
							if input.UserInputState == Enum.UserInputState.End then
								sliding = false
								if endConn then
									endConn:Disconnect()
								end
							end
						end)
						table.insert(Connections, endConn)
					end
				end))

				table.insert(Connections, UserInputService.InputChanged:Connect(function(input)
					if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
						UpdateFromInputPosition(input.Position.X)
					end
				end))

				local ElementAPI = {}
				function ElementAPI:Set(val)
					SetSliderValue(val, true)
				end
				function ElementAPI:Get()
					return currentValue
				end
				return ElementAPI
			end

			--// 4. DROPDOWN (Strictly Square Expandable/Collapsible List)
			function SectionObj:CreateDropdown(opts, legacyDefault, legacyCallback)
				local name, optionsList, defaultVal, callback
				if typeof(opts) == "table" then
					name = opts.Name or "Dropdown"
					optionsList = opts.Options or {}
					defaultVal = opts.Default or optionsList[1] or "Select..."
					callback = opts.Callback
				else
					name = tostring(opts or "Dropdown")
					optionsList = {}
					defaultVal = legacyDefault or "Select..."
					callback = legacyCallback
				end

				local selected = defaultVal
				local expanded = false

				local Container = Create("Frame", {
					Name = name .. "_Dropdown",
					Size = UDim2.new(1, 0, 0, 34),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Parent = ElementHolder
				})

				Create("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 4),
					Parent = Container
				})

				-- Square Dropdown Header Button
				local HeaderBtn = Create("TextButton", {
					Name = "Header",
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 34),
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Text = "",
					Parent = Container
				})
				RegisterTheme(HeaderBtn, "BackgroundColor3", "ControlBg")
				ApplyCorner(HeaderBtn, 0)
				local headerStroke = ApplyStroke(HeaderBtn, "Border", 1)

				local NameLabel = Create("TextLabel", {
					Name = "Title",
					Size = UDim2.new(0.5, -10, 1, 0),
					Position = UDim2.fromOffset(10, 0),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamMedium,
					Text = name,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = HeaderBtn
				})
				RegisterTheme(NameLabel, "TextColor3", "TextPrimary")

				local SelectedLabel = Create("TextLabel", {
					Name = "Selected",
					Size = UDim2.new(0.5, -28, 1, 0),
					Position = UDim2.new(0.5, 0, 0, 0),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					Text = tostring(selected),
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Right,
					Parent = HeaderBtn
				})
				RegisterTheme(SelectedLabel, "TextColor3", "Accent")

				local ArrowLabel = Create("TextLabel", {
					Name = "Arrow",
					Size = UDim2.fromOffset(20, 34),
					Position = UDim2.new(1, -24, 0, 0),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					Text = "v",
					TextSize = 12,
					Parent = HeaderBtn
				})
				RegisterTheme(ArrowLabel, "TextColor3", "TextSecondary")

				-- Square Option Panel
				local OptionsPanel = Create("Frame", {
					Name = "OptionsPanel",
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BorderSizePixel = 0,
					Visible = false,
					Parent = Container
				})
				RegisterTheme(OptionsPanel, "BackgroundColor3", "Tertiary")
				ApplyCorner(OptionsPanel, 0)
				ApplyStroke(OptionsPanel, "Border", 1)

				Create("UIPadding", {
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 4),
					PaddingLeft = UDim.new(0, 4),
					PaddingRight = UDim.new(0, 4),
					Parent = OptionsPanel
				})

				Create("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 3),
					Parent = OptionsPanel
				})

				local optionButtons = {}

				local function SelectOption(optValue, fireCallback)
					selected = optValue
					SelectedLabel.Text = tostring(selected)
					for val, btn in pairs(optionButtons) do
						local isSel = (val == selected)
						Tween(btn, {
							BackgroundColor3 = isSel and TbUI._currentTheme.Accent or TbUI._currentTheme.ControlBg,
							TextColor3 = isSel and Color3.fromHex("#FFFFFF") or TbUI._currentTheme.TextPrimary
						})
					end
					if fireCallback and callback then
						task.spawn(callback, selected)
					end
				end

				local function PopulateOptions(newOptions)
					for _, child in ipairs(OptionsPanel:GetChildren()) do
						if child:IsA("TextButton") then
							child:Destroy()
						end
					end
					table.clear(optionButtons)

					for _, opt in ipairs(newOptions) do
						local OptBtn = Create("TextButton", {
							Name = tostring(opt) .. "_Option",
							Size = UDim2.new(1, 0, 0, 26),
							BorderSizePixel = 0,
							AutoButtonColor = false,
							Font = Enum.Font.GothamMedium,
							Text = "  " .. tostring(opt),
							TextSize = 12,
							TextXAlignment = Enum.TextXAlignment.Left,
							Parent = OptionsPanel
						})
						ApplyCorner(OptBtn, 0)

						RegisterTheme(OptBtn, "BackgroundColor3", "ControlBg", function(theme)
							return (selected == opt) and theme.Accent or theme.ControlBg
						end)
						RegisterTheme(OptBtn, "TextColor3", "TextPrimary", function(theme)
							return (selected == opt) and Color3.fromHex("#FFFFFF") or theme.TextPrimary
						end)

						optionButtons[opt] = OptBtn

						table.insert(Connections, OptBtn.Activated:Connect(function()
							SelectOption(opt, true)
							expanded = false
							OptionsPanel.Visible = false
							ArrowLabel.Text = "v"
							Tween(headerStroke, { Color = TbUI._currentTheme.Border })
						end))
					end
				end

				PopulateOptions(optionsList)

				table.insert(Connections, HeaderBtn.Activated:Connect(function()
					expanded = not expanded
					OptionsPanel.Visible = expanded
					ArrowLabel.Text = expanded and "^" or "v"
					Tween(headerStroke, {
						Color = expanded and TbUI._currentTheme.Accent or TbUI._currentTheme.Border
					})
				end))

				local ElementAPI = {}
				function ElementAPI:Set(val)
					SelectOption(val, true)
				end
				function ElementAPI:Get()
					return selected
				end
				function ElementAPI:Refresh(newList, newDefault)
					PopulateOptions(newList or {})
					if newDefault ~= nil then
						SelectOption(newDefault, false)
					end
				end
				return ElementAPI
			end

			--// 5. TEXTBOX (Strictly Square Input with 1px Border firing on FocusLost)
			function SectionObj:CreateTextBox(opts, legacyDefault, legacyCallback)
				local name, placeholder, defaultVal, callback
				if typeof(opts) == "table" then
					name = opts.Name or "TextBox"
					placeholder = opts.Placeholder or "Enter text..."
					defaultVal = opts.Default or ""
					callback = opts.Callback
				else
					name = tostring(opts or "TextBox")
					placeholder = "Enter text..."
					defaultVal = tostring(legacyDefault or "")
					callback = legacyCallback
				end

				local currentText = tostring(defaultVal)

				local Row = Create("Frame", {
					Name = name .. "_TextBoxRow",
					Size = UDim2.new(1, 0, 0, 32),
					BackgroundTransparency = 1,
					Parent = ElementHolder
				})

				local Label = Create("TextLabel", {
					Name = "Label",
					Size = UDim2.new(0.45, -6, 1, 0),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamMedium,
					Text = name,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = Row
				})
				RegisterTheme(Label, "TextColor3", "TextPrimary")

				-- Strictly Square Input Box
				local Box = Create("TextBox", {
					Name = "Input",
					Size = UDim2.new(0.55, 0, 0, 28),
					Position = UDim2.new(0.45, 0, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					BorderSizePixel = 0,
					ClearTextOnFocus = false,
					Font = Enum.Font.Gotham,
					PlaceholderText = placeholder,
					Text = currentText,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					ClipsDescendants = true,
					Parent = Row
				})
				RegisterTheme(Box, "BackgroundColor3", "ControlBg")
				RegisterTheme(Box, "TextColor3", "TextPrimary")
				RegisterTheme(Box, "PlaceholderColor3", "TextSecondary")
				ApplyCorner(Box, 0)
				local boxStroke = ApplyStroke(Box, "Border", 1)

				Create("UIPadding", {
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
					Parent = Box
				})

				table.insert(Connections, Box.Focused:Connect(function()
					Tween(boxStroke, { Color = TbUI._currentTheme.Accent })
				end))

				table.insert(Connections, Box.FocusLost:Connect(function(enterPressed)
					Tween(boxStroke, { Color = TbUI._currentTheme.Border })
					currentText = Box.Text
					if callback then
						task.spawn(callback, currentText, enterPressed)
					end
				end))

				local ElementAPI = {}
				function ElementAPI:Set(val)
					currentText = tostring(val)
					Box.Text = currentText
					if callback then
						task.spawn(callback, currentText, false)
					end
				end
				function ElementAPI:Get()
					return currentText
				end
				return ElementAPI
			end

			--// 6. KEYBIND (Square Badge Button, gracefully adapts on Touch-only devices)
			function SectionObj:CreateKeybind(opts, legacyDefault, legacyCallback)
				local name, defaultKey, callback
				if typeof(opts) == "table" then
					name = opts.Name or "Keybind"
					defaultKey = opts.Default or Enum.KeyCode.E
					callback = opts.Callback
				else
					name = tostring(opts or "Keybind")
					defaultKey = legacyDefault or Enum.KeyCode.E
					callback = legacyCallback
				end

				local boundKey = defaultKey
				local listening = false

				local Row = Create("Frame", {
					Name = name .. "_Keybind",
					Size = UDim2.new(1, 0, 0, 32),
					BackgroundTransparency = 1,
					Parent = ElementHolder
				})

				local Label = Create("TextLabel", {
					Name = "Label",
					Size = UDim2.new(1, -96, 1, 0),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamMedium,
					Text = name,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = Row
				})
				RegisterTheme(Label, "TextColor3", "TextPrimary")

				local function FormatKeyName(k)
					if isTouchDevice then
						return "Touch"
					end
					if typeof(k) == "EnumItem" then
						return k.Name
					end
					return tostring(k or "None")
				end

				-- Square Keybind Badge
				local BadgeBtn = Create("TextButton", {
					Name = "Badge",
					Size = UDim2.fromOffset(88, 26),
					Position = UDim2.new(1, -88, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Font = Enum.Font.GothamBold,
					Text = FormatKeyName(boundKey),
					TextSize = 12,
					Parent = Row
				})
				RegisterTheme(BadgeBtn, "BackgroundColor3", "ControlBg")
				RegisterTheme(BadgeBtn, "TextColor3", "Accent")
				ApplyCorner(BadgeBtn, 0)
				local badgeStroke = ApplyStroke(BadgeBtn, "Border", 1)

				if not isTouchDevice then
					table.insert(Connections, BadgeBtn.Activated:Connect(function()
						if listening then return end
						listening = true
						BadgeBtn.Text = "..."
						Tween(badgeStroke, { Color = TbUI._currentTheme.Accent })
					end))

					table.insert(Connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
						if listening then
							if input.UserInputType == Enum.UserInputType.Keyboard then
								listening = false
								if input.KeyCode == Enum.KeyCode.Escape then
									BadgeBtn.Text = FormatKeyName(boundKey)
								else
									boundKey = input.KeyCode
									BadgeBtn.Text = FormatKeyName(boundKey)
								end
								Tween(badgeStroke, { Color = TbUI._currentTheme.Border })
							end
							return
						end

						if not gameProcessed and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == boundKey then
							if callback then
								task.spawn(callback, boundKey)
							end
						end
					end))
				else
					-- On touch-only devices, tapping badge acts as a manual trigger
					table.insert(Connections, BadgeBtn.Activated:Connect(function()
						if callback then
							task.spawn(callback, boundKey)
						end
					end))
				end

				local ElementAPI = {}
				function ElementAPI:Set(newKey)
					boundKey = newKey
					BadgeBtn.Text = FormatKeyName(boundKey)
				end
				function ElementAPI:Get()
					return boundKey
				end
				return ElementAPI
			end

			return SectionObj
		end

		return TabObj
	end

	--// 3. Animated Sharp-Square Loading Screen
	if showLoading then
		local resolvedLoadingTitle = TbUI.config._customTitle or config.Title or "TbUI"

		local LoadingCard = Create("Frame", {
			Name = "LoadingCard",
			Size = UDim2.fromOffset(320, 145),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			ZIndex = 100,
			Parent = ScreenGui
		})
		RegisterTheme(LoadingCard, "BackgroundColor3", "Background")
		ApplyCorner(LoadingCard, 0) -- Strictly sharp square
		local cardStroke = ApplyStroke(LoadingCard, "Border", 1)

		local TopLoadingAccent = Create("Frame", {
			Name = "AccentLine",
			Size = UDim2.new(1, 0, 0, 3),
			BorderSizePixel = 0,
			ZIndex = 101,
			Parent = LoadingCard
		})
		RegisterTheme(TopLoadingAccent, "BackgroundColor3", "Accent")

		local LoadingHeader = Create("TextLabel", {
			Name = "Header",
			Size = UDim2.new(1, -32, 0, 28),
			Position = UDim2.fromOffset(16, 22),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = resolvedLoadingTitle,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 101,
			Parent = LoadingCard
		})
		RegisterTheme(LoadingHeader, "TextColor3", "TextPrimary")

		local StatusLabel = Create("TextLabel", {
			Name = "Status",
			Size = UDim2.new(1, -32, 0, 20),
			Position = UDim2.fromOffset(16, 56),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = "Initializing modules...",
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 101,
			Parent = LoadingCard
		})
		RegisterTheme(StatusLabel, "TextColor3", "TextSecondary")

		-- Sharp Square Progress Track
		local ProgressTrack = Create("Frame", {
			Name = "ProgressTrack",
			Size = UDim2.new(1, -32, 0, 8),
			Position = UDim2.fromOffset(16, 94),
			BorderSizePixel = 0,
			ZIndex = 101,
			Parent = LoadingCard
		})
		RegisterTheme(ProgressTrack, "BackgroundColor3", "Secondary")
		ApplyCorner(ProgressTrack, 0)
		ApplyStroke(ProgressTrack, "Border", 1)

		local ProgressFill = Create("Frame", {
			Name = "ProgressFill",
			Size = UDim2.new(0, 0, 1, 0),
			BorderSizePixel = 0,
			ZIndex = 102,
			Parent = ProgressTrack
		})
		RegisterTheme(ProgressFill, "BackgroundColor3", "Accent")
		ApplyCorner(ProgressFill, 0)

		task.spawn(function()
			-- Stage 1 (~0.45s)
			StatusLabel.Text = "Initializing modules..."
			Tween(ProgressFill, { Size = UDim2.new(0.42, 0, 1, 0) }, LOADING_TWEEN)
			task.wait(0.45)

			-- Stage 2 (~0.45s)
			if not LoadingCard.Parent then return end
			StatusLabel.Text = "Applying theme (" .. TbUI._currentThemeName .. ")..."
			Tween(ProgressFill, { Size = UDim2.new(0.84, 0, 1, 0) }, LOADING_TWEEN)
			task.wait(0.45)

			-- Stage 3 (~0.40s) -> Total ~1.3s
			if not LoadingCard.Parent then return end
			StatusLabel.Text = "Ready"
			Tween(ProgressFill, { Size = UDim2.new(1, 0, 1, 0) }, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
			task.wait(0.4)

			-- Smoothly fade/scale out Loading Card
			if not LoadingCard.Parent then return end
			local fadeInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			Tween(LoadingCard, { Size = UDim2.fromOffset(290, 125), BackgroundTransparency = 1 }, fadeInfo)
			Tween(cardStroke, { Transparency = 1 }, fadeInfo)
			Tween(TopLoadingAccent, { BackgroundTransparency = 1 }, fadeInfo)
			Tween(LoadingHeader, { TextTransparency = 1 }, fadeInfo)
			Tween(StatusLabel, { TextTransparency = 1 }, fadeInfo)
			Tween(ProgressTrack, { BackgroundTransparency = 1 }, fadeInfo)
			Tween(ProgressFill, { BackgroundTransparency = 1 }, fadeInfo)
			task.wait(0.26)

			if LoadingCard and LoadingCard.Parent then
				LoadingCard:Destroy()
			end

			-- Reveal Main Window with clean scale/reveal
			if MainFrame and MainFrame.Parent then
				MainFrame.Visible = true
			end
		end)
	end

	return WindowObj
end

return TbUI

--[[
================================================================================
USAGE EXAMPLE (Remote Loadstring Execution)
================================================================================

local TbUI = loadstring(game:HttpGet("YOUR_RAW_URL"))()

-- Optional: Override the loading screen header before creating the window
TbUI:config.CustomTLtitle("example")

local Window = TbUI:CreateWindow({
	Title = "My Hub",
	Subtitle = "v1.0",
	Theme = "Obsidian",              -- "Obsidian" | "Midnight" | "Carbon" | "Emerald Dark"
	ToggleKey = Enum.KeyCode.RightShift,
	LoadingScreen = true,
	MobileButton = true              -- Auto-detects touch devices if omitted
})

local MainTab = Window:CreateTab("Main")
local PlayerSection = MainTab:CreateSection("Movement & Actions")

PlayerSection:CreateButton({
	Name = "Reset Character",
	Callback = function()
		local char = game:GetService("Players").LocalPlayer.Character
		if char then char:BreakJoints() end
	end
})

local SpeedToggle = PlayerSection:CreateToggle({
	Name = "Enable WalkSpeed",
	Default = false,
	Callback = function(state)
		print("WalkSpeed Enabled:", state)
	end
})

local SpeedSlider = PlayerSection:CreateSlider({
	Name = "WalkSpeed",
	Min = 16,
	Max = 150,
	Increment = 1,
	Default = 16,
	Callback = function(value)
		local hum = game:GetService("Players").LocalPlayer.Character and game:GetService("Players").LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = value end
	end
})

local SettingsTab = Window:CreateTab("Settings")
local ThemeSection = SettingsTab:CreateSection("Interface Appearance")

ThemeSection:CreateDropdown({
	Name = "Select Theme",
	Options = { "Obsidian", "Midnight", "Carbon", "Emerald Dark" },
	Default = "Obsidian",
	Callback = function(selectedTheme)
		TbUI:SetTheme(selectedTheme)
	end
})

ThemeSection:CreateTextBox({
	Name = "Config Name",
	Placeholder = "default_profile",
	Default = "",
	Callback = function(text, enterPressed)
		print("Saved config name:", text, "Enter pressed:", enterPressed)
	end
})

ThemeSection:CreateKeybind({
	Name = "Quick Action Key",
	Default = Enum.KeyCode.F,
	Callback = function(key)
		SpeedToggle:Set(not SpeedToggle:Get())
	end
})
]]
