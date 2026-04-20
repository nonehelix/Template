return {
	Load = function(Shared)
		local Workspace = Shared.Workspace
		local RegisterFeature = Shared.RegisterFeature
		local RegisterTabs = Shared.RegisterTabs

		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Players = game:GetService("Players")

		local player = Players.LocalPlayer

		--==================================================
		-- TABS
		--==================================================
		RegisterTabs({
			{Name = "Card", Order = 20},
			{Name = "Shop", Order = 25},
		})

		--==================================================
		-- GAME REFERENCES
		--==================================================
		local Remotes = ReplicatedStorage:WaitForChild("Remotes")
		local CardRemote = Remotes:WaitForChild("Card")
		local StockRemote = Remotes:WaitForChild("Stock")
		local GradeRemote = Remotes:WaitForChild("Grade")

		local CardConfig = require(
			ReplicatedStorage:WaitForChild("Modules")
				:WaitForChild("Config")
				:WaitForChild("Core")
				:WaitForChild("CardConfig")
		)

		local GradesConfig = require(
			ReplicatedStorage:WaitForChild("Modules")
				:WaitForChild("Config")
				:WaitForChild("Core")
				:WaitForChild("Grades")
		)

		--==================================================
		-- HELPERS
		--==================================================
		local function arrayContains(arr, target)
			for _, value in ipairs(arr or {}) do
				if value == target then
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

		local function normalizePackName(name)
			name = tostring(name or "")
			name = name:gsub("%s+", " ")
			name = name:gsub("^%s+", "")
			name = name:gsub("%s+$", "")
			name = name:gsub("%s+[Pp]ack$", "")
			return name
		end

		local function buildRemotePackId(packName, mutation)
			local base = normalizePackName(packName)
			if base == "" then
				return nil
			end

			if not mutation or mutation == "" or mutation == "Regular" then
				return base
			end

			return base .. "-" .. tostring(mutation)
		end

		local function parseStockAmount(text)
			return tonumber(string.match(tostring(text or ""), "%d+")) or 0
		end

		local function buildListItems(baseItems, sourceList)
			local items = {}
			for _, value in ipairs(baseItems or {}) do
				items[#items + 1] = tostring(value)
			end

			for _, value in pairs(sourceList or {}) do
				items[#items + 1] = tostring(value)
			end

			return items
		end

		local function getPackItems()
			return buildListItems({"All"}, CardConfig and CardConfig.List and CardConfig.List.Packs)
		end

		local function getMutationItems()
			return buildListItems({"All", "Regular"}, CardConfig and CardConfig.List and CardConfig.List.Mutations)
		end

		local function getGradeItems()
			if GradesConfig and GradesConfig.List then
				return buildListItems({}, GradesConfig.List)
			end

			return {"F", "E", "D", "C", "B", "A", "S", "S+", "SS", "SR", "UR"}
		end

		local function getAllCardNames()
			local seen = {}
			local cards = {}

			if CardConfig and CardConfig.Packs then
				for _, packData in pairs(CardConfig.Packs) do
					if packData.List then
						for cardName in pairs(packData.List) do
							cardName = tostring(cardName)
							if not seen[cardName] then
								seen[cardName] = true
								cards[#cards + 1] = cardName
							end
						end
					end
				end
			end

			table.sort(cards)

			local items = {"All"}
			for _, cardName in ipairs(cards) do
				items[#items + 1] = cardName
			end

			return items
		end

		local function getStockScrollingFrame()
			local playerGui = player:FindFirstChild("PlayerGui")
			local stockGui = playerGui and playerGui:FindFirstChild("Stock")
			local frame = stockGui and stockGui:FindFirstChild("Frame")
			return frame and frame:FindFirstChild("ScrollingFrame")
		end

		local function selectionMatches(packName, mutation, selectedPacks, selectedMutations)
			local packOk = arrayContains(selectedPacks, "All") or arrayContains(selectedPacks, packName)
			local mutationOk = arrayContains(selectedMutations, "All") or arrayContains(selectedMutations, mutation)
			return packOk and mutationOk
		end

		local function waitForItems(builder, minCount, fallback, timeout)
			timeout = timeout or 5
			local startTime = os.clock()

			while os.clock() - startTime < timeout do
				local items = builder()
				if #items >= minCount then
					return items
				end
				task.wait(0.1)
			end

			return fallback
		end

		--==================================================
		-- FEATURE: AUTO BUY (CONVEYOR)
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "AutoBuy",
				Tab = "Card",
				Order = 10,

				Defaults = {
					AutoBuyEnabled = false,
					AutoBuyPack = {},
					AutoBuyMutation = {},
				},

				State = {
					Polling = false,
					PanelRef = nil,
					LastBuyTimes = {},
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
				}
			})

			function Feature:GetValues()
				local panel = self.State.PanelRef
				return panel and panel.Config and panel.Config.Values or nil
			end

			function Feature:GetPackModelType(packModel)
				if not packModel then
					return nil
				end

				if packModel.PrimaryPart and packModel.PrimaryPart.Name ~= "" then
					return packModel.PrimaryPart.Name
				end

				local part = packModel:FindFirstChildWhichIsA("BasePart")
				return part and part.Name ~= "" and part.Name or nil
			end

			function Feature:GetPackModelMutation(packModel)
				if not packModel then
					return "Regular"
				end

				for _, descendant in ipairs(packModel:GetDescendants()) do
					if descendant:IsA("TextLabel") and descendant.Name == "Mutation" and descendant.Visible and descendant.Text ~= "" then
						return tostring(descendant.Text)
					end
				end

				return "Regular"
			end

			function Feature:GetPackModelId(packModel)
				return packModel and packModel.Name ~= "" and packModel.Name or nil
			end

			function Feature:Tick(values)
				if not values or not values.AutoBuyEnabled then
					return
				end

				local selectedPacks = normalizeSelectionArray(values.AutoBuyPack)
				local selectedMutations = normalizeSelectionArray(values.AutoBuyMutation)

				if #selectedPacks == 0 or #selectedMutations == 0 then
					return
				end

				local clientFolder = Workspace:FindFirstChild("Client")
				local packsFolder = clientFolder and clientFolder:FindFirstChild("Packs")
				if not packsFolder then
					return
				end

				local now = tick()

				for _, child in ipairs(packsFolder:GetChildren()) do
					if child:IsA("Model") then
						local packId = self:GetPackModelId(child)
						local packType = self:GetPackModelType(child)
						local mutation = self:GetPackModelMutation(child)

						if packId and packType and selectionMatches(packType, mutation, selectedPacks, selectedMutations) then
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
						local values = self:GetValues()
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
					AutoBuyEnabled = function(value, _, panelRef)
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
		end

		--==================================================
		-- FEATURE: AUTO GRADE
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "AutoGrade",
				Tab = "Card",
				Order = 15,
		
				Defaults = {
					AutoGradeEnabled = false,
					AutoGradeCards = {},
					AutoGradeTarget = {},
				},
		
				State = {
					Running = false,
					PanelRef = nil,
					Queue = {},
					QueueIndex = 0,
					TargetDone = {},
					TargetMinRank = nil,
					ReplicatedData = nil,
				},
		
				Options = {
					{
						Id = "AutoGradeEnabled",
						Type = "toggle",
						Label = "Enable Auto Grade",
						Description = "Automatically grades selected cards to target grade(s)"
					},
					{
						Id = "AutoGradeCards",
						Type = "multiselect",
						Label = "Cards",
						Description = "Choose owned cards",
						Items = waitForItems(getAllCardNames, 2, {"All"}),
						EmptyText = "Nothing selected"
					},
					{
						Id = "AutoGradeTarget",
						Type = "multiselect",
						Label = "Grades",
						Description = "Target grades",
						Items = getGradeItems(),
						EmptyText = "Nothing selected"
					},
				}
			})
		
			local GradeRankMap = {}
			if GradesConfig and GradesConfig.List then
				for index, gradeName in ipairs(GradesConfig.List) do
					GradeRankMap[tostring(gradeName)] = index
				end
			end
		
			function Feature:GetValues()
				local panel = self.State.PanelRef
				return panel and panel.Config and panel.Config.Values or nil
			end
		
			function Feature:GetReplicatedData()
				if self.State.ReplicatedData then
					return self.State.ReplicatedData
				end
		
				local module = ReplicatedFirst:FindFirstChild("ReplicatedData")
				if not module then
					return nil
				end
		
				local ok, result = pcall(require, module)
				if ok and type(result) == "table" and type(result.GetData) == "function" then
					self.State.ReplicatedData = result
					return result
				end
		
				return nil
			end
		
			function Feature:GetOwnedCardsTable()
				local replicatedData = self:GetReplicatedData()
				if not replicatedData then
					return {}
				end
		
				local ok, cards = pcall(function()
					return replicatedData.GetData("Cards")
				end)
		
				return (ok and type(cards) == "table") and cards or {}
			end
		
			function Feature:GetServerAutoGrades()
				local replicatedData = self:GetReplicatedData()
				if not replicatedData then
					return {}
				end
		
				local ok, autoGrades = pcall(function()
					return replicatedData.GetData("AutoGrades")
				end)
		
				return (ok and type(autoGrades) == "table") and autoGrades or {}
			end
		
			function Feature:GetGradeRank(gradeName)
				if not gradeName then
					return 0
				end
				return GradeRankMap[tostring(gradeName)] or 0
			end
		
			function Feature:GetCardCurrentGrade(ownedCards, cardId)
				local cardData = ownedCards[cardId]
				if type(cardData) ~= "table" then
					return nil
				end
				return cardData.Grade
			end
		
			function Feature:GetTargetMinRank(selectedGrades)
				local minRank = nil
		
				for _, gradeName in ipairs(selectedGrades or {}) do
					local rank = self:GetGradeRank(gradeName)
					if rank > 0 and (minRank == nil or rank < minRank) then
						minRank = rank
					end
				end
		
				return minRank
			end
		
			function Feature:CardMeetsOrBeatsTarget(ownedCards, cardId, targetMinRank)
				local currentRank = self:GetGradeRank(self:GetCardCurrentGrade(ownedCards, cardId))
				return currentRank >= (targetMinRank or math.huge)
			end
		
			function Feature:CurrentCardNeedsConfirm(ownedCards, cardId)
				local currentGrade = self:GetCardCurrentGrade(ownedCards, cardId)
				if not currentGrade then
					return false
				end
				return arrayContains(self:GetServerAutoGrades(), tostring(currentGrade))
			end
		
			function Feature:BuildQueue(selectedCards, ownedCards)
				local queue = {}
		
				if arrayContains(selectedCards, "All") then
					for cardId in pairs(ownedCards) do
						queue[#queue + 1] = tostring(cardId)
					end
					table.sort(queue)
				else
					local seen = {}
					for _, cardId in ipairs(selectedCards) do
						cardId = tostring(cardId)
						if cardId ~= "All" and ownedCards[cardId] ~= nil and not seen[cardId] then
							seen[cardId] = true
							queue[#queue + 1] = cardId
						end
					end
				end
		
				return queue
			end
		
			function Feature:MarkFinishedCards(ownedCards)
				if not self.State.TargetMinRank then
					return
				end
		
				for _, cardId in ipairs(self.State.Queue) do
					local cardData = ownedCards[cardId]
					if not cardData then
						self.State.TargetDone[cardId] = true
					elseif self:CardMeetsOrBeatsTarget(ownedCards, cardId, self.State.TargetMinRank) then
						self.State.TargetDone[cardId] = true
					end
				end
			end
		
			function Feature:IsCardDone(cardId)
				return self.State.TargetDone[cardId] == true
			end
		
			function Feature:AllCardsDone()
				for _, cardId in ipairs(self.State.Queue) do
					if not self:IsCardDone(cardId) then
						return false
					end
				end
				return true
			end
		
			function Feature:GetNextCardToRoll(ownedCards)
				local count = #self.State.Queue
				if count == 0 then
					return nil
				end
		
				for _ = 1, count do
					self.State.QueueIndex += 1
					if self.State.QueueIndex > count then
						self.State.QueueIndex = 1
					end
		
					local cardId = self.State.Queue[self.State.QueueIndex]
					if cardId and not self:IsCardDone(cardId) and ownedCards[cardId] ~= nil then
						return cardId
					end
				end
		
				return nil
			end
		
			function Feature:SendGradeRoll(ownedCards, cardId)
				if self:CurrentCardNeedsConfirm(ownedCards, cardId) then
					GradeRemote:FireServer("Roll", cardId, nil, true)
				else
					GradeRemote:FireServer("Roll", cardId)
				end
			end
		
			function Feature:Loop()
				while self.State.Running do
					local values = self:GetValues()
					if not values or not values.AutoGradeEnabled then
						break
					end
		
					local ownedCards = self:GetOwnedCardsTable()
					if type(ownedCards) ~= "table" then
						break
					end
		
					self:MarkFinishedCards(ownedCards)
		
					if self:AllCardsDone() then
						break
					end
		
					local nextCard = self:GetNextCardToRoll(ownedCards)
					if not nextCard then
						break
					end
		
					if self:CardMeetsOrBeatsTarget(ownedCards, nextCard, self.State.TargetMinRank) then
						self.State.TargetDone[nextCard] = true
					else
						self:SendGradeRoll(ownedCards, nextCard)
					end
		
					task.wait(0.2)
				end
		
				self:Stop()
			end
		
			function Feature:Start(panelRef)
				self:Stop()
				self.State.PanelRef = panelRef
		
				local values = self:GetValues()
				if not values then
					return
				end
		
				local selectedCards = normalizeSelectionArray(values.AutoGradeCards)
				local selectedGrades = normalizeSelectionArray(values.AutoGradeTarget)
		
				if #selectedCards == 0 or #selectedGrades == 0 then
					return
				end
		
				local ownedCards = self:GetOwnedCardsTable()
				if type(ownedCards) ~= "table" then
					return
				end
		
				local targetMinRank = self:GetTargetMinRank(selectedGrades)
				if not targetMinRank then
					return
				end
		
				local queue = self:BuildQueue(selectedCards, ownedCards)
				if #queue == 0 then
					return
				end
		
				self.State.Running = true
				self.State.Queue = queue
				self.State.QueueIndex = 0
				self.State.TargetDone = {}
				self.State.TargetMinRank = targetMinRank
		
				self:MarkFinishedCards(ownedCards)
		
				if self:AllCardsDone() then
					self:Stop()
					return
				end
		
				task.spawn(function()
					self:Loop()
				end)
			end
		
			function Feature:Stop()
				self.State.Running = false
				self.State.Queue = {}
				self.State.QueueIndex = 0
				self.State.TargetDone = {}
				self.State.TargetMinRank = nil
			end
		
			function Feature:GetHandlers()
				return {
					AutoGradeEnabled = function(value, _, panelRef)
						if value then
							self:Start(panelRef)
						else
							self:Stop()
						end
					end,
					AutoGradeCards = function(_, values, panelRef)
						if values.AutoGradeEnabled then
							self:Start(panelRef)
						end
					end,
					AutoGradeTarget = function(_, values, panelRef)
						if values.AutoGradeEnabled then
							self:Start(panelRef)
						end
					end,
				}
			end
		
			function Feature:Cleanup()
				self:Stop()
				self.State.PanelRef = nil
				self.State.ReplicatedData = nil
			end
		end

		--==================================================
		-- FEATURE: AUTO BUY MARKET
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "AutoBuyMarket",
				Tab = "Shop",
				Order = 20,

				Defaults = {
					AutoBuyMarketEnabled = false,
					AutoBuyMarketPack = {},
					AutoBuyMarketMutation = {},
				},

				State = {
					Running = false,
					LastCheckTime = 0,
					PanelRef = nil,
					BuyCooldown = 0.08,
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
					},
				}
			})

			function Feature:GetValues()
				local panel = self.State.PanelRef
				return panel and panel.Config and panel.Config.Values or nil
			end

			function Feature:GetMarketStock()
				local scrolling = getStockScrollingFrame()
				if not scrolling then
					return {}
				end

				local stockList = {}

				for i = 1, 8 do
					local slot = scrolling:FindFirstChild(tostring(i))
					if slot then
						local packLabel = slot:FindFirstChild("PackName")
						local mutationLabel = slot:FindFirstChild("Mutation")
						local stockLabel = slot:FindFirstChild("Stock")

						local packName = packLabel and packLabel.Text or ""
						local mutation = "Regular"
						local amount = stockLabel and parseStockAmount(stockLabel.Text) or 0

						if mutationLabel and mutationLabel.Visible and mutationLabel.Text and mutationLabel.Text ~= "" then
							mutation = tostring(mutationLabel.Text)
						end

						if packName ~= "" then
							stockList[#stockList + 1] = {
								PackName = packName,
								NormalizedPackName = normalizePackName(packName),
								Mutation = mutation,
								RemoteId = buildRemotePackId(packName, mutation),
								Amount = amount,
								Slot = i,
							}
						end
					end
				end

				return stockList
			end

			function Feature:RunStockCheck()
				local values = self:GetValues()
				if not values or not values.AutoBuyMarketEnabled then
					return
				end

				local selectedPacks = normalizeSelectionArray(values.AutoBuyMarketPack)
				local selectedMutations = normalizeSelectionArray(values.AutoBuyMarketMutation)

				if #selectedPacks == 0 or #selectedMutations == 0 then
					return
				end

				local selectedNormalizedPacks = {}
				for _, packName in ipairs(selectedPacks) do
					selectedNormalizedPacks[#selectedNormalizedPacks + 1] = normalizePackName(packName)
				end

				local marketStock = self:GetMarketStock()
				if #marketStock == 0 then
					return
				end

				local buyQueue = {}

				for _, item in ipairs(marketStock) do
					local packOk = arrayContains(selectedPacks, "All") or arrayContains(selectedNormalizedPacks, item.NormalizedPackName)
					local mutationOk = arrayContains(selectedMutations, "All") or arrayContains(selectedMutations, item.Mutation)

					if packOk and mutationOk and item.RemoteId and item.Amount > 0 then
						for _ = 1, item.Amount do
							buyQueue[#buyQueue + 1] = item.RemoteId
						end
					end
				end

				if #buyQueue == 0 then
					return
				end

				for i, remoteId in ipairs(buyQueue) do
					StockRemote:FireServer("Buy", remoteId)
					if self.State.BuyCooldown > 0 and i < #buyQueue then
						task.wait(self.State.BuyCooldown)
					end
				end
			end

			function Feature:Start(panelRef)
				self.State.PanelRef = panelRef
				self.State.LastCheckTime = 0

				if self.State.Running then
					return
				end

				self.State.Running = true

				task.spawn(function()
					while self.State.Running do
						local values = self:GetValues()
						if not values or not values.AutoBuyMarketEnabled then
							break
						end

						if tick() - self.State.LastCheckTime >= 60 then
							self.State.LastCheckTime = tick()
							self:RunStockCheck()
						end

						task.wait(1)
					end

					self.State.Running = false
				end)
			end

			function Feature:Stop()
				self.State.Running = false
			end

			function Feature:GetHandlers()
				return {
					AutoBuyMarketEnabled = function(value, _, panelRef)
						self.State.PanelRef = panelRef
						if value then
							self.State.LastCheckTime = 0
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
				self:Stop()
				self.State.PanelRef = nil
			end
		end
	end
}
