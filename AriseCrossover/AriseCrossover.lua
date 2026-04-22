return {
	Load = function(Shared)
		local RegisterFeature, RegisterTabs = Shared.RegisterFeature, Shared.RegisterTabs
		local Players = game:GetService("Players")
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Workspace = game:GetService("Workspace")
		local player = Players.LocalPlayer
		local NO_ENEMY_OPTION = "Select enemy"
		local NO_DUNGEON_OPTION = "Select dungeon"

		--==================================================
		-- TABS
		--==================================================
		RegisterTabs({{Name = "Combat", Order = 20}, {Name = "Dungeon", Order = 30}})

		--==================================================
		-- HELPERS
		--==================================================
		local function getSettings()
			return player:WaitForChild("Settings", 10)
		end

		local function getPasses()
			local leaderstats = player:WaitForChild("leaderstats", 10)
			return leaderstats and leaderstats:WaitForChild("Passes", 10) or nil
		end

		local function setPass(passName, enabled)
			local passes = getPasses()
			if passes then passes:SetAttribute(passName, enabled == true) end
		end

		local function setAutoAttack(enabled)
			local settings = getSettings()
			if settings then settings:SetAttribute("AutoAttack", enabled == true) end

			setPass("AutoAttack", enabled)
		end

		local function setAutoClick(enabled)
			local settings = getSettings()
			if settings then settings:SetAttribute("AutoClick", enabled == true) end

			setPass("AutoClicker", enabled)
		end

		local function getShadowExchangeButton()
			local playerGui = player:FindFirstChild("PlayerGui")
			local hud = playerGui and playerGui:FindFirstChild("Hud")
			local leftContainer = hud and hud:FindFirstChild("LeftContainer")
			return leftContainer and leftContainer:FindFirstChild("ShadowExchange") or nil
		end

		local function setShadowExchange(enabled)
			setPass("ShadowExchange", enabled)

			local button = getShadowExchangeButton()
			if button then button.Visible = enabled == true end
		end

		local bridgeCache = {}

		local function getBridge(bridgeName)
			if bridgeCache[bridgeName] ~= nil then return bridgeCache[bridgeName] end

			local bridgeModule = ReplicatedStorage:FindFirstChild("BridgeNet2")
			if not bridgeModule then return nil end

			local ok, bridgeNet = pcall(require, bridgeModule)
			if not ok or type(bridgeNet) ~= "table" or type(bridgeNet.ReferenceBridge) ~= "function" then
				return nil
			end

			local bridgeOk, bridge = pcall(function()
				return bridgeNet.ReferenceBridge(bridgeName)
			end)

			if bridgeOk then
				bridgeCache[bridgeName] = bridge
				return bridge
			end

			return nil
		end

		local function fireGeneralEvent(payload)
			local bridge = getBridge("GENERAL_EVENT")
			if not bridge or type(payload) ~= "table" then return false end

			local ok = pcall(function()
				bridge:Fire(payload)
			end)

			return ok
		end

		local function getEnemyRoot(enemy)
			if not enemy then return nil end
			return enemy.PrimaryPart or enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChildWhichIsA("BasePart", true)
		end

		local function getEnemyClientFolder()
			local main = Workspace:FindFirstChild("__Main")
			local enemies = main and main:FindFirstChild("__Enemies")
			return enemies and enemies:FindFirstChild("Client") or nil
		end

		local function getEnemyServerFolder()
			local main = Workspace:FindFirstChild("__Main")
			local enemies = main and main:FindFirstChild("__Enemies")
			return enemies and enemies:FindFirstChild("Server") or nil
		end

		local function getCharacterRoot()
			local character = player.Character
			return character and character:FindFirstChild("HumanoidRootPart") or nil
		end

		local function readValueObject(valueObject)
			if not valueObject then return nil end

			if valueObject:IsA("TextLabel") or valueObject:IsA("TextButton") or valueObject:IsA("TextBox") then
				return valueObject.Text
			end

			if valueObject:IsA("StringValue") or valueObject:IsA("NumberValue") or valueObject:IsA("IntValue") then
				return valueObject.Value
			end

			return valueObject:GetAttribute("Text") or valueObject:GetAttribute("Value")
		end

		local function getEnemyHealthBarMain(enemy)
			local healthBar = enemy and enemy:FindFirstChild("HealthBar")
			return healthBar and healthBar:FindFirstChild("Main") or nil
		end

		local function getEnemyDisplayName(enemy)
			local main = getEnemyHealthBarMain(enemy)
			local title = main and main:FindFirstChild("Title")
			local titleText = readValueObject(title)

			if titleText and tostring(titleText) ~= "" then
				return tostring(titleText)
			end

			local attributeName = enemy and enemy:GetAttribute("Name")
			if attributeName and tostring(attributeName) ~= "" then
				return tostring(attributeName)
			end

			return enemy and enemy.Name or nil
		end

		local function parseHealthNumber(value)
			if value == nil then return nil end

			local text = tostring(value):gsub(",", "")
			local numberText = text:match("%-?%d+%.?%d*")
			return numberText and tonumber(numberText) or nil
		end

		local function getEnemyClientHealth(enemy)
			local main = getEnemyHealthBarMain(enemy)
			local amount = main and main:FindFirstChild("Amount")
			return parseHealthNumber(readValueObject(amount))
		end

		local function getServerEnemy(enemy)
			local serverFolder = getEnemyServerFolder()
			return enemy and serverFolder and serverFolder:FindFirstChild(enemy.Name) or nil
		end

		local function isEnemyAlive(enemy)
			if not enemy or not enemy.Parent then return false end
			if enemy:GetAttribute("Dead") == true then return false end

			local serverEnemy = getServerEnemy(enemy)
			if serverEnemy then
				if serverEnemy:GetAttribute("Dead") == true then return false end

				local serverHealth = parseHealthNumber(serverEnemy:GetAttribute("Health") or serverEnemy:GetAttribute("HP"))
				if serverHealth ~= nil and serverHealth <= 0 then return false end
			end

			local clientHealth = getEnemyClientHealth(enemy)
			return clientHealth == nil or clientHealth > 0
		end

		local knownEnemyNameCache = nil

		local function getKnownEnemyNames()
			if knownEnemyNameCache then return knownEnemyNameCache end

			local names = {}
			local indexer = ReplicatedStorage:FindFirstChild("Indexer")
			local infoModule = nil

			if indexer then
				for _, moduleName in ipairs({"EnemiesInfo", "EnemyInfo", "Enemies", "MobsInfo"}) do
					local candidate = indexer:FindFirstChild(moduleName)
					if candidate and candidate:IsA("ModuleScript") then
						infoModule = candidate
						break
					end
				end
			end

			if not infoModule then
				return names
			end

			local ok, enemyInfo = pcall(require, infoModule)
			if not ok or type(enemyInfo) ~= "table" then
				return names
			end

			local seen = {}
			for _, info in pairs(enemyInfo) do
				if type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" and not seen[info.Name] then
					seen[info.Name] = true
					names[#names + 1] = info.Name
				end
			end

			table.sort(names)
			knownEnemyNameCache = names
			return names
		end

		local function getAutoFarmEnemyItems()
			local items = {NO_ENEMY_OPTION}
			local seen = {[NO_ENEMY_OPTION] = true}
			local enemyFolder = getEnemyClientFolder()

			if enemyFolder then
				for _, enemy in ipairs(enemyFolder:GetChildren()) do
					local enemyName = getEnemyDisplayName(enemy)
					if enemyName and enemyName ~= "" and not seen[enemyName] then
						seen[enemyName] = true
						items[#items + 1] = enemyName
					end
				end
			end

			if #items == 1 then
				for _, enemyName in ipairs(getKnownEnemyNames()) do
					if not seen[enemyName] then
						seen[enemyName] = true
						items[#items + 1] = enemyName
					end
				end
			else
				table.sort(items, function(a, b)
					if a == b then return false end
					if a == NO_ENEMY_OPTION then return true end
					if b == NO_ENEMY_OPTION then return false end
					return a < b
				end)
			end

			return items
		end

		local function teleportToEnemy(enemy, distance)
			local character = player.Character
			local enemyRoot = getEnemyRoot(enemy)
			if not character or not enemyRoot then return end

			character:PivotTo(enemyRoot.CFrame * CFrame.new(0, 0, distance or 7))
		end

		local dungeonMapsCache = nil
		local dungeonLabelToKey = {}

		local function getDungeonMaps()
			if dungeonMapsCache then return dungeonMapsCache end

			local indexer = ReplicatedStorage:FindFirstChild("Indexer")
			local dungeonMapsModule = indexer and indexer:FindFirstChild("DungeonMaps")
			if not dungeonMapsModule or not dungeonMapsModule:IsA("ModuleScript") then
				return {}
			end

			local ok, dungeonMaps = pcall(require, dungeonMapsModule)
			if ok and type(dungeonMaps) == "table" then
				dungeonMapsCache = dungeonMaps
				return dungeonMapsCache
			end

			return {}
		end

		local function getDungeonDisplayName(dungeonKey, dungeonInfo)
			local name = type(dungeonInfo) == "table" and dungeonInfo.Name or nil
			if type(name) == "string" and name ~= "" then
				return name
			end

			return tostring(dungeonKey)
		end

		local function getDungeonItems()
			local items = {NO_DUNGEON_OPTION}
			local sortable = {}
			dungeonLabelToKey = {}

			for dungeonKey, dungeonInfo in pairs(getDungeonMaps()) do
				local label = getDungeonDisplayName(dungeonKey, dungeonInfo)
				local uniqueLabel = label
				local index = 2

				while dungeonLabelToKey[uniqueLabel] ~= nil do
					uniqueLabel = label .. " (" .. tostring(index) .. ")"
					index = index + 1
				end

				dungeonLabelToKey[uniqueLabel] = tostring(dungeonKey)
				sortable[#sortable + 1] = {
					Label = uniqueLabel,
					Order = type(dungeonInfo) == "table" and tonumber(dungeonInfo.Order) or nil,
				}
			end

			table.sort(sortable, function(a, b)
				if a.Order ~= nil and b.Order ~= nil and a.Order ~= b.Order then
					return a.Order < b.Order
				end

				if a.Order ~= nil and b.Order == nil then return true end
				if a.Order == nil and b.Order ~= nil then return false end
				return a.Label < b.Label
			end)

			for _, item in ipairs(sortable) do
				items[#items + 1] = item.Label
			end

			return items
		end

		local function getSelectedDungeonKey(selectedDungeon)
			if selectedDungeon == nil or selectedDungeon == "" or selectedDungeon == NO_DUNGEON_OPTION then
				return nil
			end

			local mappedKey = dungeonLabelToKey[selectedDungeon]
			if mappedKey then return mappedKey end

			getDungeonItems()
			return dungeonLabelToKey[selectedDungeon] or selectedDungeon
		end

		local function getOwnDungeonInfo()
			local infos = ReplicatedStorage:FindFirstChild("__Infos")
			local dungeons = infos and infos:FindFirstChild("__Dungeons")
			local dungeon = dungeons and dungeons:FindFirstChild(tostring(player.UserId))
			return dungeon
		end

		local function waitForOwnDungeonInfo(timeout)
			local startedAt = os.clock()

			repeat
				local dungeon = getOwnDungeonInfo()
				if dungeon then return dungeon end
				task.wait(0.25)
			until os.clock() - startedAt >= (timeout or 5)

			return nil
		end

		local function sendDungeonAction(action, extraPayload)
			local payload = {
				Event = "DungeonAction",
				Action = action,
			}

			for key, value in pairs(extraPayload or {}) do
				payload[key] = value
			end

			return fireGeneralEvent(payload)
		end

		--==================================================
		-- FEATURE: AUTO CLICK
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "AutoClick",
				Tab = "Combat",
				Section = "Click",
				Order = 10,

				Defaults = {
					AutoClick = false,
				},

				State = {
					Running = false,
					PollDelay = 0.5,
					CapturedOriginal = false,
					OriginalAutoClick = nil,
					OriginalAutoClicker = nil,
				},

				Options = {
					{ Id = "AutoClick", Type = "toggle", Label = "Auto Click", Description = "Auto clicks attacks" },
				}
			})

			function Feature:CaptureOriginalValues()
				if self.State.CapturedOriginal then return end

				local settings = getSettings()
				local passes = getPasses()
				self.State.OriginalAutoClick = settings and settings:GetAttribute("AutoClick") or nil
				self.State.OriginalAutoClicker = passes and passes:GetAttribute("AutoClicker") or nil
				self.State.CapturedOriginal = true
			end

			function Feature:RestoreOriginalValues()
				if not self.State.CapturedOriginal then return end

				local settings = getSettings()
				if settings then settings:SetAttribute("AutoClick", self.State.OriginalAutoClick) end

				local passes = getPasses()
				if passes then passes:SetAttribute("AutoClicker", self.State.OriginalAutoClicker) end

				self.State.CapturedOriginal = false
				self.State.OriginalAutoClick = nil
				self.State.OriginalAutoClicker = nil
			end

			function Feature:Start()
				if self.State.Running then return end
				self:CaptureOriginalValues()
				self.State.Running = true

				task.spawn(function()
					while self.State.Running do
						setAutoClick(true)
						task.wait(self.State.PollDelay)
					end
				end)
			end

			function Feature:Stop()
				self.State.Running = false
				self:RestoreOriginalValues()
			end

			function Feature:GetHandlers()
				return {
					AutoClick = function(value)
						if value then self:Start() else self:Stop() end
					end,
				}
			end

			function Feature:Cleanup()
				self:Stop()
			end
		end

		--==================================================
		-- FEATURE: AUTO ATTACK
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "AutoAttack",
				Tab = "Combat",
				Section = "Attack",
				Order = 20,

				Defaults = {
					AutoAttack = false,
				},

				Options = {
					{ Id = "AutoAttack", Type = "toggle", Label = "Auto Attack", Description = "Auto attacks enemies" },
				}
			})

			function Feature:GetHandlers()
				return {
					AutoAttack = function(value)
						setAutoAttack(value)
					end,
				}
			end
		end

		--==================================================
		-- FEATURE: AUTO FARM
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "AutoFarm",
				Tab = "Combat",
				Section = "Farm",
				Order = 25,

				Defaults = {
					AutoFarmEnemy = NO_ENEMY_OPTION,
					AutoFarm = false,
				},

				State = {
					Running = false,
					LoopId = 0,
					PollDelay = 0.25,
					TeleportDistance = 7,
					CurrentTarget = nil,
				},

				Options = {
					{ Id = "AutoFarmEnemy", Type = "select", Label = "Enemy", Description = "Select enemy to farm", Items = getAutoFarmEnemyItems },
					{ Id = "AutoFarm", Type = "toggle", Label = "Auto Farm", Description = "Teleports to each selected enemy once" },
				}
			})

			function Feature:FindTarget(enemyName)
				local enemyFolder = getEnemyClientFolder()
				if not enemyFolder then return nil end

				local characterRoot = getCharacterRoot()
				local closestEnemy = nil
				local closestDistance = nil

				for _, enemy in ipairs(enemyFolder:GetChildren()) do
					if getEnemyDisplayName(enemy) == enemyName and isEnemyAlive(enemy) then
						local enemyRoot = getEnemyRoot(enemy)
						if enemyRoot then
							local distance = characterRoot and (characterRoot.Position - enemyRoot.Position).Magnitude or 0
							if closestDistance == nil or distance < closestDistance then
								closestEnemy = enemy
								closestDistance = distance
							end
						end
					end
				end

				return closestEnemy
			end

			function Feature:TargetMatches(target, enemyName)
				return target and target.Parent and getEnemyDisplayName(target) == enemyName
			end

			function Feature:SetTarget(target)
				if self.State.CurrentTarget == target then return end

				self.State.CurrentTarget = target
				if target then teleportToEnemy(target, self.State.TeleportDistance) end
			end

			function Feature:Tick(values)
				local enemyName = values and values.AutoFarmEnemy
				if enemyName == nil or enemyName == "" or enemyName == NO_ENEMY_OPTION then return end

				local target = self.State.CurrentTarget
				if not self:TargetMatches(target, enemyName) or not isEnemyAlive(target) then
					self:SetTarget(self:FindTarget(enemyName))
				end
			end

			function Feature:Start(values)
				self:Stop()

				self.State.Running = true
				self.State.LoopId = self.State.LoopId + 1
				local id = self.State.LoopId

				task.spawn(function()
					while self.State.Running and self.State.LoopId == id do
						self:Tick(values)
						task.wait(self.State.PollDelay)
					end
				end)
			end

			function Feature:Stop()
				self.State.Running = false
				self.State.LoopId = self.State.LoopId + 1
				self.State.CurrentTarget = nil
			end

			function Feature:GetHandlers()
				return {
					AutoFarm = function(value, values)
						if value then self:Start(values) else self:Stop() end
					end,
					AutoFarmEnemy = function(_, values)
						self.State.CurrentTarget = nil
						if values and values.AutoFarm then self:Start(values) end
					end,
				}
			end

			function Feature:Cleanup()
				self:Stop()
			end
		end

		--==================================================
		-- FEATURE: DUNGEON STARTER
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "DungeonStarter",
				Tab = "Dungeon",
				Section = "Dungeon",
				Order = 10,

				Defaults = {
					SelectedDungeon = NO_DUNGEON_OPTION,
				},

				State = {
					Starting = false,
					CreateDelay = 0.5,
					InstanceWait = 6,
				},

				Options = {
					{ Id = "SelectedDungeon", Type = "select", Label = "Dungeon", Description = "Detected dungeons from DungeonMaps", Items = getDungeonItems },
					{ Id = "StartDungeon", Type = "button", Label = "Start Dungeon", Description = "Creates and starts selected dungeon", ButtonText = "Start" },
				}
			})

			function Feature:CreateDungeon(dungeonKey)
				return sendDungeonAction("Create", {
					Dungeon = dungeonKey,
					DungeonMap = dungeonKey,
					Map = dungeonKey,
				})
			end

			function Feature:StartDungeon(dungeonKey)
				return sendDungeonAction("Start", {
					Dungeon = player.UserId,
					DungeonMap = dungeonKey,
					Map = dungeonKey,
				})
			end

			function Feature:Run(values)
				if self.State.Starting then return end

				local dungeonKey = getSelectedDungeonKey(values and values.SelectedDungeon)
				if not dungeonKey then return end

				self.State.Starting = true

				task.spawn(function()
					if not getOwnDungeonInfo() then
						self:CreateDungeon(dungeonKey)
						task.wait(self.State.CreateDelay)
					end

					if getOwnDungeonInfo() or waitForOwnDungeonInfo(self.State.InstanceWait) then
						self:StartDungeon(dungeonKey)
					end

					self.State.Starting = false
				end)
			end

			function Feature:GetHandlers()
				return {
					SelectedDungeon = function()
						getDungeonItems()
					end,
					StartDungeon = function(_, values)
						self:Run(values)
					end,
				}
			end

			function Feature:Cleanup()
				self.State.Starting = false
			end
		end

		--==================================================
		-- FEATURE: SHADOW EXCHANGE
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "ShadowExchange",
				Tab = "Combat",
				Section = "Exchange",
				Order = 30,

				Defaults = {
					ShadowExchange = false,
				},

				State = {
					Running = false,
					LoopId = 0,
					PollDelay = 0.5,
					CapturedOriginal = false,
					OriginalPass = nil,
					OriginalButtonVisible = nil,
				},

				Options = {
					{ Id = "ShadowExchange", Type = "toggle", Label = "Shadow Exchange", Description = "Enables Shadow Exchange" },
				}
			})

			function Feature:CaptureOriginalValues()
				if self.State.CapturedOriginal then return end

				local passes = getPasses()
				local button = getShadowExchangeButton()
				self.State.OriginalPass = passes and passes:GetAttribute("ShadowExchange") or nil
				self.State.OriginalButtonVisible = button and button.Visible or nil
				self.State.CapturedOriginal = true
			end

			function Feature:RestoreOriginalValues()
				if not self.State.CapturedOriginal then return end

				local passes = getPasses()
				if passes then passes:SetAttribute("ShadowExchange", self.State.OriginalPass == true) end

				local button = getShadowExchangeButton()
				if button then
					if self.State.OriginalButtonVisible ~= nil then
						button.Visible = self.State.OriginalButtonVisible
					else
						button.Visible = self.State.OriginalPass == true
					end
				end

				self.State.CapturedOriginal = false
				self.State.OriginalPass = nil
				self.State.OriginalButtonVisible = nil
			end

			function Feature:Start()
				self:Stop()
				self:CaptureOriginalValues()

				self.State.Running = true
				self.State.LoopId = self.State.LoopId + 1
				local id = self.State.LoopId

				task.spawn(function()
					while self.State.Running and self.State.LoopId == id do
						setShadowExchange(true)
						task.wait(self.State.PollDelay)
					end
				end)
			end

			function Feature:Stop()
				self.State.Running = false
				self.State.LoopId = self.State.LoopId + 1
				self:RestoreOriginalValues()
			end

			function Feature:GetHandlers()
				return {
					ShadowExchange = function(value)
						if value then self:Start() else self:Stop() end
					end,
				}
			end

			function Feature:Cleanup()
				self:Stop()
			end
		end

	end
}
