local GameRegistry = {}

local REGISTERED_GAMES = {
	{
		Name = "Anime Card Collection",
		Folder = "AnimeCardCollection",
		Module = "AnimeCardCollection",
		Links = {
			"https://www.roblox.com/es/games/76285745979410/Anime-Card-Collection",
		}
	},
	{
		Name = "Anime Eternal",
		Folder = "AnimeEternal",
		Module = "AnimeEternal",
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

local function resolveModule(root, entry)
	if not root or not entry then
		return nil
	end

	local folder = root:FindFirstChild(entry.Folder)
	if not folder then
		return nil
	end

	local moduleScript = folder:FindFirstChild(entry.Module)
	if not moduleScript then
		return nil
	end

	return moduleScript
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
	local entry = GameRegistry.GetCurrentGameEntry()
	if not entry then
		return false, "Current game is not registered"
	end

	local moduleScript = resolveModule(root, entry)
	if not moduleScript then
		return false, "Could not find module for game: " .. tostring(entry.Name)
	end

	local okRequire, gameModuleOrError = pcall(require, moduleScript)
	if not okRequire then
		return false, "Failed requiring module for game '" .. tostring(entry.Name) .. "': " .. tostring(gameModuleOrError)
	end

	if type(gameModuleOrError) == "table" and type(gameModuleOrError.Load) == "function" then
		local okLoad, loadError = pcall(gameModuleOrError.Load, Shared)
		if not okLoad then
			return false, "Failed loading game '" .. tostring(entry.Name) .. "': " .. tostring(loadError)
		end
		return true, entry
	end

	if type(gameModuleOrError) == "function" then
		local okLoad, loadError = pcall(gameModuleOrError, Shared)
		if not okLoad then
			return false, "Failed loading game '" .. tostring(entry.Name) .. "': " .. tostring(loadError)
		end
		return true, entry
	end

	return false, "Game module for '" .. tostring(entry.Name) .. "' must return a function or a table with Load"
end

return GameRegistry
