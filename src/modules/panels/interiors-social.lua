local interiors, skin = RikUI.Interiors, RikUI.Skin
local TEXT = { "Name", "name", "info", "Text", "Label", "Title", "Description", "description",
    "title", "Date", "Day", "Level", "Zone", "Rank", "Note", "GuildInfo", "Points", "DialogLabel" }
local ART = { "Background", "background", "BG", "Bg", "Border", "TitleBackground", "TitleBar",
    "Left", "Middle", "Right", "TopTsunami1", "BottomTsunami1", "TopLeftTsunami", "TopRightTsunami",
    "BottomLeftTsunami", "BottomRightTsunami", "RewardBackground", "GuildCornerL", "GuildCornerR" }

local function calendar(frame)
    local name = type(frame.GetName) == "function" and frame:GetName()
    if type(name) ~= "string" or not name:match("^CalendarDayButton%d+$") then return end
    interiors.Row(frame)
    skin.Typeface(_G[name .. "DateFrameDate"])
    local background = _G[name .. "EventBackgroundTexture"]
    if skin.IsRegion(background) then background:SetAlpha(0) end
    local normal = type(frame.GetNormalTexture) == "function" and frame:GetNormalTexture()
    if skin.IsRegion(normal) then normal:SetAlpha(0) end
end

local function social(frame)
    local row = false
    for _, key in ipairs(TEXT) do
        local region = frame[key]
        if skin.IsRegion(region) and type(region.SetFont) == "function" then row = true; skin.Typeface(region) end
    end
    if row then interiors.Row(frame); skin.Strip(frame, ART) end
    if skin.IsRegion(interiors.Icon(frame)) then interiors.Item(frame) end
    skin.Typeface(frame.HiddenDescription)
    calendar(frame)
end
interiors.Register("social", { "FriendsFrame", "GuildFrame", "CommunitiesFrame", "PVEFrame", "LFGParentFrame",
    "RaidFrame", "RaidInfoFrame", "PVPUIFrame", "PVPMatchScoreboard", "PVPMatchResults", "InspectFrame",
    "CalendarFrame", "AchievementFrame", "CommunitiesAddDialog", "CommunitiesCreateDialog" }, social)
interiors.RegisterRefresh("social", { "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE",
    "CALENDAR_UPDATE_EVENT_LIST", "ACHIEVEMENT_EARNED", "INSPECT_READY" },
    { "FriendsList_Update", "CalendarFrame_Update", "AchievementFrameAchievements_Update" })

