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

		local function getPlayerStats()
			local leaderstats = player:WaitForChild("leaderstats", 10)
			return leaderstats and leaderstats:WaitForChild("PlayerStats", 10) or nil
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

		local function getShadowSpeedBuff()
			local indexer = ReplicatedStorage:FindFirstChild("Indexer")
			local module = indexer and indexer:FindFirstChild("StatsInfo")
			if not module or not module:IsA("ModuleScript") then return 0.02 end

			local ok, statsInfo = pcall(require, module)
			local shadowSpeed = ok and type(statsInfo) == "table" and statsInfo.Info and statsInfo.Info.ShadowSpeed
			local buff = shadowSpeed and tonumber(shadowSpeed.Buff) or 0.02
			return buff > 0 and buff or 0.02
		end

		local function setShadowSpeedMultiplier(multiplier)
			multiplier = math.max(tonumber(multiplier) or 1, 1)

			local playerStats = getPlayerStats()
			if not playerStats then
				warn("[ShadowSpeed] PlayerStats not found")
				return
			end

			local buff = getShadowSpeedBuff()
			local level = math.floor(((multiplier - 1) / buff) + 0.5)
			playerStats:SetAttribute("ShadowSpeed", level)
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
		-- FEATURE: SHADOW SPEED
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "ShadowSpeed",
				Tab = "Combat",
				Section = "Shadow",
				Order = 30,

				Defaults = {
					ShadowSpeedMultiplier = 2,
					ForceShadowSpeed = false,
				},

				State = {
					Running = false,
					LoopId = 0,
					PollDelay = 0.5,
				},

				Options = {
					{ Id = "ShadowSpeedMultiplier", Type = "number", Label = "Shadow Speed", Description = "Set shadow speed multiplier", Min = 1, Max = 100 },
					{ Id = "ForceShadowSpeed", Type = "toggle", Label = "Force Shadow Speed", Description = "Keeps shadow speed applied" },
					{ Id = "ApplyShadowSpeed", Type = "button", Label = "Apply Shadow Speed", Description = "Apply shadow speed", ButtonText = "Apply" },
				}
			})

			function Feature:Start(values)
				self:Stop()

				self.State.Running = true
				self.State.LoopId = self.State.LoopId + 1
				local id = self.State.LoopId

				task.spawn(function()
					while self.State.Running and self.State.LoopId == id do
						if not values or not values.ForceShadowSpeed then break end
						setShadowSpeedMultiplier(values.ShadowSpeedMultiplier)
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
					ShadowSpeedMultiplier = function(value, values)
						if values and values.ForceShadowSpeed then setShadowSpeedMultiplier(value) end
					end,
					ForceShadowSpeed = function(value, values)
						if value then self:Start(values) else self:Stop() end
					end,
					ApplyShadowSpeed = function(_, values)
						setShadowSpeedMultiplier(values and values.ShadowSpeedMultiplier)
					end,
				}
			end

			function Feature:Cleanup()
				self:Stop()
			end
		end
	end
}
