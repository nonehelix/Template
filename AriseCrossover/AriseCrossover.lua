return {
	Load = function(Shared)
		local Workspace, RegisterFeature, RegisterTabs = Shared.Workspace or game:GetService("Workspace"), Shared.RegisterFeature, Shared.RegisterTabs
		local Players, ReplicatedStorage, CollectionService = game:GetService("Players"), game:GetService("ReplicatedStorage"), game:GetService("CollectionService")

		local player = Players.LocalPlayer

		--==================================================
		-- TABS
		--==================================================
		RegisterTabs({{Name = "Combat", Order = 20}, {Name = "Dungeon", Order = 30}, {Name = "Time Trial", Order = 40}, {Name = "Teleport", Order = 50}})

		--==================================================
		-- HELPERS
		--==================================================
		local ALL_OPTION, NO_ZONE_OPTION, NO_ENEMY_OPTION, NO_DUNGEON_OPTION, NO_TELEPORT_OPTION = "All", "Select zone", "Select enemy", "Select dungeon", "Select location"
		local EMPTY_TABLE = {}
		local AUTO_CLICK_POLL_DELAY, AUTO_FARM_POLL_DELAY, SHADOW_EXCHANGE_POLL_DELAY = 0.5, 0.25, 0.5
		local DUNGEON_CREATE_DELAY, DUNGEON_INSTANCE_WAIT = 0.5, 6
		local TELEPORT_SPAWN_NAMES = {"Arena", "JejuEvent", "JungleEvent", "WinterEvent", "XmasWorld"}
		local GUILD_HALL_LOCATION = "Guild Hall"
		local TIME_TRIAL_BRIDGE_TOKEN = string.char(17)
		local TIME_TRIAL_DIFFICULTIES = {"Easy", "Normal", "Hard", "Insane", "Ultra", "Nightmare", "Chaotic"}
		local TELEPORT_STATIC_LOCATIONS = {
			[GUILD_HALL_LOCATION] = CFrame.new(9557.8457, -204.696213, 106.217346, 1, 0, 0, 0, 1, 0, 0, 0, 1) * CFrame.Angles(0, math.pi, 0),
		}
		local indexerModuleCache = {}
		local autoFarmZoneItemsCache = {NO_ZONE_OPTION}
		local autoFarmZoneEnemiesCache = {}
		local autoFarmZoneDataLoading = false
		local autoFarmZoneDataLoaded = false
		local autoFarmSelectedZone = NO_ZONE_OPTION

		local function newTargetingState()
			return {Running = false, LoopId = 0, PanelRef = nil, PollDelay = AUTO_FARM_POLL_DELAY, TeleportDistance = 7, CurrentTarget = nil}
		end

		local function getPanelValues(panelRef) return panelRef and panelRef.Config and panelRef.Config.Values or nil end

		local arrayContains = Shared.arrayContains or function(array, value)
			if type(array) ~= "table" then return false end
			for _, item in ipairs(array) do
				if item == value then return true end
			end
			return false
		end

		local function normalizeSelectionArray(values)
			local result = {}
			local seen = {}

			local function addSelection(value)
				value = tostring(value or "")
				if value == "" or value == NO_ENEMY_OPTION or seen[value] then return end
				seen[value] = true
				result[#result + 1] = value
			end

			if type(values) == "table" then
				for _, value in ipairs(values) do
					addSelection(value)
				end
			else
				addSelection(values)
			end

			return result
		end

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

		local function runFeatureTask(feature, stateKey, callback)
			if feature.State[stateKey] then return false end

			feature.State[stateKey] = true
			task.spawn(function()
				pcall(callback)
				feature.State[stateKey] = false
			end)

			return true
		end

		local function bindPollingToggleFeature(feature, optionId, onTick, config)
			config = config or EMPTY_TABLE

			function feature:Start(panelRef)
				setFeaturePanelRef(self, panelRef)
				if config.RestartOnStart then
					self:Stop()
					setFeaturePanelRef(self, panelRef)
				elseif self.State.Running then
					return
				end

				if config.BeforeStart then
					config.BeforeStart(self, panelRef)
				end

				self.State.Running = true

				local loopId = nil
				if config.UseLoopId or self.State.LoopId ~= nil then
					self.State.LoopId = (self.State.LoopId or 0) + 1
					loopId = self.State.LoopId
				end

				task.spawn(function()
					while self.State.Running do
						if loopId ~= nil and self.State.LoopId ~= loopId then break end

						local values = getPanelValues(self.State.PanelRef)
						if not values or values[optionId] ~= true then break end

						onTick(self, values)
						task.wait(self.State.PollDelay or config.PollDelay or 0.5)
					end

					if self.State.Running and (loopId == nil or self.State.LoopId == loopId) then
						self:Stop()
					end
				end)
			end

			function feature:Stop()
				self.State.Running = false
				if config.UseLoopId or self.State.LoopId ~= nil then
					self.State.LoopId = (self.State.LoopId or 0) + 1
				end

				if config.BeforeStop then
					config.BeforeStop(self)
				end
			end

			function feature:GetHandlers()
				local handlers = {
					[optionId] = buildToggleHandler(self, function(panelRef) self:Start(panelRef) end),
				}

				for handlerId, handler in pairs(config.ExtraHandlers or EMPTY_TABLE) do
					handlers[handlerId] = handler
				end

				return handlers
			end

			function feature:Cleanup()
				self:Stop()
				self.State.PanelRef = nil

				if config.OnCleanup then
					config.OnCleanup(self)
				end
			end
		end

		local settingsCache, leaderstatsCache, passesCache = nil, nil, nil
		local function getSettings()
			if settingsCache and settingsCache.Parent == player then return settingsCache end
			settingsCache = player:FindFirstChild("Settings") or player:WaitForChild("Settings", 10)
			return settingsCache
		end

		local function getLeaderstats()
			if leaderstatsCache and leaderstatsCache.Parent == player then return leaderstatsCache end
			leaderstatsCache = player:FindFirstChild("leaderstats") or player:WaitForChild("leaderstats", 10)
			return leaderstatsCache
		end

		local function getPasses()
			if passesCache and passesCache.Parent then return passesCache end
			local leaderstats = getLeaderstats()
			passesCache = leaderstats and (leaderstats:FindFirstChild("Passes") or leaderstats:WaitForChild("Passes", 10)) or nil
			return passesCache
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

		local function fireBridgeDataRemote(payload)
			local bridgeModule = ReplicatedStorage:FindFirstChild("BridgeNet2")
			local remoteEvent = bridgeModule and bridgeModule:FindFirstChild("dataRemoteEvent")
			if not remoteEvent or type(payload) ~= "table" then return false end

			local ok = pcall(function()
				remoteEvent:FireServer(payload)
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

		local function requireIndexerModule(moduleNames)
			if type(moduleNames) == "string" then
				moduleNames = {moduleNames}
			end

			local indexer = ReplicatedStorage:FindFirstChild("Indexer")
			if not indexer then return nil end

			for _, moduleName in ipairs(moduleNames or EMPTY_TABLE) do
				local cached = indexerModuleCache[moduleName]
				if cached ~= nil then
					return cached
				end

				local module = indexer:FindFirstChild(moduleName)
				if module and module:IsA("ModuleScript") then
					local ok, result = pcall(require, module)
					if ok and type(result) == "table" then
						indexerModuleCache[moduleName] = result
						return result
					end
				end
			end

			return nil
		end

		local function getMapInfoConfig()
			return requireIndexerModule({"MapInfo", "MapsInfo"})
		end

		local function getEnemyInfoConfig()
			return requireIndexerModule({"EnemyInfo", "EnemiesInfo", "Enemies", "MobsInfo"})
		end

		local function getCharacterRoot()
			local character = player.Character
			return character and character:FindFirstChild("HumanoidRootPart") or nil
		end

		local function teleportCharacterToCFrame(cframe)
			local character = player.Character
			if not character or not cframe then return false end
			character:PivotTo(cframe)
			return true
		end

		local function getEnemyRoot(enemy)
			if not enemy then return nil end
			if enemy:IsA("BasePart") then return enemy end
			if enemy:IsA("Model") then
				return enemy.PrimaryPart or enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChildWhichIsA("BasePart", true)
			end

			return enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChildWhichIsA("BasePart", true)
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

		local enemyDisplayLookupCache = nil

		local function getEnemyDisplayLookup()
			if enemyDisplayLookupCache ~= nil then
				return enemyDisplayLookupCache
			end

			local lookup = {}
			local enemyInfo = getEnemyInfoConfig()
			if type(enemyInfo) == "table" then
				for id, info in pairs(enemyInfo) do
					if type(info) == "table" then
						local displayName = tostring(info.Name or "")
						if displayName ~= "" then
							for _, candidate in ipairs({id, info.Name, info.Arise, info.Model, info.CustomModel}) do
								local key = string.lower(tostring(candidate or ""))
								if key ~= "" and lookup[key] == nil then
									lookup[key] = displayName
								end
							end
						end
					end
				end
			end

			enemyDisplayLookupCache = lookup
			return lookup
		end

		local function getResolvedEnemyDisplayName(enemy)
			local displayName = getEnemyDisplayName(enemy)
			local lookup = getEnemyDisplayLookup()

			for _, candidate in ipairs({
				enemy and enemy:GetAttribute("Id"),
				enemy and enemy:GetAttribute("ID"),
				enemy and enemy:GetAttribute("Model"),
				enemy and enemy:GetAttribute("Name"),
				displayName,
				enemy and enemy.Name,
			}) do
				local key = string.lower(tostring(candidate or ""))
				if key ~= "" and lookup[key] ~= nil then
					return lookup[key]
				end
			end

			return displayName
		end

		local function getServerEnemy(enemy)
			local _, serverFolder = getEnemyFolders()
			if not enemy then return nil end

			if CollectionService:HasTag(enemy, "EnemyServer") or (serverFolder and enemy:IsDescendantOf(serverFolder)) then
				return enemy
			end

			if not serverFolder then return nil end

			for _, taggedEnemy in ipairs(CollectionService:GetTagged("EnemyServer")) do
				if taggedEnemy.Name == enemy.Name and taggedEnemy:IsDescendantOf(serverFolder) then
					return taggedEnemy
				end
			end

			return serverFolder:FindFirstChild(enemy.Name) or serverFolder:FindFirstChild(enemy.Name, true)
		end

		local function isEnemyAlive(enemy)
			if not enemy or not enemy.Parent then return false end
			if not getEnemyRoot(enemy) then return false end

			local serverEnemy = getServerEnemy(enemy)
			return serverEnemy ~= nil and serverEnemy:GetAttribute("Dead") ~= true
		end

		local function getServerEnemyCandidates()
			local _, serverFolder = getEnemyFolders()
			local candidates = {}
			local seen = {}

			local function addCandidate(enemy)
				if not enemy or seen[enemy] then return end
				if serverFolder and not enemy:IsDescendantOf(serverFolder) then return end
				if not getEnemyRoot(enemy) then return end

				local isTagged = CollectionService:HasTag(enemy, "EnemyServer")
				local hasEnemyAttributes = enemy:GetAttribute("Dead") ~= nil or enemy:GetAttribute("HP") ~= nil or enemy:GetAttribute("Id") ~= nil or enemy:GetAttribute("ID") ~= nil or enemy:GetAttribute("Model") ~= nil
				if not isTagged and not hasEnemyAttributes then return end

				seen[enemy] = true
				candidates[#candidates + 1] = enemy
			end

			for _, enemy in ipairs(CollectionService:GetTagged("EnemyServer")) do
				addCandidate(enemy)
			end

			if serverFolder then
				for _, enemy in ipairs(serverFolder:GetDescendants()) do
					addCandidate(enemy)
				end
			end

			return candidates
		end

		local function getClientEnemyCandidates()
			local clientFolder = getEnemyFolders()
			local candidates = {}

			if not clientFolder then return candidates end

			for _, enemy in ipairs(clientFolder:GetChildren()) do
				if getEnemyRoot(enemy) then
					candidates[#candidates + 1] = enemy
				end
			end

			return candidates
		end

		local function findClosestCandidate(candidates, matchFn)
			local characterRoot = getCharacterRoot()
			local closestEnemy = nil
			local closestDistance = nil

			for _, enemy in ipairs(candidates or EMPTY_TABLE) do
				if matchFn == nil or matchFn(enemy) then
					if isEnemyAlive(enemy) then
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
			end

			return closestEnemy, closestDistance
		end

		local function findClosestClientTarget(matchFn)
			return findClosestCandidate(getClientEnemyCandidates(), matchFn)
		end

		local function findClosestServerTarget(matchFn)
			return findClosestCandidate(getServerEnemyCandidates(), matchFn)
		end

		local function isTargetAlive(target)
			return target and target.Parent and isEnemyAlive(target)
		end

		local function isDungeonActive()
			return ReplicatedStorage:GetAttribute("Dungeon") == true
		end

		local function isExcludedDungeonMode()
			return player:GetAttribute("InTimeTrial") == true
			or ReplicatedStorage:GetAttribute("InTimeTrial") == true
			or player:GetAttribute("InBossRush") == true
			or ReplicatedStorage:GetAttribute("InBossRush") == true
			or ReplicatedStorage:GetAttribute("IsCastle") == true
		end

		local function isNormalDungeonInstance()
			return isDungeonActive() and not isExcludedDungeonMode()
		end

		local function addEnemyItem(items, seen, enemyName)
			enemyName = tostring(enemyName or "")
			if enemyName == "" or seen[enemyName] then return end

			seen[enemyName] = true
			items[#items + 1] = enemyName
		end

		local function loadAutoFarmZoneData()
			if autoFarmZoneDataLoading or autoFarmZoneDataLoaded then
				return
			end

			autoFarmZoneDataLoading = true

			task.spawn(function()
				local zoneItems = {NO_ZONE_OPTION}
				local zoneEnemies = {}

				local ok, err = pcall(function()
					local mapInfo = getMapInfoConfig()
					local enemyInfo = getEnemyInfoConfig()
					if type(mapInfo) ~= "table" or type(enemyInfo) ~= "table" then
						return
					end

					local internalNameMap = {}

					local function addInternalName(internalName, displayName)
						internalName = string.lower(tostring(internalName or ""))
						displayName = tostring(displayName or "")
						if internalName == "" or displayName == "" then
							return
						end

						local names = internalNameMap[internalName]
						if not names then
							names = {}
							internalNameMap[internalName] = names
						end

						if not arrayContains(names, displayName) then
							names[#names + 1] = displayName
						end
					end

					for id, info in pairs(enemyInfo) do
						if type(info) == "table" then
							local displayName = tostring(info.Name or "")
							if displayName ~= "" then
								for _, candidate in ipairs({id, info.Name, info.Arise, info.Model, info.CustomModel}) do
									addInternalName(candidate, displayName)
								end
							end
						end
					end

					local zoneEntries = {}
					for key, info in pairs(mapInfo) do
						if type(info) == "table" and info.Name ~= nil then
							zoneEntries[#zoneEntries + 1] = {Key = key, Info = info}
						end
					end

					table.sort(zoneEntries, function(a, b)
						local orderA = tonumber(a.Info.Order)
						local orderB = tonumber(b.Info.Order)
						if orderA ~= nil and orderB ~= nil and orderA ~= orderB then
							return orderA < orderB
						end
						return tostring(a.Info.Name or a.Key) < tostring(b.Info.Name or b.Key)
					end)

					local function collectInternalNames(source, items, seen)
						if type(source) ~= "table" then
							return
						end

						for _, value in pairs(source) do
							if type(value) == "string" then
								if not seen[value] then
									seen[value] = true
									items[#items + 1] = value
								end
							elseif type(value) == "table" then
								collectInternalNames(value, items, seen)
							end
						end
					end

					local function getZoneNormalList(zoneInfo)
						if type(zoneInfo) ~= "table" then
							return nil
						end

						if type(zoneInfo.Normal) == "table" then
							return zoneInfo.Normal
						end

						for _, value in pairs(zoneInfo) do
							if type(value) == "table" and type(value.Normal) == "table" then
								return value.Normal
							end
						end

						return nil
					end

					for _, entry in ipairs(zoneEntries) do
						local zoneName = tostring(entry.Info.Name or entry.Key)
						local zoneEnemyItems = {}
						local zoneEnemySeen = {}
						local internalNames = {}
						local normalList = getZoneNormalList(entry.Info)

						collectInternalNames(normalList, internalNames, {})

						for _, internalName in ipairs(internalNames) do
							local displayNames = internalNameMap[string.lower(tostring(internalName))] or EMPTY_TABLE
							for _, enemyName in ipairs(displayNames) do
								addEnemyItem(zoneEnemyItems, zoneEnemySeen, enemyName)
							end
						end

						table.sort(zoneEnemyItems)

						if #zoneEnemyItems > 0 then
							zoneItems[#zoneItems + 1] = zoneName
							zoneEnemies[zoneName] = {ALL_OPTION}
							for _, enemyName in ipairs(zoneEnemyItems) do
								zoneEnemies[zoneName][#zoneEnemies[zoneName] + 1] = enemyName
							end
						end
					end
				end)

				if ok then
					autoFarmZoneItemsCache = zoneItems
					autoFarmZoneEnemiesCache = zoneEnemies
					autoFarmZoneDataLoaded = true
				else
					warn("[AriseCrossover] Failed to load Auto Farm zone data: " .. tostring(err))
				end

				autoFarmZoneDataLoading = false
			end)
		end

		local function getAutoFarmZoneItems()
			loadAutoFarmZoneData()
			return autoFarmZoneItemsCache
		end

		local function getAutoFarmEnemyItems()
			if autoFarmSelectedZone == nil or autoFarmSelectedZone == "" or autoFarmSelectedZone == NO_ZONE_OPTION then
				return {}
			end

			loadAutoFarmZoneData()
			return autoFarmZoneEnemiesCache[autoFarmSelectedZone] or {}
		end

		loadAutoFarmZoneData()

		local function getClosestTeleportCFrame(enemyRoot, distance)
			local characterRoot = getCharacterRoot()
			local enemyPosition = enemyRoot.Position
			local radius = distance or 7

			local direction = nil
			if characterRoot then
				local offset = characterRoot.Position - enemyPosition
				local flatOffset = Vector3.new(offset.X, 0, offset.Z)
				if flatOffset.Magnitude > 0.001 then
					direction = flatOffset.Unit
				end
			end

			if not direction then
				local lookVector = enemyRoot.CFrame.LookVector
				local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
				direction = flatLook.Magnitude > 0.001 and flatLook.Unit or Vector3.new(0, 0, -1)
			end

			local targetPosition = enemyPosition + direction * radius
			targetPosition = Vector3.new(targetPosition.X, enemyPosition.Y, targetPosition.Z)

			return CFrame.lookAt(targetPosition, Vector3.new(enemyPosition.X, targetPosition.Y, enemyPosition.Z))
		end

		local function teleportToEnemy(enemy, distance)
			local enemyRoot = getEnemyRoot(enemy)
			if not enemyRoot then return end
			teleportCharacterToCFrame(getClosestTeleportCFrame(enemyRoot, distance))
		end

		local function setFeatureTarget(feature, target)
			if feature.State.CurrentTarget == target then return end

			feature.State.CurrentTarget = target
			if target then teleportToEnemy(target, feature.State.TeleportDistance) end
		end

		local teleportSpawnNameToInstance = {}

		local function getTeleportSpawnsFolder()
			return Workspace:FindFirstChild("__Spawns") or Workspace:FindFirstChild("__Spawns", true)
		end

		local function getInstanceCFrame(instance)
			if not instance then return nil end
			if instance:IsA("BasePart") then return instance.CFrame end
			if instance:IsA("Attachment") then return instance.WorldCFrame end
			if instance:IsA("Model") then return instance:GetPivot() end

			local basePart = instance:FindFirstChildWhichIsA("BasePart", true)
			return basePart and basePart.CFrame or nil
		end

		local function getTeleportSpawnCFrame(spawnInstance)
			local cframe = getInstanceCFrame(spawnInstance)
			return cframe and (cframe * CFrame.new(0, 3, 0)) or nil
		end

		local function addTeleportStaticLocations(items)
			for locationName in pairs(TELEPORT_STATIC_LOCATIONS) do
				items[#items + 1] = locationName
			end
		end

		local function getTeleportSpawnItems()
			local items = {NO_TELEPORT_OPTION}
			teleportSpawnNameToInstance = {}

			local spawnsFolder = getTeleportSpawnsFolder()
			if spawnsFolder then
				for _, spawnName in ipairs(TELEPORT_SPAWN_NAMES) do
					local spawnInstance = spawnsFolder:FindFirstChild(spawnName)
					if spawnInstance then
						teleportSpawnNameToInstance[spawnName] = spawnInstance
						items[#items + 1] = spawnName
					end
				end
			end

			addTeleportStaticLocations(items)
			return items
		end

		local function getSelectedTeleportSpawn(selectedSpawnName)
			if selectedSpawnName == nil or selectedSpawnName == "" or selectedSpawnName == NO_TELEPORT_OPTION then return nil end

			local cachedSpawn = teleportSpawnNameToInstance[selectedSpawnName]
			if cachedSpawn and cachedSpawn.Parent then return cachedSpawn end

			local spawnsFolder = getTeleportSpawnsFolder()
			return spawnsFolder and spawnsFolder:FindFirstChild(selectedSpawnName) or nil
		end

		local function getTeleportLocationCFrame(selectedLocation)
			local staticCFrame = TELEPORT_STATIC_LOCATIONS[selectedLocation]
			if staticCFrame then return staticCFrame end

			return getTeleportSpawnCFrame(getSelectedTeleportSpawn(selectedLocation))
		end

		local function teleportToSavedLocation(selectedLocation)
			local cframe = getTeleportLocationCFrame(selectedLocation)
			local character = player.Character
			if not character or not cframe then return false end

			local inGuild = selectedLocation == GUILD_HALL_LOCATION
			character:SetAttribute("InTp", true)
			if inGuild then
				character:SetAttribute("InGuild", true)
				task.defer(function()
					fireGeneralEvent({Event = "MountAction", Action = "Dismount"})
				end)
			end

			task.wait(0.25)
			character:PivotTo(cframe)
			task.wait(0.5)
			character:SetAttribute("InGuild", inGuild)
			character:SetAttribute("InTp", false)
			return true
		end

		local dungeonLabelToInfo = {}

		local function getLiveDungeonFolder()
			local main = Workspace:FindFirstChild("__Main")
			if not main then return nil end

			return main:FindFirstChild("__Dungeon")
		end

		local function makeDungeonLabel(info)
			local mapName = tostring(info.MapName or info.Dungeon or "Dungeon")
			local rank = info.DungeonRank ~= nil and tostring(info.DungeonRank) or "?"
			return mapName .. " - Rank " .. rank
		end

		local function getSafeAttributes(instance)
			if not instance then return nil end

			local ok, attrs = pcall(function()
				return instance:GetAttributes()
			end)

			if not ok or type(attrs) ~= "table" then return nil end
			return attrs
		end

		local function hasDungeonAttributes(attrs)
			if not attrs then return false end
			local hasCoreInfo = attrs.Dungeon ~= nil or attrs.DungeonMap ~= nil or attrs.MapName ~= nil
			local hasIdentifier = attrs.ID ~= nil or attrs.DoubleID ~= nil or attrs._C ~= nil
			return hasCoreInfo and hasIdentifier
		end

		local function getLiveDungeonInfo(dungeonObject)
			if not dungeonObject then return nil end

			local attrs = getSafeAttributes(dungeonObject)
			if not hasDungeonAttributes(attrs) then return nil end

			local mapName = attrs.MapName or attrs.Dungeon or attrs.DungeonMap
			local dungeonName = attrs.Dungeon or mapName or attrs.DungeonMap
			local dungeonMap = attrs.DungeonMap or attrs.Map or attrs.Dungeon or mapName
			if dungeonName == nil and dungeonMap == nil then return nil end

			local info = {
				Key = tostring(attrs.DoubleID or attrs.ID or attrs.DungeonMap or attrs.Dungeon or dungeonObject.Name),
				Dungeon = dungeonName and tostring(dungeonName) or tostring(dungeonMap),
				DungeonMap = dungeonMap and tostring(dungeonMap) or tostring(dungeonName),
				Map = dungeonMap and tostring(dungeonMap) or tostring(dungeonName),
				MapName = mapName and tostring(mapName) or nil,
				World = attrs.World and tostring(attrs.World) or nil,
				DungeonRank = attrs.DungeonRank or attrs.Rank,
				ID = attrs.ID,
				DoubleID = attrs.DoubleID,
				Instance = dungeonObject,
			}

			info.Label = makeDungeonLabel(info)
			return info
		end

		local function getLiveDungeonEntries()
			local entries = {}
			local seenInstances = {}
			local seenKeys = {}
			local folder = getLiveDungeonFolder()

			local function addCandidate(dungeonObject)
				if not dungeonObject or seenInstances[dungeonObject] then return end
				seenInstances[dungeonObject] = true

				local info = getLiveDungeonInfo(dungeonObject)
				if not info or seenKeys[info.Key] then return end

				seenKeys[info.Key] = true
				entries[#entries + 1] = info
			end

			if folder then
				addCandidate(folder)
				for _, dungeonObject in ipairs(folder:GetDescendants()) do
					addCandidate(dungeonObject)
				end
			end

			table.sort(entries, function(a, b)
				local rankA = tonumber(a.DungeonRank)
				local rankB = tonumber(b.DungeonRank)
				if rankA ~= nil and rankB ~= nil and rankA ~= rankB then return rankA < rankB end
				return tostring(a.Label) < tostring(b.Label)
			end)

			return entries
		end

		local function getDungeonItems()
			local items = {NO_DUNGEON_OPTION}
			dungeonLabelToInfo = {}

			for _, dungeonInfo in ipairs(getLiveDungeonEntries()) do
				local label = dungeonInfo.Label
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

		local function getOwnTimeTrialInfo()
			local infos = ReplicatedStorage:FindFirstChild("__Infos")
			local timeTrials = infos and infos:FindFirstChild("__TimeTrial")
			if not timeTrials then return nil end

			local ownTrial = timeTrials:FindFirstChild(tostring(player.UserId))
			if ownTrial then return ownTrial end

			for _, trial in ipairs(timeTrials:GetChildren()) do
				if tonumber(trial:GetAttribute("Leader")) == player.UserId then
					return trial
				end

				local members = trial:FindFirstChild("Members")
				local memberValue = members and members:GetAttribute(tostring(player.UserId))
				if tonumber(memberValue) == player.UserId then
					return trial
				end
			end

			return nil
		end

		local function waitForOwnTimeTrialInfo(timeout)
			local startedAt = os.clock()

			repeat
				local timeTrial = getOwnTimeTrialInfo()
				if timeTrial then return timeTrial end
				task.wait(0.25)
			until os.clock() - startedAt >= (timeout or DUNGEON_INSTANCE_WAIT)

			return nil
		end

		local function getTimeTrialDungeonId(timeTrialInfo)
			if not timeTrialInfo then return nil end

			local leader = timeTrialInfo:GetAttribute("Leader")
			if leader ~= nil then return leader end

			return tonumber(timeTrialInfo.Name) or timeTrialInfo.Name
		end

		local function sendTimeTrialAction(action, extraPayload)
			local payload = {Event = "TimeTrialAction", Action = action}

			for key, value in pairs(extraPayload or {}) do
				payload[key] = value
			end

			return fireBridgeDataRemote({payload, TIME_TRIAL_BRIDGE_TOKEN})
		end

		local function getTimeTrialDifficultyItems()
			return TIME_TRIAL_DIFFICULTIES
		end

		local function isValidTimeTrialDifficulty(difficulty)
			return arrayContains(TIME_TRIAL_DIFFICULTIES, difficulty)
		end

		local function startTimeTrial(difficulty, dungeonId)
			if not isValidTimeTrialDifficulty(difficulty) then
				return false
			end

			if dungeonId == nil then
				return false
			end

			return sendTimeTrialAction("Start", {Dungeon = dungeonId, Diff = difficulty})
		end

		local function buildDungeonActionPayload(dungeonOwner, dungeonInfo)
			local isTable = type(dungeonInfo) == "table"
			local dungeon = isTable and (dungeonInfo.Dungeon or dungeonInfo.Key) or dungeonInfo
			local dungeonMap = isTable and (dungeonInfo.DungeonMap or dungeonInfo.Map or dungeonInfo.Key) or dungeonInfo
			local map = isTable and (dungeonInfo.Map or dungeonInfo.DungeonMap or dungeonInfo.Key) or dungeonInfo

			return {
				Dungeon = dungeonOwner ~= nil and dungeonOwner or dungeon,
				DungeonMap = dungeonMap,
				Map = map,
				ID = isTable and dungeonInfo.ID or nil,
				DungeonID = isTable and dungeonInfo.ID or nil,
				DungeonName = isTable and dungeonInfo.Dungeon or nil,
				MapName = isTable and dungeonInfo.MapName or nil,
				DoubleID = isTable and dungeonInfo.DoubleID or nil,
				World = isTable and dungeonInfo.World or nil,
				DungeonRank = isTable and dungeonInfo.DungeonRank or nil,
			}
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

			bindPollingToggleFeature(Feature, "AutoClick", function()
				setAutoClick(true)
			end, {
				PollDelay = AUTO_CLICK_POLL_DELAY,
				BeforeStart = function(self)
					self:CaptureOriginalValues()
				end,
				BeforeStop = function(self)
					self:RestoreOriginalValues()
				end,
			})
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
				Defaults = {AutoFarmZone = NO_ZONE_OPTION, AutoFarmEnemy = {}, AutoFarm = false},
				State = newTargetingState(),
				Options = {
					{ Id = "AutoFarmZone", Type = "select", Label = "Zone", Description = "Select zone enemy list", Items = getAutoFarmZoneItems },
					{ Id = "AutoFarmEnemy", Type = "multiselect", Label = "Enemy", Description = "Select enemies to farm", Items = getAutoFarmEnemyItems, EmptyText = "Nothing selected" },
					{ Id = "AutoFarm", Type = "toggle", Label = "Auto Farm", Description = "Teleports to the closest selected enemy and retargets on death" },
				}
			})

			function Feature:SetZone(zoneName, panelRef)
				setFeaturePanelRef(self, panelRef)

				zoneName = tostring(zoneName or NO_ZONE_OPTION)
				local changed = autoFarmSelectedZone ~= zoneName
				autoFarmSelectedZone = zoneName

				if self.State.ZoneInitialized and changed then
					self.State.CurrentTarget = nil
					if panelRef and panelRef.SetValue then
						panelRef:SetValue("AutoFarmEnemy", {})
					end
				end

				self.State.ZoneInitialized = true
			end

			function Feature:MatchesSelection(enemy, selectedEnemies)
				if arrayContains(selectedEnemies, ALL_OPTION) then return true end
				return arrayContains(selectedEnemies, getResolvedEnemyDisplayName(enemy))
			end

			function Feature:GetMatchFn(selectedEnemies)
				if arrayContains(selectedEnemies, ALL_OPTION) then return nil end
				return function(enemy)
					return self:MatchesSelection(enemy, selectedEnemies)
				end
			end

			function Feature:FindTarget(selectedEnemies)
				return findClosestServerTarget(self:GetMatchFn(selectedEnemies))
			end

			function Feature:TargetMatches(target, selectedEnemies)
				return target and target.Parent and self:MatchesSelection(target, selectedEnemies)
			end

			function Feature:Tick(values)
				local selectedEnemies = normalizeSelectionArray(values and values.AutoFarmEnemy)
				if #selectedEnemies == 0 then
					return
				end

				local target = self.State.CurrentTarget
				if not self:TargetMatches(target, selectedEnemies) or not isTargetAlive(target) then
					local newTarget = self:FindTarget(selectedEnemies)
					setFeatureTarget(self, newTarget)
				end
			end

			bindPollingToggleFeature(Feature, "AutoFarm", function(self, values)
				self:Tick(values)
			end, {
				RestartOnStart = true,
				UseLoopId = true,
				BeforeStop = function(self)
					self.State.CurrentTarget = nil
				end,
				ExtraHandlers = {
					AutoFarmZone = function(value, _, panelRef)
						Feature:SetZone(value, panelRef)
					end,
					AutoFarmEnemy = buildRestartHandler(Feature, "AutoFarm"),
				},
			})
		end

		--==================================================
		-- FEATURE: AUTO DUNGEON
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "AutoDungeon", Tab = "Dungeon", Section = "Farm", Order = 20,
				Defaults = {AutoDungeon = false},
				State = newTargetingState(),
				Options = {
					{ Id = "AutoDungeon", Type = "toggle", Label = "Auto Dungeon", Description = "Teleports to the closest alive enemy only inside an active dungeon instance" },
				}
			})

			function Feature:FindTarget()
				return findClosestServerTarget(nil)
			end

			function Feature:Tick()
				if not isNormalDungeonInstance() then
					self.State.CurrentTarget = nil
					return
				end

				local target = self.State.CurrentTarget
				if not isTargetAlive(target) then
					local newTarget = self:FindTarget()
					setFeatureTarget(self, newTarget)
				end
			end

			bindPollingToggleFeature(Feature, "AutoDungeon", function(self)
				self:Tick()
			end, {
				RestartOnStart = true,
				UseLoopId = true,
				BeforeStop = function(self)
					self.State.CurrentTarget = nil
				end,
			})
		end

		--==================================================
		-- FEATURE: DUNGEON STARTER
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "DungeonStarter", Tab = "Dungeon", Section = "Dungeon", Order = 10,
				Defaults = {SelectedDungeon = NO_DUNGEON_OPTION},
				State = {Starting = false, PanelRef = nil},
				Options = {
					{ Id = "SelectedDungeon", Type = "select", Label = "Dungeon", Description = "Available dungeon maps and ranks", Items = getDungeonItems },
					{ Id = "StartDungeon", Type = "button", Label = "Start Dungeon", Description = "Creates and starts selected dungeon", ButtonText = "Start" },
				}
			})

			function Feature:Run(panelRef)
				local values = setFeaturePanelRef(self, panelRef)

				local dungeonInfo = getSelectedDungeonInfo(values and values.SelectedDungeon)
				if not dungeonInfo then return end

				runFeatureTask(self, "Starting", function()
					local ownDungeon = getOwnDungeonInfo()
					if not ownDungeon then
						sendDungeonAction("Create", buildDungeonActionPayload(nil, dungeonInfo))
						task.wait(DUNGEON_CREATE_DELAY)
					end

					ownDungeon = getOwnDungeonInfo() or waitForOwnDungeonInfo(DUNGEON_INSTANCE_WAIT)
					if ownDungeon then
						sendDungeonAction("Start", buildDungeonActionPayload(player.UserId, dungeonInfo))
					end
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
			end
		end

		--==================================================
		-- FEATURE: TIME TRIAL STARTER
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "TimeTrialStarter", Tab = "Time Trial", Section = "Start", Order = 10,
				Defaults = {TimeTrialDifficulty = "Easy"},
				State = {Starting = false, PanelRef = nil},
				Options = {
					{ Id = "TimeTrialDifficulty", Type = "select", Label = "Difficulty", Description = "Select Time Trial difficulty", Items = getTimeTrialDifficultyItems },
					{ Id = "StartTimeTrial", Type = "button", Label = "Start Time Trial", Description = "Starts Time Trial with selected difficulty", ButtonText = "Start" },
				}
			})

			function Feature:Run(panelRef)
				local values = setFeaturePanelRef(self, panelRef)

				local difficulty = values and values.TimeTrialDifficulty
				if not isValidTimeTrialDifficulty(difficulty) then
					return
				end

				runFeatureTask(self, "Starting", function()
					local ownTimeTrial = getOwnTimeTrialInfo()
					if not ownTimeTrial then
						sendTimeTrialAction("Create")
						task.wait(DUNGEON_CREATE_DELAY)
					end

					ownTimeTrial = getOwnTimeTrialInfo() or waitForOwnTimeTrialInfo(DUNGEON_INSTANCE_WAIT)
					local dungeonId = getTimeTrialDungeonId(ownTimeTrial)

					if dungeonId ~= nil then
						startTimeTrial(difficulty, dungeonId)
					end
				end)
			end

			function Feature:GetHandlers()
				return {
					TimeTrialDifficulty = buildPanelRefHandler(self),
					StartTimeTrial = function(_, _, panelRef) self:Run(panelRef) end,
				}
			end

			function Feature:Cleanup()
				self.State.Starting = false
				self.State.PanelRef = nil
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

			bindPollingToggleFeature(Feature, "ShadowExchange", function()
				setShadowExchange(true)
			end, {
				PollDelay = SHADOW_EXCHANGE_POLL_DELAY,
				RestartOnStart = true,
				UseLoopId = true,
				BeforeStart = function(self)
					self:CaptureOriginalValues()
				end,
				BeforeStop = function(self)
					self:RestoreOriginalValues()
				end,
			})
		end

		--==================================================
		-- FEATURE: SPAWN TELEPORT
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "SpawnTeleport", Tab = "Teleport", Section = "Spawns", Order = 10,
				Defaults = {SelectedTeleportLocation = NO_TELEPORT_OPTION},
				State = {PanelRef = nil, Teleporting = false},
				Options = {
					{ Id = "SelectedTeleportLocation", Type = "select", Label = "Location", Description = "Select a spawn location", Items = getTeleportSpawnItems },
					{ Id = "TeleportToLocation", Type = "button", Label = "Teleport", Description = "Teleports to the selected location", ButtonText = "Teleport" },
				}
			})

			function Feature:Run(panelRef)
				local values = setFeaturePanelRef(self, panelRef)
				local selectedLocation = values and values.SelectedTeleportLocation
				if selectedLocation == nil or selectedLocation == NO_TELEPORT_OPTION then return end

				runFeatureTask(self, "Teleporting", function()
					teleportToSavedLocation(selectedLocation)
				end)
			end

			function Feature:GetHandlers()
				return {
					SelectedTeleportLocation = buildPanelRefHandler(self),
					TeleportToLocation = function(_, _, panelRef) self:Run(panelRef) end,
				}
			end

			function Feature:Cleanup()
				self.State.PanelRef = nil
				self.State.Teleporting = false
			end
		end

	end
}
