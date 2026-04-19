return function(Shared)
	local Players = Shared.Players
	local Workspace = Shared.Workspace
	local RunService = Shared.RunService
	local RegisterFeature = Shared.RegisterFeature

	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		warn("[GameFeatures] Missing ReplicatedStorage.Remotes")
		return
	end

	local CardRemote = remotesFolder:FindFirstChild("Card")
	if not CardRemote then
		warn("[GameFeatures] Missing ReplicatedStorage.Remotes.Card")
		return
	end

	local modulesFolder = ReplicatedStorage:FindFirstChild("Modules")
	if not modulesFolder then
		warn("[GameFeatures] Missing ReplicatedStorage.Modules")
		return
	end

	local configFolder = modulesFolder:FindFirstChild("Config")
	if not configFolder then
		warn("[GameFeatures] Missing ReplicatedStorage.Modules.Config")
		return
	end

	local coreFolder = configFolder:FindFirstChild("Core")
	if not coreFolder then
		warn("[GameFeatures] Missing ReplicatedStorage.Modules.Config.Core")
		return
	end

	local cardConfigModule = coreFolder:FindFirstChild("CardConfig")
	if not cardConfigModule then
		warn("[GameFeatures] Missing ReplicatedStorage.Modules.Config.Core.CardConfig")
		return
	end

	local CardConfig = require(cardConfigModule)
