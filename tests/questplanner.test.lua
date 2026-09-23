-- Full-log observations describe this character, never the world's quest graph.
return function(check)
    local env = require("wow_stub")
    local names = { "RikUI", "RikUIDB", "RikUICharDB", "C_QuestLog", "GetBuildInfo", "GetLocale", "issecretvalue", "C_CombatLog", "CombatLogGetCurrentEventInfo", "C_EventUtils" }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = _G[name] end
    local reads, rows, objectives, total, secret, fail = 0, {}, {}, 0, {}, false
    local combatRegistrations,rejectCombat=0,false
    local function load(disabled)
        env.frames, env.timers, env.printed, env.inCombat = {}, {}, {}, false
        RikUIDB, RikUICharDB = { profiles = { Default = { modules = { questplanner = not disabled } } } }, nil
        GetBuildInfo = function() return "1.60.1", "69913", "date", 16001 end
        GetLocale = function() return "enUS" end
        issecretvalue = function(value) return type(value) == "table" and value == secret end
        C_QuestLog = {
            GetNumQuestLogEntries = function()
                reads = reads + 1
                if fail then error("unreadable") end
                return #rows, total
            end,
            GetInfo = function(index)
                return rows[index]
            end,
            GetQuestObjectives = function(id) return objectives[id] end,
            IsComplete = function(id) return id == 900001 end,
            IsFailed = function() return false end,
        }
        dofile("tests/load_addon.lua").Core()
        for _, name in ipairs({ "quest-schema", "quest-evidence", "quest-reader", "quest-context", "quest-plan-xp", "questplanner" }) do
            dofile("src/modules/questplanner/" .. name .. ".lua")
        end
        for _,frame in pairs(env.frames) do
            local native=frame.RegisterEvent
            frame.RegisterEvent=function(self,event)
                if event=="COMBAT_LOG_EVENT_UNFILTERED" then
                    combatRegistrations=combatRegistrations+1
                    if rejectCombat then error("forbidden native combat registration") end
                end
                return native(self,event)
            end
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        env.flushTimers()
        return RikUI.QuestPlanner
    end
    local function refresh()
        env.fire("QUEST_LOG_UPDATE")
        env.flushTimers()
    end
    local ok, reason = pcall(function()
        rows = { { isHeader = true, title = "Zone" },
            { questID = 7, title = "Old quest", level = 9 },
            { questID = 900001, title = "Forever quest", level = 12 } }
        total = 2
        objectives = { [7] = {}, [900001] = { { text = "New task", type = "monster",
            finished = false, numFulfilled = 1, numRequired = 8 } } }
        local planner = load()
        local snapshot, status = planner.GetSnapshot()
        check("diagnostic command is registered", RikUI:HasCommand("quests"))
        check("observes unwatched and new Forever quests", snapshot and snapshot.quests[7] and snapshot.quests[900001])
        check("build is exact and separate from source", snapshot.identity.product == "forever"
            and snapshot.identity.build == "1.60.1.69913")
        check("coverage is log only", snapshot.coverage == "log-complete" and status.state == "current")
        check("objectives complete does not imply historical turn-in", snapshot.quests[900001].objectivesComplete == true
            and snapshot.quests[900001].turnedIn == nil)
        check("empty objectives distinguished from unknown", #snapshot.quests[7].objectives == 0)
        check("structured objective counts retained", snapshot.quests[900001].objectives[1].numRequired == 8)
        rows[3].title = "Changed by provider"
        snapshot.quests[7].title = "Changed by consumer"
        check("published snapshot is detached both ways", planner.GetSnapshot().quests[900001].title == "Forever quest"
            and planner.GetSnapshot().quests[7].title == "Old quest")
        local before = reads
        for _ = 1, 10 do env.fire("QUEST_LOG_UPDATE") end
        env.flushTimers()
        check("event burst yields one scan with count checks", reads - before == 2)
        local generation = planner.GetSnapshot().generation
        fail = true
        refresh()
        snapshot, status = planner.GetSnapshot()
        check("failed refresh keeps prior generation with stale status", snapshot.generation == generation
            and status.state == "stale" and status.reason ~= nil)
        fail = false
        objectives[900001] = nil
        refresh()
        snapshot, status = planner.GetSnapshot()
        check("nil objectives remain unknown", snapshot.quests[900001].objectives == nil
            and snapshot.quests[900001].unknown.objectives and status.state == "partial")
        total = 3
        refresh()
        snapshot, status = planner.GetSnapshot()
        check("hidden quests mark partial coverage without expanding headers", snapshot.coverage == "log-partial"
            and snapshot.observedCount == 2 and snapshot.reportedCount == 3 and status.state == "partial")
        total = 2
        rows[3].questID = secret
        generation = planner.GetSnapshot().generation
        refresh()
        snapshot, status = planner.GetSnapshot()
        check("secret id aborts without treating quest absent", status.state == "stale" and snapshot.generation == generation)
        rows[3].questID = 900001
        objectives[900001] = { { text = secret, type = "monster", finished = false } }
        refresh()
        snapshot = planner.GetSnapshot()
        check("secret nested text never reaches snapshot", snapshot.quests[900001].objectives == nil
            and snapshot.quests[900001].unknown.objectives)
        objectives[900001] = { secret }
        refresh()
        check("secret objective row stays unknown", planner.GetSnapshot().quests[900001].objectives == nil)
        objectives[900001] = secret
        refresh()
        check("secret top-level objective table stays unknown", planner.GetSnapshot().quests[900001].objectives == nil)
        objectives[900001] = { [1] = { text = "a" }, [3] = { text = "b" } }
        refresh()
        check("sparse objectives stay unknown", planner.GetSnapshot().quests[900001].objectives == nil)
        objectives[900001] = {}
        rows[3].questID = 7
        refresh()
        check("duplicate IDs never publish an ambiguous log", select(2, planner.GetSnapshot()).state == "stale")
        rows[3].questID = 900001
        C_QuestLog.GetNumQuestLogEntries = function() return math.huge, total end
        refresh()
        check("unbounded count never starts scan", select(2, planner.GetSnapshot()).state == "stale")
        C_QuestLog.GetNumQuestLogEntries = function() return 2, 0 / 0 end
        refresh()
        check("nonfinite total rejected", select(2, planner.GetSnapshot()).state == "stale")
        C_QuestLog.GetNumQuestLogEntries = function() return 2, 2 end
        C_QuestLog.GetInfo = nil
        refresh()
        check("missing API is visible and preserves previous state", select(2, planner.GetSnapshot()).state == "stale")
        rows, total, objectives = {}, 0, {}
        planner = load()
        snapshot, status = planner.GetSnapshot()
        check("legitimate empty log publishes empty snapshot", snapshot.observedCount == 0 and status.state == "current")
        check("observations are not persisted", RikUI.Profile.questplanner == nil and RikUI.CharDB.questplanner == nil)
        GetBuildInfo = function() return "12.0.0", "69913", "date", 120000 end
        refresh()
        check("different client is never labelled Forever", select(2, planner.GetSnapshot()).state == "stale")
        GetBuildInfo = function() return "1.60.1", "69913", "date", 16001 end
        GetLocale = function() return secret end
        refresh()
        check("unreadable locale never publishes an identity", select(2, planner.GetSnapshot()).state == "stale")
        GetLocale = function() return "enUS" end
        local countReads = 0
        C_QuestLog.GetNumQuestLogEntries = function()
            countReads = countReads + 1
            return 0, countReads % 2
        end
        refresh()
        check("count changes discard unpublished scan", select(2, planner.GetSnapshot()).state == "stale")
        C_QuestLog.GetNumQuestLogEntries = function() return secret, 0 end
        refresh()
        check("secret counts cannot start scan", select(2, planner.GetSnapshot()).state == "stale")
        planner = load(true)
        check("disabled module does not observe", planner.GetSnapshot() == nil)
        before = reads
        planner.Request()
        env.flushTimers()
        check("disabled module cannot schedule observations", reads == before)
        planner = load()
        env.fire("QUEST_LOG_UPDATE")
        planner.enabled = false
        before = reads
        env.flushTimers()
        check("disabled pending callback cannot publish", reads == before)
        CombatLogGetCurrentEventInfo=nil
        C_CombatLog={GetCurrentEventInfo=function() end,IsCombatLogRestricted=function() return true end}
        C_EventUtils=nil;combatRegistrations=0;rejectCombat=true
        planner=load()
        check("restricted client starts planner without forbidden registration",combatRegistrations==0
            and planner.GetSnapshot()~=nil and not table.concat(env.printed," "):find("COMBAT_LOG_EVENT_UNFILTERED",1,true),table.concat(env.printed," | "))
        C_CombatLog.IsCombatLogRestricted=function() return false end
        C_EventUtils={IsEventValid=function() return true end,IsCallbackEvent=function() return true end}
        planner=load()
        check("callback-only client starts without native combat event",combatRegistrations==0 and not table.concat(env.printed," "):find("COMBAT_LOG_EVENT_UNFILTERED",1,true),table.concat(env.printed," | "))
        C_EventUtils.IsCallbackEvent=function() return false end
        rejectCombat=false;planner=load()
        check("supported native combat subscription still registers",combatRegistrations==1)
        C_CombatLog.GetCurrentEventInfo=nil;rejectCombat=true;planner=load()
        check("missing combat reader avoids useless native subscription",combatRegistrations==1 and not table.concat(env.printed," "):find("COMBAT_LOG_EVENT_UNFILTERED",1,true),table.concat(env.printed," | "))
    end)
    for _, name in ipairs(names) do _G[name] = saved[name] end
    if not ok then error(reason) end
end
