return {
	Load = function(Shared)
		local RegisterFeature, RegisterTabs = Shared.RegisterFeature, Shared.RegisterTabs
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Players = game:GetService("Players")
		local player = Players.LocalPlayer

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

		local function isShadowReachMatch(name)
			local lowerName = string.lower(tostring(name or ""))
			return string.find(lowerName, "reach", 1, true) ~= nil
				or string.find(lowerName, "shadow", 1, true) ~= nil
		end

		local function isShadowReachSetCandidate(name)
			local lowerName = string.lower(tostring(name or ""))
			return string.find(lowerName, "reach", 1, true) ~= nil
				or (string.find(lowerName, "shadow", 1, true) ~= nil and (
					string.find(lowerName, "range", 1, true) ~= nil
					or string.find(lowerName, "distance", 1, true) ~= nil
				))
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
			value = tonumber(value)
			if not value then return end

			local count = 0
			visitPlayerData(function(label, instance)
				local attributes = getInstanceAttributes(instance)
				if not attributes then return end

				for name, currentValue in pairs(attributes) do
					if isShadowReachSetCandidate(name) and type(currentValue) == "number" then
						local ok, err = pcall(function()
							instance:SetAttribute(name, value)
						end)

						if ok then
							count = count + 1
							print(("[ShadowReach] Set %s.%s: %s -> %s"):format(label, tostring(name), tostring(currentValue), tostring(value)))
						else
							warn(("[ShadowReach] Failed to set %s.%s: %s"):format(label, tostring(name), tostring(err)))
						end
					end
				end
			end)

			if count == 0 then
				warn("[ShadowReach] No numeric reach/range attribute found. Run Scan Shadow Reach and send the output.")
			end
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
				},

				Options = {
					{ Id = "ShadowReach", Type = "number", Label = "Shadow Reach", Description = "Set Shadow Reach", Min = 0, Max = 100000 },
					{ Id = "ApplyShadowReach", Type = "button", Label = "Apply Shadow Reach", Description = "Apply Shadow Reach", ButtonText = "Apply" },
					{ Id = "ScanShadowReach", Type = "button", Label = "Scan Shadow Reach", Description = "Print Shadow Reach keys", ButtonText = "Scan" },
				}
			})

			function Feature:GetHandlers()
				return {
					ApplyShadowReach = function(_, values)
						setShadowReach(values.ShadowReach)
					end,
					ScanShadowReach = function()
						scanShadowReach()
					end,
				}
			end
		end
	end
}
