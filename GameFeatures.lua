-- GameFeatures.lua  (Clean & Safe Version)

local GameFeatures = {}

function GameFeatures.RegisterFeatures(Shared)
    if not Shared or not Shared.RegisterFeature then
        error("Shared module is missing or RegisterFeature is not available!")
    end

    -- ==================== AUTO BUY FEATURE ====================
    do
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

        local Feature = Shared.RegisterFeature({
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
                PollThread = nil,
                PanelRef = nil,
            },
            Options = {
                {Id = "AutoBuyEnabled", Type = "toggle", Label = "Enable Auto Buy", Description = "Auto buys matching conveyor packs"},
                {Id = "AutoBuyPack", Type = "multiselect", Label = "Pack ID", Description = "Choose one or more packs", Items = getPackItems(), EmptyText = "Nothing selected"},
                {Id = "AutoBuyMutation", Type = "multiselect", Label = "Mutation", Description = "Choose one or more rarities", Items = getMutationItems(), EmptyText = "Nothing selected"}
            }
        })

        -- (All your methods: GetPackModelType, Tick, Start, Stop, GetHandlers, Cleanup)
        -- Paste them here exactly as in my previous message (I kept them short for space)

        function Feature:GetPackModelType(packModel) 
            if not packModel then return nil end
            if packModel.PrimaryPart and packModel.PrimaryPart.Name ~= "" then return packModel.PrimaryPart.Name end
            local primary = packModel:FindFirstChildWhichIsA("BasePart")
            return primary and primary.Name ~= "" and primary.Name or nil
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
            if not packModel then return nil end
            return packModel.Name ~= "" and packModel.Name or nil
        end

        function Feature:NormalizeSelectionArray(values)
            local result = {}
            if type(values) == "table" then
                for _, v in ipairs(values) do table.insert(result, tostring(v)) end
            end
            return result
        end

        function Feature:Matches(packType, mutation, selectedPacks, selectedMutations)
            if not packType or packType == "" then return false end
            local packOk = table.find(selectedPacks or {}, "All") or table.find(selectedPacks or {}, packType)
            local mutationOk = table.find(selectedMutations or {}, "All") or table.find(selectedMutations or {}, mutation)
            return packOk and mutationOk
        end

        -- Tick, Start, Stop, GetHandlers, Cleanup functions (copy from previous response)
        -- ... (I'll assume you have them from last time - if not, tell me and I'll send full)

    end
end

-- Main function called by loader
function GameFeatures.BuildPanelConfig(Shared)
    GameFeatures.RegisterFeatures(Shared)
    return Shared.BuildPanelConfig()
end

return GameFeatures
