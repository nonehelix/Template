return {
	Load = function(Shared)
		local Workspace = Shared.Workspace
		local RegisterFeature = Shared.RegisterFeature
		local RegisterTabs = Shared.RegisterTabs

		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local ReplicatedFirst = game:GetService("ReplicatedFirst")
		local Players = game:GetService("Players")

		local player = Players.LocalPlayer
		local unpackArgs = table.unpack or unpack

		--==================================================
		-- TABS
		--==================================================
		RegisterTabs({
			{Name = "Card", Order = 20},
			{Name = "Shop", Order = 25},
			{Name = "Collect", Order = 30},
		})

		--==================================================
		-- GAME REFERENCES
		--==================================================
		local Remotes = ReplicatedStorage:WaitForChild("Remotes")
		local CardRemote = Remotes:WaitForChild("Card")
		local StockRemote = Remotes:WaitForChild("Stock")
		local GradeRemote = Remotes:WaitForChild("Grade")
		local PotionRemote = Remotes:WaitForChild("Potion")

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
		local arrayContains = assert(Shared.arrayContains, "Shared.arrayContains is required")
		local AUTO_BUY_POLL_DELAY = 0.15
		local AUTO_GRADE_REQUEST_DELAY = 0.01
		local REPLICATED_DATA_WAIT_DELAY = 0.1
		local MARKET_BUY_COOLDOWN = 0.08
		local MARKET_CHECK_INTERVAL = 60
		local MARKET_POLL_DELAY = 1
		local COLLECT_POLL_DELAY = 1

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

		local function parseCardActionAmount(value)
			local amount = tonumber(string.match(tostring(value or ""), "%d+")) or 1
			if amount == 10 or amount == 100 then
				return amount
			end

			return 1
		end

		local function fireCardAction(actionName, amountValue, ...)
			local args = {actionName, ...}
			local amount = tostring(parseCardActionAmount(amountValue))

			if amount ~= "1" then
				args[#args + 1] = amount
			end

			CardRemote:FireServer(unpackArgs(args))
		end

		local function runPackMutationCardAction(actionName, amountValue, packValue, mutationValue)
			local pack = normalizePackName(packValue)
			local mutation = tostring(mutationValue or "")

			if pack == "" or mutation == "" then
				return
			end

			fireCardAction(actionName, amountValue, pack, mutation)
		end

		local function addUniqueItem(items, seen, value)
			value = tostring(value or "")
			if value == "" or value == "All" or seen[value] then
				return
			end

			seen[value] = true
			items[#items + 1] = value
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

		local function getCardActionPackItems()
			local items = {}
			local seen = {}

			addUniqueItem(items, seen, "Pirate")
			for _, packName in ipairs(getPackItems()) do
				addUniqueItem(items, seen, packName)
			end

			return items
		end

		local function getMutationItems()
			local items = {"All", "Regular"}

			if CardConfig and CardConfig.List and CardConfig.List.Mutations then
				local mutationList = CardConfig.List.Mutations
				local addedArrayItems = false

				for _, mut in ipairs(mutationList) do
					items[#items + 1] = tostring(mut)
					addedArrayItems = true
				end

				if not addedArrayItems then
					for _, mut in pairs(mutationList) do
						items[#items + 1] = tostring(mut)
					end
				end
			end

			return items
		end

		local function getFilteredMutationItems(excluded)
			local items = {}
			local seen = {}
			excluded = excluded or {}

			local function addMutation(value)
				value = tostring(value or "")
				if excluded[value] then
					return
				end

				addUniqueItem(items, seen, value)
			end

			addMutation("Regular")
			addMutation("Gold")
			addMutation("Emerald")
			for _, mutation in ipairs(getMutationItems()) do
				addMutation(mutation)
			end

			return items
		end

		local function getUpgradeMutationOrder()
			return getFilteredMutationItems({Rainbow = true})
		end

		local function getNextUpgradeMutation(fromMutation)
			fromMutation = tostring(fromMutation or "")
			local mutations = getUpgradeMutationOrder()

			for index, mutation in ipairs(mutations) do
				if tostring(mutation) == fromMutation then
					return mutations[index + 1]
				end
			end

			return nil
		end

		local function getUpgradeFromMutationItems()
			local items = {}
			local mutations = getUpgradeMutationOrder()

			for index, mutation in ipairs(mutations) do
				if index < #mutations then
					items[#items + 1] = mutation
				end
			end

			return items
		end

		local function getDowngradeMutationItems()
			return getFilteredMutationItems({Regular = true})
		end

		local function getBundleMutationItems()
			return getFilteredMutationItems({})
		end

		local function getCardActionAmountItems()
			return {"x1", "x10", "x100"}
		end

		local function registerPackMutationActionFeature(config)
			local key = config.Key
			local packId = key .. "Pack"
			local mutationId = key .. "Mutation"
			local amountId = key .. "Amount"
			local runId = key .. "Run"

			local Feature = RegisterFeature({
				Key = key,
				Tab = "Shop",
				Section = config.Section or key,
				Order = config.Order,

				Defaults = {
					[packId] = config.DefaultPack or "Pirate",
					[mutationId] = config.DefaultMutation or "Regular",
					[amountId] = config.DefaultAmount or "x1",
				},

				Options = {
					{ Id = packId, Type = "select", Label = "Pack", Description = config.PackDescription, Items = getCardActionPackItems },
					{ Id = mutationId, Type = "select", Label = "Mutation", Description = config.MutationDescription, Items = config.MutationItems },
					{ Id = amountId, Type = "select", Label = "Amount", Description = config.AmountDescription, Items = getCardActionAmountItems },
					{ Id = runId, Type = "button", Label = config.ButtonLabel or key, Description = config.ButtonDescription, ButtonText = config.ButtonText or key },
				}
			})

			function Feature:Run(values)
				values = values or {}
				runPackMutationCardAction(config.ActionName or key, values[amountId], values[packId], values[mutationId])
			end

			function Feature:GetHandlers()
				return {
					[runId] = function(_, values)
						self:Run(values)
					end
				}
			end

			return Feature
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

		local function getPanelValues(panelRef)
			return panelRef and panelRef.Config and panelRef.Config.Values or nil
		end

		local function setFeaturePanelRef(feature, panelRef)
			feature.State.PanelRef = panelRef
			return getPanelValues(panelRef)
		end

		local function buildToggleHandler(feature, onEnabled)
			return function(value, _, panelRef)
				setFeaturePanelRef(feature, panelRef)
				if value then
					onEnabled(panelRef)
				else
					feature:Stop()
				end
			end
		end

		local function buildPanelRefHandler(feature)
			return function(_, _, panelRef)
				setFeaturePanelRef(feature, panelRef)
			end
		end

		local function buildRestartHandler(feature, enabledKey)
			return function(_, values, panelRef)
				setFeaturePanelRef(feature, panelRef)
				if values and values[enabledKey] then
					feature:Start(panelRef)
				end
			end
		end

		local function bindPollingToggleFeature(feature, optionId, onTick)
			function feature:Start(panelRef)
				setFeaturePanelRef(self, panelRef)
				if self.State.Running then
					return
				end

				self.State.Running = true

				task.spawn(function()
					while self.State.Running do
						local values = getPanelValues(self.State.PanelRef)
						if not values or not values[optionId] then
							break
						end

						onTick(self)
						task.wait(self.State.PollDelay)
					end

					self.State.Running = false
				end)
			end

			function feature:Stop()
				self.State.Running = false
			end

			function feature:GetHandlers()
				return {
					[optionId] = buildToggleHandler(self, function(panelRef)
						self:Start(panelRef)
					end),
				}
			end

			function feature:Cleanup()
				self:Stop()
				self.State.PanelRef = nil
				if self.State.LastCollectAt then
					table.clear(self.State.LastCollectAt)
				end
			end
		end

		local function getClientTokenFolder()
			local items = Workspace:FindFirstChild("Items")
			local tokens = items and items:FindFirstChild("Tokens")
			return tokens and tokens:FindFirstChild("Client") or nil
		end

		local function getCollectablesFolder()
			local items = Workspace:FindFirstChild("Items")
			local misc = items and items:FindFirstChild("Misc")
			return misc and misc:FindFirstChild("Collectables") or nil
		end

		local function getCollectable(name)
			local collectables = getCollectablesFolder()
			if not collectables then
				return nil
			end

			return collectables:FindFirstChild(name)
		end

		local function isCollectableVisible(collectable)
			if not collectable then
				return false
			end

			if collectable:IsA("BasePart") then
				return collectable.Transparency < 1
			end

			for _, descendant in ipairs(collectable:GetDescendants()) do
				if descendant:IsA("BasePart") and descendant.Transparency < 1 then
					return true
				end
			end

			return false
		end

		local function canCollectVisibleItem(state, itemName)
			local item = getCollectable(itemName)
			if not item or not isCollectableVisible(item) then
				return false
			end

			local now = Workspace:GetServerTimeNow()
			local lastCollect = state.LastCollectAt[itemName] or 0
			return (now - lastCollect) >= state.CooldownSeconds
		end

		local function tryCollectVisibleItem(state, itemName)
			if not canCollectVisibleItem(state, itemName) then
				return
			end

			local fired = pcall(function()
				PotionRemote:FireServer("Collect", itemName)
			end)

			if fired then
				state.LastCollectAt[itemName] = Workspace:GetServerTimeNow()
			end
		end

		local function collectVisibleItems(state)
			for _, itemName in ipairs(state.ItemNames) do
				tryCollectVisibleItem(state, itemName)
			end
		end

		--==================================================
		-- FEATURE: AUTO BUY (CONVEYOR)
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "AutoBuy",
				Tab = "Card",
				Section = "Buying",
				Order = 10,

				Defaults = {
					AutoBuyEnabled = false,
					AutoBuyPack = {},
					AutoBuyMutation = {},
				},

				State = {
					LastBuyTimes = {},
					Running = false,
					PanelRef = nil,
					PackMetadata = setmetatable({}, {__mode = "k"}),
				},

				Options = {
					{ Id = "AutoBuyEnabled", Type = "toggle", Label = "Enable Auto Buy", Description = "Auto buys conveyor packs" },
					{ Id = "AutoBuyPack", Type = "multiselect", Label = "Pack", Description = "Select packs", Items = getPackItems, EmptyText = "Nothing selected" },
					{ Id = "AutoBuyMutation", Type = "multiselect", Label = "Mutation", Description = "Select mutations", Items = getMutationItems, EmptyText = "Nothing selected" },
				}
			})

			function Feature:GetPackMetadata(packModel)
				if not packModel then
					return nil
				end

				local cached = self.State.PackMetadata[packModel]
				if not cached then
					local packTypePart = packModel.PrimaryPart or packModel:FindFirstChildWhichIsA("BasePart")
					local mutationLabel = packModel:FindFirstChild("Mutation", true)

					cached = {
						PackId = packModel.Name ~= "" and packModel.Name or nil,
						PackTypePart = packTypePart,
						MutationLabel = mutationLabel and mutationLabel:IsA("TextLabel") and mutationLabel or nil,
					}
					self.State.PackMetadata[packModel] = cached
				end

				cached.PackId = packModel.Name ~= "" and packModel.Name or cached.PackId

				local packTypePart = cached.PackTypePart
				if not packTypePart or not packTypePart.Parent then
					packTypePart = packModel.PrimaryPart or packModel:FindFirstChildWhichIsA("BasePart")
					cached.PackTypePart = packTypePart
				end

				local mutationLabel = cached.MutationLabel
				if not mutationLabel or not mutationLabel.Parent then
					local foundMutationLabel = packModel:FindFirstChild("Mutation", true)
					mutationLabel = foundMutationLabel and foundMutationLabel:IsA("TextLabel") and foundMutationLabel or nil
					cached.MutationLabel = mutationLabel
				end

				local mutation = "Regular"
				if mutationLabel and mutationLabel.Visible and mutationLabel.Text ~= "" then
					mutation = tostring(mutationLabel.Text)
				end

				return {
					PackId = cached.PackId,
					PackType = packTypePart and packTypePart.Name ~= "" and packTypePart.Name or nil,
					Mutation = mutation,
				}
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
						local metadata = self:GetPackMetadata(child)
						local packId = metadata and metadata.PackId
						local packType = metadata and metadata.PackType
						local mutation = metadata and metadata.Mutation

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
				setFeaturePanelRef(self, panelRef)
				if self.State.Running then
					return
				end

				self.State.Running = true

				task.spawn(function()
					while self.State.Running do
						local values = getPanelValues(self.State.PanelRef)
						if values and values.AutoBuyEnabled then
							self:Tick(values)
						end
						task.wait(AUTO_BUY_POLL_DELAY)
					end
				end)
			end

			function Feature:Stop()
				self.State.Running = false
			end

			function Feature:GetHandlers()
				return {
					AutoBuyEnabled = buildToggleHandler(self, function(panelRef)
						self:Start(panelRef)
					end),
					AutoBuyPack = buildPanelRefHandler(self),
					AutoBuyMutation = buildPanelRefHandler(self),
				}
			end

			function Feature:Cleanup()
				self:Stop()
				self.State.PanelRef = nil
				table.clear(self.State.LastBuyTimes)
				self.State.PackMetadata = setmetatable({}, {__mode = "k"})
			end
		end

		--==================================================
		-- FEATURE: AUTO GRADE
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "AutoGrade",
				Tab = "Card",
				Section = "Grading",
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
					RequestDelay = AUTO_GRADE_REQUEST_DELAY,
					ReplicatedData = nil,
				},

				Options = {
					{ Id = "AutoGradeEnabled", Type = "toggle", Label = "Enable Auto Grade", Description = "Auto grades selected cards" },
					{ Id = "AutoGradeCards", Type = "multiselect", Label = "Select Cards", Description = "Select cards to grade", Items = getAllCardNames, EmptyText = "Nothing selected" },
					{ Id = "AutoGradeTarget", Type = "multiselect", Label = "Target Grade", Description = "Select target grades", Items = getGradeItems(), EmptyText = "Nothing selected" },
				}
			})

			local gradeOrder = {}
			if GradesConfig and GradesConfig.List then
				for i, g in ipairs(GradesConfig.List) do
					gradeOrder[tostring(g)] = i
				end
			end

			local function requireReplicatedDataModule()
				local replicatedDataModule = ReplicatedFirst:FindFirstChild("ReplicatedData")
				if not replicatedDataModule then
					warn("[AutoGrade] Missing ReplicatedFirst.ReplicatedData")
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
					task.wait(REPLICATED_DATA_WAIT_DELAY)
				end

				warn("[AutoGrade] ReplicatedData loaded but GetData never became available")
				return nil
			end

			function Feature:GetReplicatedTable(key)
				local replicatedData = self:GetReplicatedData()
				if not replicatedData then
					return {}
				end

				local ok, data = pcall(function()
					return replicatedData.GetData(key)
				end)

				if not ok or type(data) ~= "table" then
					return {}
				end

				return data
			end

			function Feature:GetOwnedCards()
				return self:GetReplicatedTable("Cards")
			end

			function Feature:GetServerAutoGrades()
				return self:GetReplicatedTable("AutoGrades")
			end

			function Feature:GetLoopDataSnapshot()
				return {
					OwnedCards = self:GetOwnedCards(),
					AutoGrades = self:GetServerAutoGrades(),
				}
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
					if rank > 0 and (minRank == nil or rank < minRank) then
						minRank = rank
					end
				end

				return minRank
			end

			function Feature:GetCardCurrentGrade(cardId, ownedCards)
				local cardData = (ownedCards or self:GetOwnedCards())[tostring(cardId)]
				return type(cardData) == "table" and cardData.Grade or nil
			end

			function Feature:CardMeetsOrBeatsTarget(cardId, targetMinRank, ownedCards)
				local currentRank = self:GetGradeRank(self:GetCardCurrentGrade(cardId, ownedCards))
				return currentRank >= (targetMinRank or math.huge)
			end

			function Feature:CurrentCardNeedsConfirm(cardId, ownedCards, serverAutoGrades)
				local currentGrade = self:GetCardCurrentGrade(cardId, ownedCards)
				if not currentGrade then
					return false
				end

				return arrayContains(serverAutoGrades or self:GetServerAutoGrades(), tostring(currentGrade))
			end

			function Feature:BuildQueue(selectedCards, ownedCards)
				ownedCards = ownedCards or self:GetOwnedCards()
				if type(ownedCards) ~= "table" then
					return {}
				end

				local queue = {}

				if arrayContains(selectedCards, "All") then
					for cardId in pairs(ownedCards) do
						queue[#queue + 1] = tostring(cardId)
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

				ownedCards = ownedCards or self:GetOwnedCards()

				for _, cardId in ipairs(self.State.Queue) do
					local cardData = ownedCards[cardId]
					if not cardData then
						self.State.TargetDone[cardId] = true
					elseif self:CardMeetsOrBeatsTarget(cardId, self.State.TargetMinRank, ownedCards) then
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

				ownedCards = ownedCards or self:GetOwnedCards()

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

			function Feature:SendGradeRoll(cardId, ownedCards, serverAutoGrades)
				if self:CurrentCardNeedsConfirm(cardId, ownedCards, serverAutoGrades) then
					GradeRemote:FireServer("Roll", cardId, nil, true)
				else
					GradeRemote:FireServer("Roll", cardId)
				end
			end

			function Feature:Loop()
				while self.State.Grading do
					local values = getPanelValues(self.State.PanelRef)
					if not values or not values.AutoGradeEnabled then
						self:Stop()
						break
					end

					local snapshot = self:GetLoopDataSnapshot()
					local ownedCards = snapshot.OwnedCards
					local serverAutoGrades = snapshot.AutoGrades

					self:MarkFinishedCards(ownedCards)

					if self:AllCardsDone() then
						self:Stop()
						break
					end

					local nextCard = self:GetNextCardToRoll(ownedCards)
					if not nextCard then
						self:Stop()
						break
					end

					if self:CardMeetsOrBeatsTarget(nextCard, self.State.TargetMinRank, ownedCards) then
						self.State.TargetDone[nextCard] = true
					else
						self:SendGradeRoll(nextCard, ownedCards, serverAutoGrades)
					end

					task.wait(self.State.RequestDelay)
				end
			end

			function Feature:Start(panelRef)
				setFeaturePanelRef(self, panelRef)

				local values = getPanelValues(panelRef)
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

				if not self:GetReplicatedData() then
					self:Stop()
					return
				end

				local targetMinRank = self:GetTargetMinRank(selectedGrades)
				if not targetMinRank then
					self:Stop()
					return
				end

				local ownedCards = self:GetOwnedCards()
				local queue = self:BuildQueue(selectedCards, ownedCards)
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
				self.State.Grading = false
				self.State.Queue = {}
				self.State.QueueIndex = 0
				self.State.TargetDone = {}
				self.State.TargetMinRank = nil
			end

			function Feature:GetHandlers()
				return {
					AutoGradeEnabled = buildToggleHandler(self, function(panelRef)
						self:Start(panelRef)
					end),
					AutoGradeCards = buildRestartHandler(self, "AutoGradeEnabled"),
					AutoGradeTarget = buildRestartHandler(self, "AutoGradeEnabled"),
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
					BuyCooldown = MARKET_BUY_COOLDOWN,
				},

				Options = {
					{ Id = "AutoBuyMarketEnabled", Type = "toggle", Label = "Enable Auto Buy Market", Description = "Auto buys market packs" },
					{ Id = "AutoBuyMarketPack", Type = "multiselect", Label = "Pack", Description = "Select packs", Items = getPackItems, EmptyText = "Nothing selected" },
					{ Id = "AutoBuyMarketMutation", Type = "multiselect", Label = "Mutation", Description = "Select mutations", Items = getMutationItems, EmptyText = "Nothing selected" },
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
				local values = getPanelValues(self.State.PanelRef)
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
				setFeaturePanelRef(self, panelRef)
				self.State.LastCheckTime = 0
				if self.State.Running then
					return
				end

				self.State.Running = true

				task.spawn(function()
					while self.State.Running do
						local values = getPanelValues(self.State.PanelRef)
						if not values or not values.AutoBuyMarketEnabled then
							break
						end

						if tick() - self.State.LastCheckTime >= MARKET_CHECK_INTERVAL then
							self.State.LastCheckTime = tick()
							self:RunStockCheck()
						end

						task.wait(MARKET_POLL_DELAY)
					end

					self.State.Running = false
				end)
			end

			function Feature:Stop()
				self.State.Running = false
			end

			function Feature:GetHandlers()
				return {
					AutoBuyMarketEnabled = buildToggleHandler(self, function(panelRef)
						self.State.LastCheckTime = 0
						self:Start(panelRef)
					end),
					AutoBuyMarketPack = buildPanelRefHandler(self),
					AutoBuyMarketMutation = buildPanelRefHandler(self),
				}
			end

			function Feature:Cleanup()
				self:Stop()
				self.State.PanelRef = nil
			end
		end

		--==================================================
		-- FEATURE: AUTO COLLECT GRADE TOKENS
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "AutoCollectGT",
				Tab = "Collect",
				Section = "Grade Tokens",
				Order = 10,

				Defaults = {
					AutoCollectGT = false,
				},

				State = {
					PanelRef = nil,
					Running = false,
					PollDelay = COLLECT_POLL_DELAY,
					CooldownSeconds = 0.75,
					LastCollectAt = {},
				},

				Options = {
					{ Id = "AutoCollectGT", Type = "toggle", Label = "Auto Collect Grade Tokens", Description = "Auto collects grade tokens" },
				}
			})

			function Feature:CollectVisibleTokens()
				local tokenFolder = getClientTokenFolder()
				if not tokenFolder then
					return
				end

				local now = Workspace:GetServerTimeNow()
				for _, token in ipairs(tokenFolder:GetChildren()) do
					local tokenId = tostring(token.Name or "")
					if tokenId ~= "" and (now - (self.State.LastCollectAt[tokenId] or 0)) >= self.State.CooldownSeconds then
						self.State.LastCollectAt[tokenId] = now
						CardRemote:FireServer("CollectToken", tokenId)
					end
				end
			end

			bindPollingToggleFeature(Feature, "AutoCollectGT", function(self)
				self:CollectVisibleTokens()
			end)
		end

		--==================================================
		-- FEATURE: AUTO COLLECT TRAVEL TOKENS
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "AutoCollectTT",
				Tab = "Collect",
				Section = "Travel Tokens",
				Order = 20,

				Defaults = {
					AutoCollectTT = false,
				},

				State = {
					PanelRef = nil,
					Running = false,
					PollDelay = COLLECT_POLL_DELAY,
					CooldownSeconds = 1200,
					LastCollectAt = {
						TravelToken1 = 0,
						TravelToken2 = 0,
					},
					ItemNames = {"TravelToken1", "TravelToken2"},
				},

				Options = {
					{ Id = "AutoCollectTT", Type = "toggle", Label = "Auto Collect Travel Tokens", Description = "Auto collects travel tokens" },
				}
			})

			bindPollingToggleFeature(Feature, "AutoCollectTT", function(self)
				collectVisibleItems(self.State)
			end)
		end

		--==================================================
		-- FEATURE: AUTO COLLECT POTIONS
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "AutoCollectPotions",
				Tab = "Collect",
				Section = "Potions",
				Order = 30,

				Defaults = {
					AutoCollectPotions = false,
				},

				State = {
					PanelRef = nil,
					Running = false,
					PollDelay = COLLECT_POLL_DELAY,
					CooldownSeconds = 600,
					LastCollectAt = {
						Luck = 0,
						HatchTime = 0,
					},
					ItemNames = {"Luck", "HatchTime"},
				},

				Options = {
					{ Id = "AutoCollectPotions", Type = "toggle", Label = "Auto Collect Potions", Description = "Auto collects potions" },
				}
			})

			bindPollingToggleFeature(Feature, "AutoCollectPotions", function(self)
				collectVisibleItems(self.State)
			end)
		end

		--==================================================
		-- FEATURE: UPGRADE
		--==================================================
		do
			local Feature = RegisterFeature({
				Key = "Upgrade",
				Tab = "Shop",
				Section = "Upgrade",
				Order = 30,

				Defaults = {
					UpgradePack = "Pirate",
					UpgradeFromMutation = "Regular",
					UpgradeAmount = "x1",
				},

				Options = {
					{ Id = "UpgradePack", Type = "select", Label = "Pack", Description = "Select pack", Items = getCardActionPackItems },
					{ Id = "UpgradeFromMutation", Type = "select", Label = "From Mutation", Description = "Select mutation", Items = getUpgradeFromMutationItems },
					{ Id = "UpgradeAmount", Type = "select", Label = "Amount", Description = "Select amount", Items = getCardActionAmountItems },
					{ Id = "UpgradeRun", Type = "button", Label = "Upgrade", Description = "Upgrade selected cards", ButtonText = "Upgrade" },
				}
			})

			function Feature:Run(values)
				values = values or {}

				local pack = normalizePackName(values.UpgradePack)
				local fromMutation = tostring(values.UpgradeFromMutation or "")
				local toMutation = getNextUpgradeMutation(fromMutation)

				if pack == "" or fromMutation == "" or not toMutation or toMutation == "" then
					return
				end

				fireCardAction("Exchange", values.UpgradeAmount, pack, fromMutation, toMutation)
			end

			function Feature:GetHandlers()
				return {
					UpgradeRun = function(_, values)
						self:Run(values)
					end
				}
			end
		end

		--==================================================
		-- FEATURE: DOWNGRADE
		--==================================================
		registerPackMutationActionFeature({
			Key = "Downgrade",
			Section = "Downgrade",
			Order = 31,
			ActionName = "Downgrade",
			DefaultMutation = "Gold",
			MutationItems = getDowngradeMutationItems,
			PackDescription = "Select pack",
			MutationDescription = "Select mutation",
			AmountDescription = "Select amount",
			ButtonDescription = "Downgrade selected cards",
		})

		--==================================================
		-- FEATURE: BUNDLE
		--==================================================
		registerPackMutationActionFeature({
			Key = "Bundle",
			Section = "Bundle",
			Order = 32,
			ActionName = "Bundle",
			DefaultMutation = "Regular",
			MutationItems = getBundleMutationItems,
			PackDescription = "Select pack",
			MutationDescription = "Select mutation",
			AmountDescription = "Select amount",
			ButtonDescription = "Create selected bundles",
		})
	end
}
