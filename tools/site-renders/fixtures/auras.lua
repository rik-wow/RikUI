-- Auras and timed status: aura data, mirror timers, loss of control, proc cues.

-- Auras. The seed addon makes Blizzard's aura containers work in the simulator (their intrinsic
-- OnLoad, and the PLAYER/RAID filter parts); the simulator only ever puts auras on the player, so a
-- unit's aura reads can be pointed at the player's list. Containers refresh on request, because
-- the simulator does not route UNIT_AURA into a container's private partition.
local AURA_SOURCES = {}

local auraShimsReady = false

local function installAuraShims()
    if auraShimsReady then return end
    auraShimsReady = true
    local auraFunctions = {}
    for name, fn in pairs(C_UnitAuras) do
        if type(fn) == "function" then auraFunctions[name] = fn end
    end
    for name, fn in pairs(auraFunctions) do
        C_UnitAuras[name] = function(unit, ...)
            if type(unit) == "string" and AURA_SOURCES[unit] then return fn(AURA_SOURCES[unit], ...) end
            return fn(unit, ...)
        end
    end
end

-- entries: { { id, name, icon, duration, harmful = true, own = true }, ... }; from: units whose aura
-- reads should answer with the player's list, e.g. { target = "player" }. Debuffs count as the
-- player's own; a buff does when `own` says so (the seed's PLAYER filter reads RikRenderOwnAuras).
function RikRenderAuras(entries, from)
    installAuraShims()
    for unit, source in pairs(from or {}) do AURA_SOURCES[unit] = source end
    A_Admin.ClearBuffs()
    for _, aura in ipairs(entries) do
        if aura.own then RikRenderOwnAuras[aura[1]] = true end
        if aura.harmful then
            A_Admin.AddDebuff(aura[1], aura[2], aura[3], aura[4] or 0, 0)
        else
            A_Admin.AddBuff(aura[1], aura[2], aura[3], aura[4] or 0, 0)
        end
    end
    RikRenderRefreshAuras()
end

-- Every RikUI aura container reads its unit's list again.
function RikRenderRefreshAuras()
    for name, frame in pairs(_G) do
        if type(name) == "string" and name:match("^RikUI") and type(frame) == "table" and type(frame.GetObjectType) == "function"
            and frame:GetObjectType() == "AuraContainer" and type(GetForbiddenObjectTable) == "function" then
            local private = GetForbiddenObjectTable(frame)
            if type(private) == "table" and type(private.UpdateAllAuras) == "function" then
                pcall(private.UpdateAllAuras, private)
                if type(private.OnWeaponEnchantChanged) == "function" then pcall(private.OnWeaponEnchantChanged, private) end
            end
        end
    end
end

-- A breath, fatigue or feign-death timer: the client sends the range with MIRROR_TIMER_START and the
-- bar polls GetMirrorTimerProgress (milliseconds).
function RikRenderMirrorTimer(timer, value, maximum, label)
    GetMirrorTimerProgress = function(name) if name == timer then return value end return 0 end
    GetMirrorTimerInfo = function(index) if index == 1 then return timer, value, maximum, -1, false, label end return "UNKNOWN" end
    A_Admin.FireEvent("MIRROR_TIMER_START", timer, value, maximum, -1, false, label)
end

-- Blizzard's loss-of-control alert with one active effect; RikUI skins the frame in place.
function RikRenderLossOfControl(locType, spell, text, icon, duration, remaining)
    local now = GetTime()
    local data = { locType = locType, spellID = spell, displayText = text, iconTexture = icon,
        startTime = now - (duration - remaining), timeRemaining = remaining, duration = duration,
        lockoutSchool = 0, priority = 5, displayType = 2 }
    C_LossOfControl.GetActiveLossOfControlData = function() return data end
    C_LossOfControl.GetActiveLossOfControlDataCount = function() return 1 end
    LossOfControlFrame:SetUpDisplay(false, data)
    LossOfControlFrame:Show()
end

-- A proc overlay at a screen location (Enum.ScreenLocationType); the native pool draws it and RikUI
-- replaces the artwork.
function RikRenderProc(locationType, spell)
    local getBool = GetCVarBool
    GetCVarBool = function(name, ...) if name == "displaySpellActivationOverlays" then return true end return getBool(name, ...) end
    A_Admin.FireEvent("SPELL_ACTIVATION_OVERLAY_SHOW", spell or 20375, "Interface\\SpellActivationOverlay\\Art_of_War", locationType, 1, 255, 255, 255)
    -- The overlays fade in through an animation; the capture shows them at rest.
    for _, overlay in ipairs({ SpellActivationOverlayFrame:GetChildren() }) do
        if overlay:IsShown() then
            if overlay.animIn then overlay.animIn:Stop() end
            overlay:SetAlpha(1)
        end
    end
    SpellActivationOverlayFrame:SetAlpha(1)
end
