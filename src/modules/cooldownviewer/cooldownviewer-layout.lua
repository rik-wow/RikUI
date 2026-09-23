-- Native items retain their layout. Only viewer roots follow addon-owned, saved Layout holders.
local core, viewer, layout = RikUI, RikUI.CooldownViewer, RikUI.Layout
local SPECS = {
    EssentialCooldownViewer = { "cooldownessential", "Essential cooldowns", 0, 414, 280, 50 },
    UtilityCooldownViewer = { "cooldownutility", "Utility cooldowns", 0, 500, 280, 30 },
    BuffIconCooldownViewer = { "cooldownbuffs", "Tracked buffs", 300, 414, 220, 40 },
    BuffBarCooldownViewer = { "cooldownbars", "Buff timers", 300, 490, 220, 90 },
}
local entries = {}
viewer.Holders = {}

local function number(value)
    return (type(issecretvalue) ~= "function" or not issecretvalue(value))
        and type(value) == "number" and value > 0 and value < math.huge
end

function viewer.Editing()
    return core.EditMode and core.EditMode.IsActive()
end

function viewer.Moving()
    for _, entry in pairs(entries) do
        if layout.IsUnlocked(entry.key) then return true end
    end
    return false
end

local function anchor(entry)
    if InCombatLockdown() or viewer.Editing() then return end
    local frame, holder = entry.frame, entry.holder
    if frame.isManagedFrame == true and type(frame.BreakFromFrameManager) == "function"
        and (frame.ignoreFramePositionManager ~= true or frame:GetParent() ~= UIParent) then
        frame:BreakFromFrameManager()
    end
    -- Base geometry skips Edit Mode bookkeeping: release its old snap registration explicitly,
    -- as native dragging does, so hiding the old target cannot move or save this viewer.
    if frame.snappedToFrame and type(frame.ClearFrameSnap) == "function" then frame:ClearFrameSnap() end
    local parent = frame:GetParent()
    local parentScale = parent and parent:GetEffectiveScale()
    local holderScale = holder:GetEffectiveScale()
    if number(parentScale) and number(holderScale) then
        local scale = holderScale / parentScale
        if frame:GetScale() ~= scale then frame:SetScaleBase(scale) end
    end
    local point, relative, relativePoint, x, y
    if frame:GetNumPoints() == 1 then point, relative, relativePoint, x, y = frame:GetPoint(1) end
    if point ~= "TOPLEFT" or relative ~= holder or relativePoint ~= "TOPLEFT" or x ~= 0 or y ~= 0 then
        frame:ClearAllPointsBase()
        frame:SetPointBase("TOPLEFT", holder, "TOPLEFT", 0, 0)
    end
    local width, height = frame:GetSize()
    if not number(width) then width = entry.width end
    if not number(height) then height = entry.height end
    holder:SetSize(width, height)
end

local function update(entry)
    local holder = entry.holder
    local shown = entry.frame:IsShown()
    local readable = type(issecretvalue) ~= "function" or not issecretvalue(shown)
    holder:SetShown(not viewer.Editing() and ((readable and shown == true) or layout.IsUnlocked(entry.key)))
    anchor(entry)
end

local function refreshEntry(entry)
    local ok, reason = pcall(update, entry)
    if ok or entry.warned then return end
    entry.warned = true
    core:Print("Cooldown viewer placement: " .. tostring(reason))
end

function viewer.RefreshLayout()
    for _, entry in pairs(entries) do refreshEntry(entry) end
    if viewer.RefreshControls then viewer.RefreshControls() end
end

function viewer.SetMoving(open)
    if open and (InCombatLockdown() or viewer.Editing()) then return end
    if not open then layout.EndDrag() end
    for _, entry in pairs(entries) do layout.SetUnlocked(entry.key, open) end
    viewer.RefreshLayout()
end

function viewer.Track(name, frame)
    local spec = SPECS[name]
    if not spec or entries[name] then return end
    -- These are actual frame methods saved by EditModeSystemMixin, not its bookkeeping overrides.
    if type(frame.SetPointBase) ~= "function" or type(frame.ClearAllPointsBase) ~= "function"
        or type(frame.SetScaleBase) ~= "function" then return end
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetFrameStrata("BACKGROUND")
    -- Transparent placement anchor; Layout's temporary move overlay owns all group chrome.
    holder:SetSize(spec[5], spec[6])
    holder:Hide()
    local entry = { key = spec[1], frame = frame, holder = holder, width = spec[5], height = spec[6],
        nativeScale = frame:GetScale() }
    entries[name], viewer.Holders[name] = entry, holder
    layout.Register(holder, entry.key, { point = "BOTTOM", relativePoint = "BOTTOM", x = spec[3], y = spec[4] },
        { label = spec[2], owner = viewer, onApply = function() refreshEntry(entry) end,
            onUnlock = viewer.RefreshLayout })
    core.Hooks.Script(frame, "OnHide", function() refreshEntry(entry) end)
    if core.EditMode then core.EditMode.Guard(frame, spec[2], function() refreshEntry(entry) end) end
    viewer.CreateControls()
end

function viewer.EnableLayout()
    local function refresh() viewer.RefreshLayout() end
    for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        core:RegisterEvent(event, refresh, viewer)
    end
    core:RegisterEvent("PLAYER_REGEN_DISABLED", function() viewer.SetMoving(false) end, viewer)
    if type(EventRegistry) == "table" and type(EventRegistry.RegisterCallback) == "function" then
        EventRegistry:RegisterCallback("EditMode.Enter", function()
            viewer.SetMoving(false)
            if InCombatLockdown() then return end
            for _, entry in pairs(entries) do
                local frame = entry.frame
                if type(frame.systemInfo) == "table" and type(frame.ApplySystemAnchor) == "function" then
                    local ok, reason = pcall(function()
                        if number(entry.nativeScale) then frame:SetScaleBase(entry.nativeScale) end
                        frame:ApplySystemAnchor()
                    end)
                    if not ok and not entry.warned then
                        entry.warned = true
                        core:Print("Cooldown viewer Edit Mode: " .. tostring(reason))
                    end
                end
            end
        end, viewer)
        EventRegistry:RegisterCallback("EditMode.Exit", refresh, viewer)
    end
end
