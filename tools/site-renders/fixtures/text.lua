-- Screen text and small HUD labels.

-- Small HUD frames.
function RikRenderFramerate(fps)
    GetFramerate = function() return fps end
    IsCpuBound = IsCpuBound or function() return nil end
    FramerateFrame:Show()
    FramerateFrame.fpsTime = 0
    FramerateFrame:OnUpdate(1)
    return FramerateFrame
end

function RikRenderNavigationMarker(distance, actorName, nth)
    local actor = RikRenderActor(actorName, nth)
    C_Navigation.GetDistance = function() return distance end
    IN_GAME_NAVIGATION_RANGE = "%s yds" -- the client resolves the |4 plural token when drawing
    local frame = SuperTrackedFrame
    -- The marker follows the client's navigation state every frame; the capture holds one moment.
    frame:SetScript("OnUpdate", nil)
    frame:Show()
    frame.isClamped = false
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", actor.x, RikRenderWorld.height - actor.y + 40)
    frame:UpdateDistanceText()
    frame.Icon:Show()
    frame:SetAlpha(1)
    return frame
end

-- Screen text. FadingFrame keeps time from GetTime, so the clock moves past the fade-in.
function RikRenderZoneText(zone, subzone)
    A_Admin.SetZone(zone, 37)
    A_Admin.SetSubZone(subzone or "")
    A_Admin.FireEvent("ZONE_CHANGED_NEW_AREA")
    RikRenderAdvanceClock(1)
    ZoneTextFrame:SetAlpha(1)
    return ZoneTextFrame
end

function RikRenderSubZoneText(subzone)
    A_Admin.SetSubZone(subzone)
    A_Admin.FireEvent("ZONE_CHANGED")
    RikRenderAdvanceClock(1)
    SubZoneTextFrame:SetAlpha(1)
    -- The invisible frame sits at the screen centre while its string hangs from the top; wrap it.
    SubZoneTextFrame:ClearAllPoints()
    SubZoneTextFrame:SetPoint("TOPLEFT", SubZoneTextString, "TOPLEFT", -8, 8)
    SubZoneTextFrame:SetPoint("BOTTOMRIGHT", SubZoneTextString, "BOTTOMRIGHT", 8, -8)
    return SubZoneTextFrame
end

function RikRenderErrorText(text)
    UIErrorsFrame:SetFading(false) -- the line has just arrived; it fades two seconds later
    UIErrorsFrame:AddMessage(text, 1, 0.1, 0.1)
    return UIErrorsFrame
end

function RikRenderRaidWarning(text)
    RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
    -- The line fades in by the clock; move the clock into the hold.
    RikRenderAdvanceClock(1)
    return RaidWarningFrame
end
