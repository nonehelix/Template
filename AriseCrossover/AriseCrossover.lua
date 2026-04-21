return {
	Load = function(Shared)
		local RegisterFeature, RegisterTabs = Shared.RegisterFeature, Shared.RegisterTabs
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Players = game:GetService("Players")
		local player = Players.LocalPlayer
		local shadowReachPatch = {
			GuiFunctions = nil,
			OriginalGetStatsBuff = nil,
			LastLevel = nil,
			LastMultiplier = nil,
		}

		--==================================================
		-- TABS
		--==================================================
		RegisterTabs({{Name = "Combat", Order = 20}})

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

		local function getPlayerStats()
			local leaderstats = player:WaitForChild("leaderstats", 10)
			return leaderstats and leaderstats:WaitForChild("PlayerStats", 10) or nil
		end

		local function setAutoAttack(enabled)
			local settings = getSettings()
			if settings then settings:SetAttribute("AutoAttack", enabled == true) end

			local passes = getPasses()
			if passes then passes:SetAttribute("AutoAttack", enabled == true) end
		end

		local function setAutoClick(enabled)
			local settings = getSettings()
			if settings then settings:SetAttribute("AutoClick", enabled == true) end

			local passes = getPasses()
			if passes then passes:SetAttribute("AutoClicker", enabled == true) end
		end

		local function getStatsInfo()
			local indexer = ReplicatedStorage:FindFirstChild("Indexer")
			local module = indexer and indexer:FindFirstChild("StatsInfo")
			if not module or not module:IsA("ModuleScript") then return nil end

			local ok, data = pcall(require, module)
			if ok then return data end

			warn("[ShadowReach] Failed to load StatsInfo: " .. tostring(data))
			return nil
		end

		local function getGuiFunctions()
			local sharedModules = ReplicatedStorage:FindFirstChild("SharedModules")
			local others = sharedModules and sharedModules:FindFirstChild("Others")
			local module = others and others:FindFirstChild("GuiFunctions")
			if not module or not module:IsA("ModuleScript") then return nil end

			local ok, data = pcall(require, module)
			if ok then return data end

			warn("[ShadowReach] Failed to load GuiFunctions: " .. tostring(data))
			return nil
		end

		local function getShadowReachMultiplier(level)
			local statsInfo = getStatsInfo()
			local shadowRange = statsInfo and statsInfo.Info and statsInfo.Info.ShadowRange
			local buff = shadowRange and tonumber(shadowRange.Buff) or 0.01
			return 1 + math.clamp(level, 0, 9999) * buff
		end

		local function patchShadowReachCalculator(multiplier)
			local guiFunctions = getGuiFunctions()
			if not guiFunctions or type(guiFunctions.GetStatsBuff) ~= "function" then
				warn("[ShadowReach] GuiFunctions.GetStatsBuff not found")
				return false
			end

			if shadowReachPatch.GuiFunctions ~= guiFunctions then
				shadowReachPatch.GuiFunctions = guiFunctions
				shadowReachPatch.OriginalGetStatsBuff = guiFunctions.GetStatsBuff
			end

			guiFunctions.GetStatsBuff = function(targetPlayer, statName)
				if targetPlayer == player and statName == "ShadowRange" then
					return multiplier
				end

				return shadowReachPatch.OriginalGetStatsBuff(targetPlayer, statName)
			end

			return true
		end

		local function isShadowReachMatch(name)
			local lowerName = string.lower(tostring(name or ""))
			return string.find(lowerName, "reach", 1, true) ~= nil
				or string.find(lowerName, "shadow", 1, true) ~= nil
		end

		local function getInstanceAttributes(instance)
			if typeof(instance) ~= "Instance" then return nil end

			local ok, attributes = pcall(function()
				return instance:GetAttributes()
			end)

			return ok and attributes or nil
		end

		local function visitPlayerData(callback)
			callback("Player", player)

			local settings = player:FindFirstChild("Settings")
			if settings then callback("Settings", settings) end

			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then return end

			callback("leaderstats", leaderstats)
			for _, descendant in ipairs(leaderstats:GetDescendants()) do
				callback(descendant:GetFullName(), descendant)
			end
		end

		local function scanAttributes(label, instance)
			local count = 0
			local attributes = getInstanceAttributes(instance)
			if not attributes then return count end

			for name, value in pairs(attributes) do
				if isShadowReachMatch(name) then
					count = count + 1
					print(("[ShadowReach] %s.%s = %s"):format(label, tostring(name), tostring(value)))
				end
			end

			return count
		end

		local function scanTable(label, data, depth, seen)
			if type(data) ~= "table" or depth > 5 then return 0 end

			seen = seen or {}
			if seen[data] then return 0 end
			seen[data] = true

			local count = 0
			for key, value in pairs(data) do
				local path = label .. "." .. tostring(key)
				if isShadowReachMatch(key) then
					count = count + 1
					print(("[ShadowReach] %s = %s"):format(path, type(value) == "table" and "<table>" or tostring(value)))
				end

				if type(value) == "table" then
					count = count + scanTable(path, value, depth + 1, seen)
				end
			end

			return count
		end

		local function scanIndexerModule(moduleName)
			local indexer = ReplicatedStorage:FindFirstChild("Indexer")
			local module = indexer and indexer:FindFirstChild(moduleName)
			if not module or not module:IsA("ModuleScript") then return 0 end

			local ok, data = pcall(require, module)
			if not ok then
				warn("[ShadowReach] Failed to scan " .. moduleName .. ": " .. tostring(data))
				return 0
			end

			return scanTable("Indexer." .. moduleName, data, 0)
		end

		local function scanShadowReach()
			local count = 0
			print("[ShadowReach] Scan started")

			visitPlayerData(function(label, instance)
				count = count + scanAttributes(label, instance)
			end)

			for _, moduleName in ipairs({ "StatsInfo", "Upgrades", "Talents", "ShadowTier", "BalanceInfo" }) do
				count = count + scanIndexerModule(moduleName)
			end

			print(("[ShadowReach] Scan finished. Matches: %d"):format(count))
		end

		local function setShadowReach(value)
			local level = math.clamp(tonumber(value) or 0, 0, 9999)

			local playerStats = getPlayerStats()
			if not playerStats then
				warn("[ShadowReach] PlayerStats not found")
				return
			end

			local currentValue = playerStats:GetAttribute("ShadowRange")
			if currentValue ~= level then
				local ok, err = pcall(function()
					playerStats:SetAttribute("ShadowRange", level)
				end)

				if not ok then
					warn("[ShadowReach] Failed to set ShadowRange: " .. tostring(err))
				end
			end

			local multiplier = getShadowReachMultiplier(level)
			local patched = patchShadowReachCalculator(multiplier)

			if patched and (shadowReachPatch.LastLevel ~= level or shadowReachPatch.LastMultiplier ~= multiplier) then
				shadowReachPatch.LastLevel = level
				shadowReachPatch.LastMultiplier = multiplier
				print(("[ShadowReach] ShadowRange level %s -> %s | multiplier %.2fx"):format(tostring(currentValue), tostring(level), multiplier))
			end

			return patched
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
		-- FEATURE: SHADOW REACH
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "ShadowReach",
				Tab = "Combat",
				Section = "Shadow",
				Order = 30,

				Defaults = {
					ShadowReach = 100,
					ForceShadowReach = false,
				},

				State = {
					Running = false,
					LoopId = 0,
					PollDelay = 0.5,
				},

				Options = {
					{ Id = "ShadowReach", Type = "number", Label = "Shadow Reach", Description = "Set Shadow Reach", Min = 0, Max = 100000 },
					{ Id = "ForceShadowReach", Type = "toggle", Label = "Force Shadow Reach", Description = "Keeps Shadow Reach applied" },
					{ Id = "ApplyShadowReach", Type = "button", Label = "Apply Shadow Reach", Description = "Apply Shadow Reach", ButtonText = "Apply" },
					{ Id = "ScanShadowReach", Type = "button", Label = "Scan Shadow Reach", Description = "Print Shadow Reach keys", ButtonText = "Scan" },
				}
			})

			function Feature:Start(values)
				self:Stop()

				self.State.Running = true
				self.State.LoopId = self.State.LoopId + 1
				local id = self.State.LoopId

				task.spawn(function()
					while self.State.Running and self.State.LoopId == id do
						if not values or not values.ForceShadowReach then break end
						setShadowReach(values.ShadowReach)
						task.wait(self.State.PollDelay)
					end
				end)
			end

			function Feature:Stop()
				self.State.Running = false
				self.State.LoopId = self.State.LoopId + 1
			end

			function Feature:GetHandlers()
				return {
					ShadowReach = function(value, values)
						if values and values.ForceShadowReach then setShadowReach(value) end
					end,
					ForceShadowReach = function(value, values)
						if value then self:Start(values) else self:Stop() end
					end,
					ApplyShadowReach = function(_, values)
						setShadowReach(values and values.ShadowReach)
					end,
					ScanShadowReach = function()
						scanShadowReach()
					end,
				}
			end

			function Feature:Cleanup()
				self:Stop()
			end
		end
	end
}
