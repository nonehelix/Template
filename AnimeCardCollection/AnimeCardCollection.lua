return {
	Load = function(Shared)
		local Workspace = Shared.Workspace
		local RegisterFeature = Shared.RegisterFeature
		local RegisterTabs = Shared.RegisterTabs

		local Players = game:GetService("Players")
		local ReplicatedStorage = game:GetService("ReplicatedStorage")

		RegisterTabs({
			{Name = "Auto Buy", Order = 20},
		})

		local LocalPlayer = Players.LocalPlayer
		local CardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Card")
		local StockRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Stock")
		local CardConfig = require(
			ReplicatedStorage:WaitForChild("Modules")
				:WaitForChild("Config")
				:WaitForChild("Core")
				:WaitForChild("CardConfig")
		)

		local DEBUG_MARKET = true

		local function debugLog(...)
			if DEBUG_MARKET then
				print("[AutoMarketBuy]", ...)
			end
		end

		local function arrayContains(arr, target)
			for _, v in ipairs(arr or {}) do
				if tostring(v) == tostring(target) then
					return true
				end
			end
			return false
		end

		local function normalizeSelectionArray(values)
			local result = {}

			if type(values) ~= "table" then
				return result
			end

			for _, value in ipairs(values) do
				result[#result + 1] = tostring(value)
			end

			return result
		end

		local function getPackItems()
			local items = {"All"}

			if CardConfig and CardConfig.List and CardConfig.List.Packs then
				for _, packName in pairs(CardConfig.List.Packs) do
					items[#items + 1] = tostring(packName)
				end
			end

			return items
		end

		local function getMutationItems()
			local items = {"All", "Regular"}

			if CardConfig and CardConfig.List and CardConfig.List.Mutations then
				for _, mutationName in pairs(CardConfig.List.Mutations) do
					items[#items + 1] = tostring(mutationName)
				end
			end

			return items
		end

		local function trimPackLabel(text)
			if type(text) ~= "string" then
				return nil
			end

			local cleaned = text:gsub("%s+[Pp]ack$", "")
			cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", "")

			if cleaned == "" then
				return nil
			end

			return cleaned
		end

		local function waitForItems(builder, minimumCount, fallback, timeout)
			timeout = timeout or 5
			local startTime = tick()

			while tick() - startTime < timeout do
				local items = builder()
				if #items >= minimumCount then
					return items
				end
				task.wait(0.1)
			end

			return fallback
		end

		do
			local Feature = RegisterFeature({
				Key = "AutoBuy",
				Tab = "Auto Buy",
				Order = 20,

				Defaults = {
					AutoBuyEnabled = false,
					AutoBuyPack = {},
					AutoBuyMutation = {},

					AutoMarketBuyEnabled = false,
					AutoMarketBuyPack = {},
					AutoMarketBuyMutation = {},
				},

				State = {
					LastBuyTimes = {},
					LastMarketBuyTimes = {},
					Polling = false,
					PanelRef = nil,
				},

				Options = {
					{
						Id = "AutoBuyEnabled",
						Type = "toggle",
						Label = "Enable Auto Buy",
						Description = "Auto buys matching conveyor packs"
					},
					{
						Id = "AutoBuyPack",
						Type = "multiselect",
						Label = "Pack ID",
						Description = "Choose one or more packs",
						Items = waitForItems(getPackItems, 2, {"All"}),
						EmptyText = "Nothing selected"
					},
					{
						Id = "AutoBuyMutation",
						Type = "multiselect",
						Label = "Mutation",
						Description = "Choose one or more rarities",
						Items = waitForItems(getMutationItems, 3, {"All", "Regular"}),
						EmptyText = "Nothing selected"
					},
					{
						Id = "AutoMarketBuyEnabled",
						Type = "toggle",
						Label = "Enable Auto Market Buy",
						Description = "Auto buys matching market packs"
					},
					{
						Id = "AutoMarketBuyPack",
						Type = "multiselect",
						Label = "Market Pack ID",
						Description = "Choose one or more market packs",
						Items = waitForItems(getPackItems, 2, {"All"}),
						EmptyText = "Nothing selected"
					},
					{
						Id = "AutoMarketBuyMutation",
						Type = "multiselect",
						Label = "Market Mutation",
						Description = "Choose one or more market rarities",
						Items = waitForItems(getMutationItems, 3, {"All", "Regular"}),
						EmptyText = "Nothing selected"
					}
				}
			})

			function Feature:GetPackModelType(packModel)
				if not packModel then
					return nil
				end

				if packModel.PrimaryPart and packModel.PrimaryPart.Name ~= "" then
					return packModel.PrimaryPart.Name
				end

				local primary = packModel:FindFirstChildWhichIsA("BasePart")
				if primary and primary.Name ~= "" then
					return primary.Name
				end

				return nil
			end

			function Feature:GetPackModelMutation(packModel)
				if not packModel then
					return "Regular"
				end

				for _, descendant in ipairs(packModel:GetDescendants()) do
					if descendant:IsA("TextLabel") and descendant.Name == "Mutation" then
						if descendant.Visible and descendant.Text ~= "" then
							return tostring(descendant.Text)
						end
					end
				end

				return "Regular"
			end

			function Feature:GetPackModelId(packModel)
				if not packModel then
					return nil
				end

				if packModel.Name ~= "" then
					return packModel.Name
				end

				return nil
			end

			function Feature:GetStockFrame()
				local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
				if not playerGui then
					debugLog("PlayerGui not found")
					return nil
				end

				local stockGui = playerGui:FindFirstChild("Stock")
				if not stockGui then
					debugLog("Stock gui not found under PlayerGui")
					return nil
				end

				local scrollingFrame = stockGui:FindFirstChild("ScrollingFrame", true)
				if not scrollingFrame then
					debugLog("ScrollingFrame not found under Stock gui")
					return nil
				end

				debugLog("Found stock frame:", scrollingFrame:GetFullName())
				return scrollingFrame
			end

			function Feature:GetMarketSlotPack(slot)
				local stockLabel = slot and slot:FindFirstChild("Stock")
				if not stockLabel then
					debugLog("Slot missing Stock label:", slot and slot.Name)
					return nil
				end

				local rawText = tostring(stockLabel.Text or "")
				local packName = trimPackLabel(rawText)

				debugLog("Slot", slot.Name, "raw stock text =", rawText, "parsed pack =", tostring(packName))
				return packName
			end

			function Feature:GetMarketSlotMutation(slot)
				local mutationLabel = slot and slot:FindFirstChild("Mutation")
				if not mutationLabel then
					debugLog("Slot", slot and slot.Name, "missing Mutation label, using Regular")
					return "Regular"
				end

				local mutationText = tostring(mutationLabel.Text or "")
				local visible = mutationLabel.Visible == true

				if not visible or mutationText == "" then
					debugLog("Slot", slot.Name, "mutation hidden/empty, using Regular")
					return "Regular"
				end

				debugLog("Slot", slot.Name, "mutation =", mutationText)
				return mutationText
			end

			function Feature:GetMarketBuyName(packName, mutation)
				if not packName or packName == "" then
					return nil
				end

				if not mutation or mutation == "Regular" then
					return packName
				end

				return string.format("%s-%s", packName, mutation)
			end

			function Feature:Matches(packType, mutation, selectedPacks, selectedMutations)
				if not packType or packType == "" then
					return false
				end
				if type(selectedPacks) ~= "table" or #selectedPacks == 0 then
					return false
				end
				if type(selectedMutations) ~= "table" or #selectedMutations == 0 then
					return false
				end

				local packOk = arrayContains(selectedPacks, "All") or arrayContains(selectedPacks, packType)
				local mutationOk = arrayContains(selectedMutations, "All") or arrayContains(selectedMutations, mutation)

				return packOk and mutationOk
			end

			function Feature:Tick(values)
				if not values.AutoBuyEnabled then
					return
				end

				local selectedPacks = normalizeSelectionArray(values.AutoBuyPack)
				local selectedMutations = normalizeSelectionArray(values.AutoBuyMutation)

				if #selectedPacks == 0 or #selectedMutations == 0 then
					return
				end

				local clientFolder = Workspace:FindFirstChild("Client")
				if not clientFolder then
					return
				end

				local packsFolder = clientFolder:FindFirstChild("Packs")
				if not packsFolder then
					return
				end

				local now = tick()

				for _, child in ipairs(packsFolder:GetChildren()) do
					if child:IsA("Model") then
						local packId = self:GetPackModelId(child)
						local packType = self:GetPackModelType(child)
						local mutation = self:GetPackModelMutation(child)

						if packId and packType and self:Matches(packType, mutation, selectedPacks, selectedMutations) then
							local lastTime = self.State.LastBuyTimes[packId]
							if not lastTime or (now - lastTime) > 1 then
								self.State.LastBuyTimes[packId] = now
								CardRemote:FireServer("BuyPack", packId)
							end
						end
					end
				end
			end

			function Feature:TickMarket(values)
				if not values.AutoMarketBuyEnabled then
					return
				end

				local selectedPacks = normalizeSelectionArray(values.AutoMarketBuyPack)
				local selectedMutations = normalizeSelectionArray(values.AutoMarketBuyMutation)

				if #selectedPacks == 0 or #selectedMutations == 0 then
					debugLog("No market selections set")
					return
				end

				debugLog("Selected packs:", table.concat(selectedPacks, ", "))
				debugLog("Selected mutations:", table.concat(selectedMutations, ", "))

				local scrollingFrame = self:GetStockFrame()
				if not scrollingFrame then
					return
				end

				local now = tick()
				local sawAnyFrames = false

				for _, slot in ipairs(scrollingFrame:GetChildren()) do
					if slot:IsA("Frame") then
						sawAnyFrames = true

						local packName = self:GetMarketSlotPack(slot)
						local mutation = self:GetMarketSlotMutation(slot)
						local buyName = self:GetMarketBuyName(packName, mutation)
						local matches = packName and self:Matches(packName, mutation, selectedPacks, selectedMutations) or false

						debugLog(
							"Slot", slot.Name,
							"pack =", tostring(packName),
							"mutation =", tostring(mutation),
							"buyName =", tostring(buyName),
							"matches =", tostring(matches)
						)

						if matches and buyName then
							local lastTime = self.State.LastMarketBuyTimes[buyName]
							if not lastTime or (now - lastTime) > 1 then
								self.State.LastMarketBuyTimes[buyName] = now
								debugLog("Firing Stock remote:", "Buy", buyName)
								StockRemote:FireServer("Buy", buyName)
							else
								debugLog("Skipped by cooldown:", buyName, "elapsed =", now - lastTime)
							end
						end
					end
				end

				if not sawAnyFrames then
					debugLog("No Frame children found inside stock scrolling frame")
				end
			end

			function Feature:Start(panelRef)
				self.State.PanelRef = panelRef

				if self.State.Polling then
					debugLog("Polling already running")
					return
				end

				debugLog("Starting polling")
				self.State.Polling = true

				task.spawn(function()
					while self.State.Polling do
						local values = self.State.PanelRef and self.State.PanelRef.Config and self.State.PanelRef.Config.Values
						if values then
							if values.AutoBuyEnabled then
								self:Tick(values)
							end

							if values.AutoMarketBuyEnabled then
								self:TickMarket(values)
							end
						else
							debugLog("Panel values not available yet")
						end
						task.wait(0.15)
					end
					debugLog("Polling stopped")
				end)
			end

			function Feature:Stop()
				debugLog("Stopping polling")
				self.State.Polling = false
			end

			function Feature:GetHandlers()
				return {
					AutoBuyEnabled = function(value, values, panelRef)
						if value then
							self:Start(panelRef)
						else
							if not values.AutoMarketBuyEnabled then
								self:Stop()
							else
								self.State.PanelRef = panelRef
							end
						end
					end,

					AutoBuyPack = function(_, _, panelRef)
						self.State.PanelRef = panelRef
					end,

					AutoBuyMutation = function(_, _, panelRef)
						self.State.PanelRef = panelRef
					end,

					AutoMarketBuyEnabled = function(value, values, panelRef)
						debugLog("AutoMarketBuyEnabled changed to", tostring(value))
						if value then
							self:Start(panelRef)
						else
							if not values.AutoBuyEnabled then
								self:Stop()
							else
								self.State.PanelRef = panelRef
							end
						end
					end,

					AutoMarketBuyPack = function(value, _, panelRef)
						self.State.PanelRef = panelRef
						debugLog("AutoMarketBuyPack changed")
						if type(value) == "table" then
							debugLog("New market pack selection:", table.concat(normalizeSelectionArray(value), ", "))
						end
					end,

					AutoMarketBuyMutation = function(value, _, panelRef)
						self.State.PanelRef = panelRef
						debugLog("AutoMarketBuyMutation changed")
						if type(value) == "table" then
							debugLog("New market mutation selection:", table.concat(normalizeSelectionArray(value), ", "))
						end
					end,
				}
			end

			function Feature:Cleanup()
				self:Stop()
				self.State.PanelRef = nil
				table.clear(self.State.LastBuyTimes)
				table.clear(self.State.LastMarketBuyTimes)
			end
		end
	end
}
