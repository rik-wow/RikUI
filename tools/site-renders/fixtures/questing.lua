-- Questing: the quest log, tracker, timers and the quest planner over the staged corpus.

-- The quest log the client reports: an Elwynn header and a few quests with objectives. Everything
-- RikUI reads (C_QuestLog and the older leaderboard readers) answers from this list. The
-- simulator's C_QuestLog carries a metatable, so a plain copy takes its place.
local ELWYNN_QUESTS = {
    { id = 7, title = "Kobold Camp Cleanup", level = 3, objectives = { { text = "Kobold Vermin slain: 6/10", fulfilled = 6, required = 10 } } },
    { id = 33, title = "Wolves Across the Border", level = 5, objectives = { { text = "Prowler slain: 2/8", fulfilled = 2, required = 8 }, { text = "Diseased Wolf slain: 3/8", fulfilled = 3, required = 8 } } },
    { id = 15, title = "Investigate Echo Ridge", level = 3, complete = true, objectives = { { text = "Kobold Worker slain: 10/10", finished = true, fulfilled = 10, required = 10 } } },
    { id = 62, title = "The Fargodeep Mine", level = 7, objectives = { { text = "Explore the Fargodeep Mine", type = "event", fulfilled = 0, required = 1 } } },
    { id = 85, title = "Report to Goldshire", level = 5, objectives = { { text = "Speak with Marshal Dughan", type = "object", fulfilled = 0, required = 1 } } },
}

RikRenderElwynnQuests = ELWYNN_QUESTS

function RikRenderQuestLog(quests, watched)
    quests = quests or ELWYNN_QUESTS
    -- The simulator answers some names only through its metatable; the copy names them all.
    local original, plain = C_QuestLog, {}
    for key, value in pairs(original) do plain[key] = value end
    for _, name in ipairs({ "GetNumQuestLogEntries", "GetInfo", "GetQuestIDForLogIndex", "GetLogIndexForQuestID", "GetTitleForQuestID",
        "GetNumQuestWatches", "GetQuestIDForQuestWatchIndex", "GetNumWorldQuestWatches", "GetQuestIDForWorldQuestWatchIndex", "AddQuestWatch",
        "RemoveQuestWatch", "SortQuestWatches", "IsQuestFlaggedCompleted", "IsComplete", "ReadyForTurnIn", "IsFailed", "IsQuestDisabledForSession",
        "IsPushableQuest", "IsRepeatableQuest", "IsImportantQuest", "IsMetaQuest", "IsOnMap", "IsOnQuest", "IsWorldQuest", "IsQuestTask",
        "IsQuestBounty", "GetQuestRewardCurrencies", "GetQuestTagInfo", "GetRequiredMoney", "GetSuggestedGroupSize", "ShouldShowQuestRewards",
        "QuestHasWarModeBonus", "QuestCanHaveWarModeBonus", "QuestHasQuestSessionBonus", "GetNextWaypointText", "GetTimeAllowed",
        "GetQuestDetailsTheme", "RequestLoadQuestByID", "SetSelectedQuest", "GetSelectedQuest", "CanAbandonQuest", "GetAbandonQuest",
        "SetAbandonQuest", "AbandonQuest", "GetQuestWatchType", "GetMaxNumQuests", "GetMaxNumQuestsCanAccept", "GetQuestObjectives",
        "GetQuestTimers", "GetQuestsOnMap", "GetQuestLogPortraitGiver", "GetQuestType", "GetQuestDifficultyLevel", "GetQuestAdditionalHighlights",
        "GetQuestLogMajorFactionReputationRewards", "IsAccountQuest", "IsLegendaryQuest", "IsThreatQuest", "GetNumQuestObjectives",
        "GetQuestWatchType", "GetHeaderIndexForQuest", "GetMapForQuestPOIs", "GetActiveThreatMaps", "HasActiveThreats", "IsQuestCalling",
        "GetDistanceSqToQuest", "GetNextWaypoint", "GetNextWaypointForMap", "GetBountiesForMapID", "GetBountySetInfoForMapID",
        "GetZoneStoryInfo", "GetQuestLogSpecialItemInfo", "IsUnitOnQuest", "UnitIsRelatedToActiveQuest", "SetMapForQuestPOIs",
        "GetQuestInfoByQuestID", "GetTitleForLogIndex", "GetAllCompletedQuestIDs", "IsQuestReplayable", "IsQuestReplayedRecently",
        "IsQuestTrivial", "IsQuestInvasion", "IsQuestCriteriaForBounty", "QuestContainsFirstTimeRepBonusForPlayer", "QuestIgnoresAccountCompletedFiltering",
        "GetQuestLogCompletionText", "GetQuestLogCriteriaSpell", "GetQuestLogRewardMoney", "GetQuestLogRewardXP", "GetQuestLogRewardHonor" }) do
        if plain[name] == nil then
            local ok, value = pcall(function() return original[name] end)
            if ok and value ~= nil then plain[name] = value end
        end
    end
    C_QuestLog = plain
    local entries = { { header = true, title = "Elwynn Forest" } }
    local byID, indexByID = {}, {}
    for _, quest in ipairs(quests) do
        entries[#entries + 1] = quest
        byID[quest.id], indexByID[quest.id] = quest, #entries
    end
    if not watched then
        watched = {}
        for _, quest in ipairs(quests) do watched[#watched + 1] = quest.id end
    end
    local function info(entry)
        local base = { isCollapsed = false, isHidden = false, isTask = false, isBounty = false, isStory = false, isScaling = false,
            frequency = 0, isAutoComplete = false, startEvent = false, suggestedGroup = 0, campaignID = 0, isCalling = false,
            questClassification = 0, overridesSortOrder = false, readyForTranslation = true, isInternalOnly = false, isAbandonOnDisable = false }
        if entry.header then
            base.title, base.isHeader, base.questID, base.level, base.difficultyLevel, base.isOnMap, base.hasLocalPOI = entry.title, true, 0, 0, 0, false, false
        else
            base.title, base.isHeader, base.questID, base.level, base.difficultyLevel, base.isOnMap, base.hasLocalPOI = entry.title, false, entry.id, entry.level, entry.level, true, true
        end
        return base
    end
    plain.GetNumQuestLogEntries = function() return #entries, #quests end
    plain.GetInfo = function(index) local entry = entries[index]; return entry and info(entry) or nil end
    plain.GetQuestIDForLogIndex = function(index) local entry = entries[index]; return entry and not entry.header and entry.id or 0 end
    plain.GetLogIndexForQuestID = function(id) return indexByID[id] end
    plain.GetTitleForQuestID = function(id) local quest = byID[id]; return quest and quest.title end
    plain.GetNumQuestWatches = function() return #watched end
    plain.GetQuestIDForQuestWatchIndex = function(index) return watched[index] end
    plain.GetQuestWatchType = function(id) return byID[id] and 0 or nil end
    plain.IsComplete = function(id) local quest = byID[id]; return quest ~= nil and quest.complete == true end
    plain.IsFailed = function(id) local quest = byID[id]; return quest ~= nil and quest.failed == true end
    plain.ReadyForTurnIn = plain.IsComplete
    plain.IsOnQuest = function(id) return byID[id] ~= nil end
    plain.IsQuestFlaggedCompleted = function() return false end
    plain.GetQuestObjectives = function(id)
        local quest = byID[id]
        if not quest then return nil end
        local list = {}
        for _, objective in ipairs(quest.objectives or {}) do
            list[#list + 1] = { text = objective.text, type = objective.type or "monster", finished = objective.finished == true,
                numFulfilled = objective.fulfilled or 0, numRequired = objective.required or 1 }
        end
        return list
    end
    plain.GetQuestTimers = function()
        local list = {}
        for _, quest in ipairs(quests) do
            if quest.timer then list[#list + 1] = { questID = quest.id, questTimer = quest.timer } end
        end
        return list
    end
    plain.GetTimeAllowed = function(id)
        local quest = byID[id]
        if quest and quest.timer then return quest.timerTotal or quest.timer, quest.timer end
    end
    plain.GetSelectedQuest = function() return quests[1] and quests[1].id or 0 end
    GetNumQuestLeaderBoards = function(index)
        local entry = entries[index]
        return entry and entry.objectives and #entry.objectives or 0
    end
    GetQuestLogLeaderBoard = function(objective, index)
        local entry = entries[index]
        local row = entry and entry.objectives and entry.objectives[objective]
        if not row then return nil end
        return row.text, row.type or "monster", row.finished == true, row.fulfilled or 0, row.required or 1
    end
    GetQuestLogTitle = function(index)
        local entry = entries[index]
        if not entry then return nil end
        return entry.title, entry.level or 0, 0, entry.header == true, false, entry.complete and 1 or nil, 0, entry.id or 0
    end
    A_Admin.FireEvent("QUEST_LOG_UPDATE")
    A_Admin.FireEvent("QUEST_WATCH_LIST_CHANGED")
    if RikUI.QuestTracker and RikUI.QuestTracker.Refresh then RikUI.QuestTracker.Refresh() end
    if RikUI.QuestTimers and RikUI.QuestTimers.Refresh then RikUI.QuestTimers.Refresh() end
    return quests
end

-- The tracker on its own: the planner's guidance card is another guide's subject.
function RikRenderTrackerOnly()
    RikUI.QuestPlanner.enabled = false
    if RikUI.QuestTracker and RikUI.QuestTracker.Refresh then RikUI.QuestTracker.Refresh() end
end

-- The planner's world: the character stands in Goldshire on the Elwynn map, and the client reports a
-- waypoint per quest. The simulator's character is on a retail map with no waypoints.
local ELWYNN_MAP, ELWYNN_PARENT = 1429, 1415

local ELWYNN_WAYPOINTS = {
    [7] = { x = 0.49, y = 0.30, text = "Kobold camp north of Northshire" },
    [33] = { x = 0.56, y = 0.62, text = "Wolves east of Goldshire" },
    [15] = { x = 0.45, y = 0.61, text = "Marshal McBride in Northshire" },
    [62] = { x = 0.39, y = 0.82, text = "The Fargodeep Mine" },
    [85] = { x = 0.42, y = 0.65, text = "Marshal Dughan in Goldshire" },
    [21] = { x = 0.43, y = 0.66, text = "Innkeeper Farley in Goldshire" },
}

function RikRenderPlannerWorld(playerX, playerY)
    playerX, playerY = playerX or 0.44, playerY or 0.62
    -- The planner reads C_Map only when it is a plain table; the simulator's carries a metatable.
    local original, plain = C_Map, {}
    for key, value in pairs(original) do plain[key] = value end
    for _, name in ipairs({ "GetBestMapForUnit", "GetPlayerMapPosition", "GetMapInfo", "GetMapWorldSize", "GetWorldPosFromMapPos",
        "GetMapPosFromWorldPos", "GetMapArtLayers", "GetMapArtLayerTextures", "GetMapArtID", "GetMapChildrenInfo", "GetMapRectOnMap",
        "GetMapInfoAtPosition", "GetFallbackWorldMapID", "GetMapArtBackgroundAtlas", "MapHasArt", "RequestPreloadMap", "GetMapGroupID",
        "GetMapGroupMembersInfo", "GetMapHighlightInfoAtPosition", "GetMapLinksForMap", "GetMapDisplayInfo", "GetAreaInfo",
        "GetMapBannersForMap", "GetMapArtHelpTextPosition", "GetBountySetMaps", "IsMapValidForNavBarDropdown", "CanSetUserWaypointOnMap",
        "GetUserWaypoint", "SetUserWaypoint", "ClearUserWaypoint", "HasUserWaypoint", "GetUserWaypointFromMapPoint" }) do
        if plain[name] == nil then
            local ok, value = pcall(function() return original[name] end)
            if ok and value ~= nil then plain[name] = value end
        end
    end
    C_Map = plain
    C_Map.GetBestMapForUnit = function() return ELWYNN_MAP end
    local mapInfo = C_Map.GetMapInfo
    C_Map.GetMapInfo = function(id)
        if id == ELWYNN_MAP then return { mapID = id, name = "Elwynn Forest", mapType = 3, parentMapID = ELWYNN_PARENT, flags = 0 } end
        if id == ELWYNN_PARENT then return { mapID = id, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947, flags = 0 } end
        return mapInfo(id)
    end
    C_Map.GetPlayerMapPosition = function(mapID)
        if mapID ~= ELWYNN_MAP then return nil end
        return { x = playerX, y = playerY, GetXY = function() return playerX, playerY end }
    end
    C_Map.GetMapWorldSize = function(mapID) if mapID == ELWYNN_MAP then return 3462.5, 2308.3 end end
    GetPlayerFacing = function() return 0.6 end
    -- The simulator names its own build; the navigation data is keyed by the installed client's.
    if RikRenderClient then
        local buildInfo = GetBuildInfo
        GetBuildInfo = function()
            local _, _, date, interface, a, b, c = buildInfo()
            return RikRenderClient.version, RikRenderClient.build, date, interface, a, b, c
        end
        -- The first quest snapshot was read before the override; the navigation build follows the client's.
        if RikUI.QuestPlanner.Builds then RikUI.QuestPlanner.Builds.Observe(RikRenderClient.version .. "." .. RikRenderClient.build) end
    end
    -- World yards for the road router: the same spot, as UnitPosition reports it (y, x, z, instance).
    local worldX, worldY = -9464 - (playerY - 0.65) * 2308.3, 62 - (playerX - 0.42) * 3462.5
    UnitPosition = function(unit) if unit == "player" then return worldY, worldX, 56, 0 end end
    GetUnitSpeed = function() return 0, 7, 7, 4.72 end
    local log = C_QuestLog
    log.GetNextWaypoint = function(id)
        local point = ELWYNN_WAYPOINTS[id]
        if point then return ELWYNN_MAP, point.x, point.y end
    end
    log.GetNextWaypointForMap = function(id, mapID)
        local point = ELWYNN_WAYPOINTS[id]
        if point and mapID == ELWYNN_MAP then return point.x, point.y end
    end
    log.GetNextWaypointText = function(id) local point = ELWYNN_WAYPOINTS[id]; return point and point.text end
    log.GetQuestsOnMap = function(mapID)
        local rows = {}
        if mapID ~= ELWYNN_MAP then return rows end
        for id, point in pairs(ELWYNN_WAYPOINTS) do
            rows[#rows + 1] = { questID = id, mapID = mapID, x = point.x, y = point.y, isQuestStart = false, isMapIndicatorQuest = false, inProgress = true, childDepth = 0 }
        end
        return rows
    end
    -- The context caches one frame's readings per clock tick; the clock has not moved since load.
    if RikUI.QuestPlanner.Context.Frame then RikUI.QuestPlanner.Context.Frame(true) end
end

-- Let the planner finish its search: it steps from an OnUpdate driver, one slice per frame.
function RikRenderPlannerSettle(limit)
    local planner = RikUI.QuestPlanner
    local controller = planner.Controller
    if planner.Context.Frame then planner.Context.Frame(true) end
    planner.Refresh()
    for step = 1, limit or 3000 do
        controller.Step()
        local model = controller.Peek()
        if step > 60 and model.status ~= "calculating" and model.status ~= "updating" then break end
    end
    if planner.Context.Frame then planner.Context.Frame(true) end
    -- The road router also steps from a frame driver: load the network and finish the route search.
    if planner.Terrain and planner.Terrain.Step then
        for step = 1, limit or 3000 do
            planner.Terrain.Step()
            local status = planner.Terrain.Status().status
            if step > 30 and status ~= "loading" and status ~= "calculating" and status ~= "updating" then break end
        end
    end
    if planner.Navigation and planner.Navigation.Refresh then planner.Navigation.Refresh() end
    if planner.View and planner.View.Refresh then planner.View.Refresh() end
    if RikUI.QuestTracker and RikUI.QuestTracker.Refresh then RikUI.QuestTracker.Refresh() end
    return controller.Get()
end

-- The direction arrow is an unnamed frame under UIParent; a named holder takes it for the capture.
function RikRenderPlannerArrow()
    local arrow
    for _, child in ipairs({ UIParent:GetChildren() }) do
        if child.icon and child.label and child:GetWidth() == 240 and child:GetHeight() == 66 then arrow = child end
    end
    assert(arrow, "direction arrow frame missing")
    local holder = CreateFrame("Frame", "RikRenderArrow", UIParent)
    holder:SetSize(260, 90)
    holder:SetPoint("TOP", UIParent, "TOP", 0, -100)
    arrow:SetParent(holder)
    arrow:ClearAllPoints()
    arrow:SetPoint("TOP", holder, "TOP", 0, -10)
    return holder, arrow
end
