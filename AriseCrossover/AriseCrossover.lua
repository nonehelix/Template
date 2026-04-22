return {
	Load = function(Shared)
		local Workspace, RegisterFeature, RegisterTabs = Shared.Workspace or game:GetService("Workspace"), Shared.RegisterFeature, Shared.RegisterTabs
		local Players, ReplicatedStorage = game:GetService("Players"), game:GetService("ReplicatedStorage")

		local player = Players.LocalPlayer

		--==================================================
		-- TABS
		--==================================================
		RegisterTabs({{Name = "Combat", Order = 20}, {Name = "Dungeon", Order = 30}, {Name = "Debug", Order = 40}})

		--==================================================
		-- GAME REFERENCES
		--==================================================
		local Indexer = ReplicatedStorage:FindFirstChild("Indexer")

		--==================================================
		-- HELPERS
		--==================================================
		local NO_ENEMY_OPTION, NO_DUNGEON_OPTION = "Select enemy", "Select dungeon"
		local EMPTY_TABLE = {}
		local AUTO_CLICK_POLL_DELAY, AUTO_FARM_POLL_DELAY, SHADOW_EXCHANGE_POLL_DELAY, DEBUG_POLL_DELAY = 0.5, 0.25, 0.5, 1
		local DUNGEON_CREATE_DELAY, DUNGEON_INSTANCE_WAIT = 0.5, 6

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

		local function disconnectConnection(connection)
			if connection and connection.Connected then
				connection:Disconnect()
			end
			return nil
		end

		local function bindConnectionToggleFeature(feature, optionId, onStart, config)
			config = config or EMPTY_TABLE

			function feature:Start(panelRef)
				setFeaturePanelRef(self, panelRef)
				if config.RestartOnStart then
					self:Stop()
					setFeaturePanelRef(self, panelRef)
				elseif self.State.Running then
					return
				end

				self.State.Running = true
				onStart(self, panelRef)
			end

			function feature:Stop()
				self.State.Running = false
				if config.BeforeStop then
					config.BeforeStop(self)
				end
			end

			function feature:GetHandlers()
				return {
					[optionId] = buildToggleHandler(self, function(panelRef) self:Start(panelRef) end),
				}
			end

			function feature:Cleanup()
				self:Stop()
				self.State.PanelRef = nil
				if config.OnCleanup then
					config.OnCleanup(self)
				end
			end
		end

		local function formatDebugValue(value)
			local valueType = typeof(value)
			if valueType == "Vector3" then
				return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
			elseif valueType == "Vector2" then
				return string.format("(%.2f, %.2f)", value.X, value.Y)
			elseif valueType == "CFrame" then
				local position = value.Position
				return string.format("CFrame(%.2f, %.2f, %.2f)", position.X, position.Y, position.Z)
			elseif valueType == "Instance" then
				return value:GetFullName()
			end

			return tostring(value)
		end

		local function debugLog(scope, message)
			print("[AriseCrossover][" .. tostring(scope) .. "] " .. tostring(message))
		end

		local DebugFlags = {
			Farm = false,
		}

		local function farmDebugLog(scope, message)
			if DebugFlags.Farm then
				debugLog(scope, message)
			end
		end

		local function featureDebugLog(feature, scope, message)
			if not DebugFlags.Farm then return end
			if feature and feature.State then
				if feature.State.LastDebugMessage == message then return end
				feature.State.LastDebugMessage = message
			end

			farmDebugLog(scope, message)
		end

		local function buildAttributeSnapshot(instance)
			if not instance then return "<missing>" end

			local ok, attributes = pcall(function()
				return instance:GetAttributes()
			end)
			if not ok or type(attributes) ~= "table" then return "<unavailable>" end

			local names = {}
			for name in pairs(attributes) do
				names[#names + 1] = tostring(name)
			end

			table.sort(names)
			if #names == 0 then return "<none>" end

			local parts = {}
			for _, name in ipairs(names) do
				parts[#parts + 1] = name .. "=" .. formatDebugValue(attributes[name])
			end

			return table.concat(parts, ", ")
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

		local function getEnemyHealthObject(enemy)
			local main = getEnemyHealthBarMain(enemy)
			return main and main:FindFirstChild("Amount") or nil
		end

		local function hasDeadAttribute(instance)
			if not instance then return false end

			for _, attributeName in ipairs({"Dead", "IsDead", "Died", "Removed", "Remove"}) do
				if instance:GetAttribute(attributeName) == true then
					return true
				end
			end

			return false
		end

		local function getAttributeHealth(instance)
			if not instance then return nil end

			for _, attributeName in ipairs({"Health", "HP", "CurrentHealth", "CurrentHP"}) do
				local health = parseHealthNumber(instance:GetAttribute(attributeName))
				if health ~= nil then return health end
			end

			return nil
		end

		local function getServerEnemy(enemy)
			local _, serverFolder = getEnemyFolders()
			return enemy and serverFolder and serverFolder:FindFirstChild(enemy.Name) or nil
		end

		local function getEnemyAliveState(enemy, options)
			options = options or EMPTY_TABLE

			if not enemy or not enemy.Parent then return false, "missing-model" end
			if hasDeadAttribute(enemy) then return false, "client-dead-attribute" end

			local enemyRoot = getEnemyRoot(enemy)
			if not enemyRoot then return false, "missing-root" end

			local serverEnemy = getServerEnemy(enemy)
			if serverEnemy then
				if hasDeadAttribute(serverEnemy) then return false, "server-dead-attribute" end

				local serverHealth = getAttributeHealth(serverEnemy)
				if serverHealth ~= nil and serverHealth <= 0 then return false, "server-health-zero" end
				if serverHealth ~= nil and serverHealth > 0 then return true, "server-health-positive" end
			end

			local clientAttributeHealth = getAttributeHealth(enemy)
			if clientAttributeHealth ~= nil and clientAttributeHealth <= 0 then return false, "client-health-zero" end
			if clientAttributeHealth ~= nil and clientAttributeHealth > 0 then return true, "client-health-positive" end

			local healthObject = getEnemyHealthObject(enemy)
			local clientHealth = getEnemyClientHealth(enemy)
			if clientHealth ~= nil and clientHealth <= 0 then return false, "client-healthbar-zero" end
			if clientHealth ~= nil and clientHealth > 0 then return true, "client-healthbar-positive" end
			if healthObject then return false, "client-healthbar-unreadable" end

			if options.AllowUnknownHealth then return true, "unknown-health-allowed" end
			return false, "missing-healthbar"
		end

		local function isEnemyAlive(enemy, options)
			local alive = getEnemyAliveState(enemy, options)
			return alive == true
		end

		local function findClosestEnemy(matchFn, options)
			options = options or EMPTY_TABLE
			local enemyFolder = getEnemyFolders()
			if not enemyFolder then return nil end

			local characterRoot = getCharacterRoot()
			local closestEnemy = nil
			local closestDistance = nil

			for _, enemy in ipairs(enemyFolder:GetChildren()) do
				if matchFn == nil or matchFn(enemy) then
					local alive = options.IgnoreAlive == true or isEnemyAlive(enemy, options)
					if alive then
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

		local function describeEnemy(enemy, options)
			if not enemy then return "nil" end

			options = options or EMPTY_TABLE
			local alive, reason = getEnemyAliveState(enemy, options)
			local serverEnemy = getServerEnemy(enemy)
			local enemyRoot = getEnemyRoot(enemy)
			local characterRoot = getCharacterRoot()
			local distance = characterRoot and enemyRoot and (characterRoot.Position - enemyRoot.Position).Magnitude or nil

			local parts = {
				"Name=" .. tostring(getEnemyDisplayName(enemy)),
				"Model=" .. tostring(enemy.Name),
				"Alive=" .. tostring(alive),
				"Reason=" .. tostring(reason),
				"ClientHealth=" .. tostring(getEnemyClientHealth(enemy)),
				"ClientAttrHealth=" .. tostring(getAttributeHealth(enemy)),
				"ServerHealth=" .. tostring(getAttributeHealth(serverEnemy)),
				"HasHealthObject=" .. tostring(getEnemyHealthObject(enemy) ~= nil),
				"Distance=" .. (distance and string.format("%.2f", distance) or "nil"),
				"Root=" .. (enemyRoot and formatDebugValue(enemyRoot.Position) or "nil"),
				"Path=" .. enemy:GetFullName(),
			}

			if options.IncludeAttributes then
				parts[#parts + 1] = "Attrs={" .. buildAttributeSnapshot(enemy) .. "}"
				if serverEnemy then
					parts[#parts + 1] = "ServerAttrs={" .. buildAttributeSnapshot(serverEnemy) .. "}"
				end
			end

			return table.concat(parts, " | ")
		end

		local function getEnemyScanSummary(matchFn, options)
			options = options or EMPTY_TABLE
			local enemyFolder = getEnemyFolders()
			if not enemyFolder then return "enemy-folder-missing" end

			local total, matching, alive = 0, 0, 0
			local reasons = {}
			for _, enemy in ipairs(enemyFolder:GetChildren()) do
				total = total + 1
				if matchFn == nil or matchFn(enemy) then
					matching = matching + 1
					local isAlive, reason = getEnemyAliveState(enemy, options)
					if isAlive then
						alive = alive + 1
					else
						reasons[reason] = (reasons[reason] or 0) + 1
					end
				end
			end

			local reasonParts = {}
			for reason, count in pairs(reasons) do
				reasonParts[#reasonParts + 1] = tostring(reason) .. "=" .. tostring(count)
			end
			table.sort(reasonParts)

			return "total=" .. total .. ", matching=" .. matching .. ", alive=" .. alive .. ", rejects={" .. table.concat(reasonParts, ", ") .. "}"
		end
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

		local function isDungeonInstance()
			return ReplicatedStorage:GetAttribute("Dungeon") == true
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
			local character = player.Character
			local enemyRoot = getEnemyRoot(enemy)
			if not character or not enemyRoot then return end
			character:PivotTo(getClosestTeleportCFrame(enemyRoot, distance))
		end

		local function setFeatureTarget(feature, target)
			if feature.State.CurrentTarget == target then return end

			feature.State.CurrentTarget = target
			if target then teleportToEnemy(target, feature.State.TeleportDistance) end
		end

		local dungeonLabelToInfo = {}

		local function getLiveDungeonFolder()
			local main = Workspace:FindFirstChild("__Main")
			if not main then return nil end

			return main:FindFirstChild("__Dungeon") or main:FindFirstChild("Dungeon") or main:FindFirstChild("__Dungeon", true)
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

		local function isDungeonCandidate(instance, attrs)
			if not instance or not attrs then return false end

			local hasCoreInfo = attrs.Dungeon ~= nil or attrs.DungeonMap ~= nil or attrs.MapName ~= nil
			local hasIdentifier = attrs.ID ~= nil or attrs.DoubleID ~= nil or attrs._C ~= nil
			return hasCoreInfo and hasIdentifier
		end

		local function getLiveDungeonInfo(dungeonObject)
			if not dungeonObject then return nil end

			local attrs = getSafeAttributes(dungeonObject)
			if not isDungeonCandidate(dungeonObject, attrs) then return nil end

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
			local main = Workspace:FindFirstChild("__Main")

			local function addCandidate(dungeonObject)
				if not dungeonObject or seenInstances[dungeonObject] then return end
				seenInstances[dungeonObject] = true

				local info = getLiveDungeonInfo(dungeonObject)
				if not info or seenKeys[info.Key] then return end

				seenKeys[info.Key] = true
				entries[#entries + 1] = info
			end

			local function scanContainer(container)
				if not container then return end

				addCandidate(container)

				local okChildren, children = pcall(function()
					return container:GetChildren()
				end)
				if okChildren and type(children) == "table" then
					for _, child in ipairs(children) do
						addCandidate(child)
					end
				end

				local okDescendants, descendants = pcall(function()
					return container:GetDescendants()
				end)
				if okDescendants and type(descendants) == "table" then
					for _, descendant in ipairs(descendants) do
						addCandidate(descendant)
					end
				end
			end

			if folder then
				scanContainer(folder)
			elseif main then
				scanContainer(main)
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

		local function getChildCount(instance)
			if not instance then return 0 end
			local ok, children = pcall(function()
				return instance:GetChildren()
			end)
			return ok and #children or 0
		end

		local function buildDungeonRuntimeSnapshot()
			local enemyClientFolder, enemyServerFolder = getEnemyFolders()
			local dungeonFolder = getLiveDungeonFolder()
			local characterRoot = getCharacterRoot()

			return table.concat({
				"Player.InDungeon=" .. formatDebugValue(player:GetAttribute("InDungeon")),
				"Replicated.Dungeon=" .. formatDebugValue(ReplicatedStorage:GetAttribute("Dungeon")),
				"EnemyClientCount=" .. tostring(getChildCount(enemyClientFolder)),
				"EnemyServerCount=" .. tostring(getChildCount(enemyServerFolder)),
				"DungeonEntries=" .. tostring(getChildCount(dungeonFolder)),
				"CharacterRoot=" .. (characterRoot and formatDebugValue(characterRoot.Position) or "nil"),
			}, " | ")
		end

		local function dumpDebugSnapshot()
			debugLog("Snapshot", "PlayerAttrs: " .. buildAttributeSnapshot(player))
			debugLog("Snapshot", "ReplicatedAttrs: " .. buildAttributeSnapshot(ReplicatedStorage))
			debugLog("Snapshot", "DungeonState: " .. buildDungeonRuntimeSnapshot())
			debugLog("Snapshot", "AvailableDungeons: " .. tostring(#getLiveDungeonEntries()))
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
				Defaults = {AutoFarmEnemy = NO_ENEMY_OPTION, AutoFarm = false},
				State = {Running = false, LoopId = 0, PanelRef = nil, PollDelay = AUTO_FARM_POLL_DELAY, TeleportDistance = 7, CurrentTarget = nil},
				Options = {
					{ Id = "AutoFarmEnemy", Type = "select", Label = "Enemy", Description = "Select enemy to farm", Items = getAutoFarmEnemyItems },
					{ Id = "AutoFarm", Type = "toggle", Label = "Auto Farm", Description = "Teleports to the closest selected enemy and retargets on death" },
				}
			})

			function Feature:FindTarget(enemyName)
				return findClosestEnemy(function(enemy)
					return getEnemyDisplayName(enemy) == enemyName
				end)
			end

			function Feature:TargetMatches(target, enemyName)
				return target and target.Parent and getEnemyDisplayName(target) == enemyName
			end

			function Feature:SetTarget(target)
				setFeatureTarget(self, target)
			end

			function Feature:Tick(values)
				local enemyName = values and values.AutoFarmEnemy
				if enemyName == nil or enemyName == "" or enemyName == NO_ENEMY_OPTION then
					featureDebugLog(self, "AutoFarm", "Waiting for enemy selection")
					return
				end

				local target = self.State.CurrentTarget
				if not self:TargetMatches(target, enemyName) or not isEnemyAlive(target) then
					local selectedName = enemyName
					local newTarget = self:FindTarget(selectedName)
					if newTarget then
						featureDebugLog(self, "AutoFarm", "Target selected: " .. describeEnemy(newTarget))
					else
						featureDebugLog(self, "AutoFarm", "No alive target for " .. tostring(selectedName) .. " | " .. getEnemyScanSummary(function(enemy)
							return getEnemyDisplayName(enemy) == selectedName
						end))
					end
					self:SetTarget(newTarget)
				end
			end

			bindPollingToggleFeature(Feature, "AutoFarm", function(self, values)
				self:Tick(values)
			end, {
				RestartOnStart = true,
				UseLoopId = true,
				BeforeStop = function(self)
					self.State.CurrentTarget = nil
					self.State.LastDebugMessage = nil
				end,
				ExtraHandlers = {
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
				State = {Running = false, LoopId = 0, PanelRef = nil, PollDelay = AUTO_FARM_POLL_DELAY, TeleportDistance = 7, CurrentTarget = nil},
				Options = {
					{ Id = "AutoDungeon", Type = "toggle", Label = "Auto Dungeon", Description = "Teleports to the closest alive enemy only inside an active dungeon instance" },
				}
			})

			function Feature:FindTarget()
				return findClosestEnemy(nil, {AllowUnknownHealth = true})
			end

			function Feature:SetTarget(target)
				setFeatureTarget(self, target)
			end

			function Feature:Tick()
				if not isDungeonInstance() then
					self.State.CurrentTarget = nil
					featureDebugLog(self, "AutoDungeon", "Waiting for active dungeon instance | " .. buildDungeonRuntimeSnapshot())
					return
				end

				local target = self.State.CurrentTarget
				if not target or not target.Parent or not isEnemyAlive(target, {AllowUnknownHealth = true}) then
					local newTarget = self:FindTarget()
					if newTarget then
						featureDebugLog(self, "AutoDungeon", "Target selected: " .. describeEnemy(newTarget, {AllowUnknownHealth = true}))
					else
						featureDebugLog(self, "AutoDungeon", "No alive dungeon target | " .. getEnemyScanSummary(nil, {AllowUnknownHealth = true}) .. " | " .. buildDungeonRuntimeSnapshot())
					end
					self:SetTarget(newTarget)
				end
			end

			bindPollingToggleFeature(Feature, "AutoDungeon", function(self)
				self:Tick()
			end, {
				RestartOnStart = true,
				UseLoopId = true,
				BeforeStop = function(self)
					self.State.CurrentTarget = nil
					self.State.LastDebugMessage = nil
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

			function Feature:CreateDungeon(dungeonInfo)
				return sendDungeonAction("Create", buildDungeonActionPayload(nil, dungeonInfo))
			end

			function Feature:StartDungeon(dungeonInfo)
				return sendDungeonAction("Start", buildDungeonActionPayload(player.UserId, dungeonInfo))
			end

			function Feature:Run(panelRef)
				local values = setFeaturePanelRef(self, panelRef)
				if self.State.Starting then return end

				local dungeonInfo = getSelectedDungeonInfo(values and values.SelectedDungeon)
				if not dungeonInfo then return end

				self.State.Starting = true

				task.spawn(function()
					pcall(function()
						local ownDungeon = getOwnDungeonInfo()
						if not ownDungeon then
							self:CreateDungeon(dungeonInfo)
							task.wait(DUNGEON_CREATE_DELAY)
						end

						ownDungeon = getOwnDungeonInfo() or waitForOwnDungeonInfo(DUNGEON_INSTANCE_WAIT)
						if ownDungeon then
							self:StartDungeon(dungeonInfo)
						end
					end)
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
		-- FEATURE: DEBUG PLAYER ATTRIBUTES
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "DebugPlayerAttributes", Tab = "Debug", Section = "Attributes", Order = 10,
				Defaults = {DebugPlayerAttributes = false},
				State = {Running = false, PanelRef = nil, AttributeConnection = nil},
				Options = {
					{ Id = "DebugPlayerAttributes", Type = "toggle", Label = "Monitor Player Attributes", Description = "Logs LocalPlayer attribute changes to console" },
				}
			})

			bindConnectionToggleFeature(Feature, "DebugPlayerAttributes", function(self)
				debugLog("PlayerAttrs", "Initial: " .. buildAttributeSnapshot(player))
				self.State.AttributeConnection = player.AttributeChanged:Connect(function(attributeName)
					if not self.State.Running then return end
					debugLog("PlayerAttrs", tostring(attributeName) .. "=" .. formatDebugValue(player:GetAttribute(attributeName)))
				end)
			end, {
				RestartOnStart = true,
				BeforeStop = function(self)
					self.State.AttributeConnection = disconnectConnection(self.State.AttributeConnection)
				end,
			})
		end

		--==================================================
		-- FEATURE: DEBUG REPLICATED ATTRIBUTES
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "DebugReplicatedAttributes", Tab = "Debug", Section = "Attributes", Order = 20,
				Defaults = {DebugReplicatedAttributes = false},
				State = {Running = false, PanelRef = nil, AttributeConnection = nil},
				Options = {
					{ Id = "DebugReplicatedAttributes", Type = "toggle", Label = "Monitor Replicated Attributes", Description = "Logs ReplicatedStorage attribute changes to console" },
				}
			})

			bindConnectionToggleFeature(Feature, "DebugReplicatedAttributes", function(self)
				debugLog("ReplicatedAttrs", "Initial: " .. buildAttributeSnapshot(ReplicatedStorage))
				self.State.AttributeConnection = ReplicatedStorage.AttributeChanged:Connect(function(attributeName)
					if not self.State.Running then return end
					debugLog("ReplicatedAttrs", tostring(attributeName) .. "=" .. formatDebugValue(ReplicatedStorage:GetAttribute(attributeName)))
				end)
			end, {
				RestartOnStart = true,
				BeforeStop = function(self)
					self.State.AttributeConnection = disconnectConnection(self.State.AttributeConnection)
				end,
			})
		end

		--==================================================
		-- FEATURE: DEBUG DUNGEON STATE
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "DebugDungeonState", Tab = "Debug", Section = "Dungeon", Order = 30,
				Defaults = {DebugDungeonState = false},
				State = {Running = false, LoopId = 0, PanelRef = nil, PollDelay = DEBUG_POLL_DELAY, LastSnapshot = nil},
				Options = {
					{ Id = "DebugDungeonState", Type = "toggle", Label = "Monitor Dungeon State", Description = "Logs dungeon flags and enemy counts when they change" },
				}
			})

			bindPollingToggleFeature(Feature, "DebugDungeonState", function(self)
				local snapshot = buildDungeonRuntimeSnapshot()
				if self.State.LastSnapshot ~= snapshot then
					self.State.LastSnapshot = snapshot
					debugLog("DungeonState", snapshot)
				end
			end, {
				RestartOnStart = true,
				UseLoopId = true,
				BeforeStop = function(self)
					self.State.LastSnapshot = nil
				end,
			})
		end

		--==================================================
		-- FEATURE: DEBUG FARM TARGETING
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "DebugFarmTargeting", Tab = "Debug", Section = "Farm", Order = 40,
				Defaults = {DebugFarmTargeting = false},
				State = {PanelRef = nil},
				Options = {
					{ Id = "DebugFarmTargeting", Type = "toggle", Label = "Debug Farm Targeting", Description = "Logs Auto Farm and Auto Dungeon target decisions" },
				}
			})

			function Feature:GetHandlers()
				return {
					DebugFarmTargeting = function(value, _, panelRef)
						setFeaturePanelRef(self, panelRef)
						DebugFlags.Farm = value == true
						debugLog("FarmDebug", "Farm targeting debug " .. (DebugFlags.Farm and "enabled" or "disabled"))
					end,
				}
			end

			function Feature:Cleanup()
				DebugFlags.Farm = false
				self.State.PanelRef = nil
			end
		end

		--==================================================
		-- FEATURE: DEBUG CLOSEST ENEMY
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "DebugClosestEnemy", Tab = "Debug", Section = "Farm", Order = 50,
				Defaults = {DebugClosestEnemy = false},
				State = {Running = false, LoopId = 0, PanelRef = nil, PollDelay = DEBUG_POLL_DELAY, LastSnapshot = nil},
				Options = {
					{ Id = "DebugClosestEnemy", Type = "toggle", Label = "Monitor Closest Enemy", Description = "Logs closest enemy attributes, health, distance, and path when it changes" },
				}
			})

			bindPollingToggleFeature(Feature, "DebugClosestEnemy", function(self)
				local enemy = findClosestEnemy(nil, {IgnoreAlive = true})
				local snapshot = enemy and describeEnemy(enemy, {AllowUnknownHealth = true, IncludeAttributes = true}) or "nil"
				if self.State.LastSnapshot ~= snapshot then
					self.State.LastSnapshot = snapshot
					debugLog("ClosestEnemy", snapshot)
				end
			end, {
				RestartOnStart = true,
				UseLoopId = true,
				BeforeStop = function(self)
					self.State.LastSnapshot = nil
				end,
			})
		end

		--==================================================
		-- FEATURE: DEBUG SNAPSHOT
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "DebugSnapshot", Tab = "Debug", Section = "Tools", Order = 40,
				Defaults = {},
				Options = {
					{ Id = "DumpDebugSnapshot", Type = "button", Label = "Dump Snapshot", Description = "Prints current player, replicated, and dungeon state to console", ButtonText = "Dump" },
				}
			})

			function Feature:GetHandlers()
				return {
					DumpDebugSnapshot = function()
						dumpDebugSnapshot()
					end,
				}
			end
		end
	end
}
