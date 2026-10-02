-- The arrangement system on a populated screen: whole-screen layouts, unlocked overlays, lock tags,
-- the chat grip and the General page's layout rows. RikUI places and draws everything; these only
-- supply the character's state and the capture roots.

-- A populated screen out of combat: the sample paladin one second into Holy Light with a seal up,
-- two cooldowns running and a swing in progress; chat lines, the Elwynn quest log, experience with
-- rest, the bag strip's items and the minimap tiles. The simulator's character is in a party of four;
-- the screen shows a solo character.
function RikRenderScreenState()
    RikRenderSpellbook()
    RikRenderCooldowns({ { id = 853, duration = 60, elapsed = 19.1 }, { id = 1022, duration = 300, elapsed = 268.1 } })
    A_Admin.AddBuff(20287, "Seal of Righteousness", 132325, 30, 0)
    A_Admin.SetPartySize(0)
    A_Admin.FireEvent("GROUP_ROSTER_UPDATE")
    RikRenderCast()
    RikRenderSwing()
    RikUI.Cooldowns.Rebuild()
    RikUI.UnitFrames.Refresh()
    -- The simulator's pet always exists and the frame's visibility driver would show it again after a
    -- layout change; the paladin has no pet.
    pcall(UnregisterStateDriver, RikUIUnit_petframe, "visibility")
    RikUIUnit_petframe:Hide()
    RikRenderRefreshAuras()
    RikRenderMinimapTiles()
    RikRenderChatLines()
    RikRenderQuestLog()
    RikRenderTrackerOnly()
    RikRenderExperience(1240, 2800, 900)
    RikRenderBagItems()
    RikUI.MicroMenu.RefreshBags()
    RikUI.Bars.Refresh()
end

-- A capture root for part of the screen: every child of UIParent is re-parented to a holder covering
-- the crop and keeps its screen anchors, as RikRenderGroup does for a few frames. A capture of the
-- whole screen names UIParent itself instead.
function RikRenderScreen(name, left, bottom, width, height)
    local holder = CreateFrame("Frame", name, UIParent)
    holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    holder:SetSize(width, height)
    holder:SetFrameStrata("BACKGROUND")
    holder:SetFrameLevel(0)
    local ok, children = pcall(function() return { UIParent:GetChildren() } end)
    assert(ok, "Cannot list the children of UIParent")
    for _, child in ipairs(children) do
        if child ~= holder then pcall(child.SetParent, child, holder) end
    end
    return holder
end

-- Under reduced motion the client parks an overlay's sweep band outside the overlay, where the overlay
-- clips it away. The simulator draws children outside a clipping parent, so the parked bands are hidden.
local function hideBands()
    for _, overlay in pairs(RikUI.Layout.Overlays) do
        if overlay.band then overlay.band:Hide() end
    end
end

-- Every group unlocked, as /rik move leaves the screen.
function RikRenderUnlocked()
    assert(RikUI.Layout.UnlockAll(), "Unlock failed")
    RikUI.Layout.RefreshMovers()
    hideBands()
end

-- One group unlocked; the chat window's grip lives on its overlay.
function RikRenderUnlockedGroup(key)
    assert(RikUI.Layout.SetUnlocked(key, true), "Could not unlock " .. key)
    RikUI.Layout.RefreshMovers()
    hideBands()
    return RikUI.Layout.Overlays[key]
end

-- The lock tags shown while the unlock key is held.
function RikRenderHeldTags()
    RikUI.Layout.HoldKey("down")
end

-- Exercise the real party/raid preview controls and preset setter.
function RikRenderLayoutGroup(kind)
    assert(RikUI.UnitFrames.Party.SetTest(false))
    assert(RikUI.UnitFrames.Raid.SetTest(false))
    local group = kind == "party" and RikUI.UnitFrames.Party or RikUI.UnitFrames.Raid
    assert(group.SetTest(true))
    RikRenderSetOption("general", "layoutPreset", "healer")
end
