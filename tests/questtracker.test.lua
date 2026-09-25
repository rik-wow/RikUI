local loadfile = dofile("tests/load_addon.lua").Loadfile
-- The list is plain unprotected frames fed from the quest log; the suite checks rendering, change
-- animations, coalesced refreshes, clicks, collapse and the parking of the stock tracker. Whether
-- the quest map opens for addon code in combat needs a beta check.
return function(check)
    local env = require("wow_stub")
    local restoreCreate = require("widget_stub").install()
    local API = { "C_QuestLog", "GetNumQuestLeaderBoards", "GetQuestLogLeaderBoard", "GetQuestDifficultyColor",
        "QuestMapFrame_OpenToQuestDetails", "ObjectiveTrackerFrame" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local stub = {}
    local acceptedKnown = env.KNOWN_EVENTS.QUEST_ACCEPTED
    env.KNOWN_EVENTS.QUEST_ACCEPTED = true
    local savedFlag = LE_FRAME_TUTORIAL_HOW_TO_SUPERTRACK
    local savedSet, savedGet = C_CVar.SetCVarBitfield, C_CVar.GetCVarBitfield
    local function printedContains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function tooltipContains(text)
        for _, line in ipairs(GameTooltip.lines) do
            if tostring(line.text):find(text, 1, true) then return true end
        end
        return false
    end
    local function parked(frame) return frame.parent == RikUIHiddenFrames and RikUI.Hide.IsHidden(frame) end
    local function installQuestLog()
        C_QuestLog = {
            GetNumQuestWatches = function()
                if stub.readError then error(stub.readError) end
                stub.reads = stub.reads + 1
                return #stub.watches
            end,
            GetQuestIDForQuestWatchIndex = function(index) return stub.watches[index] end,
            GetLogIndexForQuestID = function(questID) return questID * 10 end,
            GetInfo = function(logIndex)
                local quest = stub.quests[logIndex / 10]
                return quest and { title = quest.title, level = quest.level, questID = logIndex / 10 } or nil
            end,
            GetTitleForQuestID = function(questID) return stub.quests[questID].title end,
            IsComplete = function(questID) return stub.quests[questID].complete == true end,
            IsFailed = function(questID) return stub.quests[questID].failed == true end,
            RemoveQuestWatch = function(questID) stub.removed[#stub.removed + 1] = questID end,
        }
        GetNumQuestLeaderBoards = function(logIndex) return #stub.quests[logIndex / 10].objectives end
        GetQuestLogLeaderBoard = function(index, logIndex)
            local objective = stub.quests[logIndex / 10].objectives[index]
            return objective[1], "monster", objective[2] == true
        end
        GetQuestDifficultyColor = function(level) return { r = level / 100, g = 0.5, b = 0.25 } end
        QuestMapFrame_OpenToQuestDetails = function(questID) stub.opened[#stub.opened + 1] = questID end
    end
    local function installClient()
        stub.reads, stub.readError, stub.removed, stub.opened = 0, nil, {}, {}
        stub.watches = { 11, 22 }
        stub.quests = {
            [11] = { title = "Wolves at the Door", level = 12,
                objectives = { { "Wolves slain: 3/8" }, { "Pelts: 8/8", true } } },
            [22] = { title = "A Letter Home", level = 9, objectives = { { "Deliver the letter" } } },
            [33] = { title = "The Lost Tools", level = 14, objectives = { { "Tools: 0/1" } } },
        }
        stub.acknowledgedBeforePark = false
        LE_FRAME_TUTORIAL_HOW_TO_SUPERTRACK = 8
        C_CVar.GetCVarBitfield = function() return false end
        C_CVar.SetCVarBitfield = function(name, flag, value)
            stub.acknowledgedBeforePark = name == "closedInfoFrames" and flag == 8 and value == true
                and ObjectiveTrackerFrame:GetParent() == UIParent
        end
        ObjectiveTrackerFrame = CreateFrame("Frame", "ObjectiveTrackerFrame", UIParent)
        installQuestLog()
    end
    local function load(profile, combat, prepare)
        env.frames, env.printed, env.inCombat, env.hooks, env.timers, env.shiftDown = {}, {}, false, {}, {}, false
        installClient()
        if prepare then prepare() end
        profile = profile or {}
        profile.modules = profile.modules or {}
        profile.modules.unitframes = false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, nil
        for _, file in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/platform/tutorials.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/ui/motion.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua",
            "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua", "src/modules/unitframes/unitframes.lua", "src/modules/unitframes/unitframes-status.lua", "src/modules/questtracker/questtracker.lua", "src/modules/questtracker/questtracker-blocks.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.QuestTracker
    end
    local function update(event)
        env.fire(event or "QUEST_LOG_UPDATE")
        env.flushTimers()
    end
    local ok, reason = pcall(function()
        local module = load()
        check("supertrack tutorial acknowledged before parking stock tracker", stub.acknowledgedBeforePark)
        local holder, group, view = module.Holder, RikUI.Layout.Groups.questtracker, module.View
        local first, second = view.Blocks[1], view.Blocks[2]
        check("the list registers with the layout under key questtracker at the top right", holder and group
            and group.frames[1] == holder and group.defaults.point == "TOPRIGHT"
            and group.defaults.relativePoint == "TOPRIGHT" and group.defaults.x < 0 and group.defaults.y < 0)
        check("every watched quest gets a block in watch order", first.shown == true and second.shown == true
            and first.questID == 11 and second.questID == 22 and view.Blocks[3] == nil)
        check("a title carries the level tag in the RikUI font and the difficulty colour",
            first.title.text == "[12] Wolves at the Door" and first.title.fontPath == RikUI.Media.font
            and first.title.textColor[1] == 0.12 and first.title.wordWrap == false)
        check("objectives render one truncated line each with finished ones dimmed",
            first.lines[1].text.text == "- Wolves slain: 3/8" and first.lines[2].text.text == "- Pelts: 8/8"
            and first.lines[2].text.textColor[1] < first.lines[1].text.textColor[1]
            and first.lines[1].text.wordWrap == false)
        check("the holder is 240px wide and as tall as the header and both blocks", holder.width == 240
            and holder.height == 92 and first.height == 38 and second.height == 26)
        check("the header shows the label, the quest count and the collapse glyph on the flat plaque",
            view.Header.label.text == "Quests" and view.Header.count.text == "2" and view.Header.glyph.rikIcon == "chevron-down"
            and #view.Header.rikBorder == 4 and view.Header.rikBorder[1].texture == RikUI.Media.border)
        check("blocks fade in when they first appear", first.fade.plays == 1 and second.fade.plays == 1)

        local unfinished
        for _, setting in ipairs(module.Options.settings) do
            if setting.key == "hideCompleted" then unfinished = setting end
        end
        check("unfinished objectives preference exists", unfinished ~= nil)
        unfinished.set(true)
        check("completed lines are removed and height shrinks", first.height == 26 and first.lines[2].shown == false)
        GameTooltip.lines = {}
        env.runScript(first, "OnEnter")
        check("completed objectives remain accessible on hover", tooltipContains("Pelts: 8/8"))
        env.runScript(first, "OnLeave")
        unfinished.set(false)
        check("disabling compact objectives restores all lines", first.height == 38 and first.lines[2].shown)
        stub.quests[11].objectives[1][1] = "Wolves slain: 4/8"
        update()
        check("progress rewrites the objective and flashes only that line",
            first.lines[1].text.text == "- Wolves slain: 4/8" and first.lines[1].flashAnim.plays == 1
            and first.lines[2].flashAnim.plays == 0 and first.fade.plays == 1)
        local reads = stub.reads
        env.fire("QUEST_LOG_UPDATE")
        env.fire("QUEST_LOG_UPDATE")
        env.fire("QUEST_WATCH_LIST_CHANGED", 11, true)
        env.flushTimers()
        check("a burst of quest events renders once", stub.reads == reads + 1)

        stub.quests[22].objectives[1][2] = true
        update()
        check("completed objective flashes green even when its text is unchanged",
            second.lines[1].flashAnim.plays == 1 and second.lines[1].flash.color[1] == 0.3)
        update()
        check("unchanged completed objective stays quiet", second.lines[1].flashAnim.plays == 1)
        stub.quests[22].objectives[1][2] = false
        update()
        check("reopened objective restores white progress feedback", second.lines[1].flash.color[1] == 1)
        stub.quests[11].complete = true
        stub.quests[11].objectives[1] = { "Wolves slain: 8/8", true }
        update()
        check("a complete quest shrinks to a green title and a ready line", first.title.textColor[2] > 0.8
            and first.title.textColor[1] < 0.5 and first.lines[1].text.text == "Ready to turn in"
            and first.lines[2].shown == false and first.height == 26 and holder.height == 80)
        check("completing a quest flashes its accent once", first.accentAnim.plays == 1
            and first.accent.color[2] > 0.8)
        update()
        check("an unchanged refresh replays no animation", first.accentAnim.plays == 1
            and first.lines[1].flashAnim.plays == 1)
        stub.quests[22].failed = true
        update()
        check("a failed quest is marked in red", second.lines[1].text.text == "Failed"
            and second.title.textColor[1] > 0.8 and second.title.textColor[2] < 0.5)
        stub.quests[22].failed = false

        stub.watches = { 11, 22, 33 }
        update("QUEST_WATCH_LIST_CHANGED")
        local third = view.Blocks[3]
        check("a newly watched quest fades in without replaying the others", third.shown == true
            and third.fade.plays == 1 and first.fade.plays == 1 and view.Header.count.text == "3")
        stub.watches = { 22, 33 }
        update("QUEST_WATCH_LIST_CHANGED")
        check("an unwatched quest leaves and the list closes up", view.Blocks[1].questID == 22
            and view.Blocks[2].questID == 33 and view.Blocks[3].shown == false and holder.height == 18 + 4 + 26 + 6 + 26)

        local ready
        for _, setting in ipairs(module.Options.settings) do
            if setting.key == "readyFirst" then ready = setting end
        end
        check("ready-first preference exists", ready ~= nil)
        stub.watches = { 22, 33, 11 }
        ready.set(true)
        check("ready quests move ahead with stable unfinished order", view.Blocks[1].questID == 11
            and view.Blocks[2].questID == 22 and view.Blocks[3].questID == 33 and stub.watches[1] == 22)
        ready.set(false)
        check("watch order restored when ready-first is disabled", view.Blocks[1].questID == 22
            and view.Blocks[2].questID == 33 and view.Blocks[3].questID == 11)
        stub.watches = { 22, 33 }
        update()

        -- The arrangement system tells the list how tall it may get: the room down to the next frame.
        local group = RikUI.Layout.Groups.questtracker
        check("the list registers as a frame that grows downward and listens for its room",
            group.grow == "DOWN" and type(group.onLimit) == "function" and group.label == "Quest tracker")
        group.onLimit(70 - holder.height)
        check("a list capped at 70 shows the quests that fit and says how many are hidden",
            view.Blocks[1].shown == true and view.Blocks[2].shown == false and view.More.shown == true
            and view.More.text == "+1 more" and holder.height == 18 + 4 + 26 + 6 + 14
            and view.Header.count.text == "2")
        group.onLimit(200 - holder.height)
        check("with room again every quest shows and the line goes", view.Blocks[2].shown == true
            and view.More.shown == false and holder.height == 80)
        group.onLimit(nil)
        check("a client that reports no room leaves the list uncapped", view.Blocks[2].shown == true and holder.height == 80)

        env.click(view.Blocks[1])
        check("clicking a quest opens it in the quest log", stub.opened[1] == 22 and #stub.removed == 0)
        env.shiftDown = true
        env.click(view.Blocks[2])
        env.shiftDown = false
        check("shift-clicking a quest stops tracking it", stub.removed[1] == 33 and #stub.opened == 1)
        GameTooltip.lines = {}
        env.runScript(view.Blocks[1], "OnEnter")
        check("hovering a quest lights it and explains the clicks", view.Blocks[1].highlight.shown == true
            and GameTooltip.owner == view.Blocks[1] and tooltipContains("Shift-click"))
        check("hover shows complete objective details", tooltipContains("Deliver the letter"))
        env.runScript(view.Blocks[1], "OnHide")
        check("hidden quest clears owned tooltip", GameTooltip.shown == false)
        env.runScript(view.Blocks[1], "OnLeave")
        check("leaving a quest clears the highlight", view.Blocks[1].highlight.shown == false)

        local beforeExpand = view.Blocks[1].fade.plays
        env.click(view.Header)
        check("clicking the header collapses the list to the header and remembers it",
            view.Blocks[1].shown == false and holder.height == 18 and view.Header.glyph.rikIcon == "chevron-right"
            and RikUI.Profile.questtracker.collapsed == true and view.Header.count.text == "2")
        env.click(view.Header)
        check("clicking it again expands the list with a fade", view.Blocks[1].shown == true
            and holder.height > 18 and RikUI.Profile.questtracker.collapsed == false
            and view.Blocks[1].fade.plays == beforeExpand + 1)

        local combatSetting = module.Options.settings[1]
        combatSetting.set(true)
        env.inCombat = true
        env.fire("PLAYER_REGEN_DISABLED")
        check("combat collapse keeps header and saved preference", holder.height == 18 and not RikUI.Profile.questtracker.collapsed)
        env.click(view.Header)
        check("header can temporarily reveal quests during combat", holder.height > 18 and not RikUI.Profile.questtracker.collapsed)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("combat end restores expanded preference", holder.height > 18)
        RikUI.Profile.questtracker.collapsed = true
        env.inCombat = true
        env.fire("PLAYER_REGEN_DISABLED")
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("combat end preserves manual collapse", holder.height == 18 and RikUI.Profile.questtracker.collapsed)
        RikUI.Profile.questtracker.collapsed = false
        combatSetting.set(false)

        stub.watches = {}
        update("QUEST_WATCH_LIST_CHANGED")
        check("nothing watched hides the whole list", holder.shown == false)
        stub.watches = { 22 }
        env.inCombat = true
        update("QUEST_WATCH_LIST_CHANGED")
        env.inCombat = false
        check("the list returns in combat without a protected write", holder.shown == true
            and view.Blocks[1].questID == 22)

        stub.readError = "quest log unavailable"
        update()
        update()
        check("a failing quest read is reported once and keeps the last list", printedContains("Quest tracker read")
            and #env.printed == 1 and view.Blocks[1].shown == true)
        stub.readError = nil

        check("the stock objective tracker is parked once the list exists", parked(ObjectiveTrackerFrame))
        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports the list state", printedContains("Quest tracker holder=true quests=1"))

        module = load({ questtracker = { collapsed = true } })
        check("a collapsed list stays collapsed after a reload", module.View.Blocks[1].shown == false
            and module.Holder.height == 18 and module.View.Header.glyph.rikIcon == "chevron-right")

        module = load(nil, true)
        check("a combat login builds nothing and parks nothing", module.Holder == nil
            and ObjectiveTrackerFrame.parent == UIParent)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat builds the list and parks the stock tracker", module.Holder ~= nil
            and module.View.Blocks[2].questID == 22 and parked(ObjectiveTrackerFrame))

        module = load(nil, false, function() C_QuestLog.GetInfo, GetQuestDifficultyColor = nil, nil end)
        check("a client without quest info or difficulty colours still lists titles",
            module.View.Blocks[1].title.text == "Wolves at the Door" and #env.printed == 0)

        module = load(nil, false, function() C_QuestLog = nil end)
        check("a client without the quest log API keeps the stock tracker", module.Holder == nil
            and ObjectiveTrackerFrame.parent == UIParent and printedContains("Quest tracker unavailable"))

        module = load()
        assert(loadfile("src/modules/questplanner/quest-schema.lua"))("RikUI", {})
        RikUI.QuestPlanner.enabled=true
        RikUI.QuestPlanner.Controller={
            Get=function() return {status="observed",detail="Walking route is not verified",quests={}} end,
            Policy=function() return {pins={},paused=false} end,
        }
        assert(loadfile("src/modules/questplanner/quest-guidance.lua"))("RikUI", {})
        assert(loadfile("src/modules/questplanner/quest-view.lua"))("RikUI", {})
        stub.watches={}
        update()
        check("planner guidance remains available with no watched quests",module.Holder:IsShown() and module.Holder.height>18)
        env.click(module.View.Header)
        check("collapsed planner keeps a clickable header with no watches",module.Holder:IsShown() and module.Holder.height==18)
        env.click(module.View.Header)
        check("unwatched planner can expand again",module.Holder:IsShown() and module.Holder.height>18)

        module = load({ questtracker = { readyFirst = true } })
        stub.quests[11].complete = true
        local oldControl = IsControlKeyDown
        IsControlKeyDown = function() return true end
        env.click(module.View.Blocks[2])
        check("control click pins quest ahead of ready turnin", module.View.Blocks[1].questID == 22
            and module.View.Blocks[1].title.text:find("* ", 1, true) == 1 and #stub.removed == 0 and #stub.opened == 0)
        check("quest pin persists in profile", RikUI.Profile.questtracker.pins == "22")
        env.click(module.View.Blocks[1])
        check("second control click unpins and restores ready order", module.View.Blocks[1].questID == 11
            and RikUI.Profile.questtracker.pins == "")
        IsControlKeyDown = oldControl
        module = load({ questtracker = { pins = "22" } })
        check("saved pins survive reload", module.View.Blocks[1].questID == 22)
        GameTooltip.lines = {}
        env.runScript(module.View.Blocks[1], "OnEnter")
        check("pinned quest tooltip explains unpin", tooltipContains("Control-click: unpin"))
        check("invalid pins rejected by sharing schema", not pcall(RikUI.ProfileSchema.Project, {questtracker={pins="oops"}}))

        module = load()
        local watched = {}
        C_QuestLog.AddQuestWatch = function(id) watched[#watched + 1] = id; return true end
        env.fire("QUEST_ACCEPTED", 33)
        check("auto tracking defaults off", #watched == 0)
        RikUI.Profile.questtracker.autoWatch = true
        env.fire("QUEST_ACCEPTED", 33)
        check("newly accepted quest is tracked", watched[1] == 33)
        env.fire("QUEST_ACCEPTED", env.SECRET)
        env.fire("QUEST_ACCEPTED", 0)
        check("invalid accepted ids do nothing", #watched == 1)
        env.inCombat = true
        env.fire("QUEST_ACCEPTED", 22)
        check("watch changes wait during combat", #watched == 1)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("watch request applies after combat", watched[2] == 22)
        env.inCombat = true
        env.fire("QUEST_ACCEPTED", 11)
        RikUI.Profile.questtracker.autoWatch = false
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("disabling auto tracking cancels deferred intent", #watched == 2)
        RikUI.Profile.questtracker.autoWatch = true
        C_QuestLog.AddQuestWatch = function() return false end
        env.fire("QUEST_ACCEPTED", 33)
        check("native watch refusal is explained", printedContains("could not track"))
        C_QuestLog.AddQuestWatch = function(id) watched[#watched + 1] = id; return true end
        env.fire("QUEST_ACCEPTED", 3, 33)
        check("classic acceptance uses quest id rather than log index", watched[3] == 33)
        env.fire("QUEST_ACCEPTED", 3, env.SECRET)
        check("protected second payload cannot become log index", #watched == 3)
        C_QuestLog.GetLogIndexForQuestID = function() return nil end
        env.fire("QUEST_ACCEPTED", 33)
        check("quest removed before processing is not tracked", #watched == 3)

        module = load({ questtracker = { maxVisible = 1, pins = "22" } })
        check("visible quest cap preserves pinned priority", module.View.Blocks[1].questID == 22
            and module.View.Blocks[1].shown and not module.View.Blocks[2].shown)
        check("quest cap reports hidden count without untracking", module.View.More.text == "+1 more"
            and module.View.Header.count.text == "2" and #stub.watches == 2)
        local limitSetting
        for _, setting in ipairs(module.Options.settings) do
            if setting.key == "maxVisible" then limitSetting = setting end
        end
        check("visible cap setting exists", limitSetting ~= nil)
        if limitSetting then
            limitSetting.set(0)
            check("zero cap restores all quest blocks", module.View.Blocks[2].shown and not module.View.More.shown)
            limitSetting.set(1)
            env.click(module.View.Header)
            check("collapse hides overflow line", not module.View.More.shown and module.Holder.height == 18)
        end
        check("out of bounds cap rejected in sharing", not pcall(RikUI.ProfileSchema.Project, {questtracker={maxVisible=26}}))

        module = load({ modules = { questtracker = false } })
        check("a disabled module leaves the stock tracker untouched", module.Holder == nil
            and ObjectiveTrackerFrame.parent == UIParent and RikUI.Layout.Groups.questtracker == nil)
    end)
    C_CVar.SetCVarBitfield, C_CVar.GetCVarBitfield = savedSet, savedGet
    LE_FRAME_TUTORIAL_HOW_TO_SUPERTRACK = savedFlag
    env.KNOWN_EVENTS.QUEST_ACCEPTED = acceptedKnown
    restoreCreate()
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat, env.shiftDown = false, false
    check("quest tracker suite completes", ok, reason)
end
