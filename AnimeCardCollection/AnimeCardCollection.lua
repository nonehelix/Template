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
		-- ReplicatedData Resolver (Robust)
		--==================================================
		local ReplicatedData = nil

		local function GetReplicatedData()
			if ReplicatedData and type(ReplicatedData.GetData) == "function" then
				return ReplicatedData
			end

			-- Try ReplicatedFirst first (as you said is necessary)
			local rdModule = ReplicatedFirst:FindFirstChild("ReplicatedData")
			if rdModule then
				local success, result = pcall(require, rdModule)
				if success and type(result) == "table" and type(result.GetData) == "function" then
					ReplicatedData = result
					print("[AutoGrade] ReplicatedData loaded from ReplicatedFirst")
					return result
				end
			end

			-- Fallback to Shared
			if Shared and Shared.ReplicatedData and type(Shared.ReplicatedData.GetData) == "function" then
				ReplicatedData = Shared.ReplicatedData
				print("[AutoGrade] ReplicatedData loaded from Shared")
				return ReplicatedData
			end

			warn("[AutoGrade] Could not find ReplicatedData!")
			return nil
		end

		--==================================================
		-- HELPERS
		--==================================================
		local function normalizeSelectionArray(values)
			local result = {}
			if type(values) ~= "table" then return result end
			for _, v in ipairs(values) do
				table.insert(result, tostring(v))
			end
			return result
		end

		local arrayContains = Shared.arrayContains or function(arr, target)
			for _, v in ipairs(arr or {}) do
				if tostring(v) == tostring(target) then return true end
			end
			return false
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
			local cards = {"All"}
			if CardConfig and CardConfig.Packs then
				for _, packData in pairs(CardConfig.Packs) do
					if packData.List then
						for cardName in pairs(packData.List) do
							cardName = tostring(cardName)
							if not seen[cardName] then
								seen[cardName] = true
								table.insert(cards, cardName)
							end
						end
					end
				end
			end
			table.sort(cards)
			return cards
		end

		local function waitForItems(builder, minCount, fallback, timeout)
			timeout = timeout or 5
			local start = os.clock()
			while os.clock() - start < timeout do
				local items = builder()
				if #items >= minCount then return items end
				task.wait(0.1)
			end
			return fallback
		end

		-- Grade order
		local gradeOrder = {}
		if GradesConfig and GradesConfig.List then
			for i, g in ipairs(GradesConfig.List) do
				gradeOrder[tostring(g)] = i
			end
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
					{ Id = "AutoBuyEnabled", Type = "toggle", Label = "Enable Auto Buy", Description = "Auto buys matching conveyor packs" },
					{ Id = "AutoBuyPack", Type = "multiselect", Label = "Pack ID", Description = "Choose one or more packs",
						Items = waitForItems(getPackItems, 2, {"All"}), EmptyText = "Nothing selected" },
					{ Id = "AutoBuyMutation", Type = "multiselect", Label = "Mutation", Description = "Choose one or more rarities",
						Items = waitForItems(getMutationItems, 3, {"All", "Regular"}), EmptyText = "Nothing selected" },
				}
			})

			-- ... (your existing conveyor methods - kept unchanged)
			function Feature:GetPackModelType(packModel)
				if not packModel then return nil end
				if packModel.PrimaryPart and packModel.PrimaryPart.Name ~= "" then return packModel.PrimaryPart.Name end
				local part = packModel:FindFirstChildWhichIsA("BasePart")
				return part and part.Name ~= "" and part.Name or nil
			end

			function Feature:GetPackModelMutation(packModel)
				if not packModel then return "Regular" end
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
				if not packType or packType == "" then return false end
				if type(selectedPacks) ~= "table" or #selectedPacks == 0 then return false end
				if type(selectedMutations) ~= "table" or #selectedMutations == 0 then return false end
				local packOk = arrayContains(selectedPacks, "All") or arrayContains(selectedPacks, packType)
				local mutOk  = arrayContains(selectedMutations, "All") or arrayContains(selectedMutations, mutation)
				return packOk and mutOk
			end

			function Feature:Tick(values)
				if not values.AutoBuyEnabled then return end
				local selectedPacks = normalizeSelectionArray(values.AutoBuyPack)
				local selectedMutations = normalizeSelectionArray(values.AutoBuyMutation)
				if #selectedPacks == 0 or #selectedMutations == 0 then return end

				local packsFolder = Workspace:FindFirstChild("Client") and Workspace.Client:FindFirstChild("Packs")
				if not packsFolder then return end

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
				if self.State.Polling then return end
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
						if value then self:Start(panelRef) else self:Stop() end
					end,
					AutoBuyPack = function(_, _, panelRef) self.State.PanelRef = panelRef end,
					AutoBuyMutation = function(_, _, panelRef) self.State.PanelRef = panelRef end,
				}
			end

			function Feature:Cleanup()
				self:Stop()
				self.State.PanelRef = nil
				table.clear(self.State.LastBuyTimes)
			end
		end

		--==================================================
		-- FEATURE: AUTO GRADE (Robust version)
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
				},

				Options = {
					{ Id = "AutoGradeEnabled", Type = "toggle", Label = "Enable Auto Grade", Description = "Automatically grades selected cards" },
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

			function Feature:GetOwnedCards()
				local rd = GetReplicatedData()
				if not rd then
					warn("[AutoGrade] GetOwnedCards failed - ReplicatedData not found")
					return {}
				end

				local success, cards = pcall(function()
					return rd.GetData("Cards")
				end)

				if not success then
					warn("[AutoGrade] GetData('Cards') errored:", tostring(cards))
					return {}
				end

				if type(cards) ~= "table" then
					warn("[AutoGrade] Cards data is not a table")
					return {}
				end

				return cards
			end

			function Feature:IsGradeGoodEnough(currentGrade, targetGrades)
				if not currentGrade then return false end
				local currentRank = gradeOrder[tostring(currentGrade)] or 0
				for _, tgt in ipairs(targetGrades) do
					if gradeOrder[tostring(tgt)] and currentRank >= gradeOrder[tostring(tgt)] then
						return true
					end
				end
				return false
			end

			function Feature:BuildQueue(selectedCards)
				local owned = self:GetOwnedCards()
				local queue = {}

				if arrayContains(selectedCards, "All") then
					for cardName in pairs(owned) do
						table.insert(queue, tostring(cardName))
					end
				else
					for _, cardName in ipairs(selectedCards) do
						if owned[tostring(cardName)] then
							table.insert(queue, tostring(cardName))
						end
					end
				end

				table.sort(queue)
				return queue
			end

			function Feature:Tick()
				if not self.State.Grading then return end

				local values = self.State.PanelRef and self.State.PanelRef.Config and self.State.PanelRef.Config.Values
				if not values or not values.AutoGradeEnabled then
					self:Stop()
					return
				end

				local selectedCards = normalizeSelectionArray(values.AutoGradeCards)
				local targetGrades  = normalizeSelectionArray(values.AutoGradeTarget)

				if #selectedCards == 0 or #targetGrades == 0 then return end

				if #self.State.Queue == 0 then
					self.State.Queue = self:BuildQueue(selectedCards)
					self.State.QueueIndex = 0
					if #self.State.Queue == 0 then 
						print("[AutoGrade] Queue is empty - no cards to grade")
						return 
					end
				end

				-- Round-robin
				self.State.QueueIndex = self.State.QueueIndex + 1
				if self.State.QueueIndex > #self.State.Queue then
					self.State.QueueIndex = 1
				end

				local cardName = self.State.Queue[self.State.QueueIndex]
				local cardData = self:GetOwnedCards()[cardName]
				local currentGrade = cardData and cardData.Grade

				print("[AutoGrade] Attempting to grade:", cardName, "| Current Grade:", currentGrade or "None")

				if not self:IsGradeGoodEnough(currentGrade, targetGrades) then
					print("[AutoGrade] Firing Roll on:", cardName)
					CardRemote:FireServer("Roll", cardName)
				else
					print("[AutoGrade] Skipping", cardName, "- already good enough")
				end
			end

			function Feature:Start(panelRef)
				self.State.PanelRef = panelRef
				if self.State.Grading then return end

				self.State.Grading = true
				self.State.Queue = {}
				self.State.QueueIndex = 0

				print("[AutoGrade] Starting Auto Grade...")

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
					AutoGradeCards = function(_, _, panelRef) self.State.PanelRef = panelRef end,
					AutoGradeTarget = function(_, _, panelRef) self.State.PanelRef = panelRef end,
				}
			end

			function Feature:Cleanup()
				self:Stop()
				self.State.PanelRef = nil
			end
		end

		--==================================================
		-- FEATURE: AUTO BUY MARKET (unchanged)
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
					{ Id = "AutoBuyMarketEnabled", Type = "toggle", Label = "Enable Auto Buy Market", Description = "Automatically buys selected packs from the market every 60 seconds" },
					{ Id = "AutoBuyMarketPack", Type = "multiselect", Label = "Pack ID", Description = "Choose packs to buy from market", Items = waitForItems(getPackItems, 2, {"All"}), EmptyText = "Nothing selected" },
					{ Id = "AutoBuyMarketMutation", Type = "multiselect", Label = "Mutation", Description = "Choose mutations/rarities to buy", Items = waitForItems(getMutationItems, 3, {"All", "Regular"}), EmptyText = "Nothing selected" },
				}
			})

			-- Your existing market code (shortened for space - paste your full version if needed)
			function Feature:GetMarketStock()
				-- ... your existing GetMarketStock code ...
				-- (keep it exactly as you had it)
			end

			-- ... keep RunStockCheck, Start, Stop, GetHandlers, Cleanup as they were ...
		end
	end
}
