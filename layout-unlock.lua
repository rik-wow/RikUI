-- What the player touches in the arrangement system. Holding a key shows a lock tag on every layout
-- group and a master tag at the top of the screen; clicking a tag unlocks that group. An unlocked
-- group gets the animated overlay of layout-drag.lua and stays draggable until it is locked again,
-- the session ends or combat starts. The key is the RIKUI_UNLOCK binding (Bindings.xml); while that
-- has no key, holding Ctrl+Alt+Shift together does the same. Tags are plain frames on UIParent:
-- nothing here touches a secure frame.
local core, layout, skin, media, motion = RikUI, RikUI.Layout, RikUI.Skin, RikUI.Media, RikUI.Motion
layout.Tags = {}

local BINDING = "RIKUI_UNLOCK"
local TAG_HEIGHT, TAG_PAD, DOT, STAGGER, MASTER_Y = 18, 6, 8, 0.01, -60
local LOCKED, OPEN = { 1, 0.82, 0, 1 }, { 0.3, 0.75, 1, 1 }
local TEXT = { unlock = "Unlock all", lock = "Lock all", combat = "Frames are locked in combat" }
local held, everything, unlocked, order = false, false, {}, 0

BINDING_HEADER_RIKUI = "RikUI"
BINDING_NAME_RIKUI_UNLOCK = "Hold to show frame locks"

function layout.IsHeld() return held end
function layout.IsUnlocked(key) return unlocked[key] == true end
-- True after "unlock all" even on a screen without a single group yet.
function layout.IsMoving() return everything or next(unlocked) ~= nil end

-- Names for the groups whose modules register without a label of their own.
local LABELS = { main = "Main bar", bar2 = "Bar 2", bar3 = "Bar 3", bar4 = "Bar 4", bar5 = "Bar 5",
    stance = "Stance bar", pet = "Pet bar", xpbar = "XP bar", player = "Player frame", target = "Target frame",
    tot = "Target of target", petframe = "Pet frame", focus = "Focus frame", castplayer = "Player castbar",
    casttarget = "Target castbar", castfocus = "Focus castbar", castpet = "Pet castbar", buffs = "Buffs",
    debuffs = "Debuffs", minimap = "Minimap", micromenu = "Micro menu", bags = "Bags", chat = "Chat window",
    loot = "Loot", questtracker = "Quest tracker", questtimers = "Quest timers", damagemeter = "Damage meter",
    durability = "Durability", mirrortimers = "Breath and fatigue", swingtimer = "Swing timer",
    combopoints = "Combo points", totems = "Totems" }

function layout.Label(key)
    local group = layout.Groups[key]
    return group and group.label or LABELS[key] or key
end
local labelOf = layout.Label

local function paint(tag, open)
    tag.dot:SetVertexColor(unpack(open and OPEN or LOCKED))
    tag.label:SetTextColor(unpack(open and OPEN or LOCKED))
end

local function decorate(tag, text)
    tag.fill = skin.Fill(tag, skin.BACKING)
    tag.edge = skin.Outline(tag)
    tag.dot = tag:CreateTexture(nil, "ARTWORK")
    tag.dot:SetTexture(skin.FLAT)
    tag.dot:SetSize(DOT, DOT)
    tag.dot:SetPoint("LEFT", tag, "LEFT", TAG_PAD, 0)
    tag.label = tag:CreateFontString(nil, "OVERLAY")
    media.Font(tag.label, "small")
    tag.label:SetPoint("LEFT", tag.dot, "RIGHT", TAG_PAD, 0)
    tag.label:SetText(text)
    local width = type(tag.label.GetStringWidth) == "function" and tag.label:GetStringWidth() or nil
    tag:SetSize((type(width) == "number" and width or 8 * #text) + DOT + 3 * TAG_PAD, TAG_HEIGHT)
end

local function newTag(text, onClick)
    local tag = CreateFrame("Button", nil, UIParent)
    tag:SetFrameStrata("TOOLTIP")
    decorate(tag, text)
    order = order + 1
    tag.fade = motion.Tween(tag, 0, 1, skin.FADE_SECONDS, order * STAGGER)
    tag:SetScript("OnClick", onClick)
    tag:Hide()
    return tag
end

local function setUnlocked(key, open)
    if open and InCombatLockdown() then return end
    unlocked[key] = open and true or nil
    if not open then everything = false end
    if layout.Tags[key] then paint(layout.Tags[key], open) end
    if layout.RefreshOverlay then layout.RefreshOverlay(key) end
end

local function tagFor(key)
    local tag = layout.Tags[key]
    if tag then return tag end
    tag = newTag(labelOf(key), function() setUnlocked(key, not unlocked[key]) end)
    paint(tag, unlocked[key] == true)
    layout.Tags[key] = tag
    return tag
end

-- A tag sits on its group's top left corner; at the top of the screen it drops inside the group.
local function placeTag(key)
    local rect, screen = layout.Rect(key), layout.Screen()
    if not rect or not screen then return end
    local tag = tagFor(key)
    local bottom = math.min(rect.top, screen.height - TAG_HEIGHT)
    tag:ClearAllPoints()
    tag:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", rect.left, bottom)
    if not tag:IsShown() then
        tag:Show()
        motion.Play(tag.fade)
    end
end

local function masterText()
    if InCombatLockdown() then return TEXT.combat end
    return layout.IsMoving() and TEXT.lock or TEXT.unlock
end

local function refreshMaster()
    local tag = layout.MasterTag
    tag.label:SetText(masterText())
    paint(tag, layout.IsMoving())
end

function layout.UnlockAll()
    if InCombatLockdown() then return false end
    everything = true
    for key in pairs(layout.Groups) do setUnlocked(key, true) end
    refreshMaster()
    return true
end

function layout.LockAll()
    if layout.EndDrag then layout.EndDrag() end
    everything = false
    for key in pairs(layout.Groups) do setUnlocked(key, false) end
    refreshMaster()
end

local function toggleAll()
    if layout.IsMoving() then layout.LockAll() else layout.UnlockAll() end
    refreshMaster()
end

local function showTags()
    refreshMaster()
    layout.MasterTag:Show()
    motion.Play(layout.MasterTag.fade)
    if InCombatLockdown() then return end
    for key in pairs(layout.Groups) do placeTag(key) end
end

local function hideTags()
    layout.MasterTag:Hide()
    for _, tag in pairs(layout.Tags) do tag:Hide() end
end

local function setHeld(value)
    if held == value then return end
    held = value
    if held then showTags() else hideTags() end
end

-- Called by the RIKUI_UNLOCK binding on key down and key up.
function layout.HoldKey(state) setHeld(state == "down") end

local function chordDown()
    return IsControlKeyDown() and IsAltKeyDown() and IsShiftKeyDown()
end

local function onModifier()
    if type(GetBindingKey) == "function" and GetBindingKey(BINDING) then return end
    setHeld(chordDown() == true)
end

-- Tags and overlays follow a group that moved or changed size. The old name is kept: layout.lua and
-- options.lua call it.
function layout.RefreshMovers()
    if held and not InCombatLockdown() then
        for key in pairs(layout.Groups) do placeTag(key) end
    end
    if layout.RefreshOverlay then
        for key in pairs(unlocked) do layout.RefreshOverlay(key) end
    end
end

layout.StopMoving = layout.LockAll

local function count(set)
    local total = 0
    for _ in pairs(set) do total = total + 1 end
    return total
end

layout.MasterTag = newTag(TEXT.unlock, toggleAll)
layout.MasterTag:SetPoint("TOP", UIParent, "TOP", 0, MASTER_Y)

core:RegisterCommand("move", function(args)
    if args == "" then
        if InCombatLockdown() then core:Print("Cannot move frames in combat."); return end
        toggleAll()
        core:Print(layout.IsMoving() and "Frames unlocked: drag them, Shift drags without snapping. /rik move locks."
            or "Frames locked.")
        return
    end
    if args:lower() ~= "reset" then core:Print("Usage: /rik move [reset]"); return end
    local ok, reason = layout.Reset()
    core:Print(ok and "Frame positions reset." or reason)
end, "Unlock or lock every frame, or restore defaults: /rik move [reset]")

core:RegisterCommand("scale", function(args)
    local ok, reason = layout.SetScale(tonumber(args))
    core:Print(ok and ("Frame scale: " .. core.Profile.scale) or reason)
end, "Scale every registered frame: /rik scale <0.25-3>")

core:RegisterCommand("layout", function(args)
    if args ~= "" and layout.PresetCommand then return layout.PresetCommand(args) end
    core:Print("Layout groups=" .. count(layout.Groups) .. " unlocked=" .. count(unlocked)
        .. " key=" .. tostring(type(GetBindingKey) == "function" and GetBindingKey(BINDING) or nil))
end, "Show the frame arrangement state, or apply a layout: /rik layout [list|undo|<name>]")

core:RegisterEvent("MODIFIER_STATE_CHANGED", onModifier)
-- Every rectangle changes with the screen; layout-rects.lua settles again, and nothing stays unlocked.
core:RegisterEvent("UI_SCALE_CHANGED", function() layout.LockAll() end)
core:RegisterEvent("DISPLAY_SIZE_CHANGED", function() layout.LockAll() end)
core:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if layout.IsMoving() then core:Print("Frames locked for combat.") end
    layout.LockAll()
    if held then hideTags(); showTags() end
end)
core:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if held then hideTags(); showTags() end
end)
