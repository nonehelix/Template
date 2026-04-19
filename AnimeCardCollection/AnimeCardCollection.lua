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
		-- LOCAL REPLICATED DATA RESOLVER
		--==================================================
		local CachedReplicatedData = nil

		local function tryGetField(container, key)
			if type(container) == "table" then
				return container[key]
			end
			return nil
		end

		local function resolveReplicatedData()
			if CachedReplicatedData and type(CachedReplicatedData.GetData) == "function" then
				return CachedReplicatedData
			end

			local candidates = {
				tryGetField(Shared, "ReplicatedData"),
				tryGetField(tryGetField(Shared, "Game"), "ReplicatedData"),
				tryGetField(tryGetField(Shared, "Framework"), "ReplicatedData"),
				tryGetField(tryGetField(Shared, "Client"), "ReplicatedData"),
				rawget(_G, "ReplicatedData"),
			}

			local globalEnv = getgenv and getgenv()
			if type(globalEnv) == "table" then
				table.insert(candidates, globalEnv.ReplicatedData)
			end

			for _, candidate in ipairs(candidates) do
				if type(candidate) == "table" and type(candidate.GetData) == "function" then
					CachedReplicatedData = candidate
					print("[AutoGrade] ReplicatedData resolved:", tostring(candidate))
					return candidate
				end
			end

			warn("[AutoGrade] ReplicatedData resolver could not find a valid object")
			return nil
		end

		--==================================================
		-- HELPERS
		--==================================================
		local function normalizePackName(name)
			name = tostring(name or "")
			name = name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
			name = name:gsub("%s+[Pp]ack$", "")
			return name
		end

		local function buildRemotePackId(packName, mutation)
			local base = normalizePackName(packName)
			if base == "" then
				return nil
			end

			if mutation == "Regular" or not mutation or mutation == "" then
				return base
			end

			return base .. "-" .. tostring(mutation)
		end

		local function parseStockAmount(text)
			return tonumber(string.match(tostring(text or ""), "%d+")) or 0
		end

		local arrayContains = Shared.arrayContains or function(arr, target)
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

			for _, v in ipairs(values) do
				table.insert(result, tostring(v))
			end

			return result
		end

		local function getPackItems()
			local items = {"All"}

			if CardConfig and CardConfig.List and CardConfig.List.Packs then
				for _, packName in pairs(CardConfig.List.Packs) do
					table.insert(items, tostring(packName))
				end
			end

			return items
		end

		local function getMutationItems()
			local items = {"All", "Regular"}

			if CardConfig and CardConfig.List and CardConfig.List.Mutations then
				for _, mut in pairs(CardConfig.List.Mutations) do
					table.insert(items, tostring(mut))
				end
			end

			return items
		end

		local function getGradeItems()
			local items = {}

			if GradesConfig and GradesConfig.List then
				for _, grade in ipairs(GradesConfig.List) do
					table.insert(items, grade)
				end
			else
				items = {"F", "E", "D", "C", "B", "A", "S", "S+", "SS", "SR", "UR"}
			end

			return items
		end

		local function getAllCardNames()
			local seen = {}
			local cardNames = {}

			if CardConfig and CardConfig.Packs then
				for _, packData in pairs(CardConfig.Packs) do
					if packData.List then
						for cardName in pairs(packData.List) do
							cardName = tostring(cardName)
							if not seen[cardName] then
								seen[cardName] = true
								table.insert(cardNames, cardName)
							end
						end
					end
				end
			end

			table.sort(cardNames)

			local items = {"All"}
			for _, cardName in ipairs(cardNames) do
				table.insert(items, cardName)
			end

			return items
		end

		local function waitForItems(builder, minCount, fallback, timeout)
			timeout = timeout or 5
			local start = os.clock()

			while os.clock() - start < timeout do
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
					},
				}
			})

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

				for _, desc in ipairs(packModel:GetDescendants()) do
					if desc:IsA("TextLabel") and desc.Name == "Mutation" and desc.Visible and desc.Text ~= "" then
						return tostring(desc.Text)
					end
				end

				return "Regular"
			end

			function Feature:GetPackModelId(packModel)
				return packModel and packModel.Name ~= "" and packModel.Name or nil
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
				local mutOk = arrayContains(selectedMutations, "All") or arrayContains(selectedMutations, mutation)

				return packOk and mutOk
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

				local packsFolder = Workspace:FindFirstChild("Client") and Workspace.Client:FindFirstChild("Packs")
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
							if not self.State.LastBuyTimes[packId] or (now - self.State.LastBuyTimes[packId]) > 1 then
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
					Grading = false,
					PanelRef = nil,
					Queue = {},
					QueueIndex = 0,
					TargetDone = {},
					TargetMinRank = nil,
					RequestDelay = 0.01,
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
						Label = "Select Cards",
						Description = "Choose which cards to auto grade (All = every owned card)",
						Items = waitForItems(getAllCardNames, 2, {"All"}),
						EmptyText = "Nothing selected"
					},
					{
						Id = "AutoGradeTarget",
						Type = "multiselect",
						Label = "Target Grade",
						Description = "Stop grading when card reaches any of these grades or better",
						Items = getGradeItems(),
						EmptyText = "Nothing selected"
					},
				}
			})

			local gradeOrder = {}
			if GradesConfig and GradesConfig.List then
				for i, g in ipairs(GradesConfig.List) do
					gradeOrder[tostring(g)] = i
				end
			end

			local function requireReplicatedDataModule()
				local modules = ReplicatedStorage:FindFirstChild("Modules")
				if not modules then
					warn("[AutoGrade] Missing ReplicatedStorage.Modules")
					return nil
				end

				local clientFolder = modules:FindFirstChild("Client")
				if not clientFolder then
					warn("[AutoGrade] Missing ReplicatedStorage.Modules.Client")
					return nil
				end

				local replicatedDataModule = clientFolder:FindFirstChild("ReplicatedData")
				if not replicatedDataModule then
					warn("[AutoGrade] Missing ReplicatedStorage.Modules.Client.ReplicatedData")
					return nil
				end

				local ok, result = pcall(require, replicatedDataModule)
				if not ok then
					warn("[AutoGrade] Failed to require ReplicatedData:", tostring(result))
					return nil
				end

				return result
			end

			function Feature:GetReplicatedData(timeout)
				if self.State.ReplicatedData and type(self.State.ReplicatedData.GetData) == "function" then
					return self.State.ReplicatedData
				end

				timeout = timeout or 10

				local replicatedData = requireReplicatedDataModule()
				if not replicatedData then
					return nil
				end

				local startTime = tick()
				while tick() - startTime < timeout do
					if type(replicatedData.GetData) == "function" then
						self.State.ReplicatedData = replicatedData
						return replicatedData
					end
					task.wait(0.1)
				end

				warn("[AutoGrade] ReplicatedData loaded but GetData never became available")
				return nil
			end

			function Feature:GetOwnedCards()
				local replicatedData = self:GetReplicatedData()
				if not replicatedData then
					return {}
				end

				local ok, cards = pcall(function()
					return replicatedData.GetData("Cards")
				end)

				if not ok then
					warn("[AutoGrade] GetData('Cards') failed:", tostring(cards))
					return {}
				end

				if type(cards) ~= "table" then
					warn("[AutoGrade] Cards data is not a table")
					return {}
				end

				return cards
			end

			function Feature:GetServerAutoGrades()
				local replicatedData = self:GetReplicatedData()
				if not replicatedData then
					return {}
				end

				local ok, autoGrades = pcall(function()
					return replicatedData.GetData("AutoGrades")
				end)

				if not ok or type(autoGrades) ~= "table" then
					return {}
				end

				return autoGrades
			end

			function Feature:GetGradeRank(gradeName)
				if not gradeName then
					return 0
				end
				return gradeOrder[tostring(gradeName)] or 0
			end

			function Feature:GetTargetMinRank(selectedGrades)
				local minRank = nil

				for _, gradeName in ipairs(selectedGrades or {}) do
					local rank = self:GetGradeRank(gradeName)
					if rank > 0 then
						if minRank == nil or rank < minRank then
							minRank = rank
						end
					end
				end

				return minRank
			end

			function Feature:GetCardCurrentGrade(cardId)
				local ownedCards = self:GetOwnedCards()
				local cardData = ownedCards[tostring(cardId)]

				if type(cardData) ~= "table" then
					return nil
				end

				return cardData.Grade
			end

			function Feature:CardMeetsOrBeatsTarget(cardId, targetMinRank)
				local currentRank = self:GetGradeRank(self:GetCardCurrentGrade(cardId))
				return currentRank >= (targetMinRank or math.huge)
			end

			function Feature:CurrentCardNeedsConfirm(cardId)
				local currentGrade = self:GetCardCurrentGrade(cardId)
				if not currentGrade then
					return false
				end

				return arrayContains(self:GetServerAutoGrades(), tostring(currentGrade))
			end

			function Feature:BuildQueue(selectedCards)
				local ownedCards = self:GetOwnedCards()
				if type(ownedCards) ~= "table" then
					return {}
				end

				local queue = {}

				if arrayContains(selectedCards, "All") then
					for cardId in pairs(ownedCards) do
						table.insert(queue, tostring(cardId))
					end

					table.sort(queue, function(a, b)
						return tostring(a) < tostring(b)
					end)
				else
					local seen = {}

					for _, cardId in ipairs(selectedCards) do
						cardId = tostring(cardId)
						if cardId ~= "All" and ownedCards[cardId] ~= nil and not seen[cardId] then
							seen[cardId] = true
							table.insert(queue, cardId)
						end
					end
				end

				return queue
			end

			function Feature:MarkFinishedCards()
				if not self.State.TargetMinRank then
					return
				end

				local ownedCards = self:GetOwnedCards()

				for _, cardId in ipairs(self.State.Queue) do
					local cardData = ownedCards[cardId]
					if not cardData then
						self.State.TargetDone[cardId] = true
					elseif self:CardMeetsOrBeatsTarget(cardId, self.State.TargetMinRank) then
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

			function Feature:GetNextCardToRoll()
				local count = #self.State.Queue
				if count == 0 then
					return nil
				end

				local ownedCards = self:GetOwnedCards()

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

			function Feature:SendGradeRoll(cardId)
				if self:CurrentCardNeedsConfirm(cardId) then
					GradeRemote:FireServer("Roll", cardId, nil, true)
				else
					GradeRemote:FireServer("Roll", cardId)
				end
			end

			function Feature:Loop()
				while self.State.Grading do
					local values = self.State.PanelRef and self.State.PanelRef.Config and self.State.PanelRef.Config.Values
					if not values or not values.AutoGradeEnabled then
						self:Stop()
						break
					end

					self:MarkFinishedCards()

					if self:AllCardsDone() then
						self:Stop()
						break
					end

					local nextCard = self:GetNextCardToRoll()
					if not nextCard then
						self:Stop()
						break
					end

					if self:CardMeetsOrBeatsTarget(nextCard, self.State.TargetMinRank) then
						self.State.TargetDone[nextCard] = true
					else
						self:SendGradeRoll(nextCard)
					end

					task.wait(self.State.RequestDelay)
				end
			end

			function Feature:Start(panelRef)
				self.State.PanelRef = panelRef

				local values = panelRef and panelRef.Config and panelRef.Config.Values
				if not values then
					self:Stop()
					return
				end

				local selectedCards = normalizeSelectionArray(values.AutoGradeCards)
				local selectedGrades = normalizeSelectionArray(values.AutoGradeTarget)

				if #selectedCards == 0 or #selectedGrades == 0 then
					self:Stop()
					return
				end

				local replicatedData = self:GetReplicatedData()
				if not replicatedData then
					self:Stop()
					return
				end

				local targetMinRank = self:GetTargetMinRank(selectedGrades)
				if not targetMinRank then
					self:Stop()
					return
				end

				local queue = self:BuildQueue(selectedCards)
				if #queue == 0 then
					self:Stop()
					return
				end

				self:Stop()

				self.State.Grading = true
				self.State.Queue = queue
				self.State.QueueIndex = 0
				self.State.TargetDone = {}
				self.State.TargetMinRank = targetMinRank

				self:MarkFinishedCards()

				if self:AllCardsDone() then
					self:Stop()
					return
				end

				task.spawn(function()
					self:Loop()
				end)
			end

			function Feature:Stop()
				self.State.Grading = false
				self.State.Queue = {}
				self.State.QueueIndex = 0
				self.State.TargetDone = {}
				self.State.TargetMinRank = nil
			end

			function Feature:GetHandlers()
				return {
					AutoGradeEnabled = function(value, _, panelRef)
						self.State.PanelRef = panelRef
						if value then
							self:Start(panelRef)
						else
							self:Stop()
						end
					end,
					AutoGradeCards = function(_, values, panelRef)
						self.State.PanelRef = panelRef
						if values.AutoGradeEnabled then
							self:Start(panelRef)
						end
					end,
					AutoGradeTarget = function(_, values, panelRef)
						self.State.PanelRef = panelRef
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
					LastCheckTime = 0,
					PanelRef = nil,
					Running = false,
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

			function Feature:GetMarketStock()
				local playerGui = player:FindFirstChild("PlayerGui")
				if not playerGui then
					return {}
				end

				local stockGui = playerGui:FindFirstChild("Stock")
				if not stockGui then
					return {}
				end

				local frame = stockGui:FindFirstChild("Frame")
				if not frame then
					return {}
				end

				local scrolling = frame:FindFirstChild("ScrollingFrame")
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
							table.insert(stockList, {
								PackName = packName,
								NormalizedPackName = normalizePackName(packName),
								Mutation = mutation,
								RemoteId = buildRemotePackId(packName, mutation),
								Amount = amount,
								Slot = i
							})
						end
					end
				end

				return stockList
			end

			function Feature:RunStockCheck()
				local values = self.State.PanelRef and self.State.PanelRef.Config and self.State.PanelRef.Config.Values
				if not values or not values.AutoBuyMarketEnabled then
					return
				end

				local selectedPacks = normalizeSelectionArray(values.AutoBuyMarketPack)
				local selectedMutations = normalizeSelectionArray(values.AutoBuyMarketMutation)

				if #selectedPacks == 0 or #selectedMutations == 0 then
					return
				end

				local selectedNormalizedPacks = {}
				for _, p in ipairs(selectedPacks) do
					table.insert(selectedNormalizedPacks, normalizePackName(p))
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
							table.insert(buyQueue, item.RemoteId)
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
						local values = self.State.PanelRef and self.State.PanelRef.Config and self.State.PanelRef.Config.Values
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
