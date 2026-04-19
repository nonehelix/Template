return {
	Load = function(Shared)
		local Workspace = Shared.Workspace
		local RegisterFeature = Shared.RegisterFeature
		local RegisterTabs = Shared.RegisterTabs

		local ReplicatedStorage = game:GetService("ReplicatedStorage")

		--==================================================
		-- TABS
		--==================================================

		RegisterTabs({
			{Name = "Auto Buy", Order = 20},
			{Name = "Shop", Order = 25},
		})

		--==================================================
		-- GAME REFERENCES
		--==================================================

		local CardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Card")
		local CardConfig = require(
			ReplicatedStorage:WaitForChild("Modules")
				:WaitForChild("Config")
				:WaitForChild("Core")
				:WaitForChild("CardConfig")
		)

		--==================================================
		-- LOCAL HELPERS
		--==================================================

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

		--==================================================
		-- FEATURE: AUTO BUY
		--==================================================

		do
			local Feature = RegisterFeature({
				Key = "AutoBuy",
				Tab = "Auto Buy",
				Order = 20,

				Defaults = {
					AutoBuyEnabled = false,
					AutoBuyPack = {},
					AutoBuyMutation = {},
				},

				State = {
					LastBuyTimes = {},
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

			function Feature:Start(panelRef)
				self.State.PanelRef = panelRef

				if self.State.Polling then
					return
				end

				self.State.Polling = true

				task.spawn(function()
					while self.State.Polling do
						local values = self.State.PanelRef and self.State.PanelRef.Config and self.State.PanelRef.Config.Values
						if values and values.AutoBuyEnabled then
							self:Tick(values)
						end
						task.wait(0.15)
					end
				end)
			end

			function Feature:Stop()
				self.State.Polling = false
			end

			function Feature:GetHandlers()
				return {
					AutoBuyEnabled = function(value, values, panelRef)
						if value then
							self:Start(panelRef)
						else
							self:Stop()
						end
					end,

					AutoBuyPack = function(_, _, panelRef)
						self.State.PanelRef = panelRef
					end,

					AutoBuyMutation = function(_, _, panelRef)
						self.State.PanelRef = panelRef
					end,
				}
			end
			
			function Feature:Cleanup()
				self:Stop()
				self.State.PanelRef = nil
				table.clear(self.State.LastBuyTimes)
			end
			--==================================================
		-- FEATURE: AUTO BUY MARKET (New Feature)
		--==================================================

		do
			local Feature = RegisterFeature({
				Key = "AutoBuyMarket",
				Tab = "Shop",
				Order = 10,

				Defaults = {
					AutoBuyMarketEnabled = false,
					AutoBuyMarketPack = {},
					AutoBuyMarketMutation = {},
				},

				State = {
					LastCheckTime = 0,
					PanelRef = nil,
				},

				Options = {
					{
						Id = "AutoBuyMarketEnabled",
						Type = "toggle",
						Label = "Enable Auto Buy Market",
						Description = "Automatically buys selected packs from the market every 60 seconds"
					},
					{
						Id = "AutoBuyMarketPack",
						Type = "multiselect",
						Label = "Pack ID",
						Description = "Choose packs to buy from market",
						Items = waitForItems(getPackItems, 2, {"All"}),
						EmptyText = "Nothing selected"
					},
					{
						Id = "AutoBuyMarketMutation",
						Type = "multiselect",
						Label = "Mutation",
						Description = "Choose mutations/rarities to buy",
						Items = waitForItems(getMutationItems, 3, {"All", "Regular"}),
						EmptyText = "Nothing selected"
					}
				}
			})

			-- Helper to read market stock from GUI
			function Feature:GetMarketStock()
				local stockGui = player:WaitForChild("PlayerGui"):FindFirstChild("Stock")
				if not stockGui then return {} end

				local frame = stockGui:FindFirstChild("Frame")
				if not frame then return {} end

				local scrolling = frame:FindFirstChild("ScrollingFrame")
				if not scrolling then return {} end

				local stockList = {}

				for i = 1, 8 do
					local slot = scrolling:FindFirstChild(tostring(i))
					if slot then
						local packLabel = slot:FindFirstChild("PackName")
						local mutationLabel = slot:FindFirstChild("Mutation")

						local packName = packLabel and packLabel.Text or ""
						local mutation = "Regular"

						if mutationLabel and mutationLabel.Visible and mutationLabel.Text ~= "" then
							mutation = mutationLabel.Text
						end

						if packName ~= "" then
							table.insert(stockList, {
								PackName = packName,
								Mutation = mutation,
								Slot = i
							})
						end
					end
				end

				return stockList
			end

			function Feature:Tick()
				local now = tick()
				if now - self.State.LastCheckTime < 60 then
					return -- Check only every 60 seconds
				end

				self.State.LastCheckTime = now

				local values = self.State.PanelRef and self.State.PanelRef.Config.Values
				if not values or not values.AutoBuyMarketEnabled then return end

				local selectedPacks = normalizeSelectionArray(values.AutoBuyMarketPack)
				local selectedMutations = normalizeSelectionArray(values.AutoBuyMarketMutation)

				if #selectedPacks == 0 or #selectedMutations == 0 then return end

				local marketStock = self:GetMarketStock()

				for _, item in ipairs(marketStock) do
					local packOk = arrayContains(selectedPacks, "All") or arrayContains(selectedPacks, item.PackName)
					local mutationOk = arrayContains(selectedMutations, "All") or arrayContains(selectedMutations, item.Mutation)

					if packOk and mutationOk then
						-- Fire buy event
						CardRemote:FireServer("BuyPack", item.PackName)
						print("[AutoBuyMarket] Bought from market:", item.PackName, "-", item.Mutation)
						task.wait(1.2) -- Small delay between buys to avoid rate limits
					end
				end
			end

			function Feature:Start(panelRef)
				self.State.PanelRef = panelRef

				task.spawn(function()
					while self.State.PanelRef and self.State.PanelRef.Config.Values.AutoBuyMarketEnabled do
						self:Tick()
						task.wait(5) -- Fast polling but actual check is throttled to 60s
					end
				end)
			end

			function Feature:Stop()
				-- Nothing extra needed, the loop checks the toggle
			end

			function Feature:GetHandlers()
				return {
					AutoBuyMarketEnabled = function(value, _, panelRef)
						self.State.PanelRef = panelRef
						if value then
							self:Start(panelRef)
						else
							self:Stop()
						end
					end,

					AutoBuyMarketPack = function(_, _, panelRef)
						self.State.PanelRef = panelRef
					end,

					AutoBuyMarketMutation = function(_, _, panelRef)
						self.State.PanelRef = panelRef
					end,
				}
			end

			function Feature:Cleanup()
				self.State.PanelRef = nil
			end
		end
	end
}
