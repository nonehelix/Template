return {
	Load = function(Shared)
		local Workspace = Shared.Workspace
		local RegisterFeature = Shared.RegisterFeature
		local RegisterTabs = Shared.RegisterTabs

		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local ReplicatedFirst = game:GetService("ReplicatedFirst")
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
				result[#result + 1] = tostring(v)
			end

			return result
		end

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

			if mutation == "Regular" or mutation == nil or mutation == "" then
				return base
			end

			return base .. "-" .. tostring(mutation)
		end

		local function parseStockAmount(text)
			return tonumber(string.match(tostring(text or ""), "%d+")) or 0
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
				for _, mut in pairs(CardConfig.List.Mutations) do
					items[#items + 1] = tostring(mut)
				end
			end

			return items
		end

		local function getGradeItems()
			local items = {}

			if GradesConfig and GradesConfig.List then
				for _, grade in ipairs(GradesConfig.List) do
					items[#items + 1] = tostring(grade)
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
								cardNames[#cardNames + 1] = cardName
							end
						end
					end
				end
			end

			table.sort(cardNames)

			local items = {"All"}
			for _, cardName in ipairs(cardNames) do
				items[#items + 1] = cardName
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
		-- FEATURE: AUTO GRADE (FIXED - SIMPLE + STABLE)
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
					Queue = {},
					QueueIndex = 0,
					TargetDone = {},
					TargetMinRank = nil,
					RequestDelay = 0.1, -- 🔥 tuned to server pace
					ReplicatedData = nil,
				},
		
				Options = {
					{
						Id = "AutoGradeEnabled",
						Type = "toggle",
						Label = "Enable Auto Grade",
					},
					{
						Id = "AutoGradeCards",
						Type = "multiselect",
						Label = "Cards",
						Items = waitForItems(getAllCardNames, 2, {"All"}),
					},
					{
						Id = "AutoGradeTarget",
						Type = "multiselect",
						Label = "Grades",
						Items = getGradeItems(),
					},
				}
			})
		
			--==================================================
			-- REPLICATED DATA (ReplicatedFirst)
			--==================================================
			function Feature:GetReplicatedData()
				if self.State.ReplicatedData then
					return self.State.ReplicatedData
				end
		
				local module = ReplicatedFirst:FindFirstChild("ReplicatedData")
				if not module then return nil end
		
				local ok, result = pcall(require, module)
				if ok and type(result.GetData) == "function" then
					self.State.ReplicatedData = result
					return result
				end
		
				return nil
			end
		
			function Feature:GetOwnedCards()
				local data = self:GetReplicatedData()
				if not data then return {} end
		
				local ok, cards = pcall(function()
					return data.GetData("Cards")
				end)
		
				return (ok and type(cards) == "table") and cards or {}
			end
		
			function Feature:GetServerAutoGrades()
				local data = self:GetReplicatedData()
				if not data then return {} end
		
				local ok, result = pcall(function()
					return data.GetData("AutoGrades")
				end)
		
				return (ok and type(result) == "table") and result or {}
			end
		
			--==================================================
			-- GRADE LOGIC
			--==================================================
			local GradeRankMap = {}
			if GradesConfig and GradesConfig.List then
				for i, g in ipairs(GradesConfig.List) do
					GradeRankMap[tostring(g)] = i
				end
			end
		
			function Feature:GetGradeRank(grade)
				return GradeRankMap[tostring(grade)] or 0
			end
		
			function Feature:GetCardGrade(cardId)
				local card = self:GetOwnedCards()[cardId]
				return card and card.Grade
			end
		
			function Feature:GetTargetMinRank(targets)
				local min
				for _, g in ipairs(targets) do
					local r = self:GetGradeRank(g)
					if r > 0 and (not min or r < min) then
						min = r
					end
				end
				return min
			end
		
			function Feature:IsDone(cardId)
				local rank = self:GetGradeRank(self:GetCardGrade(cardId))
				return rank >= (self.State.TargetMinRank or math.huge)
			end
		
			function Feature:NeedsConfirm(cardId)
				local grade = self:GetCardGrade(cardId)
				return grade and arrayContains(self:GetServerAutoGrades(), grade)
			end
		
			--==================================================
			-- QUEUE
			--==================================================
			function Feature:BuildQueue(selected)
				local owned = self:GetOwnedCards()
				local queue = {}
		
				if arrayContains(selected, "All") then
					for id in pairs(owned) do
						table.insert(queue, tostring(id))
					end
					table.sort(queue)
				else
					local seen = {}
					for _, id in ipairs(selected) do
						id = tostring(id)
						if owned[id] and not seen[id] then
							seen[id] = true
							table.insert(queue, id)
						end
					end
				end
		
				return queue
			end
		
			function Feature:GetNext()
				local count = #self.State.Queue
				if count == 0 then return nil end
		
				for _ = 1, count do
					self.State.QueueIndex += 1
					if self.State.QueueIndex > count then
						self.State.QueueIndex = 1
					end
		
					local id = self.State.Queue[self.State.QueueIndex]
					if id and not self.State.TargetDone[id] and self:GetOwnedCards()[id] then
						return id
					end
				end
			end
		
			--==================================================
			-- ACTION
			--==================================================
			function Feature:Roll(cardId)
				if self:NeedsConfirm(cardId) then
					GradeRemote:FireServer("Roll", cardId, nil, true)
				else
					GradeRemote:FireServer("Roll", cardId)
				end
			end
		
			--==================================================
			-- LOOP (SIMPLE + STABLE)
			--==================================================
			function Feature:Loop()
				while self.State.Running do
					local values = self.State.PanelRef.Config.Values
					if not values or not values.AutoGradeEnabled then break end
		
					local nextCard = self:GetNext()
					if not nextCard then break end
		
					if self:IsDone(nextCard) then
						self.State.TargetDone[nextCard] = true
					else
						self:Roll(nextCard)
					end
		
					task.wait(self.State.RequestDelay) -- 🔥 critical throttle
				end
		
				self:Stop()
			end
		
			--==================================================
			-- CONTROL
			--==================================================
			function Feature:Start(panelRef)
				self:Stop()
		
				self.State.PanelRef = panelRef
				local values = panelRef.Config.Values
		
				local cards = normalizeSelectionArray(values.AutoGradeCards)
				local grades = normalizeSelectionArray(values.AutoGradeTarget)
		
				if #cards == 0 or #grades == 0 then return end
		
				local minRank = self:GetTargetMinRank(grades)
				if not minRank then return end
		
				local queue = self:BuildQueue(cards)
				if #queue == 0 then return end
		
				self.State.Running = true
				self.State.Queue = queue
				self.State.QueueIndex = 0
				self.State.TargetDone = {}
				self.State.TargetMinRank = minRank
		
				task.spawn(function()
					self:Loop()
				end)
			end
		
			function Feature:Stop()
				self.State.Running = false
				self.State.Queue = {}
				self.State.TargetDone = {}
				self.State.QueueIndex = 0
			end
		
			function Feature:GetHandlers()
				return {
					AutoGradeEnabled = function(v, _, panel)
						if v then
							self:Start(panel)
						else
							self:Stop()
						end
					end,
					AutoGradeCards = function(_, values, panel)
						if values.AutoGradeEnabled then
							self:Start(panel)
						end
					end,
					AutoGradeTarget = function(_, values, panel)
						if values.AutoGradeEnabled then
							self:Start(panel)
						end
					end,
				}
			end
		
			function Feature:Cleanup()
				self:Stop()
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
							stockList[#stockList + 1] = {
								PackName = packName,
								NormalizedPackName = normalizePackName(packName),
								Mutation = mutation,
								RemoteId = buildRemotePackId(packName, mutation),
								Amount = amount,
								Slot = i
							}
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
					selectedNormalizedPacks[#selectedNormalizedPacks + 1] = normalizePackName(p)
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
