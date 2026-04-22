-- === POTASSIUM ADMIN PANEL LOADER (Fixed for Settings File Name) ===

repeat task.wait() until game:IsLoaded()

local function loadModule(url)
    local success, result = pcall(function()
        return loadstring(game:HttpGet(url))()
    end)
    
    if not success then
        error("[AdminPanel] Failed to load from:\n" .. url .. "\nError: " .. tostring(result))
    end
    if not result then
        error("[AdminPanel] Module returned nil: " .. url)
    end
    return result
end

-- Load core files
local Shared       = loadModule("https://raw.githubusercontent.com/nonehelix/Template/main/Shared.lua")
local GameRegistry = loadModule("https://raw.githubusercontent.com/nonehelix/Template/main/GameRegistry.lua")
local PanelUI      = loadModule("https://raw.githubusercontent.com/nonehelix/Template/main/PanelUI.lua")

-- Load game-specific module
local currentEntry = GameRegistry.GetCurrentGameEntry()

if not currentEntry then
    warn("[AdminPanel] Current game is not registered. Loading universal panel only.")
else
    print("[AdminPanel] Detected game: " .. currentEntry.Name)
    
    -- CRITICAL FIX: Set the key on the Shared table
    Shared.CurrentGameKey = currentEntry.Key
    
    local moduleUrl = "https://raw.githubusercontent.com/nonehelix/Template/main/" ..
                      currentEntry.Key .. "/" .. currentEntry.Key .. ".lua"
    
    local success, gameModule = pcall(function()
        return loadModule(moduleUrl)
    end)
    
    if success and gameModule then
        if type(gameModule) == "function" then
            pcall(gameModule, Shared)
        elseif type(gameModule) == "table" and type(gameModule.Load) == "function" then
            pcall(gameModule.Load, Shared)
        end
        print("[AdminPanel] Game-specific features loaded successfully.")
    else
        warn("[AdminPanel] Failed to load game module for " .. currentEntry.Name)
    end
end

-- Build and initialize the panel
local panelConfig = Shared.BuildPanelConfig()
local panel = PanelUI.new(panelConfig)
panel:Init()

print("[AdminPanel] Panel loaded successfully!")