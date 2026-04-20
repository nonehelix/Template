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
		
			--========================
			-- GRADE ORDER
			--========================
			local gradeOrder = {}
			if GradesConfig and GradesConfig.List then
				for i, g in ipairs(GradesConfig.List) do
					gradeOrder[tostring(g)] = i
				end
			end
		
			--========================
			-- REPLICATED DATA
			--========================
			local function requireReplicatedDataModule()
				local module = ReplicatedFirst:FindFirstChild("ReplicatedData")
				if not module then
					warn("[AutoGrade] Missing ReplicatedFirst.ReplicatedData")
					return nil
				end
		
				local ok, result = pcall(require, module)
				if not ok then
					warn("[AutoGrade] Failed to require ReplicatedData:", result)
					return nil
				end
		
				return result
			end
		
			function Feature:GetReplicatedData()
				if self.State.ReplicatedData and type(self.State.ReplicatedData.GetData) == "function" then
					return self.State.ReplicatedData
				end
		
				local data = requireReplicatedDataModule()
				if data and type(data.GetData) == "function" then
					self.State.ReplicatedData = data
					return data
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
		
			--========================
			-- CORE HELPERS
			--========================
			function Feature:GetGradeRank(g)
				return gradeOrder[tostring(g)] or 0
			end
		
			function Feature:GetTargetMinRank(selectedGrades)
				local minRank
		
				for _, g in ipairs(selectedGrades) do
					local r = self:GetGradeRank(g)
					if r > 0 and (not minRank or r < minRank) then
						minRank = r
					end
				end
		
				return minRank
			end
		
			function Feature:GetCardData(cardId)
				return self:GetOwnedCards()[tostring(cardId)]
			end
		
			function Feature:GetCardGrade(cardId)
				local d = self:GetCardData(cardId)
				return d and d.Grade
			end
		
			function Feature:CardMeetsOrBeatsTarget(cardId, targetMinRank)
				return self:GetGradeRank(self:GetCardGrade(cardId)) >= (targetMinRank or math.huge)
			end
		
			function Feature:NeedsConfirm(cardId)
				local grade = self:GetCardGrade(cardId)
				return grade and arrayContains(self:GetServerAutoGrades(), tostring(grade))
			end
		
			--========================
			-- ROUND ROBIN (SIMPLE)
			--========================
			function Feature:GetNextCardToRoll()
				local count = #self.State.Queue
				if count == 0 then return nil end
		
				local owned = self:GetOwnedCards()
		
				for _ = 1, count do
					self.State.QueueIndex += 1
					if self.State.QueueIndex > count then
						self.State.QueueIndex = 1
					end
		
					local id = self.State.Queue[self.State.QueueIndex]
		
					if id and owned[id] and not self.State.TargetDone[id] then
						return id
					end
				end
		
				return nil
			end
		
			--========================
			-- SYNC WITH GAME (KEY FIX)
			--========================
			function Feature:GetSnapshot(cardId)
				local d = self:GetCardData(cardId)
				return d and tostring(d.Grade or "")
			end
		
			function Feature:WaitForUpdate(cardId, before)
				local start = tick()
		
				while tick() - start < 2 do
					local now = self:GetSnapshot(cardId)
					if now ~= before then
						return true
					end
					task.wait(0.05)
				end
		
				return false
			end
		
			function Feature:SendRoll(cardId)
				local before = self:GetSnapshot(cardId)
		
				if self:NeedsConfirm(cardId) then
					GradeRemote:FireServer("Roll", cardId, nil, true)
				else
					GradeRemote:FireServer("Roll", cardId)
				end
		
				self:WaitForUpdate(cardId, before)
			end
		
			--========================
			-- QUEUE BUILD
			--========================
			function Feature:BuildQueue(selected)
				local owned = self:GetOwnedCards()
				local q = {}
		
				if arrayContains(selected, "All") then
					for id in pairs(owned) do
						q[#q+1] = tostring(id)
					end
					table.sort(q)
				else
					local seen = {}
					for _, id in ipairs(selected) do
						id = tostring(id)
						if owned[id] and not seen[id] then
							seen[id] = true
							q[#q+1] = id
						end
					end
				end
		
				return q
			end
		
			function Feature:MarkDone()
				for _, id in ipairs(self.State.Queue) do
					if self:CardMeetsOrBeatsTarget(id, self.State.TargetMinRank) then
						self.State.TargetDone[id] = true
					end
				end
			end
		
			function Feature:AllDone()
				for _, id in ipairs(self.State.Queue) do
					if not self.State.TargetDone[id] then
						return false
					end
				end
				return true
			end
		
			--========================
			-- LOOP
			--========================
			function Feature:Loop()
				while self.State.Grading do
					local values = self.State.PanelRef.Config.Values
					if not values or not values.AutoGradeEnabled then break end
		
					self:MarkDone()
		
					if self:AllDone() then break end
		
					local id = self:GetNextCardToRoll()
		
					if id then
						if not self:CardMeetsOrBeatsTarget(id, self.State.TargetMinRank) then
							self:SendRoll(id)
						else
							self.State.TargetDone[id] = true
						end
					else
						task.wait(0.1)
					end
				end
		
				self:Stop()
			end
		
			--========================
			-- START / STOP
			--========================
			function Feature:Start(panelRef)
				self.State.PanelRef = panelRef
		
				local values = panelRef.Config.Values
				if not values then return self:Stop() end
		
				local cards = normalizeSelectionArray(values.AutoGradeCards)
				local grades = normalizeSelectionArray(values.AutoGradeTarget)
		
				if #cards == 0 or #grades == 0 then return self:Stop() end
				if not self:GetReplicatedData() then return self:Stop() end
		
				local minRank = self:GetTargetMinRank(grades)
				if not minRank then return self:Stop() end
		
				local queue = self:BuildQueue(cards)
				if #queue == 0 then return self:Stop() end
		
				self:Stop()
		
				self.State.Grading = true
				self.State.Queue = queue
				self.State.QueueIndex = 0
				self.State.TargetDone = {}
				self.State.TargetMinRank = minRank
		
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
					AutoGradeEnabled = function(v, _, panel)
						self.State.PanelRef = panel
						if v then self:Start(panel) else self:Stop() end
					end,
					AutoGradeCards = function(_, values, panel)
						self.State.PanelRef = panel
						if values.AutoGradeEnabled then self:Start(panel) end
					end,
					AutoGradeTarget = function(_, values, panel)
						self.State.PanelRef = panel
						if values.AutoGradeEnabled then self:Start(panel) end
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
