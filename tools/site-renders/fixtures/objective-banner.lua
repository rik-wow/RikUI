-- Exercise Blizzard's own objective banner, including pooled reuse and native alpha resets.
function RikRenderObjectiveCard(title, worldQuest, previous)
    local frame = ObjectiveTrackerTopBannerFrame
    local width, height = frame:GetSize()
    if previous then
        RikRenderObjectiveBanner(previous)
        frame:StopBanner()
    end
    frame.questTitle, frame.showWorldQuests = title, worldQuest == true
    TopBannerManager_Show(frame)
    frame.PopAnim:Stop()
    for _, key in ipairs({ "Title", "Subtitle", "UpLine", "DownLine", "UpLineGlow", "DownLineGlow" }) do
        frame[key]:SetAlpha(1)
    end
    frame:SetAlpha(1)
    assert(frame:GetWidth() == width and frame:GetHeight() == height, "Native animation envelope changed")
    assert(frame.rikCardHost and frame.rikCardHost.ignoreInLayout, "Missing text card")
    assert(frame.Title:GetWidth() <= 568 and frame.Title:GetWidth() == frame.Subtitle:GetWidth(), "Unbounded banner text")
    for _, key in ipairs({ "BlackBar", "UpLine", "DownLine", "UpLineGlow", "DownLineGlow" }) do
        assert(not frame[key]:GetTexture(), "Animated native decoration survived: " .. key)
    end
    return frame
end

function RikRenderObjectiveCardBounds()
    local frame = ObjectiveTrackerTopBannerFrame
    local host = assert(frame.rikCardHost)
    assert(host:GetWidth() >= frame.Title:GetWidth() + 31, "Title exceeds card width")
    assert(host:GetHeight() >= frame.Title:GetHeight() + frame.Subtitle:GetHeight() + 34, "Title/subtitle exceed card height")
    assert(frame.Title:GetHeight() > 0 and frame.Subtitle:GetHeight() > 0, "Collapsed banner text")
end
