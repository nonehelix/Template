return {
	Load = function(Shared)
		local Workspace, RegisterFeature, RegisterTabs = Shared.Workspace or game:GetService("Workspace"), Shared.RegisterFeature, Shared.RegisterTabs
		local Players, ReplicatedStorage = game:GetService("Players"), game:GetService("ReplicatedStorage")

		local player = Players.LocalPlayer

		--==================================================
		-- TABS
		--==================================================
		RegisterTabs({{Name = "Combat", Order = 20}, {Name = "Dungeon", Order = 30}})

		--==================================================
		-- GAME REFERENCES
		--==================================================
		local Indexer = ReplicatedStorage:FindFirstChild("Indexer")

		--==================================================
		-- HELPERS
		--==================================================
		local NO_ENEMY_OPTION, NO_DUNGEON_OPTION = "Select enemy", "Select dungeon"
		local AUTO_CLICK_POLL_DELAY, AUTO_FARM_POLL_DELAY, SHADOW_EXCHANGE_POLL_DELAY = 0.5, 0.25, 0.5
		local DUNGEON_CREATE_DELAY, DUNGEON_INSTANCE_WAIT, AVAILABLE_DUNGEON_CACHE_TTL = 0.5, 6, 960

		local function getPanelValues(panelRef) return panelRef and panelRef.Config and panelRef.Config.Values or nil end

		local function setFeaturePanelRef(feature, panelRef)
			feature.State.PanelRef = panelRef
			return getPanelValues(panelRef)
		end

		local function buildToggleHandler(feature, onEnabled)
			return function(value, _, panelRef)
				setFeaturePanelRef(feature, panelRef)
				if value then
					onEnabled(panelRef)
				else
					feature:Stop()
				end
			end
		end

		local function buildPanelRefHandler(feature)
			return function(_, _, panelRef) setFeaturePanelRef(feature, panelRef) end
		end

		local function buildRestartHandler(feature, enabledKey)
			return function(_, values, panelRef)
				setFeaturePanelRef(feature, panelRef)
				if values and values[enabledKey] then
					feature:Start(panelRef)
				end
			end
		end

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

		local bridgeCache = {}

		local function getBridge(bridgeName)
			if bridgeCache[bridgeName] ~= nil then return bridgeCache[bridgeName] end

			local bridgeModule = ReplicatedStorage:FindFirstChild("BridgeNet2")
			if not bridgeModule then return nil end

			local ok, bridgeNet = pcall(require, bridgeModule)
			if not ok or type(bridgeNet) ~= "table" or type(bridgeNet.ReferenceBridge) ~= "function" then return nil end

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

		local function readValueObject(valueObject)
			if not valueObject then return nil end
			if valueObject:IsA("TextLabel") or valueObject:IsA("TextButton") or valueObject:IsA("TextBox") then return valueObject.Text end
			if valueObject:IsA("StringValue") or valueObject:IsA("NumberValue") or valueObject:IsA("IntValue") then return valueObject.Value end
			return valueObject:GetAttribute("Text") or valueObject:GetAttribute("Value")
		end

		local function parseHealthNumber(value)
			if value == nil then return nil end

			local text = tostring(value):gsub(",", "")
			local numberText = text:match("%-?%d+%.?%d*")
			return numberText and tonumber(numberText) or nil
		end

		local function getCharacterRoot()
			local character = player.Character
			return character and character:FindFirstChild("HumanoidRootPart") or nil
		end

		local function getEnemyRoot(enemy)
			if not enemy then return nil end
			return enemy.PrimaryPart or enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChildWhichIsA("BasePart", true)
		end

		local function getEnemyFolders()
			local main = Workspace:FindFirstChild("__Main")
			local enemies = main and main:FindFirstChild("__Enemies")
			return enemies and enemies:FindFirstChild("Client") or nil, enemies and enemies:FindFirstChild("Server") or nil
		end

		local function getEnemyHealthBarMain(enemy)
			local healthBar = enemy and enemy:FindFirstChild("HealthBar")
			return healthBar and healthBar:FindFirstChild("Main") or nil
		end

		local function getEnemyDisplayName(enemy)
			local main = getEnemyHealthBarMain(enemy)
			local title = main and main:FindFirstChild("Title")
			local titleText = readValueObject(title)
			if titleText and tostring(titleText) ~= "" then return tostring(titleText) end

			local attributeName = enemy and enemy:GetAttribute("Name")
			if attributeName and tostring(attributeName) ~= "" then return tostring(attributeName) end

			return enemy and enemy.Name or nil
		end

		local function getEnemyClientHealth(enemy)
			local main = getEnemyHealthBarMain(enemy)
			local amount = main and main:FindFirstChild("Amount")
			return parseHealthNumber(readValueObject(amount))
		end

		local function getServerEnemy(enemy)
			local _, serverFolder = getEnemyFolders()
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
			local infoModule = nil

			if Indexer then
				for _, moduleName in ipairs({"EnemiesInfo", "EnemyInfo", "Enemies", "MobsInfo"}) do
					local candidate = Indexer:FindFirstChild(moduleName)
					if candidate and candidate:IsA("ModuleScript") then
						infoModule = candidate
						break
					end
				end
			end

			if not infoModule then return names end

			local ok, enemyInfo = pcall(require, infoModule)
			if not ok or type(enemyInfo) ~= "table" then return names end

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
			local enemyFolder = getEnemyFolders()

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
		local dungeonKeyAliasesCache = nil
		local dungeonLabelToInfo = {}
		local availableDungeonKeys = {}
		local availableDungeonUpdatedAt = 0

		local function getDungeonMaps()
			if dungeonMapsCache then return dungeonMapsCache end

			local dungeonMapsModule = Indexer and Indexer:FindFirstChild("DungeonMaps")
			if not dungeonMapsModule or not dungeonMapsModule:IsA("ModuleScript") then return {} end

			local ok, dungeonMaps = pcall(require, dungeonMapsModule)
			if ok and type(dungeonMaps) == "table" then
				dungeonMapsCache = dungeonMaps
				return dungeonMapsCache
			end

			return {}
		end

		local function getDungeonDisplayName(dungeonKey, dungeonInfo)
			local name = type(dungeonInfo) == "table" and dungeonInfo.Name or nil
			return type(name) == "string" and name ~= "" and name or tostring(dungeonKey)
		end

		local function getLiveDungeonFolder()
			local main = Workspace:FindFirstChild("__Main")
			return main and main:FindFirstChild("__Dungeon") or nil
		end

		local function makeDungeonLabel(info)
			local baseName = tostring(info.MapName or info.Dungeon or info.Key or "Dungeon")
			local mapName = tostring(info.DungeonMap or "")
			local rank = info.DungeonRank ~= nil and tostring(info.DungeonRank) or nil
			local world = info.World ~= nil and tostring(info.World) or nil
			local parts = {baseName}

			if mapName ~= "" and mapName ~= baseName then
				parts[#parts + 1] = mapName
			end
			if rank and rank ~= "" then
				parts[#parts + 1] = "Rank " .. rank
			end
			if world and world ~= "" then
				parts[#parts + 1] = world
			end

			return table.concat(parts, " - ")
		end

		local function getLiveDungeonInfo(dungeonObject)
			if not dungeonObject then return nil end

			local attrs = dungeonObject:GetAttributes()
			local dungeonName = attrs.Dungeon or attrs.MapName
			local dungeonMap = attrs.DungeonMap or attrs.Map

			if dungeonName == nil and dungeonMap == nil then return nil end

			local info = {
				Key = tostring(attrs.ID or attrs.DoubleID or dungeonObject.Name),
				Dungeon = dungeonName and tostring(dungeonName) or tostring(dungeonMap),
				DungeonMap = dungeonMap and tostring(dungeonMap) or tostring(dungeonName),
				Map = dungeonMap and tostring(dungeonMap) or tostring(dungeonName),
				MapName = attrs.MapName and tostring(attrs.MapName) or nil,
				World = attrs.World and tostring(attrs.World) or nil,
				DungeonRank = attrs.DungeonRank,
				ID = attrs.ID,
				DoubleID = attrs.DoubleID,
				Instance = dungeonObject,
				Source = "Workspace"
			}

			info.Label = makeDungeonLabel(info)
			return info
		end

		local function getLiveDungeonEntries()
			local folder = getLiveDungeonFolder()
			if not folder then return {} end

			local entries = {}
			local seen = {}

			local function addCandidate(dungeonObject)
				if seen[dungeonObject] then return end
				seen[dungeonObject] = true

				local info = getLiveDungeonInfo(dungeonObject)
				if info then
					entries[#entries + 1] = info
				end
			end

			for _, dungeonObject in ipairs(folder:GetChildren()) do
				addCandidate(dungeonObject)
			end

			for _, dungeonObject in ipairs(folder:GetDescendants()) do
				addCandidate(dungeonObject)
			end

			table.sort(entries, function(a, b)
				local rankA = tonumber(a.DungeonRank)
				local rankB = tonumber(b.DungeonRank)
				if rankA ~= nil and rankB ~= nil and rankA ~= rankB then return rankA < rankB end
				return tostring(a.Label) < tostring(b.Label)
			end)

			return entries
		end

		local function addDungeonAlias(aliases, alias, dungeonKey)
			if alias == nil or dungeonKey == nil then return end

			local text = tostring(alias)
			if text == "" then return end

			aliases[text] = tostring(dungeonKey)
			aliases[string.lower(text)] = tostring(dungeonKey)
		end

		local function getDungeonKeyAliases()
			if dungeonKeyAliasesCache then return dungeonKeyAliasesCache end

			local aliases = {}
			for dungeonKey, dungeonInfo in pairs(getDungeonMaps()) do
				addDungeonAlias(aliases, dungeonKey, dungeonKey)
				addDungeonAlias(aliases, getDungeonDisplayName(dungeonKey, dungeonInfo), dungeonKey)

				if type(dungeonInfo) == "table" then
					for _, field in ipairs({"Id", "ID", "Key", "Map", "Dungeon", "DungeonMap"}) do
						addDungeonAlias(aliases, dungeonInfo[field], dungeonKey)
					end
				end
			end

			dungeonKeyAliasesCache = aliases
			return aliases
		end

		local function resolveDungeonKey(value)
			if value == nil then return nil end

			local valueType = type(value)
			if valueType ~= "string" and valueType ~= "number" then return nil end

			local text = tostring(value)
			local aliases = getDungeonKeyAliases()
			return aliases[text] or aliases[string.lower(text)]
		end

		local function addAvailableDungeonKey(keys, seen, dungeonKey)
			dungeonKey = resolveDungeonKey(dungeonKey)
			if not dungeonKey or seen[dungeonKey] then return end

			seen[dungeonKey] = true
			keys[#keys + 1] = dungeonKey
		end

		local function dungeonInfoLooksAvailable(info)
			if type(info) ~= "table" then return info ~= false and info ~= nil end
			if info.Available ~= nil then return info.Available == true end
			if info.Enabled ~= nil then return info.Enabled == true end
			if info.Active ~= nil then return info.Active == true end
			if info.Locked == true or info.Disabled == true or info.Completed == true then return false end
			return true
		end

		local function collectAvailableDungeonKeys(value, keys, seen, depth)
			depth = depth or 0
			if depth > 6 or value == nil then return end

			local directKey = resolveDungeonKey(value)
			if directKey then
				addAvailableDungeonKey(keys, seen, directKey)
				return
			end

			if type(value) ~= "table" then return end

			for _, field in ipairs({"DungeonMap", "Dungeon", "Map", "Key", "Id", "ID", "Name"}) do
				addAvailableDungeonKey(keys, seen, value[field])
			end

			for childKey, childValue in pairs(value) do
				if dungeonInfoLooksAvailable(childValue) then
					addAvailableDungeonKey(keys, seen, childKey)
					collectAvailableDungeonKeys(childValue, keys, seen, depth + 1)
				end
			end
		end

		local function sortDungeonKeys(keys)
			local dungeonMaps = getDungeonMaps()
			table.sort(keys, function(a, b)
				local infoA, infoB = dungeonMaps[a], dungeonMaps[b]
				local orderA = type(infoA) == "table" and tonumber(infoA.Order) or nil
				local orderB = type(infoB) == "table" and tonumber(infoB.Order) or nil

				if orderA ~= nil and orderB ~= nil and orderA ~= orderB then return orderA < orderB end
				if orderA ~= nil and orderB == nil then return true end
				if orderA == nil and orderB ~= nil then return false end
				return getDungeonDisplayName(a, infoA) < getDungeonDisplayName(b, infoB)
			end)
		end

		local function setAvailableDungeonsFromInfo(info)
			local keys, seen = {}, {}
			collectAvailableDungeonKeys(info, keys, seen)
			sortDungeonKeys(keys)

			availableDungeonKeys = keys
			availableDungeonUpdatedAt = os.clock()
			return keys
		end

		local function readInstanceValue(instance)
			if not instance then return nil end
			if instance:IsA("StringValue") or instance:IsA("NumberValue") or instance:IsA("IntValue") then return instance.Value end
			return nil
		end

		local function collectAvailableDungeonsFromInstance(instance, keys, seen, depth)
			depth = depth or 0
			if not instance or depth > 5 then return end

			addAvailableDungeonKey(keys, seen, readInstanceValue(instance))

			for attrName, attrValue in pairs(instance:GetAttributes()) do
				if string.find(string.lower(tostring(attrName)), "dungeon", 1, true) then
					addAvailableDungeonKey(keys, seen, attrName)
				end

				addAvailableDungeonKey(keys, seen, attrValue)
			end

			for _, child in ipairs(instance:GetChildren()) do
				local childName = tostring(child.Name)
				if childName ~= "__Dungeons" and childName ~= "__DungeonItens" then
					addAvailableDungeonKey(keys, seen, childName)
					collectAvailableDungeonsFromInstance(child, keys, seen, depth + 1)
				end
			end
		end

		local function collectAvailableDungeonsFromReplicatedInfo(keys, seen)
			local infos = ReplicatedStorage:FindFirstChild("__Infos")
			if not infos then return end

			for _, childName in ipairs({"__AvailableDungeons", "__CurrentDungeons", "__DungeonRotation", "__DungeonMaps", "AvailableDungeons", "CurrentDungeons", "DungeonRotation"}) do
				local child = infos:FindFirstChild(childName)
				if child then
					collectAvailableDungeonsFromInstance(child, keys, seen)
				end
			end

			for attrName, attrValue in pairs(infos:GetAttributes()) do
				if string.find(string.lower(tostring(attrName)), "dungeon", 1, true) then
					addAvailableDungeonKey(keys, seen, attrName)
					addAvailableDungeonKey(keys, seen, attrValue)
				end
			end
		end

		local function isVisibleGuiObject(guiObject)
			local current = guiObject
			while current do
				if current:IsA("GuiObject") and current.Visible == false then return false end
				if current:IsA("ScreenGui") and current.Enabled == false then return false end
				current = current.Parent
			end

			return true
		end

		local function hasDungeonGuiAncestor(guiObject, playerGui)
			local current = guiObject
			while current and current ~= playerGui do
				if string.find(string.lower(tostring(current.Name)), "dungeon", 1, true) then return true end
				current = current.Parent
			end

			return false
		end

		local function collectAvailableDungeonsFromGui(keys, seen)
			local playerGui = player:FindFirstChild("PlayerGui")
			if not playerGui then return end

			for _, descendant in ipairs(playerGui:GetDescendants()) do
				if (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) and hasDungeonGuiAncestor(descendant, playerGui) and isVisibleGuiObject(descendant) then
					local text = descendant.Text
					addAvailableDungeonKey(keys, seen, text)
				end
			end
		end

		local function getAvailableDungeonKeys()
			local keys, seen = {}, {}
			local cacheIsFresh = availableDungeonUpdatedAt > 0 and os.clock() - availableDungeonUpdatedAt <= AVAILABLE_DUNGEON_CACHE_TTL

			if cacheIsFresh then
				for _, dungeonKey in ipairs(availableDungeonKeys) do
					addAvailableDungeonKey(keys, seen, dungeonKey)
				end
			end

			if #keys == 0 then
				collectAvailableDungeonsFromReplicatedInfo(keys, seen)
				collectAvailableDungeonsFromGui(keys, seen)
				sortDungeonKeys(keys)
			end

			return keys
		end

		local function getAvailableDungeonEntries()
			local liveEntries = getLiveDungeonEntries()
			if #liveEntries > 0 then return liveEntries end

			local entries = {}
			for _, dungeonKey in ipairs(getAvailableDungeonKeys()) do
				local dungeonInfo = getDungeonMaps()[dungeonKey]
				entries[#entries + 1] = {
					Key = tostring(dungeonKey),
					Dungeon = tostring(dungeonKey),
					DungeonMap = tostring(dungeonKey),
					Map = tostring(dungeonKey),
					Label = getDungeonDisplayName(dungeonKey, dungeonInfo),
					Source = "Fallback"
				}
			end

			return entries
		end

		local function getDungeonItems()
			local items = {NO_DUNGEON_OPTION}
			dungeonLabelToInfo = {}

			for _, dungeonInfo in ipairs(getAvailableDungeonEntries()) do
				local label = dungeonInfo.Label or makeDungeonLabel(dungeonInfo)
				local uniqueLabel = label
				local index = 2

				while dungeonLabelToInfo[uniqueLabel] ~= nil do
					uniqueLabel = label .. " (" .. tostring(index) .. ")"
					index = index + 1
				end

				dungeonLabelToInfo[uniqueLabel] = dungeonInfo
				items[#items + 1] = uniqueLabel
			end

			return items
		end

		local function getSelectedDungeonInfo(selectedDungeon)
			if selectedDungeon == nil or selectedDungeon == "" or selectedDungeon == NO_DUNGEON_OPTION then return nil end

			local mappedInfo = dungeonLabelToInfo[selectedDungeon]
			if mappedInfo then return mappedInfo end

			getDungeonItems()
			return dungeonLabelToInfo[selectedDungeon]
		end

		local function getOwnDungeonInfo()
			local infos = ReplicatedStorage:FindFirstChild("__Infos")
			local dungeons = infos and infos:FindFirstChild("__Dungeons")
			return dungeons and dungeons:FindFirstChild(tostring(player.UserId)) or nil
		end

		local function waitForOwnDungeonInfo(timeout)
			local startedAt = os.clock()

			repeat
				local dungeon = getOwnDungeonInfo()
				if dungeon then return dungeon end
				task.wait(0.25)
			until os.clock() - startedAt >= (timeout or DUNGEON_INSTANCE_WAIT)

			return nil
		end

		local function sendDungeonAction(action, extraPayload)
			local payload = {Event = "DungeonAction", Action = action}

			for key, value in pairs(extraPayload or {}) do
				payload[key] = value
			end

			return fireGeneralEvent(payload)
		end

		local function updateAvailableDungeonsFromEvent(payload)
			if type(payload) ~= "table" or payload.Event ~= "OpenDungeon" then return end

			local info = payload.Info or payload.Infos
			if info ~= nil then
				setAvailableDungeonsFromInfo(info)
			end
		end

		--==================================================
		-- FEATURE: AUTO CLICK
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "AutoClick", Tab = "Combat", Section = "Click", Order = 10,
				Defaults = {AutoClick = false},
				State = {Running = false, PanelRef = nil, CapturedOriginal = false, OriginalAutoClick = nil, OriginalAutoClicker = nil},
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

			function Feature:Start(panelRef)
				setFeaturePanelRef(self, panelRef)
				if self.State.Running then return end

				self:CaptureOriginalValues()
				self.State.Running = true

				task.spawn(function()
					while self.State.Running do
						local values = getPanelValues(self.State.PanelRef)
						if not values or values.AutoClick ~= true then break end

						setAutoClick(true)
						task.wait(AUTO_CLICK_POLL_DELAY)
					end

					if self.State.Running then self:Stop() end
				end)
			end

			function Feature:Stop()
				self.State.Running = false
				self:RestoreOriginalValues()
			end

			function Feature:GetHandlers()
				return {AutoClick = buildToggleHandler(self, function(panelRef) self:Start(panelRef) end)}
			end

			function Feature:Cleanup()
				self:Stop()
				self.State.PanelRef = nil
			end
		end

		--==================================================
		-- FEATURE: AUTO ATTACK
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "AutoAttack", Tab = "Combat", Section = "Attack", Order = 20,
				Defaults = {AutoAttack = false},
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
				Key = "AutoFarm", Tab = "Combat", Section = "Farm", Order = 25,
				Defaults = {AutoFarmEnemy = NO_ENEMY_OPTION, AutoFarm = false},
				State = {Running = false, LoopId = 0, PanelRef = nil, PollDelay = AUTO_FARM_POLL_DELAY, TeleportDistance = 7, CurrentTarget = nil},
				Options = {
					{ Id = "AutoFarmEnemy", Type = "select", Label = "Enemy", Description = "Select enemy to farm", Items = getAutoFarmEnemyItems },
					{ Id = "AutoFarm", Type = "toggle", Label = "Auto Farm", Description = "Teleports to each selected enemy once" },
				}
			})

			function Feature:FindTarget(enemyName)
				local enemyFolder = getEnemyFolders()
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

			function Feature:Start(panelRef)
				setFeaturePanelRef(self, panelRef)
				self:Stop()
				setFeaturePanelRef(self, panelRef)

				self.State.Running = true
				self.State.LoopId = self.State.LoopId + 1
				local loopId = self.State.LoopId

				task.spawn(function()
					while self.State.Running and self.State.LoopId == loopId do
						local values = getPanelValues(self.State.PanelRef)
						if not values or values.AutoFarm ~= true then break end

						self:Tick(values)
						task.wait(self.State.PollDelay)
					end

					if self.State.Running and self.State.LoopId == loopId then self:Stop() end
				end)
			end

			function Feature:Stop()
				self.State.Running = false
				self.State.LoopId = self.State.LoopId + 1
				self.State.CurrentTarget = nil
			end

			function Feature:GetHandlers()
				return {
					AutoFarm = buildToggleHandler(self, function(panelRef) self:Start(panelRef) end),
					AutoFarmEnemy = buildRestartHandler(self, "AutoFarm"),
				}
			end

			function Feature:Cleanup()
				self:Stop()
				self.State.PanelRef = nil
			end
		end

		--==================================================
		-- FEATURE: DUNGEON STARTER
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "DungeonStarter", Tab = "Dungeon", Section = "Dungeon", Order = 10,
				Defaults = {SelectedDungeon = NO_DUNGEON_OPTION},
				State = {Starting = false, PanelRef = nil, DungeonEventConnection = nil},
				Options = {
					{ Id = "SelectedDungeon", Type = "select", Label = "Dungeon", Description = "Currently available dungeons", Items = getDungeonItems },
					{ Id = "StartDungeon", Type = "button", Label = "Start Dungeon", Description = "Creates and starts selected dungeon", ButtonText = "Start" },
				}
			})

			function Feature:Init()
				if self.State.DungeonEventConnection then return end

				local bridge = getBridge("DUNGEON_EVENT")
				if not bridge or type(bridge.Connect) ~= "function" then return end

				local ok, connection = pcall(function()
					return bridge:Connect(updateAvailableDungeonsFromEvent)
				end)

				if ok then
					self.State.DungeonEventConnection = connection
				end
			end

			function Feature:CreateDungeon(dungeonInfo)
				local dungeon = type(dungeonInfo) == "table" and (dungeonInfo.Dungeon or dungeonInfo.Key) or dungeonInfo
				local dungeonMap = type(dungeonInfo) == "table" and (dungeonInfo.DungeonMap or dungeonInfo.Map or dungeonInfo.Key) or dungeonInfo
				local map = type(dungeonInfo) == "table" and (dungeonInfo.Map or dungeonInfo.DungeonMap or dungeonInfo.Key) or dungeonInfo

				return sendDungeonAction("Create", {
					Dungeon = dungeon,
					DungeonMap = dungeonMap,
					Map = map,
					ID = type(dungeonInfo) == "table" and dungeonInfo.ID or nil,
					DungeonID = type(dungeonInfo) == "table" and dungeonInfo.ID or nil,
					DungeonName = type(dungeonInfo) == "table" and dungeonInfo.Dungeon or nil,
					MapName = type(dungeonInfo) == "table" and dungeonInfo.MapName or nil,
					DoubleID = type(dungeonInfo) == "table" and dungeonInfo.DoubleID or nil,
					World = type(dungeonInfo) == "table" and dungeonInfo.World or nil,
					DungeonRank = type(dungeonInfo) == "table" and dungeonInfo.DungeonRank or nil,
				})
			end

			function Feature:StartDungeon(dungeonInfo)
				local dungeonMap = type(dungeonInfo) == "table" and (dungeonInfo.DungeonMap or dungeonInfo.Map or dungeonInfo.Key) or dungeonInfo
				local map = type(dungeonInfo) == "table" and (dungeonInfo.Map or dungeonInfo.DungeonMap or dungeonInfo.Key) or dungeonInfo

				return sendDungeonAction("Start", {
					Dungeon = player.UserId,
					DungeonMap = dungeonMap,
					Map = map,
					ID = type(dungeonInfo) == "table" and dungeonInfo.ID or nil,
					DungeonID = type(dungeonInfo) == "table" and dungeonInfo.ID or nil,
					DungeonName = type(dungeonInfo) == "table" and dungeonInfo.Dungeon or nil,
					MapName = type(dungeonInfo) == "table" and dungeonInfo.MapName or nil,
					DoubleID = type(dungeonInfo) == "table" and dungeonInfo.DoubleID or nil,
					World = type(dungeonInfo) == "table" and dungeonInfo.World or nil,
					DungeonRank = type(dungeonInfo) == "table" and dungeonInfo.DungeonRank or nil,
				})
			end

			function Feature:Run(panelRef)
				local values = setFeaturePanelRef(self, panelRef)
				if self.State.Starting then return end

				local dungeonInfo = getSelectedDungeonInfo(values and values.SelectedDungeon)
				if not dungeonInfo then return end

				self.State.Starting = true

				task.spawn(function()
					if not getOwnDungeonInfo() then
						self:CreateDungeon(dungeonInfo)
						task.wait(DUNGEON_CREATE_DELAY)
					end

					if getOwnDungeonInfo() or waitForOwnDungeonInfo(DUNGEON_INSTANCE_WAIT) then
						self:StartDungeon(dungeonInfo)
					end

					self.State.Starting = false
				end)
			end

			function Feature:GetHandlers()
				return {
					SelectedDungeon = buildPanelRefHandler(self),
					StartDungeon = function(_, _, panelRef) self:Run(panelRef) end,
				}
			end

			function Feature:Cleanup()
				self.State.Starting = false
				self.State.PanelRef = nil

				if self.State.DungeonEventConnection then
					pcall(function()
						self.State.DungeonEventConnection:Disconnect()
					end)
					self.State.DungeonEventConnection = nil
				end
			end
		end

		--==================================================
		-- FEATURE: SHADOW EXCHANGE
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "ShadowExchange", Tab = "Combat", Section = "Exchange", Order = 30,
				Defaults = {ShadowExchange = false},
				State = {Running = false, LoopId = 0, PanelRef = nil, CapturedOriginal = false, OriginalPass = nil, OriginalButtonVisible = nil},
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

			function Feature:Start(panelRef)
				setFeaturePanelRef(self, panelRef)
				self:Stop()
				setFeaturePanelRef(self, panelRef)
				self:CaptureOriginalValues()

				self.State.Running = true
				self.State.LoopId = self.State.LoopId + 1
				local loopId = self.State.LoopId

				task.spawn(function()
					while self.State.Running and self.State.LoopId == loopId do
						local values = getPanelValues(self.State.PanelRef)
						if not values or values.ShadowExchange ~= true then break end

						setShadowExchange(true)
						task.wait(SHADOW_EXCHANGE_POLL_DELAY)
					end

					if self.State.Running and self.State.LoopId == loopId then self:Stop() end
				end)
			end

			function Feature:Stop()
				self.State.Running = false
				self.State.LoopId = self.State.LoopId + 1
				self:RestoreOriginalValues()
			end

			function Feature:GetHandlers()
				return {ShadowExchange = buildToggleHandler(self, function(panelRef) self:Start(panelRef) end)}
			end

			function Feature:Cleanup()
				self:Stop()
				self.State.PanelRef = nil
			end
		end
	end
}
