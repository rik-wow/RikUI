-- Experience, reputation and durability.

-- Experience and reputation come from the unit readers.
function RikRenderExperience(current, maximum, rested)
    UnitXP = function() return current end
    UnitXPMax = function() return maximum end
    GetXPExhaustion = function() return rested end
    -- The simulator's character watches a retail faction; no faction is watched unless a fixture says so.
    if not RikRenderWatchedFaction then C_Reputation.GetWatchedFactionData = function() return nil end end
    RikUI.XPBar.Refresh()
end

function RikRenderReputation(name, reaction, standing, low, high)
    RikRenderWatchedFaction = true
    C_Reputation.GetWatchedFactionData = function()
        return { factionID = 72, name = name, reaction = reaction, currentStanding = standing,
            currentReactionThreshold = low, nextReactionThreshold = high }
    end
    RikUI.XPBar.Refresh()
end

-- A gain: the bar records the value it showed, then the client raises PLAYER_XP_UPDATE.
function RikRenderExperienceGain(before, after, maximum)
    -- The gain label is part of the bar's animation; captures otherwise run with motion reduced.
    RikUI.Profile.reducedMotion = false
    RikRenderSetOption("xpbar", "xpbar.animations", true)
    RikRenderExperience(before, maximum, nil)
    A_Admin.FireEvent("PLAYER_XP_UPDATE", "player")
    RikRenderExperience(after, maximum, nil)
    A_Admin.FireEvent("PLAYER_XP_UPDATE", "player")
    local row = RikUI.XPBar.Rows.xp
    if row.gainAnim then row.gainAnim:Stop() end
    if row.gainText then row.gainText:SetAlpha(1) end
    if row.flashAnim then row.flashAnim:Stop() end
    if row.flash then row.flash:SetAlpha(0) end
end

-- Durability: the client answers GetInventoryAlertStatus per alert slot (1 worn, 2 broken) and
-- GetInventoryItemDurability per inventory slot.
function RikRenderDurability(statuses, percents, tooltip)
    GetInventoryAlertStatus = function(index) return statuses[index] or 0 end
    GetInventoryItemDurability = function(slot)
        local value = percents and percents[slot]
        if value then return value, 100 end
        return nil
    end
    RikUI.Durability.Refresh()
    local pill = RikUI.Durability.Pill
    local broken = false
    for _, status in pairs(statuses) do if status == 2 then broken = true end end
    if RikUI.Durability.Pulse then RikUI.Durability.Pulse:Stop() end
    if pill.alert then pill.alert:SetAlpha(broken and 0.25 or 0) end
    if RikUI.Durability.Fade then RikUI.Durability.Fade:Stop() end
    pill:SetAlpha(1)
    if tooltip then pill:GetScript("OnEnter")(pill) end
    return pill
end
