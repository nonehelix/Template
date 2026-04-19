return function(Shared)
	local Players = Shared.Players
	local Workspace = Shared.Workspace
	local RunService = Shared.RunService
	local RegisterFeature = Shared.RegisterFeature

	--==================================================
	-- LOCAL HELPERS FOR THIS GAME
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
			table.insert(result, tostring(value))
		end

		return result
	end

	local function getPackItems()
		local items = {"All"}

		if CardConfig and CardConfig.List and CardConfig.List.Packs then
			for _, packName in ipairs(CardConfig.List.Packs) do
				table.insert(items, tostring(packName))
			end
		end

		return items
	end

	local function getMutationItems()
		local items = {"All", "Regular"}

		if CardConfig and CardConfig.List and CardConfig.List.Mutations then
			for _, mutationName in ipairs(CardConfig.List.Mutations) do
				table.insert(items, tostring(mutationName))
			end
		end

		return items
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
					Items = getPackItems(),
					EmptyText = "Nothing selected"
				},
				{
					Id = "AutoBuyMutation",
					Type = "multiselect",
					Label = "Mutation",
					Description = "Choose one or more rarities",
					Items = getMutationItems(),
					EmptyText = "Nothing selected"
				}
			}
		})

		function Feature:GetPackModelType(packModel)
			if not packModel then
				return nil
			end

			if packModel.PrimaryPart and packModel.PrimaryPart.Name and packModel.PrimaryPart.Name ~= "" then
				return packModel.PrimaryPart.Name
			end

			local primary = packModel:FindFirstChildWhichIsA("BasePart")
			if primary and primary.Name and primary.Name ~= "" then
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
					if descendant.Visible and descendant.Text and descendant.Text ~= "" then
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

			if packModel.Name and packModel.Name ~= "" then
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

			if not CardRemote then
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

				AutoBuyPack = function(value, values, panelRef)
					self.State.PanelRef = panelRef
				end,

				AutoBuyMutation = function(value, values, panelRef)
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
end
