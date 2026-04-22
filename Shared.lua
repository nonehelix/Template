-- ==================================================
-- SHARED.LUA - Clean & Updated Version
-- ==================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

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

local ACCENT_PRESETS = {
	Blue = Theme.Accent,
	Green = Theme.Green,
	Purple = Color3.fromRGB(170, 110, 255)
}

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

local function arrayContains(arr, target)
	for _, value in ipairs(arr or {}) do
		if tostring(value) == tostring(target) then
			return true
		end
	end

	return false
end

local function extractPlaceIdFromLink(link)
	if type(link) ~= "string" then return nil end
	local id = string.match(link, "/games/(%d+)")
	if id then return tonumber(id) end
	id = string.match(link, "placeId=(%d+)")
	if id then return tonumber(id) end
	return nil
end

local function waitForCharacterParts(timeoutSeconds)
	timeoutSeconds = timeoutSeconds or 8
	local deadline = os.clock() + timeoutSeconds

	local character = player.Character
	if not character then
		local remaining = deadline - os.clock()
		if remaining <= 0 then return nil, nil end

		local connection
		local receivedCharacter
		connection = player.CharacterAdded:Connect(function(newCharacter)
			receivedCharacter = newCharacter
		end)

		while not receivedCharacter and os.clock() < deadline do
			task.wait()
		end

		if connection then connection:Disconnect() end
		character = receivedCharacter
		if not character then return nil, nil end
	end

	local remaining = deadline - os.clock()
	if remaining <= 0 then return character, nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then return character, humanoid end

	humanoid = character:WaitForChild("Humanoid", remaining)
	return character, humanoid
end

local function getCharacter(timeoutSeconds)
	local character = player.Character
	if character then return character end
	return waitForCharacterParts(timeoutSeconds or 8)
end

local function getHumanoid(timeoutSeconds)
	local _, humanoid = waitForCharacterParts(timeoutSeconds or 8)
	return humanoid
end

local function getRootPart(timeoutSeconds)
	local character = getCharacter(timeoutSeconds or 8)
	if not character then return nil end
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
			if item.Connected then item:Disconnect() end
		elseif itemType == "Instance" then
			if item.Parent then item:Destroy() end
		elseif type(item) == "function" then
			pcall(item)
		elseif type(item) == "table" and item.Destroy then
			pcall(function() item:Destroy() end)
		end
	end
	table.clear(bag.Items)
end

--==================================================
-- SETTINGS SAVE / LOAD (Saved inside AdminPanel folder)
--==================================================

local function sanitizeFileName(text)
	text = tostring(text or "UnknownGame")
	text = text:gsub("[^%w%-_]", "_")
	text = text:gsub("_+", "_")
	text = text:gsub("^_+", "")
	text = text:gsub("_+$", "")
	if text == "" then text = "UnknownGame" end
	return text
end

local function getSettingsFileName()
	local gameKey = Features.CurrentGameKey or tostring(game.PlaceId) or "UnknownGame"
	return "AdminPanel/" .. sanitizeFileName(gameKey) .. ".json"
end

local function ensureFolderExists()
	if not isfolder then return end
	if not isfolder("AdminPanel") then
		pcall(makefolder, "AdminPanel")
	end
end

local function HasSavedSettings()
	local file = getSettingsFileName()
	return isfile and isfile(file) or false
end

local function SaveSettings(values)
	if not writefile then return end
	ensureFolderExists()
	local file = getSettingsFileName()
	local ok, err = pcall(function()
		writefile(file, HttpService:JSONEncode(values or {}))
	end)
	if not ok then
		warn("[Shared] Failed to save settings to '" .. tostring(file) .. "': " .. tostring(err))
	end
end

local function LoadSettings(defaultValues)
	local mergedValues = copySimpleValue(defaultValues or {})
	local file = getSettingsFileName()

	if not (isfile and readfile) or not isfile(file) then
		return mergedValues
	end

	local success, loaded = pcall(function()
		local data = readfile(file)
		return HttpService:JSONDecode(data)
	end)

	if not success then
		warn("[Shared] Failed to load settings from '" .. tostring(file) .. "': " .. tostring(loaded))
	end

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
Features.HasSavedSettings = HasSavedSettings
Features.GetSettingsFileName = getSettingsFileName

--==================================================
-- FEATURE REGISTRY + CONTEXT
--==================================================

local FeatureList = {}
local ExtraTabs = {}

local VALID_OPTION_TYPES = {
	number = true, toggle = true, button = true,
	select = true, multiselect = true, section = true,
}

local function findFeatureIndex(featureKey)
	for index, existing in ipairs(FeatureList) do
		if existing.Key == featureKey then
			return index
		end
	end

	return nil
end

local function validateFeatureOptions(feature)
	for index, option in ipairs(feature.Options or {}) do
		assert(type(option) == "table", "Feature option #" .. tostring(index) .. " must be a table")
		assert(VALID_OPTION_TYPES[option.Type], "Invalid option type for feature '" .. feature.Key .. "': " .. tostring(option.Type))

		if option.Type ~= "section" then
			assert(type(option.Id) == "string" and option.Id ~= "", "Feature option Id is required for feature '" .. feature.Key .. "'")
		end
	end
end

local function RegisterFeature(feature)
	assert(type(feature) == "table", "Feature must be a table")
	assert(type(feature.Key) == "string" and feature.Key ~= "", "Feature.Key is required")
	assert(type(feature.Tab) == "string" and feature.Tab ~= "", "Feature.Tab is required")

	feature.Order = feature.Order or 999
	feature.Defaults = feature.Defaults or {}
	feature.Options = feature.Options or {}
	feature.State = feature.State or {}

	validateFeatureOptions(feature)

	local existingIndex = findFeatureIndex(feature.Key)
	if existingIndex then
		FeatureList[existingIndex] = feature
	else
		table.insert(FeatureList, feature)
	end

	return feature
end

local function RegisterTab(tab)
	assert(type(tab) == "table", "Tab must be a table")
	assert(type(tab.Name) == "string" and tab.Name ~= "", "Tab.Name is required")

	for index, existing in ipairs(ExtraTabs) do
		if existing.Name == tab.Name then
			ExtraTabs[index] = {
				Name = tab.Name,
				Message = tab.Message,
				Order = tonumber(tab.Order) or 999
			}
			return ExtraTabs[index]
		end
	end

	local newTab = {
		Name = tab.Name,
		Message = tab.Message,
		Order = tonumber(tab.Order) or 999
	}

	table.insert(ExtraTabs, newTab)
	return newTab
end

local function RegisterTabs(tabs)
	for _, tab in ipairs(tabs) do
		RegisterTab(tab)
	end
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

local function ApplyFeatureDefaults(values)
	for _, feature in ipairs(FeatureList) do
		if feature.ApplyDefaults then
			pcall(function()
				feature:ApplyDefaults(values)
			end)
		end
	end
end

local FeatureContext = {}

function FeatureContext:GetPlayer() return player end
function FeatureContext:GetCharacter(timeoutSeconds) return getCharacter(timeoutSeconds) end
function FeatureContext:GetHumanoid(timeoutSeconds) return getHumanoid(timeoutSeconds) end
function FeatureContext:GetRootPart(timeoutSeconds) return getRootPart(timeoutSeconds) end
function FeatureContext:WaitForCharacterParts(timeoutSeconds) return waitForCharacterParts(timeoutSeconds) end

--==================================================
-- FEATURE: PLAYER MOVEMENT
--==================================================

do
	local BASE_WALKSPEED_ATTRIBUTE = "AdminPanel_BaseWalkSpeed"
	local BASE_JUMPPOWER_ATTRIBUTE = "AdminPanel_BaseJumpPower"

	local flyPressed = { W = false, A = false, S = false, D = false, Space = false, Ctrl = false }

	local function resetFlyPressed()
		for k in pairs(flyPressed) do flyPressed[k] = false end
	end

	local function getFlyInputVector()
		local x, y, z = 0, 0, 0
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
		Order = 10,

		Defaults = {
			WalkSpeed = 16,
			JumpPower = 50,
			Noclip = false,
			Fly = false
		},

		State = {
			noclipEnabled = false,
			noclipConnection = nil,
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
			desiredWalkSpeed = nil,
			walkSpeedConnection = nil,
			walkSpeedHumanoid = nil,
			applyingWalkSpeed = false,
		},

		Options = {
			{Id = "WalkSpeed", Type = "number", Label = "Walk Speed", Description = "Adjust movement speed", Min = 0, Max = 500},
			{Id = "JumpPower", Type = "number", Label = "Jump Power", Description = "Adjust jump strength", Min = 0, Max = 500},
			{Id = "Noclip", Type = "toggle", Label = "Noclip", Description = "Walk through parts"},
			{Id = "Fly", Type = "toggle", Label = "Fly", Description = "WASD + Space + Ctrl"}
		}
	})

	function Feature:GetPanelValue(optionId)
		if not self.State.panelRef then return nil end
		return self.State.panelRef:GetValue(optionId)
	end

	function Feature:CaptureCharacterDefaults(character)
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end

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

	function Feature:DisconnectWalkSpeedLock()
		if self.State.walkSpeedConnection then
			self.State.walkSpeedConnection:Disconnect()
			self.State.walkSpeedConnection = nil
		end
		self.State.walkSpeedHumanoid = nil
		self.State.applyingWalkSpeed = false
	end

	function Feature:ApplyDesiredWalkSpeed(humanoid)
		local desiredWalkSpeed = self.State.desiredWalkSpeed
		if not humanoid or typeof(desiredWalkSpeed) ~= "number" or humanoid.WalkSpeed == desiredWalkSpeed then return end

		self.State.applyingWalkSpeed = true
		humanoid.WalkSpeed = desiredWalkSpeed
		self.State.applyingWalkSpeed = false
	end

	function Feature:TrackWalkSpeed(humanoid)
		if not humanoid then return end

		if self.State.walkSpeedHumanoid ~= humanoid then
			self:DisconnectWalkSpeedLock()
			self.State.walkSpeedHumanoid = humanoid
			self.State.walkSpeedConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
				if self.State.applyingWalkSpeed then return end
				self:ApplyDesiredWalkSpeed(humanoid)
			end)
		end

		self:ApplyDesiredWalkSpeed(humanoid)
	end

	function Feature:ApplyWalkSpeedLock(character)
		if typeof(self.State.desiredWalkSpeed) ~= "number" then return end

		character = character or player.Character
		if not character then return end

		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 8)
		if humanoid then self:TrackWalkSpeed(humanoid) end
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
			if part then
				if part.Parent then
					part.CanCollide = originalCanCollide
				end
				self.State.originalCollision[part] = nil
			end
		end
	end

	function Feature:ApplyNoclipToPart(part)
		if not part or not part:IsA("BasePart") then return end
		if self.State.originalCollision[part] == nil then
			self.State.originalCollision[part] = part.CanCollide
		end
		part.CanCollide = false
	end

	function Feature:RestorePartCollision(part)
		local original = self.State.originalCollision[part]
		if original ~= nil then
			if part and part.Parent then
				part.CanCollide = original
			end
			self.State.originalCollision[part] = nil
		end
	end

	function Feature:TrackPart(part)
		if not part or not part:IsA("BasePart") then return end
		self.State.trackedParts[part] = true
		if self.State.noclipEnabled and self:GetPanelValue("Noclip") then
			self:ApplyNoclipToPart(part)
		end
	end

	function Feature:UntrackPart(part)
		if not part then return end
		self.State.trackedParts[part] = nil
		self:RestorePartCollision(part)
	end

	function Feature:CacheCharacterParts(character)
		self:DisconnectCharacterTracking()
		self:RestoreTrackedCharacterCollision()

		self.State.trackedCharacter = character
		self.State.trackedParts = {}

		if not character then return end

		self:CaptureCharacterDefaults(character)

		for _, obj in ipairs(character:GetDescendants()) do
			if obj:IsA("BasePart") then
				self:TrackPart(obj)
			end
		end

		self.State.descendantAddedConnection = character.DescendantAdded:Connect(function(obj)
			if obj:IsA("BasePart") then self:TrackPart(obj) end
		end)

		self.State.descendantRemovingConnection = character.DescendantRemoving:Connect(function(obj)
			if obj:IsA("BasePart") then self:UntrackPart(obj) end
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

		if not self.State.globalBag then
			self.State.globalBag = NewCleanupBag()
			self:CacheCharacterParts(player.Character)

			AddCleanupItem(self.State.globalBag, player.CharacterAdded:Connect(function(character)
				self:CacheCharacterParts(character)
				resetFlyPressed()
				task.defer(function()
					self:ApplyWalkSpeedLock(character)
				end)
			end))

			AddCleanupItem(self.State.globalBag, UserInputService.InputBegan:Connect(function(input, gameProcessed)
				if gameProcessed then return end
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
		else
			self:CacheCharacterParts(player.Character)
		end
	end

	function Feature:ApplyDefaults(values)
		local character = self.Context:GetCharacter(8)
		if character then self:CaptureCharacterDefaults(character) end

		if values.WalkSpeed ~= nil and self.State.defaultWalkSpeed ~= nil then
			values.WalkSpeed = self.State.defaultWalkSpeed
		end
		if values.JumpPower ~= nil and self.State.defaultJumpPower ~= nil then
			values.JumpPower = self.State.defaultJumpPower
		end
	end

	function Feature:StopNoclip()
		self.State.noclipEnabled = false

		if self.State.noclipConnection then
			self.State.noclipConnection:Disconnect()
			self.State.noclipConnection = nil
		end

		self:RestoreTrackedCharacterCollision()
	end

	function Feature:StartNoclip(panelRef)
		self:StopNoclip()
		self.State.panelRef = panelRef
		self.State.noclipEnabled = true

		for part in pairs(self:GetTrackedParts()) do
			self:ApplyNoclipToPart(part)
		end

		self.State.noclipConnection = RunService.Stepped:Connect(function()
			if not self.State.noclipEnabled then
				return
			end

			for part in pairs(self:GetTrackedParts()) do
				if part and part.Parent and part.CanCollide ~= false then
					self:ApplyNoclipToPart(part)
				end
			end
		end)
	end

	function Feature:StopFly()
		if self.State.flyConnection then
			self.State.flyConnection:Disconnect()
			self.State.flyConnection = nil
		end
		resetFlyPressed()

		local character = player.Character
		if not character then return end

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
		if not character then return end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root then return end

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
			if not camera or not root or not root.Parent then return end

			local rawForward = camera.CFrame.LookVector
			local flatForward = Vector3.new(rawForward.X, 0, rawForward.Z)
			if flatForward.Magnitude <= 0.001 then flatForward = Vector3.zAxis else flatForward = flatForward.Unit end

			local flatRight = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
			if flatRight.Magnitude <= 0.001 then flatRight = Vector3.xAxis else flatRight = flatRight.Unit end

			local inputVector = getFlyInputVector()
			local moveDir = (flatRight * inputVector.X) + (Vector3.yAxis * inputVector.Y) + (flatForward * -inputVector.Z)

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
				if typeof(value) ~= "number" then return end

				local humanoid = self.Context:GetHumanoid(8)
				if not humanoid then return end
				if humanoid.Parent then self:CaptureCharacterDefaults(humanoid.Parent) end

				if self.State.defaultWalkSpeed ~= nil and value == self.State.defaultWalkSpeed then
					self.State.desiredWalkSpeed = nil
					self:DisconnectWalkSpeedLock()
					humanoid.WalkSpeed = value
					return
				end

				self.State.desiredWalkSpeed = value
				self:TrackWalkSpeed(humanoid)
			end,
			JumpPower = function(value)
				local humanoid = self.Context:GetHumanoid(8)
				if humanoid and typeof(value) == "number" then
					humanoid.UseJumpPower = true
					humanoid.JumpPower = value
				end
			end,
			Noclip = function(value, _, panelRef)
				self.State.panelRef = panelRef
				if value then self:StartNoclip(panelRef) else self:StopNoclip() end
			end,
			Fly = function(value, _, panelRef)
				self.State.panelRef = panelRef
				if value then self:StartFly(panelRef) else self:StopFly() end
			end
		}
	end

	function Feature:Cleanup()
		self:StopFly()
		self:StopNoclip()
		self:DisconnectWalkSpeedLock()
		self:DisconnectCharacterTracking()
		resetFlyPressed()

		if self.State.globalBag then
			CleanupBag(self.State.globalBag)
			self.State.globalBag = nil
		end

		self.State.trackedParts = {}
		self.State.trackedCharacter = nil
		self.State.panelRef = nil
		self.State.desiredWalkSpeed = nil
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

	function Feature:GetHandlers()
		return {
			ResetCharacter = function()
				local character = player.Character
				if not character then return end
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					humanoid:ChangeState(Enum.HumanoidStateType.Dead)
				end
			end
		}
	end

end

--==================================================
-- FEATURE: SETTINGS APPEARANCE
--==================================================

do
	local Feature = RegisterFeature({
		Key = "SettingsAppearance",
		Tab = "Settings",
		Order = 110,
		Defaults = { UIAccent = "Blue" },
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

	function Feature:GetHandlers()
		return {
			UIAccent = function(value, _, panelRef)
				Theme.Accent = ACCENT_PRESETS[value] or ACCENT_PRESETS.Blue

				if panelRef and panelRef.RefreshAllControls then
					panelRef:RefreshAllControls()
				end

				if panelRef and panelRef.ApplyAccentTheme then
					panelRef:ApplyAccentTheme()
				end
			end
		}
	end

end

--==================================================
-- FEATURE: ANTI AFK (Strong 2026 Version with Debug)
--==================================================

do
	local Feature = RegisterFeature({
		Key = "AntiAFK",
		Tab = "Settings",
		Order = 120,

		Defaults = {
			AntiAFK = false
		},

		State = {
			antiAfkConnection = nil,
			heartbeatConnection = nil,
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
		self.State.virtualUser = game:GetService("VirtualUser")
	end

	function Feature:StartAntiAFK()
		self:StopAntiAFK()

		local localPlayer = Players.LocalPlayer

		-- Do NOT disable every Idled connection globally unless you really need to.
		-- It can break other scripts and doesn't help anti-idle reliability.
		local function fireAntiIdle(reason)
			local vu = self.State.virtualUser
			local camera = workspace.CurrentCamera

			if not vu then
				warn("[AntiAFK] VirtualUser missing (" .. reason .. ")")
				return
			end

			if not camera then
				warn("[AntiAFK] Camera missing (" .. reason .. ")")
				return
			end

			local ok, err = pcall(function()
				vu:CaptureController()
				vu:ClickButton2(Vector2.new(0, 0))
				-- Optional extra signal:
				vu:Button2Down(Vector2.new(0, 0), camera.CFrame)
				task.wait(0.03)
				vu:Button2Up(Vector2.new(0, 0), camera.CFrame)
			end)

			if not ok then
				warn("[AntiAFK] Input failed (" .. reason .. "): " .. tostring(err))
			end
		end

		self.State.antiAfkConnection = localPlayer.Idled:Connect(function(idleTime)
			fireAntiIdle("Idled")
		end)

		-- Stronger fallback cadence
		self.State.heartbeatConnection = task.spawn(function()
			while self.State.antiAfkConnection do
				task.wait(120) -- every 2 min
				if not self.State.antiAfkConnection then
					break
				end
				fireAntiIdle("Heartbeat")
			end
		end)
	end

	function Feature:StopAntiAFK()
		if self.State.antiAfkConnection then
			self.State.antiAfkConnection:Disconnect()
			self.State.antiAfkConnection = nil
		end

		if self.State.heartbeatConnection then
			task.cancel(self.State.heartbeatConnection)
			self.State.heartbeatConnection = nil
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
	local function getRequestFunction()
		if type(request) == "function" then return request end
		if type(http_request) == "function" then return http_request end
		if type(syn) == "table" and type(syn.request) == "function" then return syn.request end
		if type(http) == "table" and type(http.request) == "function" then return http.request end
		if type(fluxus) == "table" and type(fluxus.request) == "function" then return fluxus.request end
	end

	local function requestServerPage(cursor)
		local requester = getRequestFunction()
		if not requester then return nil, "HTTP request is not available" end

		local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true"):format(game.PlaceId)
		if cursor and cursor ~= "" then
			url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
		end

		local ok, response = pcall(requester, {
			Url = url,
			Method = "GET",
			Headers = {["Accept"] = "application/json"}
		})

		if not ok then return nil, response end

		local body = response and (response.Body or response.body)
		if not body then return nil, "Empty response" end

		local decodedOk, decoded = pcall(function()
			return HttpService:JSONDecode(body)
		end)

		if not decodedOk then return nil, decoded end
		return decoded
	end

	local function findEmptiestServer()
		local bestServer = nil
		local cursor = nil

		for _ = 1, 5 do
			local page, err = requestServerPage(cursor)
			if not page then return nil, err end

			for _, server in ipairs(page.data or {}) do
				local playing = tonumber(server.playing) or 0
				local maxPlayers = tonumber(server.maxPlayers) or math.huge
				if server.id ~= game.JobId and playing < maxPlayers then
					if not bestServer or playing < bestServer.playing then
						bestServer = {id = server.id, playing = playing, maxPlayers = maxPlayers}
						if playing <= 1 then return bestServer end
					end
				end
			end

			cursor = page.nextPageCursor
			if not cursor or cursor == "" then break end
		end

		return bestServer
	end

	local function hopEmptyServer()
		local server, err = findEmptiestServer()
		if server and server.id then
			TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, player)
			return
		end

		warn("[ServerHop] Could not find low-pop server; using normal teleport. Reason: " .. tostring(err or "none found"))
		TeleportService:Teleport(game.PlaceId, player)
	end

	local Feature = RegisterFeature({
		Key = "SettingsGeneral",
		Tab = "Settings",
		Order = 500,
		Defaults = { Minimized = false },
		State = {},
		Options = {
			{
				Id = "HopEmptyServer",
				Type = "button",
				Label = "Hop Empty Server",
				Description = "Join a low population server",
				ButtonText = "Hop"
			},
			{
				Id = "ResetDefaults",
				Type = "button",
				Label = "Reset Defaults",
				Description = "Restore saved settings to defaults",
				ButtonText = "Reset"
			}
		}
	})

	function Feature:GetHandlers()
		return {
			HopEmptyServer = function()
				task.spawn(hopEmptyServer)
			end,
			ResetDefaults = function(_, values, panelRef)
				local resetValues = BuildFeatureDefaults()
				ApplyFeatureDefaults(resetValues)

				for optionId, value in pairs(resetValues) do
					panelRef:SetValue(optionId, copySimpleValue(value), true)
				end

				panelRef:ApplyAll()
				panelRef:Restore(true)
				if Features.SaveSettings then
					Features.SaveSettings(panelRef.Config.Values)
				end
			end
		}
	end

end

--==================================================
-- CONFIG SANITIZING
--==================================================

local function resolveOptionItems(option)
	local items = option and option.Items

	if type(items) == "function" then
		local ok, resolved = pcall(items)
		if ok and type(resolved) == "table" then
			return resolved
		end

		warn("[Shared] Failed to resolve items for option '" .. tostring(option and option.Id) .. "': " .. tostring(resolved))
		return nil
	end

	if type(items) == "table" then
		return items
	end

	return nil
end

local function sanitizeLoadedNumber(value, option)
	local numericValue = tonumber(value)
	if numericValue == nil then
		return nil
	end

	if option.Min ~= nil and numericValue < option.Min then
		numericValue = option.Min
	end
	if option.Max ~= nil and numericValue > option.Max then
		numericValue = option.Max
	end

	return roundTo2(numericValue)
end

local function sanitizeLoadedToggle(value)
	if type(value) == "boolean" then
		return value
	end
	if type(value) == "number" then
		return value ~= 0
	end
	if type(value) == "string" then
		local lowered = string.lower(value)
		if lowered == "true" then
			return true
		end
		if lowered == "false" then
			return false
		end
	end

	return nil
end

local function sanitizeLoadedSelect(value, option)
	if value == nil then
		return nil
	end

	local stringValue = tostring(value)
	local items = resolveOptionItems(option)
	if not items or type(option.Items) == "function" then
		return stringValue
	end

	for _, item in ipairs(items) do
		if tostring(item) == stringValue then
			return item
		end
	end

	return nil
end

local function sanitizeLoadedMultiSelect(value, option)
	if type(value) ~= "table" then
		return nil
	end

	local items = resolveOptionItems(option)
	local allowedItemsByKey = nil
	if items and type(option.Items) ~= "function" then
		allowedItemsByKey = {}
		for _, item in ipairs(items) do
			allowedItemsByKey[tostring(item)] = item
		end
	end

	local result = {}
	local seen = {}

	for _, entry in ipairs(value) do
		local key = tostring(entry)
		if not seen[key] then
			if allowedItemsByKey then
				local allowedItem = allowedItemsByKey[key]
				if allowedItem ~= nil then
					result[#result + 1] = allowedItem
					seen[key] = true
				end
			else
				result[#result + 1] = key
				seen[key] = true
			end
		end
	end

	return result
end

local function BuildOptionDefinitions(panelConfig)
	local definitions = {}

	for _, tab in ipairs(panelConfig.Tabs or {}) do
		for _, option in ipairs(tab.Options or {}) do
			if type(option) == "table" and type(option.Id) == "string" and option.Id ~= "" then
				definitions[option.Id] = option
			end
		end
	end

	return definitions
end

local function SanitizePanelValues(panelConfig, fallbackValues)
	local optionDefinitions = BuildOptionDefinitions(panelConfig)

	for optionId, option in pairs(optionDefinitions) do
		local currentValue = panelConfig.Values[optionId]
		if currentValue ~= nil then
			local sanitizedValue = currentValue

			if option.Type == "number" then
				sanitizedValue = sanitizeLoadedNumber(currentValue, option)
			elseif option.Type == "toggle" then
				sanitizedValue = sanitizeLoadedToggle(currentValue)
			elseif option.Type == "select" then
				sanitizedValue = sanitizeLoadedSelect(currentValue, option)
			elseif option.Type == "multiselect" then
				sanitizedValue = sanitizeLoadedMultiSelect(currentValue, option)
			end

			if sanitizedValue == nil and option.Type ~= "button" and option.Type ~= "section" then
				panelConfig.Values[optionId] = copySimpleValue(fallbackValues and fallbackValues[optionId])
			elseif sanitizedValue ~= nil then
				panelConfig.Values[optionId] = sanitizedValue
			end
		end
	end
end

--==================================================
-- BASE CONFIG + CONFIG COMPILER
--==================================================

local BASE_CONFIG = {
	GuiName = "AdminPanel",
	Title = "Admin Panel",
	Subtitle = "Universal local template",
	PageSubtitle = "Live settings update instantly",
	WindowSize = UDim2.new(0, 760, 0, 460),
	WindowPosition = UDim2.new(0.5, -380, 0.5, -230),
	Tabs = {
		{Name = "Player", Order = 10},
		{Name = "Settings", Order = 900}
	}
}

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
		SaveSettings = SaveSettings,
		Shared = Features
	}

	local tabsByName = {}
	local seenOptionIds = {}
	local allTabs = {}

	for _, tab in ipairs(baseConfig.Tabs or {}) do
		table.insert(allTabs, {
			Name = tab.Name,
			Message = tab.Message,
			Order = tonumber(tab.Order) or 999
		})
	end

	for _, tab in ipairs(ExtraTabs) do
		table.insert(allTabs, {
			Name = tab.Name,
			Message = tab.Message,
			Order = tonumber(tab.Order) or 999
		})
	end

	table.sort(allTabs, function(a, b)
		if a.Order == b.Order then return a.Name < b.Name end
		return a.Order < b.Order
	end)

	for _, tab in ipairs(allTabs) do
		local newTab = { Name = tab.Name, Message = tab.Message, Order = tab.Order, Options = {} }
		tabsByName[tab.Name] = newTab
		table.insert(config.Tabs, newTab)
	end

	table.sort(FeatureList, function(a, b)
		if (a.Order or 999) == (b.Order or 999) then return a.Key < b.Key end
		return (a.Order or 999) < (b.Order or 999)
	end)

	local insertedSectionsByTab = {}

	for _, feature in ipairs(FeatureList) do
		table.insert(config.Features, feature)
		feature.Context = FeatureContext

		if feature.Init then
			feature:Init(FeatureContext)
		end

		for key, value in pairs(feature.Defaults or {}) do
			if seenOptionIds[key] then
				warn("Duplicate option Id detected: " .. key)
			end
			seenOptionIds[key] = true
			config.Values[key] = copySimpleValue(value)
		end
	end

	for _, feature in ipairs(FeatureList) do
		local tab = tabsByName[feature.Tab]
		if not tab then
			warn("Feature '" .. feature.Key .. "' references unregistered tab '" .. feature.Tab .. "'")
			continue
		end

		if feature.Section and not insertedSectionsByTab[feature.Tab] then
			insertedSectionsByTab[feature.Tab] = {}
		end

		if feature.Section and feature.Section ~= "" and not insertedSectionsByTab[feature.Tab][feature.Section] then
			table.insert(tab.Options, { Type = "section", Label = feature.Section })
			insertedSectionsByTab[feature.Tab][feature.Section] = true
		end

		for _, option in ipairs(feature.Options or {}) do
			table.insert(tab.Options, option)
		end

		local handlers = feature.GetHandlers and feature:GetHandlers() or {}
		for key, fn in pairs(handlers) do
			config.Handlers[key] = fn
		end
	end

	return config
end

function Features.BuildPanelConfig()
	local panelConfig = CompilePanelConfig(BASE_CONFIG)
	ApplyFeatureDefaults(panelConfig.Values)
	local defaultValues = copySimpleValue(panelConfig.Values)

	if HasSavedSettings() then
		panelConfig.Values = LoadSettings(panelConfig.Values)
		SanitizePanelValues(panelConfig, defaultValues)
	end

	return panelConfig
end

--==================================================
-- EXPORTS
--==================================================

Features.Players = Players
Features.UserInputService = UserInputService
Features.RunService = RunService
Features.Workspace = Workspace
Features.HttpService = HttpService
Features.player = player

Features.RegisterFeature = RegisterFeature
Features.RegisterTab = RegisterTab
Features.RegisterTabs = RegisterTabs
Features.BuildFeatureDefaults = BuildFeatureDefaults
Features.FeatureList = FeatureList

Features.copySimpleValue = copySimpleValue
Features.roundTo2 = roundTo2
Features.arrayContains = arrayContains
Features.ExtractPlaceIdFromLink = extractPlaceIdFromLink
Features.ResolveOptionItems = resolveOptionItems

return Features
