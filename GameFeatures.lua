return function(Shared)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	print("=== DEBUG START ===")
	print("ReplicatedStorage:", ReplicatedStorage)

	print("Remotes exists:", ReplicatedStorage:FindFirstChild("Remotes"))
	print("Card remote exists:", ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Card"))

	print("Modules exists:", ReplicatedStorage:FindFirstChild("Modules"))
	print("Config exists:", ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("Config"))
	print("Core exists:", ReplicatedStorage:FindFirstChild("Modules")
		and ReplicatedStorage.Modules:FindFirstChild("Config")
		and ReplicatedStorage.Modules.Config:FindFirstChild("Core"))
	print("CardConfig exists:", ReplicatedStorage:FindFirstChild("Modules")
		and ReplicatedStorage.Modules:FindFirstChild("Config")
		and ReplicatedStorage.Modules.Config:FindFirstChild("Core")
		and ReplicatedStorage.Modules.Config.Core:FindFirstChild("CardConfig"))
	print("=== DEBUG END ===")

	return
end
