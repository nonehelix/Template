return {
	Load = function(Shared)
		local RegisterFeature, RegisterTabs = Shared.RegisterFeature, Shared.RegisterTabs
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
	end
}
