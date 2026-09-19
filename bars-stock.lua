-- Hide overlapping stock bars without removing native paging or binding logic.
local core, bars = RikUI, RikUI.Bars
local TARGETS = {
    { overlay = "main", name = "MainActionBar" },
    { overlay = "main", name = "MainMenuBarArtFrame" },
    { overlay = "main", name = "MicroMenu" },
    { overlay = "main", name = "BagsBar" },
    { overlay = "main", name = "StatusTrackingBarManager" },
    { overlay = "bar2", name = "MultiBarBottomLeft" },
    { overlay = "bar3", name = "MultiBarBottomRight" },
    { overlay = "bar4", name = "MultiBarRight" },
    { overlay = "bar5", name = "MultiBarLeft" },
}
local saved, hidden, pending, changing = {}, nil, false, false

local function wantsHidden()
    return bars.enabled and core.Profile.showStockBars ~= true
end

local function hiddenParent()
    if not hidden then
        hidden = CreateFrame("Frame", "RikUIHiddenActionBars", UIParent)
        hidden:Hide()
    end
    return hidden
end

local function reparent(frame, parent)
    changing = true
    local ok, reason = pcall(frame.SetParent, frame, parent)
    changing = false
    if not ok then error(reason) end
end

local function remember(frame)
    if saved[frame] then return end
    saved[frame] = { parent = frame:GetParent() }
    hooksecurefunc(frame, "SetParent", function(self)
        if changing or self:GetParent() == hidden then return end
        -- Restore the latest Blizzard attachment, including Edit Mode changes.
        saved[self].parent = self:GetParent()
        if wantsHidden() then bars.UpdateStockVisibility() end
    end)
end

local function targetFrame(target)
    local frame = _G[target.name]
    if not frame and target.name == "MainActionBar" and ActionButton1 then frame = ActionButton1.bar end
    if type(frame) ~= "table" and type(frame) ~= "userdata" then return end
    if type(frame.SetParent) == "function" and type(frame.GetParent) == "function" then return frame end
end

local function restore(frame, parent)
    reparent(frame, parent)
    -- Native menu layout skips anchors while it is parked outside its container.
    if frame == MicroMenu and parent and parent == MicroMenuContainer and type(parent.Layout) == "function" then
        parent:Layout()
    end
end

local function applyVisibility()
    pending = false
    local parked = {}
    if wantsHidden() then
        for _, target in ipairs(TARGETS) do
            local overlay, frame = bars.Frames[target.overlay], targetFrame(target)
            if overlay and #overlay.buttons == 12 and frame then
                remember(frame)
                local parent = hiddenParent()
                if frame:GetParent() ~= parent then reparent(frame, parent) end
                parked[frame] = true
            end
        end
    end
    for frame, original in pairs(saved) do
        if not parked[frame] and frame:GetParent() == hidden then restore(frame, original.parent) end
    end
end

function bars.UpdateStockVisibility()
    if not core.Profile or pending then return end
    pending = true
    core.Combat.Queue(applyVisibility)
end

local function setStockBars(shown)
    core.Profile.showStockBars = shown == true
    bars.UpdateStockVisibility()
    if InCombatLockdown() then core:Print("Stock bar visibility queued until combat ends.") end
end

core:RegisterCommand("stockbars", function(args)
    if args ~= "show" and args ~= "hide" then
        core:Print("Usage: /rik stockbars show|hide")
        return
    end
    if not core.Profile then core:Print("Still loading."); return end
    setStockBars(args == "show")
end, "Show or hide stock bars, bag/menu buttons and XP/reputation bars: /rik stockbars show|hide")

table.insert(bars.Options.settings, { type = "checkbox", key = "showStockBars", label = "Show stock Blizzard bars",
    get = function() return core.Profile.showStockBars == true end, set = setStockBars })
