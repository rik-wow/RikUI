-- Hide overlapping stock bars without removing native paging or binding logic.
local core, bars = RikUI, RikUI.Bars
local BUTTONS = 12

-- MicroMenu and BagsBar belong to micromenu.lua, which parks them once its strip exists.
local TARGETS = {
    { overlay = "main", name = "MainActionBar" },
    { overlay = "main", name = "MainMenuBarArtFrame" },
    { overlay = "main", name = "StatusTrackingBarManager" },
    { overlay = "bar2", name = "MultiBarBottomLeft" },
    { overlay = "bar3", name = "MultiBarBottomRight" },
    { overlay = "bar4", name = "MultiBarRight" },
    { overlay = "bar5", name = "MultiBarLeft" },
    { control = "stance", name = "StanceBar" },
    { control = "pet", name = "PetActionBar" },
}
local known, pending = {}, false

local function wantsHidden()
    return bars.enabled and core.Profile.showStockBars ~= true
end

local function targetFrame(target)
    local frame = _G[target.name]
    if not frame and target.name == "MainActionBar" and ActionButton1 then frame = ActionButton1.bar end
    if type(frame) ~= "table" and type(frame) ~= "userdata" then return end
    if type(frame.SetParent) == "function" and type(frame.GetParent) == "function" then return frame end
end

-- A stock frame goes only after its RikUI replacement exists.
local function replacementReady(target)
    if target.control then return bars.ControlFrames ~= nil and bars.ControlFrames[target.control] ~= nil end
    local overlay = bars.Frames[target.overlay]
    return overlay ~= nil and #overlay.buttons == BUTTONS
end

local function applyVisibility()
    pending = false
    local parked = {}
    if wantsHidden() then
        for _, target in ipairs(TARGETS) do
            local frame = targetFrame(target)
            if frame and replacementReady(target) then
                -- Native bindings still invoke these buttons, so their events stay registered.
                core.Hide.Frame(frame, true)
                known[frame], parked[frame] = target, true
            end
        end
    end
    for frame, target in pairs(known) do
        if not parked[frame] and core.Hide.IsHidden(frame) then core.Hide.Restore(frame, target.onRestored) end
    end
end

function bars.UpdateStockVisibility()
    if not core.Profile or pending then return end
    pending = true
    core.Combat.Queue(applyVisibility)
end

local function describe(target)
    local frame = targetFrame(target)
    if not frame then return target.name .. ": missing" end
    local name = type(frame.GetName) == "function" and frame:GetName() or nil
    local state = "native"
    if core.Hide.IsHidden(frame) then
        state = InCombatLockdown() and "hide queued" or "hidden"
    elseif not replacementReady(target) then
        state = "native, no RikUI replacement"
    end
    return target.name .. " -> " .. tostring(name or "unnamed") .. " (" .. state .. ")"
end

local function printStatus()
    core:Print("Stock frames (" .. (wantsHidden() and "hiding" or "showing") .. "):")
    for _, target in ipairs(TARGETS) do core:Print(describe(target)) end
end

local function setStockBars(shown)
    core.Profile.showStockBars = shown == true
    bars.UpdateStockVisibility()
    if InCombatLockdown() then core:Print("Stock bar visibility queued until combat ends.") end
end

core:RegisterCommand("stockbars", function(args)
    if args ~= "show" and args ~= "hide" and args ~= "status" then
        core:Print("Usage: /rik stockbars show|hide|status")
        return
    end
    if not core.Profile then core:Print("Still loading."); return end
    if args == "status" then printStatus() else setStockBars(args == "show") end
end, "Show, hide or report stock bars, stance/pet bars, bag/menu buttons and XP/reputation bars: /rik stockbars show|hide|status")

table.insert(bars.Options.settings, { type = "checkbox", key = "showStockBars", label = "Show stock Blizzard bars",
    get = function() return core.Profile.showStockBars == true end, set = setStockBars })
