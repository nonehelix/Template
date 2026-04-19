return function(Shared)
	local GamesFolder = script.Parent:WaitForChild("Games")
	local currentPlaceId = game.PlaceId

	local gameModules = {
		require(GamesFolder:WaitForChild("AnimeCardCollection")),
		require(GamesFolder:WaitForChild("AnimeEternal")),
	}

	for _, gameModule in ipairs(gameModules) do
		if type(gameModule) == "table" and type(gameModule.IsForPlace) == "function" then
			if gameModule.IsForPlace(currentPlaceId) then
				if type(gameModule.Load) == "function" then
					gameModule.Load(Shared)
					return gameModule
				end
			end
		end
	end

	warn("[AdminPanel] No GameFeatures registered for place:", currentPlaceId)
	return nil
end
