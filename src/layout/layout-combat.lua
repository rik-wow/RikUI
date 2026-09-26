-- Refresh the combat area of an existing profile without replacing its surrounding UI.
local core, layout = RikUI, RikUI.Layout
local KEYS = { "combatresource", "cooldowns", "castplayer", "classbuffs", "classeffects",
    "combopoints", "totems", "druidmana", "swingtimer", "player", "target",
    "focus", "petframe", "tot", "casttarget", "castfocus", "castpet" }

function layout.ApplyCombatHUD()
    if InCombatLockdown() then return nil, "Cannot change the HUD in combat." end
    if not core.Profile then return nil, "Still loading." end
    if core.Setup.IsApplying() or (core.Setup.IsUndoing and core.Setup.IsUndoing()) then
        return nil, "Finish the pending Setup operation."
    end
    local positions = layout.PresetPositions(layout.MatchingPreset() or "hud")
    local profile, copy = core.Profile, core.Setup.CopyState
    profile.layoutUndo = { positions=copy(profile.positions),
        chatSize=copy(profile.chat and profile.chat.size) or false }
    layout.LockAll()
    for _, key in ipairs(KEYS) do profile.positions[key] = copy(positions[key]) end
    core:Changed()
    layout.Apply()
    -- A custom surrounding frame keeps its place; only the requested combat groups give way.
    for _, key in ipairs(KEYS) do
        if layout.Groups[key] then layout.Settle(key) end
    end
    core:Print("Combat HUD arranged. /rik layout undo reverts it; /rik move adjusts frames.")
    return true
end

core:RegisterCommand("hud", function(args)
    if args ~= "" then core:Print("Usage: /rik hud. Undo with /rik layout undo."); return end
    local ok, reason = layout.ApplyCombatHUD()
    if not ok then core:Print(reason) end
end, "Arrange the combat HUD, keeping other frame positions and settings")
