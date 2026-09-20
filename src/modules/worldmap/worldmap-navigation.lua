-- Guarded return-to-player action; native UI owns quest interactions.
local core, map = RikUI, RikUI.WorldMap
local nav = {}
map.Navigation = nav
local function readable(value, kind) return not core.Secret.IsSecret(value) and type(value) == kind end
local function number(value)
    return readable(value, "number") and value == value and value > -math.huge and value < math.huge
end
function nav.Call(reader, ...)
    if type(reader) ~= "function" then return nil end
    local ok, value = pcall(reader, ...)
    if ok and not core.Secret.IsSecret(value) then return value end
end
function nav.Run(action)
    if InCombatLockdown() then core:Print("World map: this action is available after combat."); return false end
    local ok, reason = pcall(action)
    if not ok then core:Print("World map: " .. tostring(reason)) end
    return ok
end
function nav.Player(frame)
    return nav.Run(function()
        local id = C_Map and nav.Call(C_Map.GetBestMapForUnit, "player")
        if not number(id) or id <= 0 then error("Player location unavailable.", 0) end
        frame:SetMapID(id)
    end)
end
