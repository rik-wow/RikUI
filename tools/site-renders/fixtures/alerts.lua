-- Alerts, banners and toasts through their own systems.

-- Alert toasts through their own systems. The loot toast obeys the enableLootToasts CVar.
local function freezeAlerts(system)
    for frame in system.alertFramePool:EnumerateActive() do
        if frame.animIn then frame.animIn:Stop() end
        if frame.waitAndAnimOut then frame.waitAndAnimOut:Stop() end
        frame:SetAlpha(1)
    end
end

function RikRenderAlerts(kinds)
    local getBool = C_CVar.GetCVarBool
    C_CVar.GetCVarBool = function(name, ...)
        if name == "enableLootToasts" then return true end
        return getBool(name, ...)
    end
    local systems = {}
    for _, kind in ipairs(kinds) do
        if kind == "loot" then
            local link = select(2, GetItemInfo(6948))
            assert(LootAlertSystem:AddAlert(link, 1, 0, 0, nil, false, false, 0, false, false, false), "loot alert refused")
            systems[#systems + 1] = LootAlertSystem
        elseif kind == "money" then
            -- The client draws coin icons inside the money string; the simulator has none.
            GetMoneyString = function(copper) return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100) end
            assert(MoneyWonAlertSystem:AddAlert(15342), "money alert refused")
            systems[#systems + 1] = MoneyWonAlertSystem
        elseif kind == "achievement" then
            assert(AchievementAlertSystem:AddAlert(6), "achievement alert refused")
            systems[#systems + 1] = AchievementAlertSystem
        else error("Unknown alert " .. tostring(kind)) end
    end
    for _, system in ipairs(systems) do freezeAlerts(system) end
    AlertFrame:Show()
    -- Alert frames are pooled under UIParent and anchored to AlertFrame; a group holds them all.
    local frames = { AlertFrame }
    for _, system in ipairs(systems) do
        for frame in system.alertFramePool:EnumerateActive() do frames[#frames + 1] = frame end
    end
    return frames
end

-- Centre-screen banners. The event toast manager reads the next toast from the client.
function RikRenderEventToast(title, subtitle, textureKit)
    local info = { eventToastID = 1, title = title, subtitle = subtitle,
        displayType = Enum.EventToastDisplayType.NormalTitleAndSubTitle, uiTextureKit = textureKit or "levelup" }
    C_EventToastManager.GetNextToastToDisplay = function() return info end
    EventToastManagerFrame:DisplayToast(true)
    local toast = EventToastManagerFrame.currentDisplayingToast
    assert(toast, "no event toast shown")
    for _, region in ipairs({ toast:GetRegions() }) do region:SetAlpha(1) end
    toast:SetAlpha(1)
    EventToastManagerFrame:SetAlpha(1)
    return EventToastManagerFrame
end

function RikRenderBossBanner(name)
    A_Admin.FireEvent("BOSS_KILL", 1, name)
    assert(BossBanner:IsShown(), "boss banner hidden")
    BossBanner.Title:SetAlpha(1)
    BossBanner.SubTitle:SetAlpha(1)
    return BossBanner
end

function RikRenderObjectiveBanner(title)
    local frame = ObjectiveTrackerTopBannerFrame
    frame.questTitle, frame.showWorldQuests = title, false
    TopBannerManager_Show(frame)
    assert(frame:IsShown(), "objective banner hidden")
    frame.PopAnim:Stop()
    for _, key in ipairs({ "Title", "Subtitle", "UpLine", "DownLine" }) do
        if frame[key] then frame[key]:SetAlpha(1) end
    end
    frame:SetAlpha(1)
    return frame
end

-- Social toasts. Their templates' animation groups inherit parentKeys the simulator drops, so the
-- groups are created from Blizzard's own templates before the alert code plays them.
local function socialAnimations(frame)
    if not frame.animIn then frame.animIn = frame:CreateAnimationGroup(nil, "SocialToastAnimInTemplate") end
    if not frame.waitAndAnimOut then
        local group = frame:CreateAnimationGroup(nil, "SocialToastAnimOutTemplate")
        if not group.animOut then group.animOut = group:CreateAnimation("Alpha") end
        frame.waitAndAnimOut = group
    end
end

local function freezeSocial(frame)
    frame.animIn:Stop()
    frame.waitAndAnimOut:Stop()
    frame:SetAlpha(1)
end

function RikRenderTimeAlert(seconds)
    GetSessionTime = function() return seconds end
    -- The client resolves the |4 plural tokens SecondsToTime emits when it draws the string; the
    -- simulator draws them raw, so the resolved text is supplied.
    SecondsToTime = function()
        local hours, minutes = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
        return string.format("%d %s %d %s", hours, hours == 1 and "Hour" or "Hours", minutes, minutes == 1 and "Minute" or "Minutes")
    end
    socialAnimations(TimeAlertFrame)
    TimeAlertFrame:Start(600000)
    TimeAlertFrame:OnUpdate(0)
    freezeSocial(TimeAlertFrame)
    return TimeAlertFrame
end

function RikRenderFriendToast(invites)
    BNGetNumFriendInvites = function() return invites end
    socialAnimations(BNToastFrame)
    -- A new friend request: the pending-invite line uses a plural token the simulator leaves raw.
    BNToastFrame:AddToast(5, invites)
    assert(BNToastFrame:IsShown(), "friend toast hidden")
    freezeSocial(BNToastFrame)
    return BNToastFrame
end

function RikRenderVoiceToast()
    local frame = VoiceChatPromptActivateChannel
    socialAnimations(frame)
    if frame.Text and (frame.Text:GetText() or "") == "" then
        frame.Text:SetText(VOICE_CHAT_PROMPT_CHANNEL_ACTIVATE or "Voice chat is available for this channel.")
    end
    frame:Show()
    frame:SetAlpha(1)
    return frame
end
