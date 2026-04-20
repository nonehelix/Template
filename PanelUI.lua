local Panel = {}
Panel.__index = Panel

local FALLBACK_PANEL_STATE = {}

local function getPanelSharedState()
	if type(shared) == "table" then
		shared.__AdminPanelState = shared.__AdminPanelState or {}
		return shared.__AdminPanelState
	end

	return FALLBACK_PANEL_STATE
end

local function createCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function createStroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.Parent = parent
	return s
end

local function createPadding(parent, top, bottom, left, right)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, top or 0)
	p.PaddingBottom = UDim.new(0, bottom or 0)
	p.PaddingLeft = UDim.new(0, left or 0)
	p.PaddingRight = UDim.new(0, right or 0)
	p.Parent = parent
	return p
end

local function roundTo2(num)
	return math.floor(num * 100 + 0.5) / 100
end

local function formatNumber(num)
	num = tonumber(num) or 0
	num = roundTo2(num)
	if math.floor(num) == num then
		return tostring(math.floor(num))
	end
	return string.format("%.2f", num):gsub("0+$", ""):gsub("%.$", "")
end

local function copySimpleValue(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for k, v in pairs(value) do
		copy[k] = copySimpleValue(v)
	end
	return copy
end

local function arrayContains(arr, target)
	for _, v in ipairs(arr or {}) do
		if tostring(v) == tostring(target) then
			return true
		end
	end
	return false
end

local function toggleArrayValue(arr, target)
	local newArr = copySimpleValue(arr or {})
	target = tostring(target)

	local function removeValue(value)
		for i = #newArr, 1, -1 do
			if tostring(newArr[i]) == tostring(value) then
				table.remove(newArr, i)
			end
		end
	end

	local function hasValue(value)
		for _, v in ipairs(newArr) do
			if tostring(v) == tostring(value) then
				return true
			end
		end
		return false
	end

	if target == "All" then
		if hasValue("All") then
			removeValue("All")
			return newArr
		end
		return {"All"}
	end

	if hasValue(target) then
		removeValue(target)
		return newArr
	end

	removeValue("All")
	table.insert(newArr, target)
	return newArr
end

local function formatMultiSelectLabel(values, emptyText)
	emptyText = emptyText or "Nothing selected"

	if type(values) ~= "table" or #values == 0 then
		return emptyText
	end

	local text = table.concat(values, ", ")
	if #text > 24 then
		text = string.sub(text, 1, 21) .. "..."
	end
	return text
end

local function clampNumber(value, minValue, maxValue)
	value = tonumber(value)
	if value == nil then
		return nil
	end
	if minValue ~= nil and value < minValue then
		value = minValue
	end
	if maxValue ~= nil and value > maxValue then
		value = maxValue
	end
	return roundTo2(value)
end

local function isPointInsideGuiObject(guiObject, point)
	if not guiObject then
		return false
	end

	local absPos = guiObject.AbsolutePosition
	local absSize = guiObject.AbsoluteSize

	return
		point.X >= absPos.X and
		point.X <= absPos.X + absSize.X and
		point.Y >= absPos.Y and
		point.Y <= absPos.Y + absSize.Y
end

local function NewCleanupBag()
	return {Items = {}}
end

local function AddCleanupItem(bag, item)
	table.insert(bag.Items, item)
	return item
end

local function CleanupBag(bag)
	for _, item in ipairs(bag.Items) do
		local itemType = typeof(item)

		if itemType == "RBXScriptConnection" then
			if item.Connected then
				item:Disconnect()
			end
		elseif itemType == "Instance" then
			if item.Parent then
				item:Destroy()
			end
		elseif type(item) == "function" then
			pcall(item)
		elseif type(item) == "table" and item.Destroy then
			pcall(function()
				item:Destroy()
			end)
		end
	end

	table.clear(bag.Items)
end

function Panel.new(config)
	assert(type(config) == "table", "Panel.new requires config")
	assert(type(config.Shared) == "table", "Panel.new requires config.Shared")

	local self = setmetatable({}, Panel)

	self.Shared = config.Shared
	self.Player = self.Shared.player
	self.PlayerGui = self.Player:WaitForChild("PlayerGui")
	self.UserInputService = self.Shared.UserInputService
	self.Workspace = self.Shared.Workspace

	self.Config = {
		GuiName = config.GuiName,
		Title = config.Title,
		Subtitle = config.Subtitle,
		PageSubtitle = config.PageSubtitle,
		WindowSize = config.WindowSize,
		WindowPosition = config.WindowPosition,
		Values = {},
		Tabs = {},
		Handlers = config.Handlers or {},
		Features = config.Features or {},
		Theme = config.Theme,
		SaveSettings = config.SaveSettings
	}

	for key, value in pairs(config.Values or {}) do
		self.Config.Values[key] = copySimpleValue(value)
	end

	for _, tab in ipairs(config.Tabs or {}) do
		local newTab = {
			Name = tab.Name,
			Message = tab.Message,
			Options = {}
		}

		for _, opt in ipairs(tab.Options or {}) do
			table.insert(newTab.Options, opt)
		end

		table.insert(self.Config.Tabs, newTab)
	end

	self.State = {
		CurrentTab = nil,
		TabButtons = {},
		Pages = {},
		Controls = {},
		OpenDropdown = nil,
		OpenDropdownAnchor = nil,
		OpenDropdownBag = nil,
		IsMinimized = false,
		SaveQueued = false,
		Destroyed = false,
		AccentObjects = {
			TabButtons = {},
			ActionButtons = {},
			ToggleEnabledKnobs = {},
			ToggleEnabledLabels = {},
			ToggleButtons = {},
			DropdownButtons = {},
			DropdownStrokes = {},
			RowStrokes = {},
			HeaderButtons = {}
		}
	}

	self.Runtime = NewCleanupBag()
	self.GlobalState = getPanelSharedState()

	return self
end

function Panel:GetTheme()
	return self.Config.Theme
end

function Panel:GetValue(optionId)
	return self.Config.Values[optionId]
end

function Panel:RegisterControl(optionId, controlData)
	self.State.Controls[optionId] = controlData
end

function Panel:GetOptionItems(option)
	local resolver = self.Shared and self.Shared.ResolveOptionItems
	if type(resolver) == "function" then
		return resolver(option) or {}
	end

	return {}
end

function Panel:BindDrag(handle, getPosition, setPosition, onMove)
	local dragging = false
	local dragStart
	local startPosition

	AddCleanupItem(self.Runtime, handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPosition = getPosition()
		end
	end))

	AddCleanupItem(self.Runtime, handle.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end))

	AddCleanupItem(self.Runtime, self.UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			setPosition(UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset + delta.X,
				startPosition.Y.Scale,
				startPosition.Y.Offset + delta.Y
			))

			if onMove then
				onMove()
			end
		end
	end))
end

function Panel:CreateDropdownTrigger(row, initialText)
	local Theme = self:GetTheme()

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 140, 0, 34)
	button.Position = UDim2.new(1, -154, 0.5, -17)
	button.BackgroundColor3 = Theme.Input
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.ZIndex = 3
	button.Parent = row
	createCorner(button, 8)
	table.insert(self.State.AccentObjects.DropdownButtons, button)
	table.insert(self.State.AccentObjects.DropdownStrokes, createStroke(button, Theme.Stroke, 1, 0.45))

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(1, -26, 1, 0)
	valueLabel.Position = UDim2.new(0, 10, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = initialText
	valueLabel.TextColor3 = Theme.Text
	valueLabel.TextSize = 13
	valueLabel.Font = Enum.Font.Gotham
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	valueLabel.ZIndex = 4
	valueLabel.Parent = button

	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.new(0, 16, 1, 0)
	arrow.Position = UDim2.new(1, -20, 0, 0)
	arrow.BackgroundTransparency = 1
	arrow.Text = "v"
	arrow.TextColor3 = Theme.SubText
	arrow.TextSize = 11
	arrow.Font = Enum.Font.GothamBold
	arrow.ZIndex = 4
	arrow.Parent = button

	return button, valueLabel
end

function Panel:BindDropdownToggle(button, openDropdown)
	button.MouseButton1Click:Connect(function()
		if self.State.OpenDropdown then
			if self.State.OpenDropdownAnchor == button then
				self:CloseDropdown()
				return
			end
			self:CloseDropdown()
		end

		openDropdown()
	end)
end

function Panel:ClaimSingleton()
	local activeInstance = self.GlobalState.ActiveInstance
	if activeInstance and activeInstance ~= self and type(activeInstance.Destroy) == "function" then
		pcall(function()
			activeInstance:Destroy()
		end)
	end

	self.GlobalState.ActiveInstance = self
end

function Panel:QueueSave()
	if self.State.Destroyed or self.State.SaveQueued then
		return
	end

	self.State.SaveQueued = true

	task.delay(0.15, function()
		if self.State.Destroyed then
			return
		end

		self.State.SaveQueued = false
		if self.Config.SaveSettings then
			self.Config.SaveSettings(self.Config.Values)
		end
	end)
end

function Panel:FlushSave()
	if self.State.Destroyed then
		return
	end

	self.State.SaveQueued = false
	if self.Config.SaveSettings then
		self.Config.SaveSettings(self.Config.Values)
	end
end

function Panel:ApplyAccentTheme()
	local Theme = self:GetTheme()

	for tabName, button in pairs(self.State.AccentObjects.TabButtons) do
		if button and button.Parent then
			button.BackgroundColor3 = (self.State.CurrentTab == tabName) and Theme.Accent or Theme.Card
		end
	end

	for _, button in ipairs(self.State.AccentObjects.ActionButtons) do
		if button and button.Parent then
			button.BackgroundColor3 = Theme.Accent
		end
	end

	for _, knob in ipairs(self.State.AccentObjects.ToggleEnabledKnobs) do
		if knob and knob.Parent then
			knob.BackgroundColor3 = Theme.Accent
		end
	end

	for _, label in ipairs(self.State.AccentObjects.ToggleEnabledLabels) do
		if label and label.Parent and label.Text == "Enabled" then
			label.TextColor3 = Theme.Accent
		end
	end

	for _, button in ipairs(self.State.AccentObjects.ToggleButtons) do
		if button and button.Parent and button.BackgroundColor3 ~= Theme.Input then
			button.BackgroundColor3 = Color3.fromRGB(28, 42, 34)
		end
	end

	for _, button in ipairs(self.State.AccentObjects.DropdownButtons) do
		if button and button.Parent then
			button.BackgroundColor3 = Theme.Input
		end
	end

	for _, stroke in ipairs(self.State.AccentObjects.DropdownStrokes) do
		if stroke and stroke.Parent then
			stroke.Color = Theme.Stroke
		end
	end

	for _, stroke in ipairs(self.State.AccentObjects.RowStrokes) do
		if stroke and stroke.Parent then
			stroke.Color = Theme.Stroke
		end
	end

	for _, button in ipairs(self.State.AccentObjects.HeaderButtons) do
		if button and button.Parent then
			button.BackgroundColor3 = Theme.Card
		end
	end
end

function Panel:RefreshControl(optionId)
	local control = self.State.Controls[optionId]
	if not control or not control.Update then
		return
	end

	control.Update(self:GetValue(optionId))
end

function Panel:RefreshAllControls()
	for optionId in pairs(self.State.Controls) do
		self:RefreshControl(optionId)
	end
end

function Panel:SetValue(optionId, value, skipHandler)
	if self.State.Destroyed then
		return
	end

	self.Config.Values[optionId] = value
	self:RefreshControl(optionId)

	if not skipHandler then
		local handler = self.Config.Handlers[optionId]
		if handler then
			handler(value, self.Config.Values, self)
		end
	end

	self:QueueSave()
end

function Panel:ApplyAll()
	if self.State.Destroyed then
		return
	end

	for optionId, value in pairs(self.Config.Values) do
		local handler = self.Config.Handlers[optionId]
		if handler then
			handler(value, self.Config.Values, self)
		end
	end

	self:RefreshAllControls()
	self:ApplyAccentTheme()
end

function Panel:CloseDropdown()
	if self.State.OpenDropdownBag then
		CleanupBag(self.State.OpenDropdownBag)
		self.State.OpenDropdownBag = nil
	elseif self.State.OpenDropdown and self.State.OpenDropdown.Parent then
		self.State.OpenDropdown:Destroy()
	end

	self.State.OpenDropdown = nil
	self.State.OpenDropdownAnchor = nil
end

function Panel:Minimize(skipSave)
	self:CloseDropdown()
	self.State.IsMinimized = true

	if self.MainFrame then
		self.MainFrame.Visible = false
	end
	if self.OpenButton then
		self.OpenButton.Visible = true
	end

	if not skipSave and self.Config.Values.Minimized ~= nil then
		self.Config.Values.Minimized = true
		self:QueueSave()
	end
end

function Panel:Restore(skipSave)
	self.State.IsMinimized = false

	if self.MainFrame then
		self.MainFrame.Visible = true
	end
	if self.OpenButton then
		self.OpenButton.Visible = false
	end

	if not skipSave and self.Config.Values.Minimized ~= nil then
		self.Config.Values.Minimized = false
		self:QueueSave()
	end
end

function Panel:Destroy()
	if self.State.Destroyed then
		return
	end

	self:CloseDropdown()

	for _, feature in ipairs(self.Config.Features) do
		if feature.Cleanup then
			pcall(function()
				feature:Cleanup()
			end)
		end
	end

	self:FlushSave()
	self.State.Destroyed = true

	CleanupBag(self.Runtime)

	if self.ScreenGui then
		self.ScreenGui:Destroy()
		self.ScreenGui = nil
	end

	if self.GlobalState.ActiveInstance == self then
		self.GlobalState.ActiveInstance = nil
	end
end

function Panel:CreateGui()
	local Theme = self:GetTheme()

	local oldGui = self.PlayerGui:FindFirstChild(self.Config.GuiName or "AdminPanel")
	if oldGui then
		oldGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = self.Config.GuiName or "AdminPanel"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 999
	screenGui.Parent = self.PlayerGui
	self.ScreenGui = screenGui

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 50
	overlay.Parent = screenGui
	self.Overlay = overlay

	local openButton = Instance.new("TextButton")
	openButton.Name = "OpenButton"
	openButton.Size = UDim2.new(0, 42, 0, 42)
	openButton.Position = UDim2.new(0.5, -21, 0, 70)
	openButton.BackgroundColor3 = Color3.fromRGB(70, 74, 84)
	openButton.BorderSizePixel = 0
	openButton.Text = ""
	openButton.Visible = false
	openButton.ZIndex = 55
	openButton.AutoButtonColor = false
	openButton.Parent = screenGui
	createCorner(openButton, 12)
	createStroke(openButton, Color3.fromRGB(255, 255, 255), 1, 0.85)

	local openIcon = Instance.new("TextLabel")
	openIcon.Size = UDim2.new(1, 0, 1, 0)
	openIcon.BackgroundTransparency = 1
	openIcon.Text = "="
	openIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
	openIcon.TextSize = 20
	openIcon.Font = Enum.Font.GothamBold
	openIcon.ZIndex = 56
	openIcon.Parent = openButton

	openButton.MouseButton1Click:Connect(function()
		self:Restore()
	end)

	self:BindDrag(
		openButton,
		function()
			return openButton.Position
		end,
		function(position)
			openButton.Position = position
		end
	)

	self.OpenButton = openButton

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = self.Config.WindowSize or UDim2.new(0, 760, 0, 460)
	mainFrame.Position = self.Config.WindowPosition or UDim2.new(0.5, -380, 0.5, -230)
	mainFrame.BackgroundColor3 = Theme.Window
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui
	createCorner(mainFrame, 14)
	createStroke(mainFrame, Theme.Stroke, 1, 0.2)
	self.MainFrame = mainFrame

	local sidebar = Instance.new("Frame")
	sidebar.Size = UDim2.new(0, 190, 1, 0)
	sidebar.BackgroundColor3 = Theme.Sidebar
	sidebar.BorderSizePixel = 0
	sidebar.Parent = mainFrame
	createCorner(sidebar, 14)

	local sidebarFix = Instance.new("Frame")
	sidebarFix.Size = UDim2.new(0, 20, 1, 0)
	sidebarFix.Position = UDim2.new(1, -20, 0, 0)
	sidebarFix.BackgroundColor3 = Theme.Sidebar
	sidebarFix.BorderSizePixel = 0
	sidebarFix.Parent = sidebar

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 28)
	title.Position = UDim2.new(0, 16, 0, 18)
	title.BackgroundTransparency = 1
	title.Text = self.Config.Title or "Admin Panel"
	title.TextColor3 = Theme.Text
	title.TextSize = 20
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = sidebar

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -20, 0, 18)
	subtitle.Position = UDim2.new(0, 16, 0, 44)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = self.Config.Subtitle or "Template"
	subtitle.TextColor3 = Theme.SubText
	subtitle.TextSize = 12
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = sidebar

	local tabHolder = Instance.new("Frame")
	tabHolder.Size = UDim2.new(1, -20, 1, -100)
	tabHolder.Position = UDim2.new(0, 10, 0, 82)
	tabHolder.BackgroundTransparency = 1
	tabHolder.Parent = sidebar
	self.TabHolder = tabHolder

	local tabList = Instance.new("UIListLayout")
	tabList.Padding = UDim.new(0, 8)
	tabList.Parent = tabHolder

	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, -206, 1, -16)
	content.Position = UDim2.new(0, 198, 0, 8)
	content.BackgroundColor3 = Theme.Content
	content.BorderSizePixel = 0
	content.Parent = mainFrame
	createCorner(content, 12)
	createStroke(content, Theme.Stroke, 1, 0.3)
	self.Content = content

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 56)
	header.BackgroundTransparency = 1
	header.Parent = content
	self.Header = header

	local pageTitle = Instance.new("TextLabel")
	pageTitle.Size = UDim2.new(1, -110, 0, 24)
	pageTitle.Position = UDim2.new(0, 18, 0, 12)
	pageTitle.BackgroundTransparency = 1
	pageTitle.Text = ""
	pageTitle.TextColor3 = Theme.Text
	pageTitle.TextSize = 18
	pageTitle.Font = Enum.Font.GothamBold
	pageTitle.TextXAlignment = Enum.TextXAlignment.Left
	pageTitle.Parent = header
	self.PageTitle = pageTitle

	local pageSub = Instance.new("TextLabel")
	pageSub.Size = UDim2.new(1, -110, 0, 18)
	pageSub.Position = UDim2.new(0, 18, 0, 32)
	pageSub.BackgroundTransparency = 1
	pageSub.Text = self.Config.PageSubtitle or "Live settings update instantly"
	pageSub.TextColor3 = Theme.SubText
	pageSub.TextSize = 12
	pageSub.Font = Enum.Font.Gotham
	pageSub.TextXAlignment = Enum.TextXAlignment.Left
	pageSub.Parent = header

	local minimizeBtn = Instance.new("TextButton")
	minimizeBtn.Size = UDim2.new(0, 30, 0, 30)
	minimizeBtn.Position = UDim2.new(1, -76, 0, 14)
	minimizeBtn.BackgroundColor3 = Theme.Card
	minimizeBtn.Text = "_"
	minimizeBtn.TextColor3 = Theme.Text
	minimizeBtn.TextSize = 18
	minimizeBtn.Font = Enum.Font.GothamBold
	minimizeBtn.Parent = header
	createCorner(minimizeBtn, 8)
	table.insert(self.State.AccentObjects.HeaderButtons, minimizeBtn)
	table.insert(self.State.AccentObjects.RowStrokes, createStroke(minimizeBtn, Theme.Stroke, 1, 0.35))

	minimizeBtn.MouseButton1Click:Connect(function()
		self:Minimize()
	end)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -42, 0, 14)
	closeBtn.BackgroundColor3 = Theme.Card
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Theme.Text
	closeBtn.TextSize = 18
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = header
	createCorner(closeBtn, 8)
	table.insert(self.State.AccentObjects.HeaderButtons, closeBtn)
	table.insert(self.State.AccentObjects.RowStrokes, createStroke(closeBtn, Theme.Stroke, 1, 0.35))

	closeBtn.MouseButton1Click:Connect(function()
		self:Destroy()
	end)

	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -24, 0, 1)
	divider.Position = UDim2.new(0, 12, 0, 56)
	divider.BackgroundColor3 = Theme.Stroke
	divider.BackgroundTransparency = 0.45
	divider.BorderSizePixel = 0
	divider.Parent = content

	local pagesHolder = Instance.new("Frame")
	pagesHolder.Size = UDim2.new(1, -20, 1, -74)
	pagesHolder.Position = UDim2.new(0, 10, 0, 64)
	pagesHolder.BackgroundTransparency = 1
	pagesHolder.Parent = content
	self.PagesHolder = pagesHolder
end

function Panel:CreatePage(tabName)
	local page = Instance.new("ScrollingFrame")
	page.Name = tabName
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 4
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.AutomaticCanvasSize = Enum.AutomaticSize.None
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.ClipsDescendants = true
	page.Visible = false
	page.Parent = self.PagesHolder

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.Parent = page

	createPadding(page, 4, 10, 4, 8)

	local function updateCanvas()
		page.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 14)
	end

	AddCleanupItem(self.Runtime, layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas))
	task.defer(updateCanvas)

	self.State.Pages[tabName] = page
	return page
end

function Panel:CreateSectionRow(parent, option)
	local Theme = self:GetTheme()

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.ZIndex = 2
	row.Parent = parent

	local lineLeft = Instance.new("Frame")
	lineLeft.Size = UDim2.new(0.25, -6, 0, 1)
	lineLeft.Position = UDim2.new(0, 0, 0.5, 0)
	lineLeft.AnchorPoint = Vector2.new(0, 0.5)
	lineLeft.BackgroundColor3 = Theme.Stroke
	lineLeft.BackgroundTransparency = 0.35
	lineLeft.BorderSizePixel = 0
	lineLeft.Parent = row

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.5, 0, 1, 0)
	title.Position = UDim2.new(0.25, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = tostring(option.Label or "Section")
	title.TextColor3 = Theme.SubText
	title.TextSize = 12
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.ZIndex = 3
	title.Parent = row

	local lineRight = Instance.new("Frame")
	lineRight.Size = UDim2.new(0.25, -6, 0, 1)
	lineRight.Position = UDim2.new(1, 0, 0.5, 0)
	lineRight.AnchorPoint = Vector2.new(1, 0.5)
	lineRight.BackgroundColor3 = Theme.Stroke
	lineRight.BackgroundTransparency = 0.35
	lineRight.BorderSizePixel = 0
	lineRight.Parent = row

	return row
end

function Panel:CreateRow(parent, option)
	local Theme = self:GetTheme()

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 62)
	row.BackgroundColor3 = Theme.Card
	row.BorderSizePixel = 0
	row.ClipsDescendants = true
	row.ZIndex = 2
	row.Parent = parent
	createCorner(row, 10)
	table.insert(self.State.AccentObjects.RowStrokes, createStroke(row, Theme.Stroke, 1, 0.4))

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.55, 0, 0, 20)
	title.Position = UDim2.new(0, 14, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = option.Label or option.Id
	title.TextColor3 = Theme.Text
	title.TextSize = 14
	title.Font = Enum.Font.GothamMedium
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	title.Parent = row

	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(0.58, 0, 0, 16)
	desc.Position = UDim2.new(0, 14, 0, 32)
	desc.BackgroundTransparency = 1
	desc.Text = option.Description or ""
	desc.TextColor3 = Theme.SubText
	desc.TextSize = 11
	desc.Font = Enum.Font.Gotham
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.ZIndex = 3
	desc.Parent = row

	return row
end

function Panel:CreateNumberInput(row, option)
	local Theme = self:GetTheme()

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(0, 110, 0, 34)
	holder.Position = UDim2.new(1, -124, 0.5, -17)
	holder.BackgroundColor3 = Theme.Input
	holder.BorderSizePixel = 0
	holder.ZIndex = 3
	holder.Parent = row
	createCorner(holder, 8)
	table.insert(self.State.AccentObjects.DropdownStrokes, createStroke(holder, Theme.Stroke, 1, 0.45))

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -16, 1, 0)
	box.Position = UDim2.new(0, 8, 0, 0)
	box.BackgroundTransparency = 1
	box.Text = formatNumber(self:GetValue(option.Id))
	box.PlaceholderText = "Value"
	box.ClearTextOnFocus = false
	box.TextColor3 = Theme.Text
	box.PlaceholderColor3 = Theme.SubText
	box.TextSize = 13
	box.Font = Enum.Font.Gotham
	box.ZIndex = 4
	box.Parent = holder

	box.FocusLost:Connect(function(enterPressed)
		local value = clampNumber(box.Text, option.Min, option.Max)
		if value ~= nil then
			self:SetValue(option.Id, value)
		else
			self:RefreshControl(option.Id)
		end
	end)

	self:RegisterControl(option.Id, {
		Update = function(value)
			box.Text = formatNumber(value)
		end
	})
end

function Panel:CreateToggle(row, option)
	local Theme = self:GetTheme()

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Size = UDim2.new(0, 56, 0, 16)
	stateLabel.Position = UDim2.new(1, -136, 0.5, -8)
	stateLabel.BackgroundTransparency = 1
	stateLabel.TextSize = 11
	stateLabel.Font = Enum.Font.Gotham
	stateLabel.TextXAlignment = Enum.TextXAlignment.Right
	stateLabel.ZIndex = 3
	stateLabel.Parent = row

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 46, 0, 24)
	button.Position = UDim2.new(1, -72, 0.5, -12)
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.ZIndex = 3
	button.Parent = row
	createCorner(button, 999)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 18, 0, 18)
	fill.BorderSizePixel = 0
	fill.ZIndex = 4
	fill.Parent = button
	createCorner(fill, 999)

	table.insert(self.State.AccentObjects.ToggleButtons, button)
	table.insert(self.State.AccentObjects.ToggleEnabledKnobs, fill)
	table.insert(self.State.AccentObjects.ToggleEnabledLabels, stateLabel)

	local function updateVisual(state)
		if state then
			button.BackgroundColor3 = Color3.fromRGB(28, 42, 34)
			fill.Position = UDim2.new(1, -22, 0.5, -9)
			fill.BackgroundColor3 = Theme.Accent
			stateLabel.Text = "Enabled"
			stateLabel.TextColor3 = Theme.Accent
		else
			button.BackgroundColor3 = Theme.Input
			fill.Position = UDim2.new(0, 4, 0.5, -9)
			fill.BackgroundColor3 = Theme.SubText
			stateLabel.Text = "Disabled"
			stateLabel.TextColor3 = Theme.SubText
		end
	end

	updateVisual(self:GetValue(option.Id))

	button.MouseButton1Click:Connect(function()
		local newValue = not self:GetValue(option.Id)
		self:SetValue(option.Id, newValue)
	end)

	self:RegisterControl(option.Id, {
		Update = function(value)
			updateVisual(not not value)
		end
	})
end

function Panel:CreateButton(row, option)
	local Theme = self:GetTheme()

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 100, 0, 32)
	button.Position = UDim2.new(1, -114, 0.5, -16)
	button.BackgroundColor3 = Theme.Accent
	button.BorderSizePixel = 0
	button.Text = option.ButtonText or "Run"
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 13
	button.Font = Enum.Font.GothamMedium
	button.ZIndex = 3
	button.Parent = row
	createCorner(button, 8)

	table.insert(self.State.AccentObjects.ActionButtons, button)

	button.MouseButton1Click:Connect(function()
		local handler = self.Config.Handlers[option.Id]
		if handler then
			handler(self:GetValue(option.Id), self.Config.Values, self)
		end
	end)

	self:RegisterControl(option.Id, {
		Update = function()
		end
	})
end

function Panel:CreateDropdownBase(button, itemCount)
	local Theme = self:GetTheme()
	local dropdownBag = NewCleanupBag()

	local dropdown = Instance.new("Frame")
	dropdown.Name = "Dropdown"
	dropdown.BackgroundColor3 = Theme.Dropdown
	dropdown.BorderSizePixel = 0
	dropdown.ZIndex = 60
	dropdown.Parent = self.Overlay
	createCorner(dropdown, 8)
	createStroke(dropdown, Theme.Stroke, 1, 0.2)
	AddCleanupItem(dropdownBag, dropdown)

	local buttonPos = button.AbsolutePosition
	local buttonSize = button.AbsoluteSize
	local viewport = self.Workspace.CurrentCamera and self.Workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)

	local maxVisible = math.min(itemCount, 6)
	local dropdownHeight = math.max(34, maxVisible * 30 + 8)
	local dropdownWidth = buttonSize.X

	local x = buttonPos.X
	local y = buttonPos.Y + buttonSize.Y + 4

	if x + dropdownWidth > viewport.X - 8 then
		x = math.max(8, viewport.X - dropdownWidth - 8)
	end

	if y + dropdownHeight > viewport.Y - 8 then
		y = math.max(8, buttonPos.Y - dropdownHeight - 4)
	end

	dropdown.Size = UDim2.new(0, dropdownWidth, 0, dropdownHeight)
	dropdown.Position = UDim2.new(0, x, 0, y)

	local useScroll = itemCount > 6
	local parentForItems

	if useScroll then
		local scroll = Instance.new("ScrollingFrame")
		scroll.Size = UDim2.new(1, -8, 1, -8)
		scroll.Position = UDim2.new(0, 4, 0, 4)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = 4
		scroll.ZIndex = 61
		scroll.Parent = dropdown

		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Size = UDim2.new(1, -4, 0, 0)
		holder.Parent = scroll

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.Parent = holder

		local function updateScrollCanvas()
			local contentHeight = layout.AbsoluteContentSize.Y
			holder.Size = UDim2.new(1, -4, 0, contentHeight)
			scroll.CanvasSize = UDim2.new(0, 0, 0, contentHeight)
		end

		AddCleanupItem(dropdownBag, layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateScrollCanvas))
		task.defer(updateScrollCanvas)

		parentForItems = holder
	else
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Size = UDim2.new(1, -8, 1, -8)
		holder.Position = UDim2.new(0, 4, 0, 4)
		holder.ZIndex = 61
		holder.Parent = dropdown

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.Parent = holder

		parentForItems = holder
	end

	self.State.OpenDropdown = dropdown
	self.State.OpenDropdownAnchor = button
	self.State.OpenDropdownBag = dropdownBag

	return dropdown, parentForItems
end

function Panel:CreateSelect(row, option)
	local Theme = self:GetTheme()
	local button, valueLabel = self:CreateDropdownTrigger(row, tostring(self:GetValue(option.Id) or ""))

	local function openDropdown()
		self:CloseDropdown()

		local items = self:GetOptionItems(option)

		local _, parentForItems = self:CreateDropdownBase(button, #items)

		for _, item in ipairs(items) do
			local itemButton = Instance.new("TextButton")
			itemButton.Size = UDim2.new(1, 0, 0, 26)
			itemButton.BackgroundColor3 = Theme.Input
			itemButton.BorderSizePixel = 0
			itemButton.Text = tostring(item)
			itemButton.TextColor3 = Theme.Text
			itemButton.TextSize = 13
			itemButton.Font = Enum.Font.Gotham
			itemButton.ZIndex = 62
			itemButton.Parent = parentForItems
			createCorner(itemButton, 6)

			itemButton.MouseButton1Click:Connect(function()
				self:SetValue(option.Id, item)
				self:CloseDropdown()
			end)
		end
	end

	self:BindDropdownToggle(button, openDropdown)

	self:RegisterControl(option.Id, {
		Update = function(value)
			valueLabel.Text = tostring(value or "")
		end
	})
end

function Panel:CreateMultiSelect(row, option)
	local Theme = self:GetTheme()
	local emptyText = option.EmptyText or "Nothing selected"

	if type(self.Config.Values[option.Id]) ~= "table" then
		self.Config.Values[option.Id] = {}
	end

	local button, valueLabel = self:CreateDropdownTrigger(row, formatMultiSelectLabel(self:GetValue(option.Id), emptyText))
	valueLabel.TextColor3 = (#self:GetValue(option.Id) == 0) and Theme.SubText or Theme.Text

	local function openDropdown()
		self:CloseDropdown()

		local items = self:GetOptionItems(option)

		local totalItems = #items + 1
		local _, parentForItems = self:CreateDropdownBase(button, totalItems)

		local function refreshAllButtons()
			for _, child in ipairs(parentForItems:GetChildren()) do
				if child:IsA("TextButton") and child:GetAttribute("ItemValue") ~= nil then
					local itemValue = child:GetAttribute("ItemValue")
					local check = child:FindFirstChild("CheckLabel")
					local selected = arrayContains(self:GetValue(option.Id), itemValue)

					if selected then
						child.BackgroundColor3 = Color3.fromRGB(28, 42, 34)
						if check then
							check.Text = "x"
							check.TextColor3 = Theme.Accent
						end
					else
						child.BackgroundColor3 = Theme.Input
						if check then
							check.Text = ""
							check.TextColor3 = Theme.SubText
						end
					end
				end
			end
		end

		local clearButton = Instance.new("TextButton")
		clearButton.Size = UDim2.new(1, 0, 0, 26)
		clearButton.BackgroundColor3 = Theme.Input
		clearButton.BorderSizePixel = 0
		clearButton.Text = emptyText
		clearButton.TextColor3 = Theme.SubText
		clearButton.TextSize = 13
		clearButton.Font = Enum.Font.Gotham
		clearButton.ZIndex = 62
		clearButton.Parent = parentForItems
		createCorner(clearButton, 6)

		clearButton.MouseButton1Click:Connect(function()
			self:SetValue(option.Id, {})
			refreshAllButtons()
		end)

		for _, item in ipairs(items) do
			local itemButton = Instance.new("TextButton")
			itemButton.Size = UDim2.new(1, 0, 0, 26)
			itemButton.BorderSizePixel = 0
			itemButton.Text = ""
			itemButton.ZIndex = 62
			itemButton.Parent = parentForItems
			itemButton:SetAttribute("ItemValue", item)
			createCorner(itemButton, 6)

			local check = Instance.new("TextLabel")
			check.Name = "CheckLabel"
			check.Size = UDim2.new(0, 18, 1, 0)
			check.Position = UDim2.new(0, 8, 0, 0)
			check.BackgroundTransparency = 1
			check.Text = ""
			check.TextSize = 13
			check.Font = Enum.Font.GothamBold
			check.ZIndex = 63
			check.Parent = itemButton

			local textLabel = Instance.new("TextLabel")
			textLabel.Size = UDim2.new(1, -32, 1, 0)
			textLabel.Position = UDim2.new(0, 26, 0, 0)
			textLabel.BackgroundTransparency = 1
			textLabel.Text = tostring(item)
			textLabel.TextColor3 = Theme.Text
			textLabel.TextSize = 13
			textLabel.Font = Enum.Font.Gotham
			textLabel.TextXAlignment = Enum.TextXAlignment.Left
			textLabel.ZIndex = 63
			textLabel.Parent = itemButton

			itemButton.MouseButton1Click:Connect(function()
				local newValues = toggleArrayValue(self:GetValue(option.Id), item)
				self:SetValue(option.Id, newValues)
				refreshAllButtons()
			end)
		end

		refreshAllButtons()
	end

	self:BindDropdownToggle(button, openDropdown)

	self:RegisterControl(option.Id, {
		Update = function(values)
			values = values or {}
			valueLabel.Text = formatMultiSelectLabel(values, emptyText)
			valueLabel.TextColor3 = (#values == 0) and Theme.SubText or Theme.Text
		end
	})
end

function Panel:CreateOption(parent, option)
	if option.Type == "section" then
		self:CreateSectionRow(parent, option)
		return
	end

	local row = self:CreateRow(parent, option)

	if option.Type == "number" then
		self:CreateNumberInput(row, option)
	elseif option.Type == "toggle" then
		self:CreateToggle(row, option)
	elseif option.Type == "button" then
		self:CreateButton(row, option)
	elseif option.Type == "select" then
		self:CreateSelect(row, option)
	elseif option.Type == "multiselect" then
		self:CreateMultiSelect(row, option)
	end
end

function Panel:CreateTabButton(tab)
	local Theme = self:GetTheme()

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 38)
	btn.BackgroundColor3 = Theme.Card
	btn.BorderSizePixel = 0
	btn.Text = tab.Name
	btn.TextColor3 = Theme.SubText
	btn.TextSize = 13
	btn.Font = Enum.Font.GothamMedium
	btn.Parent = self.TabHolder
	createCorner(btn, 10)
	table.insert(self.State.AccentObjects.RowStrokes, createStroke(btn, Theme.Stroke, 1, 0.45))

	btn.MouseButton1Click:Connect(function()
		self:CloseDropdown()
		self:SwitchTab(tab.Name)
	end)

	self.State.TabButtons[tab.Name] = btn
	self.State.AccentObjects.TabButtons[tab.Name] = btn
end

function Panel:SwitchTab(tabName)
	local Theme = self:GetTheme()

	self.State.CurrentTab = tabName
	self.PageTitle.Text = tabName

	for name, page in pairs(self.State.Pages) do
		page.Visible = (name == tabName)
	end

	for name, button in pairs(self.State.TabButtons) do
		if name == tabName then
			button.BackgroundColor3 = Theme.Accent
			button.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			button.BackgroundColor3 = Theme.Card
			button.TextColor3 = Theme.SubText
		end
	end
end

function Panel:BuildTabs()
	local Theme = self:GetTheme()

	for _, tab in ipairs(self.Config.Tabs) do
		self:CreateTabButton(tab)

		local page = self:CreatePage(tab.Name)

		for _, option in ipairs(tab.Options or {}) do
			self:CreateOption(page, option)
		end

		if tab.Message then
			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, 0, 0, 90)
			card.BackgroundColor3 = Theme.Card
			card.BorderSizePixel = 0
			card.Parent = page
			createCorner(card, 10)
			table.insert(self.State.AccentObjects.RowStrokes, createStroke(card, Theme.Stroke, 1, 0.4))

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, -24, 1, -24)
			label.Position = UDim2.new(0, 12, 0, 12)
			label.BackgroundTransparency = 1
			label.Text = tab.Message
			label.TextWrapped = true
			label.TextColor3 = Theme.SubText
			label.TextSize = 13
			label.Font = Enum.Font.Gotham
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextYAlignment = Enum.TextYAlignment.Top
			label.Parent = card
		end
	end

	if self.Config.Tabs[1] then
		self:SwitchTab(self.Config.Tabs[1].Name)
	end
end

function Panel:SetupDragging()
	self:BindDrag(
		self.Header,
		function()
			return self.MainFrame.Position
		end,
		function(position)
			self.MainFrame.Position = position
		end,
		function()
			self:CloseDropdown()
		end
	)
end

function Panel:SetupRespawnApply()
	AddCleanupItem(self.Runtime, self.Player.CharacterAdded:Connect(function()
		task.wait(0.8)

		if self.State.Destroyed then
			return
		end

		self:ApplyAll()

		if self:GetValue("Minimized") then
			self:Minimize(true)
		else
			self:Restore(true)
		end
	end))
end

function Panel:SetupOutsideClick()
	AddCleanupItem(self.Runtime, self.UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 and self.State.OpenDropdown then
			local mousePos = input.Position
			local clickedDropdown = isPointInsideGuiObject(self.State.OpenDropdown, mousePos)
			local clickedAnchor = isPointInsideGuiObject(self.State.OpenDropdownAnchor, mousePos)

			if not clickedDropdown and not clickedAnchor then
				task.defer(function()
					if self.State.Destroyed then
						return
					end

					local focused = self.UserInputService:GetFocusedTextBox()
					if not focused then
						self:CloseDropdown()
					end
				end)
			end
		end
	end))
end

function Panel:Init()
	self:ClaimSingleton()
	self:CreateGui()
	self:BuildTabs()
	self:SetupDragging()
	self:SetupRespawnApply()
	self:SetupOutsideClick()
	self:ApplyAll()

	if self:GetValue("Minimized") then
		self:Minimize(true)
	else
		self:Restore(true)
	end
end

return Panel
