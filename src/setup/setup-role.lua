-- Suggest a role once per login/reload; all writes still use the Apply engine.
local core, setup = RikUI, RikUI.Setup
local POPUP = "RIKUI_SWITCH_ROLE"
local shown, queued, pending = false, false, nil

local function eligible()
    local db = core.CharDB
    local marker = db and db.applied
    local _, class = UnitClass("player")
    if not db or db.askRole ~= true or type(marker) ~= "table" or marker.class ~= class then return end
    if setup.IsApplying() or setup.IsUndoing() then return end
    local progress = type(db.undo) == "table" and db.undo.progress
    if type(progress) == "table" and next(progress) then return end
    return marker, class
end

local function current(context)
    local marker, class = eligible()
    return core.CharDB == context.db and marker == context.marker and class == context.class
        and marker.role == context.previousRole and core.Presets[class] == context.preset
        and setup.GuessRole(class) == context.role
end

local function dismiss(_, context)
    if pending == context then pending = nil end
end

local function accept(_, context)
    if not context or pending ~= context then return end
    pending = nil
    core.Combat.Queue(function()
        if not current(context) then
            core:Print("Role switch cancelled: talents or setup changed; use /rik role to check.")
            return
        end
        setup.Apply(context.class, context.role,
            { bars = true, macros = true, binds = false, cvars = false, layout = false })
    end)
end

local function stopAsking(_, context)
    if not context or pending ~= context then return end
    pending = nil
    if core.CharDB == context.db then context.db.askRole = false end
end

local function installPopup()
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return false end
    StaticPopupDialogs[POPUP] = {
        text = "Looks like you went %s. Switch to the %s preset? This replaces preset bars and macros.",
        button1 = "Yes", button2 = "No", button3 = "Stop asking",
        OnAccept = accept, OnCancel = dismiss, OnAlt = stopAsking,
        OnHide = function(_, context) dismiss(nil, context) end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    return true
end

local function suggest()
    queued = false
    if shown then return end
    local marker, class = eligible()
    if not marker then return end
    local role = setup.GuessRole(class)
    if not role or role == marker.role or not installPopup() then return end
    local preset = core.Presets[class]
    local context = { db = core.CharDB, marker = marker, class = class,
        previousRole = marker.role, role = role, preset = preset }
    pending = context
    local dialog = StaticPopup_Show(POPUP, preset.roles[role].label or role, role, context)
    if dialog then shown = true else pending = nil end
end

local function request()
    if shown or queued then return end
    queued = true
    core.Combat.Queue(suggest)
end

for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "CHARACTER_POINTS_CHANGED",
    "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED" }) do
    core:RegisterEvent(event, request)
end

core:RegisterCommand("role", function(args)
    if args ~= "" then core:Print("Usage: /rik role"); return end
    local _, class = UnitClass("player")
    local role, trees, reason = setup.GuessRole(class)
    if not role then core:Print("Role unavailable: " .. reason); return end
    local values = {}
    for _, tree in ipairs(trees) do
        values[#values + 1] = string.format("%s=%d", tree.name, tree.points)
    end
    core:Print("Role guess: " .. role .. " (" .. table.concat(values, ", ") .. ").")
end, "Show the talent-based role and points per tree: /rik role")
