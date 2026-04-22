local GameRegistry = {}

local REGISTERED_GAMES = {
	{
		Key = "AnimeCardCollection",
		Name = "Anime Card Collection",
		Links = {
			"https://www.roblox.com/es/games/76285745979410/Anime-Card-Collection",
		}
	},
	{
		Key = "AnimeEternal",
		Name = "Anime Eternal",
		Links = {
			"https://www.roblox.com/es/games/90462358603255/Anime-Eternal",
		}
	},
	{
		Key = "AriseCrossover",
		Name = "Arise Crossover",
		PlaceIds = {
			87039211657390,
		},
		Links = {
			"https://www.roblox.com/es/games/87039211657390/ARISE-1-0",
		},
		Detect = function()
			local replicatedStorage = game:GetService("ReplicatedStorage")
			local indexer = replicatedStorage:FindFirstChild("Indexer")
			local sharedModules = replicatedStorage:FindFirstChild("SharedModules")

			return replicatedStorage:FindFirstChild("BridgeNet2") ~= nil
				and indexer ~= nil
				and sharedModules ~= nil
				and indexer:FindFirstChild("ShadowTier") ~= nil
				and indexer:FindFirstChild("DungeonMaps") ~= nil
				and sharedModules:FindFirstChild("PetsService") ~= nil
				and sharedModules:FindFirstChild("ExtraFunctions") ~= nil
		end
	},
}

local function extractPlaceIdFromLink(link)
	if type(link) ~= "string" then
		return nil
	end

	local id = string.match(link, "/games/(%d+)")
	if id then
		return tonumber(id)
	end

	id = string.match(link, "placeId=(%d+)")
	if id then
		return tonumber(id)
	end

	return nil
end

local function containsNumber(values, numberValue)
	if type(values) ~= "table" or numberValue == nil then
		return false
	end

	for _, value in ipairs(values) do
		if tonumber(value) == numberValue then
			return true
		end
	end

	return false
end

local function hasRegisteredLinkPlaceId(entry, placeId)
	for _, link in ipairs(entry.Links or {}) do
		local linkPlaceId = extractPlaceIdFromLink(link)
		if linkPlaceId and linkPlaceId == placeId then
			return true
		end
	end

	return false
end

local function runDetector(entry)
	if type(entry.Detect) ~= "function" then
		return false
	end

	local ok, detected = pcall(entry.Detect)
	if not ok then
		warn("Game detector failed for '" .. tostring(entry.Name) .. "': " .. tostring(detected))
		return false
	end

	return detected == true
end

local function matchesCurrentGame(entry)
	local currentPlaceId = game.PlaceId
	local currentGameId = game.GameId

	return containsNumber(entry.PlaceIds, currentPlaceId)
		or hasRegisteredLinkPlaceId(entry, currentPlaceId)
		or containsNumber(entry.GameIds, currentGameId)
		or containsNumber(entry.UniverseIds, currentGameId)
		or runDetector(entry)
end

local function describeChildren(parent)
	if not parent or not parent.GetChildren then
		return "(none)"
	end

	local names = {}
	for _, child in ipairs(parent:GetChildren()) do
		names[#names + 1] = child.Name
	end

	if #names == 0 then
		return "(none)"
	end

	table.sort(names)
	return table.concat(names, ", ")
end

local function resolveModule(root, entry)
	if not root then
		return nil, "Root is nil"
	end

	local candidateNames = {
		entry.Key,
		entry.Key .. ".lua",
	}

	for _, candidateName in ipairs(candidateNames) do
		local directModule = root:FindFirstChild(candidateName)
		if directModule and directModule:IsA("ModuleScript") then
			return directModule, nil
		end
	end

	local folder = root:FindFirstChild(entry.Key)
	if not folder then
		return nil, "Missing folder '" .. tostring(entry.Key) .. "' under " .. root:GetFullName() .. ". Root children: " .. describeChildren(root)
	end

	if folder:IsA("ModuleScript") then
		return folder, nil
	end

	for _, candidateName in ipairs(candidateNames) do
		local moduleScript = folder:FindFirstChild(candidateName)
		if moduleScript and moduleScript:IsA("ModuleScript") then
			return moduleScript, nil
		end
	end

	return nil, "Missing module '" .. tostring(entry.Key) .. "' or '" .. tostring(entry.Key .. ".lua") .. "' inside folder " .. folder:GetFullName() .. ". Folder children: " .. describeChildren(folder)
end

function GameRegistry.GetCurrentGameEntry()
	for _, entry in ipairs(REGISTERED_GAMES) do
		if matchesCurrentGame(entry) then
			return entry
		end
	end

	return nil
end

function GameRegistry.IsAllowedGame()
	return GameRegistry.GetCurrentGameEntry() ~= nil
end

function GameRegistry.LoadCurrentGameFeatures(root, Shared)
	local entry = GameRegistry.GetCurrentGameEntry()
	if not entry then
		local message = "Current game is not registered for PlaceId " .. tostring(game.PlaceId) .. " / GameId " .. tostring(game.GameId)
		warn("Game-Specific features failed")
		return false, message
	end

	print("Detected Game: " .. tostring(entry.Name) .. " (" .. tostring(game.PlaceId) .. " / " .. tostring(game.GameId) .. ")")
	Shared.CurrentGameKey = entry.Key

	local moduleScript, resolveError = resolveModule(root, entry)
	if not moduleScript then
		local message = "Could not find module for game '" .. tostring(entry.Name) .. "': " .. tostring(resolveError)
		warn("Game-Specific features failed")
		return false, message
	end

	local okRequire, gameModuleOrError = pcall(require, moduleScript)
	if not okRequire then
		local message = "Failed requiring module for game '" .. tostring(entry.Name) .. "': " .. tostring(gameModuleOrError)
		warn("Game-Specific features failed")
		return false, message
	end

	if type(gameModuleOrError) == "table" and type(gameModuleOrError.Load) == "function" then
		local okLoad, loadError = pcall(function()
			gameModuleOrError.Load(Shared)
		end)
		if not okLoad then
			local message = "Failed loading game '" .. tostring(entry.Name) .. "': " .. tostring(loadError)
			warn("Game-Specific features failed")
			return false, message
		end

		print("Game-Specific features loaded succesfully")
		return true, entry
	end

	if type(gameModuleOrError) == "function" then
		local okLoad, loadError = pcall(function()
			gameModuleOrError(Shared)
		end)
		if not okLoad then
			local message = "Failed loading game '" .. tostring(entry.Name) .. "': " .. tostring(loadError)
			warn("Game-Specific features failed")
			return false, message
		end

		print("Game-Specific features loaded succesfully")
		return true, entry
	end

	local message = "Game module for '" .. tostring(entry.Name) .. "' must return a function or a table with Load"
	warn("Game-Specific features failed")
	return false, message
end

return GameRegistry
