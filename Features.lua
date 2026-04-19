local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

local Features = {}

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

Features.Theme = Theme

--==================================================
-- ACCESS CONTROL
--==================================================

local ACCESS_LINKS = {
	"https://www.roblox.com/es/games/76285745979410/Anime-Card-Collection",
	"https://www.roblox.com/es/games/90462358603255/Anime-Eternal",
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

function Features.IsAllowedGame()
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

local function roundTo2(num)
	return math.floor(num * 100 + 0.5) / 100
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

local function waitForCharacterParts(timeoutSeconds)
	timeoutSeconds = timeoutSeconds or 8
	local deadline = os.clock() + timeoutSeconds

	local character = player.Character
	if not character then
		local remaining = deadline - os.clock()
		if remaining <= 0 then
			return nil, nil
		end

		local connection
		local receivedCharacter
		connection = player.CharacterAdded:Connect(function(newCharacter)
			receivedCharacter = newCharacter
		end)

		while not receivedCharacter and os.clock() < deadline do
			task.wait()
		end

		if connection then
			connection:Disconnect()
		end

		character = receivedCharacter
		if not character then
			return nil, nil
		end
	end

	local remaining = deadline - os.clock()
	if remaining <= 0 then
		return character, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return character, humanoid
	end

	humanoid = character:WaitForChild("Humanoid", remaining)
	return character, humanoid
end

local function getCharacter(timeoutSeconds)
	local character = player.Character
	if character then
		return character
	end

	local waitedCharacter = waitForCharacterParts(timeoutSeconds or 8)
	return waitedCharacter
end

local function getHumanoid(timeoutSeconds)
	local _, humanoid = waitForCharacterParts(timeoutSeconds or 8)
	return humanoid
end

local function getRootPart(timeoutSeconds)
	local character = getCharacter(timeoutSeconds or 8)
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
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

--==================================================
-- SETTINGS SAVE / LOAD
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
	local mergedValues = copySimpleValue(defaultValues or {})

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

Features.SaveSettings = SaveSettings
Features.LoadSettings = LoadSettings

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

local function BuildFeatureDefaults()
	local values = {}

	for _, feature in ipairs(FeatureList) do
		for key, value in pairs(feature.Defaults or {}) do
			values[key] = copySimpleValue(value)
		end
	end

	return values
end

local FeatureContext = {}

function FeatureContext:GetPlayer()
	return player
end

function FeatureContext:GetCharacter(timeoutSeconds)
	return getCharacter(timeoutSeconds)
end

function FeatureContext:GetHumanoid(timeoutSeconds)
	return getHumanoid(timeoutSeconds)
end

function FeatureContext:GetRootPart(timeoutSeconds)
	return getRootPart(timeoutSeconds)
end

function FeatureContext:WaitForCharacterParts(timeoutSeconds)
	return waitForCharacterParts(timeoutSeconds)
end

--==================================================
-- FEATURE: PLAYER MOVEMENT
--==================================================

do
	local BASE_WALKSPEED_ATTRIBUTE = "AdminPanel_BaseWalkSpeed"
	local BASE_JUMPPOWER_ATTRIBUTE = "AdminPanel_BaseJumpPower"

	local flyPressed = {
		W = false,
		A = false,
		S = false,
		D = false,
		Space = false,
		Ctrl = false,
	}

	local function resetFlyPressed()
		flyPressed.W = false
		flyPressed.A = false
		flyPressed.S = false
		flyPressed.D = false
		flyPressed.Space = false
		flyPressed.Ctrl = false
	end

	local function getFlyInputVector()
		local x = 0
		local y = 0
		local z = 0

		if flyPressed.A then x -= 1 end
		if flyPressed.D then x += 1 end
		if flyPressed.Space then y += 1 end
		if flyPressed.Ctrl then y -= 1 end
		if flyPressed.W then z -= 1 end
		if flyPressed.S then z += 1 end

		return Vector3.new(x, y, z)
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
			noclipEnabled = false,
			flyConnection = nil,
			globalBag = nil,
			trackedCharacter = nil,
			trackedParts = {},
			originalCollision = {},
			descendantAddedConnection = nil,
			descendantRemovingConnection = nil,
			panelRef = nil,
			defaultWalkSpeed = nil,
			defaultJumpPower = nil,
		},

		Options = {
			{Id = "WalkSpeed", Type = "number", Label = "Walk Speed", Description = "Adjust movement speed", Min = 0, Max = 500},
			{Id = "JumpPower", Type = "number", Label = "Jump Power", Description = "Adjust jump strength", Min = 0, Max = 500},
			{Id = "Noclip", Type = "toggle", Label = "Noclip", Description = "Walk through parts"},
			{Id = "Fly", Type = "toggle", Label = "Fly", Description = "WASD + Space + Ctrl"}
		}
	})

	function Feature:GetPanelValue(optionId)
		if not self.State.panelRef then
			return nil
		end
		return self.State.panelRef:GetValue(optionId)
	end

	function Feature:CaptureCharacterDefaults(character)
		if not character then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		local storedWalkSpeed = humanoid:GetAttribute(BASE_WALKSPEED_ATTRIBUTE)
		local storedJumpPower = humanoid:GetAttribute(BASE_JUMPPOWER_ATTRIBUTE)

		if storedWalkSpeed == nil then
			storedWalkSpeed = roundTo2(humanoid.WalkSpeed)
			humanoid:SetAttribute(BASE_WALKSPEED_ATTRIBUTE, storedWalkSpeed)
		end

		if storedJumpPower == nil then
			storedJumpPower = roundTo2(humanoid.JumpPower)
			humanoid:SetAttribute(BASE_JUMPPOWER_ATTRIBUTE, storedJumpPower)
		end

		self.State.defaultWalkSpeed = storedWalkSpeed
		self.State.defaultJumpPower = storedJumpPower
	end

	function Feature:DisconnectCharacterTracking()
		if self.State.descendantAddedConnection then
			self.State.descendantAddedConnection:Disconnect()
			self.State.descendantAddedConnection = nil
		end

		if self.State.descendantRemovingConnection then
			self.State.descendantRemovingConnection:Disconnect()
			self.State.descendantRemovingConnection = nil
		end
	end

	function Feature:RestoreTrackedCharacterCollision()
		for part, originalCanCollide in pairs(self.State.originalCollision) do
			if part and part.Parent then
				part.CanCollide = originalCanCollide
			end
		end
		table.clear(self.State.originalCollision)
	end

	function Feature:ApplyNoclipToPart(part)
		if not part or not part.Parent then
			return
		end

		if self.State.originalCollision[part] == nil then
			self.State.originalCollision[part] = part.CanCollide
		end

		part.CanCollide = false
	end

	function Feature:RestorePartCollision(part)
		local originalCanCollide = self.State.originalCollision[part]
		if originalCanCollide ~= nil then
			if part and part.Parent then
				part.CanCollide = originalCanCollide
			end
			self.State.originalCollision[part] = nil
		end
	end

	function Feature:TrackPart(part)
		if not part or not part:IsA("BasePart") then
			return
		end

		self.State.trackedParts[part] = true

		if self.State.noclipEnabled and self:GetPanelValue("Noclip") then
			self:ApplyNoclipToPart(part)
		end
	end

	function Feature:UntrackPart(part)
		if not part then
			return
		end

		self.State.trackedParts[part] = nil
		self:RestorePartCollision(part)
	end

	function Feature:CacheCharacterParts(character)
		self:DisconnectCharacterTracking()
		self:RestoreTrackedCharacterCollision()

		self.State.trackedCharacter = character
		self.State.trackedParts = {}

		if not character then
			return
		end

		self:CaptureCharacterDefaults(character)

		for _, obj in ipairs(character:GetDescendants()) do
			if obj:IsA("BasePart") then
				self.State.trackedParts[obj] = true
				if self.State.noclipEnabled and self:GetPanelValue("Noclip") then
					self:ApplyNoclipToPart(obj)
				end
			end
		end

		self.State.descendantAddedConnection = character.DescendantAdded:Connect(function(obj)
			if obj:IsA("BasePart") then
				self:TrackPart(obj)
			end
		end)

		self.State.descendantRemovingConnection = character.DescendantRemoving:Connect(function(obj)
			if obj:IsA("BasePart") then
				self:UntrackPart(obj)
			end
		end)
	end

	function Feature:GetTrackedParts()
		local character = player.Character

		if character ~= self.State.trackedCharacter then
			self:CacheCharacterParts(character)
		end

		return self.State.trackedParts
	end

	function Feature:Init(context)
		self.Context = context
		self.State.globalBag = NewCleanupBag()

		self:CacheCharacterParts(player.Character)

		AddCleanupItem(self.State.globalBag, player.CharacterAdded:Connect(function(character)
			self:CacheCharacterParts(character)
			resetFlyPressed()
		end))

		AddCleanupItem(self.State.globalBag, UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end

			if input.KeyCode == Enum.KeyCode.W then flyPressed.W = true end
			if input.KeyCode == Enum.KeyCode.A then flyPressed.A = true end
			if input.KeyCode == Enum.KeyCode.S then flyPressed.S = true end
			if input.KeyCode == Enum.KeyCode.D then flyPressed.D = true end
			if input.KeyCode == Enum.KeyCode.Space then flyPressed.Space = true end
			if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
				flyPressed.Ctrl = true
			end
		end))

		AddCleanupItem(self.State.globalBag, UserInputService.InputEnded:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.W then flyPressed.W = false end
			if input.KeyCode == Enum.KeyCode.A then flyPressed.A = false end
			if input.KeyCode == Enum.KeyCode.S then flyPressed.S = false end
			if input.KeyCode == Enum.KeyCode.D then flyPressed.D = false end
			if input.KeyCode == Enum.KeyCode.Space then flyPressed.Space = false end
			if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
				flyPressed.Ctrl = false
			end
		end))
	end

	function Feature:ApplyDefaults(values)
		local character = self.Context:GetCharacter(8)
		if character then
			self:CaptureCharacterDefaults(character)
		end

		if values.WalkSpeed ~= nil and self.State.defaultWalkSpeed ~= nil then
			values.WalkSpeed = self.State.defaultWalkSpeed
		end

		if values.JumpPower ~= nil and self.State.defaultJumpPower ~= nil then
			values.JumpPower = self.State.defaultJumpPower
		end
	end

	function Feature:StopNoclip()
		self.State.noclipEnabled = false
		self:RestoreTrackedCharacterCollision()
	end

	function Feature:StartNoclip(panelRef)
		self.State.panelRef = panelRef
		self.State.noclipEnabled = true

		for part in pairs(self:GetTrackedParts()) do
			self:ApplyNoclipToPart(part)
		end
	end

	function Feature:StopFly()
		if self.State.flyConnection then
			self.State.flyConnection:Disconnect()
			self.State.flyConnection = nil
		end

		resetFlyPressed()

		local character = player.Character
		if not character then
			return
		end

		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")

		if humanoid then
			humanoid.PlatformStand = false
			humanoid.AutoRotate = true
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
		self.State.panelRef = panelRef

		local character = self.Context:GetCharacter(8)
		if not character then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")

		if not humanoid or not root then
			return
		end

		humanoid.PlatformStand = true
		humanoid.AutoRotate = false

		local attachment = Instance.new("Attachment")
		attachment.Name = "AdminFlyAttachment"
		attachment.Parent = root

		local linearVelocity = Instance.new("LinearVelocity")
		linearVelocity.Name = "AdminFlyLinearVelocity"
		linearVelocity.Attachment0 = attachment
		linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		linearVelocity.MaxForce = math.huge
		linearVelocity.VectorVelocity = Vector3.zero
		linearVelocity.Parent = root

		local alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = "AdminFlyAlignOrientation"
		alignOrientation.Attachment0 = attachment
		alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		alignOrientation.RigidityEnabled = true
		alignOrientation.Responsiveness = 200
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

			local rawForward = camera.CFrame.LookVector
			local flatForward = Vector3.new(rawForward.X, 0, rawForward.Z)
			if flatForward.Magnitude <= 0.001 then
				flatForward = Vector3.zAxis
			else
				flatForward = flatForward.Unit
			end

			local flatRight = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
			if flatRight.Magnitude <= 0.001 then
				flatRight = Vector3.xAxis
			else
				flatRight = flatRight.Unit
			end

			local inputVector = getFlyInputVector()
			local moveDir =
				(flatRight * inputVector.X) +
				(Vector3.yAxis * inputVector.Y) +
				(flatForward * -inputVector.Z)

			if moveDir.Magnitude > 0 then
				moveDir = moveDir.Unit * 60
			end

			linearVelocity.VectorVelocity = moveDir
			alignOrientation.CFrame = CFrame.lookAt(root.Position, root.Position + flatForward, Vector3.yAxis)
		end)
	end

	function Feature:GetHandlers()
		return {
			WalkSpeed = function(value)
				local humanoid = self.Context:GetHumanoid(8)
				if humanoid and typeof(value) == "number" then
					humanoid.WalkSpeed = value
				end
			end,

			JumpPower = function(value)
				local humanoid = self.Context:GetHumanoid(8)
				if humanoid and typeof(value) == "number" then
					humanoid.UseJumpPower = true
					humanoid.JumpPower = value
				end
			end,

			Noclip = function(value, values, panelRef)
				self.State.panelRef = panelRef
				if value then
					self:StartNoclip(panelRef)
				else
					self:StopNoclip()
				end
			end,

			Fly = function(value, values, panelRef)
				self.State.panelRef = panelRef
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
		self:DisconnectCharacterTracking()
		resetFlyPressed()

		if self.State.globalBag then
			CleanupBag(self.State.globalBag)
			self.State.globalBag = nil
		end

		self.State.trackedParts = {}
		self.State.trackedCharacter = nil
		self.State.panelRef = nil
	end
end

--==================================================
-- FEATURE: PLAYER UTILITY
--==================================================

do
	local Feature = RegisterFeature({
		Key = "PlayerUtility",
		Tab = "Player",
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
-- FEATURE: SETTINGS APPEARANCE
--==================================================

do
	local Feature = RegisterFeature({
		Key = "SettingsAppearance",
		Tab = "Settings",
		Section = "Appearance",
		Order = 110,
		Defaults = {
			UIAccent = "Blue"
		},
		State = {},
		Options = {
			{
				Id = "UIAccent",
				Type = "select",
				Label = "Accent Preset",
				Description = "Change the panel accent color",
				Items = {"Blue", "Green", "Purple"}
			}
		}
	})

	function Feature:Init(context)
		self.Context = context
	end

	function Feature:GetHandlers()
		return {
			UIAccent = function(value, values, panelRef)
				if value == "Green" then
					Theme.Accent = Color3.fromRGB(60, 200, 120)
				elseif value == "Purple" then
					Theme.Accent = Color3.fromRGB(170, 110, 255)
				else
					Theme.Accent = Color3.fromRGB(90, 140, 255)
				end

				if panelRef and panelRef.ApplyAccentTheme then
					panelRef:ApplyAccentTheme()
				end
			end
		}
	end

	function Feature:Cleanup()
	end
end

--==================================================
-- FEATURE: ANTI AFK
--==================================================

do
	local Feature = RegisterFeature({
		Key = "AntiAFK",
		Tab = "Settings",
		Section = "Utility",
		Order = 120,
		Defaults = {
			AntiAFK = false
		},
		State = {
			antiAfkConnection = nil,
			virtualUser = nil,
		},
		Options = {
			{
				Id = "AntiAFK",
				Type = "toggle",
				Label = "Anti-AFK",
				Description = "Prevent Roblox from kicking you for being idle"
			}
		}
	})

	function Feature:Init(context)
		self.Context = context
		self.State.virtualUser = game:GetService("VirtualUser")
	end

	function Feature:StartAntiAFK()
		self:StopAntiAFK()

		local localPlayer = Players.LocalPlayer

		if getconnections then
			for _, connection in pairs(getconnections(localPlayer.Idled)) do
				if connection.Disable then
					connection:Disable()
				elseif connection.Disconnect then
					connection:Disconnect()
				end
			end
		end

		self.State.antiAfkConnection = localPlayer.Idled:Connect(function()
			if self.State.virtualUser then
				self.State.virtualUser:CaptureController()
				self.State.virtualUser:ClickButton2(Vector2.new())
			end
		end)
	end

	function Feature:StopAntiAFK()
		if self.State.antiAfkConnection then
			self.State.antiAfkConnection:Disconnect()
			self.State.antiAfkConnection = nil
		end
	end

	function Feature:GetHandlers()
		return {
			AntiAFK = function(enabled)
				if enabled then
					self:StartAntiAFK()
				else
					self:StopAntiAFK()
				end
			end
		}
	end

	function Feature:Cleanup()
		self:StopAntiAFK()
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
		Order = 500,
		Defaults = {
			Minimized = false
		},
		State = {},
		Options = {
			{
				Id = "ResetDefaults",
				Type = "button",
				Label = "Reset Defaults",
				Description = "Restore saved settings to defaults",
				ButtonText = "Reset"
			}
		}
	})

	function Feature:Init(context)
		self.Context = context
	end

	function Feature:GetHandlers()
		return {
			Minimized = function()
			end,

			ResetDefaults = function(_, values, panelRef)
				local resetValues = BuildFeatureDefaults()

				for _, feature in ipairs(FeatureList) do
					if feature.ApplyDefaults then
						pcall(function()
							feature:ApplyDefaults(resetValues)
						end)
					end
				end

				for optionId, value in pairs(resetValues) do
					panelRef:SetValue(optionId, copySimpleValue(value), true)
				end

				panelRef:ApplyAll()
				panelRef:Restore(true)
				SaveSettings(panelRef.Config.Values)
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
		{Name = "Settings"}
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
		Features = {},
		Theme = Theme,
		SaveSettings = SaveSettings
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
			config.Values[key] = copySimpleValue(value)
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

function Features.BuildPanelConfig()
	local panelConfig = CompilePanelConfig(BASE_CONFIG)
	panelConfig.Values = LoadSettings(panelConfig.Values)

	for _, feature in ipairs(FeatureList) do
		if feature.ApplyDefaults then
			pcall(function()
				feature:ApplyDefaults(panelConfig.Values)
			end)
		end
	end

	return panelConfig
end

return Features
