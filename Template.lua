--[[
	UNIVERSAL ADMIN PANEL TEMPLATE
	Single LocalScript
	Single-file modular architecture

	STRUCTURE
	- Services
	- Access control
	- Shared helpers
	- Runtime cleanup helpers
	- Theme
	- Feature registry + context
	- Feature blocks
	- Base config + compiler
	- Panel framework
	- Startup

	SUPPORTED CONTROL TYPES
	- "number"
	- "toggle"
	- "button"
	- "select"
	- "multiselect"

	DISPLAY-ONLY TYPE
	- "section" -- auto-inserted header row

	FEATURE CONTRACT
	- Key = "UniqueFeatureKey"
	- Tab = "Tab Name"
	- Section = "Section Name"      -- optional
	- Order = number                -- optional sort order
	- Defaults = {}
	- Options = {}
	- State = {}
	- Init(self, context)           -- optional
	- ApplyDefaults(self, values)   -- optional
	- GetHandlers(self) -> table
	- Cleanup(self)                 -- optional
]]

--==================================================
-- AUTO RE-EXECUTE ON TELEPORT (Like Infinite Yield)
--==================================================
local TeleportCheck = false

Players.LocalPlayer.OnTeleport:Connect(function(State)
    if TeleportCheck then return end
    TeleportCheck = true

    -- Replace this link with your own raw script link
    local scriptUrl = "https://raw.githubusercontent.com/nonehelix/Template/main/Template.lua"

    local teleportCode = [[
        repeat task.wait() until game:IsLoaded()
        task.wait(0.5)
        loadstring(game:HttpGet("]] .. scriptUrl .. [[", true))()
    ]]

    if queue_on_teleport then
        queue_on_teleport(teleportCode)
    elseif syn and syn.queue_on_teleport then
        syn.queue_on_teleport(teleportCode)
    elseif fluxus and fluxus.queue_on_teleport then
        fluxus.queue_on_teleport(teleportCode)
    end

    print("✅ Panel will auto re-execute after teleport")
end)

--==================================================
-- SERVICES
--==================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")


--==================================================
-- ACCESS CONTROL (LINK CHECK)
--==================================================

local ACCESS_LINKS = {
	"https://www.roblox.com/es/games/76285745979410/Anime-Card-Collection",
    "https://www.roblox.com/es/games/90462358603255/Anime-Eternal",
	-- Add more allowed links here if needed
}

local function extractPlaceIdFromLink(link)
	if type(link) ~= "string" then
		return nil
	end

	local id = string.match(link, "/games/(%d+)")
	if id then
		return tonumber(id)
	end

	id = string.match(link, "placeId=(%d+)")
	if id then
		return tonumber(id)
	end

	return nil
end

local function isAllowedGame()
	local currentPlaceId = game.PlaceId

	for _, link in ipairs(ACCESS_LINKS) do
		local placeId = extractPlaceIdFromLink(link)
		if placeId and placeId == currentPlaceId then
			return true
		end
	end

	return false
end

--==================================================
-- SHARED HELPERS
--==================================================

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

local function shallowCopyArray(arr)
	local copy = {}
	for i, v in ipairs(arr or {}) do
		copy[i] = v
	end
	return copy
end

local function deepCopySimple(value)
	if type(value) ~= "table" then
		return value
	end

	local newTable = {}
	for k, v in pairs(value) do
		if type(v) == "table" then
			newTable[k] = deepCopySimple(v)
		else
			newTable[k] = v
		end
	end
	return newTable
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
	local newArr = shallowCopyArray(arr)
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
		else
			return {"All"}
		end
	end

	if hasValue(target) then
		removeValue(target)
		return newArr
	else
		removeValue("All")
		table.insert(newArr, target)
		return newArr
	end
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

local function waitForCharacterParts(timeoutSeconds)
	timeoutSeconds = timeoutSeconds or 8
	local deadline = tick() + timeoutSeconds

	local character = player.Character
	while not character do
		if tick() >= deadline then
			return nil, nil
		end
		task.wait()
		character = player.Character
	end

	local remaining = deadline - tick()
	if remaining <= 0 then
		return character, nil
	end

	local humanoid = character:WaitForChild("Humanoid", remaining)
	return character, humanoid
end

local function getCharacter()
	return player.Character or player.CharacterAdded:Wait()
end

local function getHumanoid()
	local character = getCharacter()
	return character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart()
	local character = getCharacter()
	return character:FindFirstChild("HumanoidRootPart")
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

--==================================================
-- AUTOMATIC SETTINGS SAVE / LOAD
--==================================================

local SETTINGS_FILE = "AnimeCardPanel_Settings.json"

local function SaveSettings(values)
	if not writefile then
		return
	end

	pcall(function()
		local jsonData = HttpService:JSONEncode(values or {})
		writefile(SETTINGS_FILE, jsonData)
	end)
end

local function LoadSettings(defaultValues)
	local mergedValues = deepCopySimple(defaultValues or {})

	if not (isfile and readfile) then
		return mergedValues
	end

	if not isfile(SETTINGS_FILE) then
		return mergedValues
	end

	local success, loaded = pcall(function()
		local data = readfile(SETTINGS_FILE)
		return HttpService:JSONDecode(data)
	end)

	if success and type(loaded) == "table" then
		for k, v in pairs(loaded) do
			if mergedValues[k] ~= nil then
				mergedValues[k] = v
			end
		end
	end

	return mergedValues
end

--==================================================
-- RUNTIME CLEANUP HELPERS
--==================================================

local function NewCleanupBag()
	return {
		Items = {}
	}
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

--==================================================
-- THEME
--==================================================

local Theme = {
	Window = Color3.fromRGB(18, 20, 26),
	Sidebar = Color3.fromRGB(22, 24, 31),
	Content = Color3.fromRGB(24, 27, 35),
	Card = Color3.fromRGB(31, 35, 45),
	Stroke = Color3.fromRGB(60, 67, 86),
	Text = Color3.fromRGB(242, 245, 255),
	SubText = Color3.fromRGB(160, 168, 188),
	Accent = Color3.fromRGB(90, 140, 255),
	Green = Color3.fromRGB(60, 200, 120),
	Input = Color3.fromRGB(20, 23, 30),
	Dropdown = Color3.fromRGB(27, 31, 40)
}

--==================================================
-- FEATURE REGISTRY + CONTEXT
--==================================================

local RegisteredFeatures = {}
local FeatureList = {}
local VALID_OPTION_TYPES = {
	number = true,
	toggle = true,
	button = true,
	select = true,
	multiselect = true,
	section = true,
}

local function RegisterFeature(feature)
	assert(type(feature) == "table", "Feature must be a table")
	assert(type(feature.Key) == "string" and feature.Key ~= "", "Feature.Key is required")
	assert(type(feature.Tab) == "string" and feature.Tab ~= "", "Feature.Tab is required")
	assert(not RegisteredFeatures[feature.Key], "Duplicate Feature.Key: " .. feature.Key)

	feature.Section = feature.Section or nil
	feature.Order = feature.Order or 999
	feature.Defaults = feature.Defaults or {}
	feature.Options = feature.Options or {}
	feature.State = feature.State or {}

	RegisteredFeatures[feature.Key] = feature
	table.insert(FeatureList, feature)

	return feature
end

local FeatureContext = {}

function FeatureContext:GetPlayer()
	return player
end

function FeatureContext:GetPlayerGui()
	return playerGui
end

function FeatureContext:GetCharacter()
	return getCharacter()
end

function FeatureContext:GetHumanoid()
	return getHumanoid()
end

function FeatureContext:GetRootPart()
	return getRootPart()
end

function FeatureContext:GetWorkspace()
	return Workspace
end

function FeatureContext:WaitForCharacterParts(timeoutSeconds)
	return waitForCharacterParts(timeoutSeconds)
end

--==================================================
-- FEATURE: PLAYER MOVEMENT
--==================================================

do
	local flyControl = {F = 0, B = 0, L = 0, R = 0, U = 0, D = 0}

	local function resetFlyControl()
		flyControl.F = 0
		flyControl.B = 0
		flyControl.L = 0
		flyControl.R = 0
		flyControl.U = 0
		flyControl.D = 0
	end

	local Feature = RegisterFeature({
		Key = "PlayerMovement",
		Tab = "Player",
		Section = "Movement",
		Order = 10,

		Defaults = {
			WalkSpeed = 16,
			JumpPower = 50,
			Noclip = false,
			Fly = false
		},

		State = {
			noclipConnection = nil,
			flyConnection = nil,
			globalBag = nil,
			trackedCharacter = nil,
			cachedParts = {},
			originalCollision = {},
		},

		Options = {
			{Id = "WalkSpeed", Type = "number", Label = "Walk Speed", Description = "Adjust movement speed", Min = 0, Max = 500},
			{Id = "JumpPower", Type = "number", Label = "Jump Power", Description = "Adjust jump strength", Min = 0, Max = 500},
			{Id = "Noclip", Type = "toggle", Label = "Noclip", Description = "Walk through parts"},
			{Id = "Fly", Type = "toggle", Label = "Fly", Description = "WASD + Space + Ctrl"}
		}
	})

	function Feature:CacheCharacterParts(character)
		self.State.trackedCharacter = character
		self.State.cachedParts = {}

		if not character then
			return
		end

		for _, obj in ipairs(character:GetDescendants()) do
			if obj:IsA("BasePart") then
				table.insert(self.State.cachedParts, obj)
			end
		end
	end

	function Feature:GetTrackedParts()
		local character = player.Character

		if character ~= self.State.trackedCharacter then
			self:CacheCharacterParts(character)
		end

		return self.State.cachedParts
	end

	function Feature:Init(context)
		self.Context = context
		self.State.globalBag = NewCleanupBag()

		self:CacheCharacterParts(player.Character)

		AddCleanupItem(self.State.globalBag, player.CharacterAdded:Connect(function(character)
			self:CacheCharacterParts(character)
			resetFlyControl()
		end))

		AddCleanupItem(self.State.globalBag, UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end

			if input.KeyCode == Enum.KeyCode.W then flyControl.F = 1 end
			if input.KeyCode == Enum.KeyCode.S then flyControl.B = 1 end
			if input.KeyCode == Enum.KeyCode.A then flyControl.L = 1 end
			if input.KeyCode == Enum.KeyCode.D then flyControl.R = 1 end
			if input.KeyCode == Enum.KeyCode.Space then flyControl.U = 1 end
			if input.KeyCode == Enum.KeyCode.LeftControl then flyControl.D = 1 end
		end))

		AddCleanupItem(self.State.globalBag, UserInputService.InputEnded:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.W then flyControl.F = 0 end
			if input.KeyCode == Enum.KeyCode.S then flyControl.B = 0 end
			if input.KeyCode == Enum.KeyCode.A then flyControl.L = 0 end
			if input.KeyCode == Enum.KeyCode.D then flyControl.R = 0 end
			if input.KeyCode == Enum.KeyCode.Space then flyControl.U = 0 end
			if input.KeyCode == Enum.KeyCode.LeftControl then flyControl.D = 0 end
		end))
	end

	function Feature:ApplyDefaults(values)
		local humanoid = self.Context:GetHumanoid()
		if humanoid then
			if values.WalkSpeed ~= nil then
				values.WalkSpeed = roundTo2(humanoid.WalkSpeed)
			end
			if values.JumpPower ~= nil then
				values.JumpPower = roundTo2(humanoid.JumpPower)
			end
		end
	end

	function Feature:StopNoclip()
		if self.State.noclipConnection then
			self.State.noclipConnection:Disconnect()
			self.State.noclipConnection = nil
		end

		for part, originalCanCollide in pairs(self.State.originalCollision) do
			if part and part.Parent then
				part.CanCollide = originalCanCollide
			end
		end

		self.State.originalCollision = {}
	end

	function Feature:StartNoclip(panelRef)
		self:StopNoclip()

		self.State.noclipConnection = RunService.Stepped:Connect(function()
			if not panelRef or not panelRef:GetValue("Noclip") then
				return
			end

			for _, obj in ipairs(self:GetTrackedParts()) do
				if obj and obj.Parent then
					if self.State.originalCollision[obj] == nil then
						self.State.originalCollision[obj] = obj.CanCollide
					end
					obj.CanCollide = false
				end
			end
		end)
	end

	function Feature:StopFly()
		if self.State.flyConnection then
			self.State.flyConnection:Disconnect()
			self.State.flyConnection = nil
		end

		resetFlyControl()

		local character = player.Character
		if not character then
			return
		end

		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")

		if humanoid then
			humanoid.PlatformStand = false
		end

		if root then
			local attachment = root:FindFirstChild("AdminFlyAttachment")
			local linearVelocity = root:FindFirstChild("AdminFlyLinearVelocity")
			local alignOrientation = root:FindFirstChild("AdminFlyAlignOrientation")

			if linearVelocity then linearVelocity:Destroy() end
			if alignOrientation then alignOrientation:Destroy() end
			if attachment then attachment:Destroy() end
		end
	end

	function Feature:StartFly(panelRef)
		self:StopFly()

		local character = self.Context:GetCharacter()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")

		if not humanoid or not root then
			return
		end

		humanoid.PlatformStand = true

		local attachment = Instance.new("Attachment")
		attachment.Name = "AdminFlyAttachment"
		attachment.Parent = root

		local linearVelocity = Instance.new("LinearVelocity")
		linearVelocity.Name = "AdminFlyLinearVelocity"
		linearVelocity.Attachment0 = attachment
		linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		linearVelocity.MaxForce = 100000
		linearVelocity.VectorVelocity = Vector3.zero
		linearVelocity.Parent = root

		local alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = "AdminFlyAlignOrientation"
		alignOrientation.Attachment0 = attachment
		alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		alignOrientation.RigidityEnabled = true
		alignOrientation.Responsiveness = 200
		alignOrientation.CFrame = Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame or CFrame.new()
		alignOrientation.Parent = root

		self.State.flyConnection = RunService.RenderStepped:Connect(function()
			if not panelRef or not panelRef:GetValue("Fly") then
				self:StopFly()
				return
			end

			local camera = Workspace.CurrentCamera
			if not camera or not root or not root.Parent then
				return
			end

			local moveDir =
				(camera.CFrame.LookVector * (flyControl.F - flyControl.B)) +
				(camera.CFrame.RightVector * (flyControl.R - flyControl.L)) +
				(Vector3.new(0, 1, 0) * (flyControl.U - flyControl.D))

			if moveDir.Magnitude > 0 then
				moveDir = moveDir.Unit * 60
			end

			linearVelocity.VectorVelocity = moveDir
			alignOrientation.CFrame = camera.CFrame
		end)
	end

	function Feature:GetHandlers()
		return {
			WalkSpeed = function(value)
				local humanoid = self.Context:GetHumanoid()
				if humanoid and typeof(value) == "number" then
					humanoid.WalkSpeed = value
				end
			end,

			JumpPower = function(value)
				local humanoid = self.Context:GetHumanoid()
				if humanoid and typeof(value) == "number" then
					humanoid.UseJumpPower = true
					humanoid.JumpPower = value
				end
			end,

			Noclip = function(value, values, panelRef)
				if value then
					self:StartNoclip(panelRef)
				else
					self:StopNoclip()
				end
			end,

			Fly = function(value, values, panelRef)
				if value then
					self:StartFly(panelRef)
				else
					self:StopFly()
				end
			end
		}
	end

	function Feature:Cleanup()
		self:StopFly()
		self:StopNoclip()
		resetFlyControl()

		if self.State.globalBag then
			CleanupBag(self.State.globalBag)
			self.State.globalBag = nil
		end

		self.State.cachedParts = {}
		self.State.trackedCharacter = nil
	end
end

--==================================================
-- FEATURE: PLAYER UTILITY
--==================================================

do
	local Feature = RegisterFeature({
		Key = "PlayerUtility",
		Tab = "Player",
		Section = "Utility",
		Order = 20,

		Defaults = {},

		State = {},

		Options = {
			{Id = "ResetCharacter", Type = "button", Label = "Reset Character", Description = "Respawn your character", ButtonText = "Reset"}
		}
	})

	function Feature:Init(context)
		self.Context = context
	end

	function Feature:GetHandlers()
		return {
			ResetCharacter = function()
				local character = player.Character
				if not character then
					return
				end

				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					humanoid:ChangeState(Enum.HumanoidStateType.Dead)
				end
			end
		}
	end

	function Feature:Cleanup()
	end
end

--==================================================
-- FEATURE: SETTINGS GENERAL
--==================================================

do
	local Feature = RegisterFeature({
		Key = "SettingsGeneral",
		Tab = "Settings",
		Section = "General",
		Order = 100,

		Defaults = {
			UIAccent = "Blue"
		},

		State = {},

		Options = {
			{
				Id = "UIAccent",
				Type = "select",
				Label = "Accent Preset",
				Description = "Visual placeholder for template settings",
				Items = {"Blue", "Green", "Purple"}
			}
		}
	})

	function Feature:Init(context)
		self.Context = context
	end

	function Feature:GetHandlers()
		return {
			UIAccent = function(value)
			end
		}
	end

	function Feature:Cleanup()
	end
end

--==================================================
-- BASE CONFIG
--==================================================

local BASE_CONFIG = {
	GuiName = "AdminPanel",
	Title = "Admin Panel",
	Subtitle = "Universal local template",
	PageSubtitle = "Live settings update instantly",
	WindowSize = UDim2.new(0, 760, 0, 460),
	WindowPosition = UDim2.new(0.5, -380, 0.5, -230),

	Tabs = {
		{Name = "Player"},
		{Name = "Settings", Message = "Add profiles, presets, and utility tools here."}
	}
}

--==================================================
-- CONFIG COMPILER
--==================================================

local function CompilePanelConfig(baseConfig)
	local config = {
		GuiName = baseConfig.GuiName,
		Title = baseConfig.Title,
		Subtitle = baseConfig.Subtitle,
		PageSubtitle = baseConfig.PageSubtitle,
		WindowSize = baseConfig.WindowSize,
		WindowPosition = baseConfig.WindowPosition,
		Values = {},
		Tabs = {},
		Handlers = {},
		Features = {}
	}

	local tabsByName = {}
	local seenOptionIds = {}

	for _, tab in ipairs(baseConfig.Tabs or {}) do
		local newTab = {
			Name = tab.Name,
			Message = tab.Message,
			Options = {}
		}
		tabsByName[tab.Name] = newTab
		table.insert(config.Tabs, newTab)
	end

	table.sort(FeatureList, function(a, b)
		return (a.Order or 999) < (b.Order or 999)
	end)

	local insertedSectionsByTab = {}

	for _, feature in ipairs(FeatureList) do
		table.insert(config.Features, feature)

		if feature.Init then
			feature:Init(FeatureContext)
		end

		for key, value in pairs(feature.Defaults or {}) do
			assert(seenOptionIds[key] == nil, "Duplicate option/default Id detected: " .. tostring(key))
			seenOptionIds[key] = true
			config.Values[key] = deepCopySimple(value)
		end
	end

	for _, feature in ipairs(FeatureList) do
		if feature.ApplyDefaults then
			pcall(function()
				feature:ApplyDefaults(config.Values)
			end)
		end
	end

	for _, feature in ipairs(FeatureList) do
		local tab = tabsByName[feature.Tab]
		if tab then
			insertedSectionsByTab[feature.Tab] = insertedSectionsByTab[feature.Tab] or {}

			if feature.Section and feature.Section ~= "" and not insertedSectionsByTab[feature.Tab][feature.Section] then
				table.insert(tab.Options, {
					Type = "section",
					Label = feature.Section
				})
				insertedSectionsByTab[feature.Tab][feature.Section] = true
			end

			for _, option in ipairs(feature.Options or {}) do
				assert(type(option.Id) == "string" and option.Id ~= "", "Option missing valid Id in feature: " .. feature.Key)
				assert(VALID_OPTION_TYPES[option.Type], "Invalid option type '" .. tostring(option.Type) .. "' in feature: " .. feature.Key)
				assert(config.Values[option.Id] ~= nil or option.Type == "button", "Missing default for option Id: " .. option.Id)

				table.insert(tab.Options, option)
			end
		end

		local handlers = feature.GetHandlers and feature:GetHandlers() or {}
		for key, fn in pairs(handlers) do
			assert(type(fn) == "function", "Handler for '" .. tostring(key) .. "' must be a function")
			config.Handlers[key] = fn
		end
	end

	return config
end

--==================================================
-- PANEL FRAMEWORK - FIXED SetValue
--==================================================
local Panel = {}
Panel.__index = Panel

function Panel.new(config)
    local self = setmetatable({}, Panel)
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
        Features = config.Features or {}
    }

    for key, value in pairs(config.Values or {}) do
        self.Config.Values[key] = deepCopySimple(value)
    end

    for _, tab in ipairs(config.Tabs or {}) do
        local newTab = {Name = tab.Name, Message = tab.Message, Options = {}}
        for _, opt in ipairs(tab.Options or {}) do table.insert(newTab.Options, opt) end
        table.insert(self.Config.Tabs, newTab)
    end

    self.State = {
        CurrentTab = nil, TabButtons = {}, Pages = {}, Controls = {},
        Dragging = false, DragStart = nil, StartPos = nil,
        OpenDropdown = nil, OpenDropdownAnchor = nil, IsMinimized = false
    }
    self.Runtime = NewCleanupBag()
    return self
end

function Panel:GetValue(optionId)
    return self.Config.Values[optionId]
end

function Panel:RegisterControl(optionId, controlData)
    self.State.Controls[optionId] = controlData
end

function Panel:RefreshControl(optionId)
    local control = self.State.Controls[optionId]
    if not control or not control.Update then return end
    control.Update(self:GetValue(optionId))
end

function Panel:RefreshAllControls()
    for id in pairs(self.State.Controls) do self:RefreshControl(id) end
end

function Panel:SetValue(optionId, value, skipHandler)
	self.Config.Values[optionId] = value
	self:RefreshControl(optionId)

	if not skipHandler then
		local handler = self.Config.Handlers[optionId]
		if handler then
			handler(value, self.Config.Values, self)
		end
	end

	task.defer(function()
		SaveSettings(self.Config.Values)
	end)
end

function Panel:ApplyAll()
	for optionId, value in pairs(self.Config.Values) do
		local handler = self.Config.Handlers[optionId]
		if handler then
			handler(value, self.Config.Values, self)
		end
	end
	self:RefreshAllControls()
end

function Panel:CloseDropdown()
	if self.State.OpenDropdown and self.State.OpenDropdown.Parent then
		self.State.OpenDropdown:Destroy()
	end
	self.State.OpenDropdown = nil
	self.State.OpenDropdownAnchor = nil
end

function Panel:Minimize()
	self:CloseDropdown()
	self.State.IsMinimized = true

	if self.MainFrame then
		self.MainFrame.Visible = false
	end
	if self.OpenButton then
		self.OpenButton.Visible = true
	end
end

function Panel:Restore()
	self.State.IsMinimized = false

	if self.MainFrame then
		self.MainFrame.Visible = true
	end
	if self.OpenButton then
		self.OpenButton.Visible = false
	end
end

function Panel:Destroy()
	self:CloseDropdown()

	for _, feature in ipairs(self.Config.Features) do
		if feature.Cleanup then
			pcall(function()
				feature:Cleanup()
			end)
		end
	end

	CleanupBag(self.Runtime)

	if self.ScreenGui then
		self.ScreenGui:Destroy()
		self.ScreenGui = nil
	end
end

function Panel:CreateGui()
	local oldGui = playerGui:FindFirstChild(self.Config.GuiName or "AdminPanel")
	if oldGui then
		oldGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = self.Config.GuiName or "AdminPanel"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 999
	screenGui.Parent = playerGui
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
	openIcon.Text = "≡"
	openIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
	openIcon.TextSize = 20
	openIcon.Font = Enum.Font.GothamBold
	openIcon.ZIndex = 56
	openIcon.Parent = openButton

	openButton.MouseButton1Click:Connect(function()
		self:Restore()
	end)

	local openDragging = false
	local openDragStart
	local openStartPos

	AddCleanupItem(self.Runtime, openButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			openDragging = true
			openDragStart = input.Position
			openStartPos = openButton.Position
		end
	end))

	AddCleanupItem(self.Runtime, openButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			openDragging = false
		end
	end))

	AddCleanupItem(self.Runtime, UserInputService.InputChanged:Connect(function(input)
		if openDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - openDragStart
			openButton.Position = UDim2.new(
				openStartPos.X.Scale,
				openStartPos.X.Offset + delta.X,
				openStartPos.Y.Scale,
				openStartPos.Y.Offset + delta.Y
			)
		end
	end))

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
	createStroke(minimizeBtn, Theme.Stroke, 1, 0.35)

	minimizeBtn.MouseButton1Click:Connect(function()
		self:Minimize()
	end)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -42, 0, 14)
	closeBtn.BackgroundColor3 = Theme.Card
	closeBtn.Text = "×"
	closeBtn.TextColor3 = Theme.Text
	closeBtn.TextSize = 18
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = header
	createCorner(closeBtn, 8)
	createStroke(closeBtn, Theme.Stroke, 1, 0.35)

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
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 62)
	row.BackgroundColor3 = Theme.Card
	row.BorderSizePixel = 0
	row.ClipsDescendants = true
	row.ZIndex = 2
	row.Parent = parent
	createCorner(row, 10)
	createStroke(row, Theme.Stroke, 1, 0.4)

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
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(0, 110, 0, 34)
	holder.Position = UDim2.new(1, -124, 0.5, -17)
	holder.BackgroundColor3 = Theme.Input
	holder.BorderSizePixel = 0
	holder.ZIndex = 3
	holder.Parent = row
	createCorner(holder, 8)
	createStroke(holder, Theme.Stroke, 1, 0.45)

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

	box.FocusLost:Connect(function()
		local value = clampNumber(box.Text, option.Min, option.Max)
		if value ~= nil then
			self:SetValue(option.Id, value)
		else
			self:RefreshControl(option.Id)
		end
	end)

	self:RegisterControl(option.Id, {
		Instance = box,
		Update = function(value)
			box.Text = formatNumber(value)
		end
	})
end

function Panel:CreateToggle(row, option)
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

	local function updateVisual(state)
		if state then
			button.BackgroundColor3 = Color3.fromRGB(28, 42, 34)
			fill.Position = UDim2.new(1, -22, 0.5, -9)
			fill.BackgroundColor3 = Theme.Green
			stateLabel.Text = "Enabled"
			stateLabel.TextColor3 = Theme.Green
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
		Instance = button,
		Update = function(value)
			updateVisual(not not value)
		end
	})
end

function Panel:CreateButton(row, option)
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

	button.MouseButton1Click:Connect(function()
		local handler = self.Config.Handlers[option.Id]
		if handler then
			handler(self:GetValue(option.Id), self.Config.Values, self)
		end
	end)

	self:RegisterControl(option.Id, {
		Instance = button,
		Update = function()
		end
	})
end

function Panel:CreateDropdownBase(button, itemCount)
	local dropdown = Instance.new("Frame")
	dropdown.Name = "Dropdown"
	dropdown.BackgroundColor3 = Theme.Dropdown
	dropdown.BorderSizePixel = 0
	dropdown.ZIndex = 60
	dropdown.Parent = self.Overlay
	createCorner(dropdown, 8)
	createStroke(dropdown, Theme.Stroke, 1, 0.2)

	local buttonPos = button.AbsolutePosition
	local buttonSize = button.AbsoluteSize
	local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)

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
		scroll.CanvasSize = UDim2.new(0, 0, 0, itemCount * 30)
		scroll.ZIndex = 61
		scroll.Parent = dropdown

		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Size = UDim2.new(1, -4, 0, itemCount * 30)
		holder.Parent = scroll

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.Parent = holder

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

	return dropdown, parentForItems
end

function Panel:CreateSelect(row, option)
	local items = option.Items or {}

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
	createStroke(button, Theme.Stroke, 1, 0.45)

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(1, -26, 1, 0)
	valueLabel.Position = UDim2.new(0, 10, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = tostring(self:GetValue(option.Id) or "")
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
	arrow.Text = "▼"
	arrow.TextColor3 = Theme.SubText
	arrow.TextSize = 11
	arrow.Font = Enum.Font.GothamBold
	arrow.ZIndex = 4
	arrow.Parent = button

	local function openDropdown()
		self:CloseDropdown()

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

	self:RegisterControl(option.Id, {
		Button = button,
		Label = valueLabel,
		Update = function(value)
			valueLabel.Text = tostring(value or "")
		end
	})
end

function Panel:CreateMultiSelect(row, option)
	local items = option.Items or {}
	local emptyText = option.EmptyText or "Nothing selected"

	if type(self.Config.Values[option.Id]) ~= "table" then
		self.Config.Values[option.Id] = {}
	end

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
	createStroke(button, Theme.Stroke, 1, 0.45)

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(1, -26, 1, 0)
	valueLabel.Position = UDim2.new(0, 10, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = formatMultiSelectLabel(self:GetValue(option.Id), emptyText)
	valueLabel.TextColor3 = (#self:GetValue(option.Id) == 0) and Theme.SubText or Theme.Text
	valueLabel.TextSize = 13
	valueLabel.Font = Enum.Font.Gotham
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	valueLabel.ZIndex = 4
	valueLabel.Parent = button

	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.new(0, 16, 1, 0)
	arrow.Position = UDim2.new(1, -20, 0, 0)
	arrow.BackgroundTransparency = 1
	arrow.Text = "▼"
	arrow.TextColor3 = Theme.SubText
	arrow.TextSize = 11
	arrow.Font = Enum.Font.GothamBold
	arrow.ZIndex = 4
	arrow.Parent = button

	local function openDropdown()
		self:CloseDropdown()

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
							check.Text = "✓"
							check.TextColor3 = Theme.Green
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

	self:RegisterControl(option.Id, {
		Button = button,
		Label = valueLabel,
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
	createStroke(btn, Theme.Stroke, 1, 0.45)

	btn.MouseButton1Click:Connect(function()
		self:CloseDropdown()
		self:SwitchTab(tab.Name)
	end)

	self.State.TabButtons[tab.Name] = btn
end

function Panel:SwitchTab(tabName)
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
			createStroke(card, Theme.Stroke, 1, 0.4)

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
	AddCleanupItem(self.Runtime, self.Header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.State.Dragging = true
			self.State.DragStart = input.Position
			self.State.StartPos = self.MainFrame.Position
		end
	end))

	AddCleanupItem(self.Runtime, self.Header.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.State.Dragging = false
		end
	end))

	AddCleanupItem(self.Runtime, UserInputService.InputChanged:Connect(function(input)
		if self.State.Dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - self.State.DragStart
			self.MainFrame.Position = UDim2.new(
				self.State.StartPos.X.Scale,
				self.State.StartPos.X.Offset + delta.X,
				self.State.StartPos.Y.Scale,
				self.State.StartPos.Y.Offset + delta.Y
			)
			self:CloseDropdown()
		end
	end))
end

function Panel:SetupRespawnApply()
	AddCleanupItem(self.Runtime, player.CharacterAdded:Connect(function()
		task.wait(0.8)
		self:ApplyAll()
	end))
end

function Panel:SetupOutsideClick()
	AddCleanupItem(self.Runtime, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 and self.State.OpenDropdown then
			local mousePos = input.Position
			local clickedDropdown = isPointInsideGuiObject(self.State.OpenDropdown, mousePos)
			local clickedAnchor = isPointInsideGuiObject(self.State.OpenDropdownAnchor, mousePos)

			if not clickedDropdown and not clickedAnchor then
				task.defer(function()
					local focused = UserInputService:GetFocusedTextBox()
					if not focused then
						self:CloseDropdown()
					end
				end)
			end
		end
	end))
end

function Panel:Init()
	self:CreateGui()
	self:BuildTabs()
	self:SetupDragging()
	self:SetupRespawnApply()
	self:SetupOutsideClick()
	self:ApplyAll()
end

--==================================================
-- STARTUP
--==================================================

if not isAllowedGame() then
	warn("[AdminPanel] This game is not allowed.")
	return
end

waitForCharacterParts(8)

local PANEL_CONFIG = CompilePanelConfig(BASE_CONFIG)
PANEL_CONFIG.Values = LoadSettings(PANEL_CONFIG.Values)

local panel = Panel.new(PANEL_CONFIG)
panel:Init()

