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

local function getDebugLog(Shared)
	if type(Shared) == "table" and type(Shared.DebugLog) == "function" then
		return function(message, level)
			Shared.DebugLog("GameRegistry", message, level)
		end
	end

	return function() end
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

local function updateLoadStatus(Shared, status)
	if type(Shared) == "table" then
		Shared.LastGameFeatureLoadStatus = status
	end
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
	local currentPlaceId = game.PlaceId

	for _, entry in ipairs(REGISTERED_GAMES) do
		for _, link in ipairs(entry.Links or {}) do
			local placeId = extractPlaceIdFromLink(link)
			if placeId and placeId == currentPlaceId then
				return entry
			end
		end
	end

	return nil
end

function GameRegistry.IsAllowedGame()
	return GameRegistry.GetCurrentGameEntry() ~= nil
end

function GameRegistry.LoadCurrentGameFeatures(root, Shared)
	local debugLog = getDebugLog(Shared)
	local entry = GameRegistry.GetCurrentGameEntry()
	if not entry then
		local message = "Current game is not registered for PlaceId " .. tostring(game.PlaceId)
		debugLog(message, "warn")
		updateLoadStatus(Shared, {
			Ok = false,
			Step = "GetCurrentGameEntry",
			Reason = message,
			PlaceId = game.PlaceId,
		})
		return false, "Current game is not registered"
	end

	debugLog("Matched game '" .. tostring(entry.Name) .. "' for PlaceId " .. tostring(game.PlaceId))
	Shared.CurrentGameKey = entry.Key

	local moduleScript, resolveError = resolveModule(root, entry)
	if not moduleScript then
		local message = "Could not find module for game '" .. tostring(entry.Name) .. "': " .. tostring(resolveError)
		debugLog(message, "warn")
		updateLoadStatus(Shared, {
			Ok = false,
			Step = "resolveModule",
			Reason = message,
			PlaceId = game.PlaceId,
			GameKey = entry.Key,
		})
		return false, message
	end

	debugLog("Resolved module script '" .. tostring(moduleScript:GetFullName()) .. "'")
	local okRequire, gameModuleOrError = pcall(require, moduleScript)
	if not okRequire then
		local message = "Failed requiring module for game '" .. tostring(entry.Name) .. "': " .. tostring(gameModuleOrError)
		debugLog(message, "warn")
		updateLoadStatus(Shared, {
			Ok = false,
			Step = "require",
			Reason = message,
			PlaceId = game.PlaceId,
			GameKey = entry.Key,
			ModulePath = moduleScript:GetFullName(),
		})
		return false, message
	end

	if type(gameModuleOrError) == "table" and type(gameModuleOrError.Load) == "function" then
		local okLoad, loadError = pcall(function()
			gameModuleOrError.Load(Shared)
		end)
		if not okLoad then
			local message = "Failed loading game '" .. tostring(entry.Name) .. "': " .. tostring(loadError)
			debugLog(message, "warn")
			updateLoadStatus(Shared, {
				Ok = false,
				Step = "module.Load",
				Reason = message,
				PlaceId = game.PlaceId,
				GameKey = entry.Key,
				ModulePath = moduleScript:GetFullName(),
			})
			return false, message
		end

		debugLog("Game module table loaded successfully for '" .. tostring(entry.Key) .. "'")
		updateLoadStatus(Shared, {
			Ok = true,
			Step = "module.Load",
			PlaceId = game.PlaceId,
			GameKey = entry.Key,
			ModulePath = moduleScript:GetFullName(),
		})
		return true, entry
	end

	if type(gameModuleOrError) == "function" then
		local okLoad, loadError = pcall(function()
			gameModuleOrError(Shared)
		end)
		if not okLoad then
			local message = "Failed loading game '" .. tostring(entry.Name) .. "': " .. tostring(loadError)
			debugLog(message, "warn")
			updateLoadStatus(Shared, {
				Ok = false,
				Step = "module function",
				Reason = message,
				PlaceId = game.PlaceId,
				GameKey = entry.Key,
				ModulePath = moduleScript:GetFullName(),
			})
			return false, message
		end

		debugLog("Game module function loaded successfully for '" .. tostring(entry.Key) .. "'")
		updateLoadStatus(Shared, {
			Ok = true,
			Step = "module function",
			PlaceId = game.PlaceId,
			GameKey = entry.Key,
			ModulePath = moduleScript:GetFullName(),
		})
		return true, entry
	end

	local message = "Game module for '" .. tostring(entry.Name) .. "' must return a function or a table with Load"
	debugLog(message, "warn")
	updateLoadStatus(Shared, {
		Ok = false,
		Step = "module return shape",
		Reason = message,
		PlaceId = game.PlaceId,
		GameKey = entry.Key,
		ModulePath = moduleScript:GetFullName(),
	})
	return false, message
end

return GameRegistry
