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
					LastGradedCard = nil,
					PanelRef = nil,
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

			function Feature:GetReplicatedData()
				if Shared and Shared.ReplicatedData and type(Shared.ReplicatedData.GetData) == "function" then
					return Shared.ReplicatedData
				end

				warn("[AutoGrade] Shared.ReplicatedData missing or invalid")
				return nil
			end

			function Feature:GetOwnedCards()
				local replicatedData = self:GetReplicatedData()
				if not replicatedData then
					return {}
				end

				local ok, cardsOrError = pcall(function()
					return replicatedData.GetData("Cards")
				end)

				if not ok then
					warn("[AutoGrade] GetData('Cards') failed:", tostring(cardsOrError))
					return {}
				end

				local cards = cardsOrError or {}
				local count = 0
				for _ in pairs(cards) do
					count += 1
				end

				print("[AutoGrade] Owned cards count:", count)
				return cards
			end

			function Feature:GetServerAutoGrades()
				local replicatedData = self:GetReplicatedData()
				if not replicatedData then
					return {}
				end

				local ok, autoGradesOrError = pcall(function()
					return replicatedData.GetData("AutoGrades")
				end)

				if not ok then
					warn("[AutoGrade] GetData('AutoGrades') failed:", tostring(autoGradesOrError))
					return {}
				end

				return type(autoGradesOrError) == "table" and autoGradesOrError or {}
			end

			function Feature:IsGradeBetterOrEqual(currentGrade, targetGrades)
				if not currentGrade or #targetGrades == 0 then
					return false
				end

				local currentIdx = gradeOrder[tostring(currentGrade)] or 0
				for _, tgt in ipairs(targetGrades) do
					local targetIdx = gradeOrder[tostring(tgt)]
					if targetIdx and currentIdx >= targetIdx then
						return true
					end
				end

				return false
			end

			function Feature:NeedsConfirm(cardName)
				local ownedCards = self:GetOwnedCards()
				local cardData = ownedCards[cardName]

				if type(cardData) ~= "table" then
					return false
				end

				local currentGrade = cardData.Grade
				if not currentGrade then
					return false
				end

				return arrayContains(self:GetServerAutoGrades(), tostring(currentGrade))
			end

			function Feature:Tick()
				if not self.State.Grading then
					return
				end

				local values = self.State.PanelRef and self.State.PanelRef.Config and self.State.PanelRef.Config.Values
				if not values or not values.AutoGradeEnabled then
					return
				end

				local selectedCards = normalizeSelectionArray(values.AutoGradeCards)
				local targetGrades = normalizeSelectionArray(values.AutoGradeTarget)

				if #selectedCards == 0 or #targetGrades == 0 then
					return
				end

				local ownedCards = self:GetOwnedCards()
				local eligible = {}
				local useAll = arrayContains(selectedCards, "All")

				for cardName, cardData in pairs(ownedCards) do
					cardName = tostring(cardName)

					local currentGrade = type(cardData) == "table" and cardData.Grade or nil
					local cardSelected = useAll or arrayContains(selectedCards, cardName)
					local alreadyGood = self:IsGradeBetterOrEqual(currentGrade, targetGrades)

					if cardSelected and not alreadyGood then
						table.insert(eligible, cardName)
					end
				end

				print("[AutoGrade] Eligible count:", #eligible)

				if #eligible == 0 then
					return
				end

				local nextIndex = 1
				if self.State.LastGradedCard then
					for i, card in ipairs(eligible) do
						if card == self.State.LastGradedCard then
							nextIndex = (i % #eligible) + 1
							break
						end
					end
				end

				local cardToGrade = eligible[nextIndex]
				self.State.LastGradedCard = cardToGrade

				local needsConfirm = self:NeedsConfirm(cardToGrade)

				print("[AutoGrade] Rolling card:", tostring(cardToGrade), "NeedsConfirm:", tostring(needsConfirm))

				local ok, err = pcall(function()
					if needsConfirm then
						GradeRemote:FireServer("Roll", cardToGrade, nil, true)
					else
						GradeRemote:FireServer("Roll", cardToGrade)
					end
				end)

				if not ok then
					warn("[AutoGrade] GradeRemote fire failed:", tostring(err))
				end
			end

			function Feature:Start(panelRef)
				self.State.PanelRef = panelRef
				if self.State.Grading then
					return
				end

				self.State.Grading = true
				self.State.LastGradedCard = nil

				print("[AutoGrade] Started")

				task.spawn(function()
					while self.State.Grading do
						self:Tick()
						task.wait(0.5)
					end
				end)
			end

			function Feature:Stop()
				self.State.Grading = false
				print("[AutoGrade] Stopped")
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
					AutoGradeCards = function(_, _, panelRef)
						self.State.PanelRef = panelRef
					end,
					AutoGradeTarget = function(_, _, panelRef)
						self.State.PanelRef = panelRef
					end,
				}
			end

			function Feature:Cleanup()
				self:Stop()
				self.State.PanelRef = nil
				self.State.LastGradedCard = nil
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
