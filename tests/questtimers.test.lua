-- C_QuestLog.GetQuestTimers with the 69913 shape: a list of { questID, questTimer } in seconds. The
-- list is re-read once a second while it is not empty, driven here through the holder's OnUpdate.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local saved = C_QuestLog
    local restore = widgets.install()
    local stub = {}
    local TITLES = { [101] = "The Escort", [202] = "Race Against Time" }
    local function installClient()
        stub.timers, stub.error, stub.reads = {}, nil, 0
        C_QuestLog = {
            GetQuestTimers = function()
                stub.reads = stub.reads + 1
                if stub.error then error(stub.error) end
                return stub.timers
            end,
            GetTitleForQuestID = function(questID) return TITLES[questID] end,
        }
    end
    local function load(profile, combat, prepare)
        widgets.loadAddon(env, { "skin.lua", "questtimers.lua" }, profile, combat, function()
            installClient()
            if prepare then prepare() end
        end)
        return RikUI.QuestTimers
    end
    local function update(timers)
        stub.timers = timers
        env.fire("QUEST_LOG_UPDATE")
    end
    local function tick(module, seconds) env.runScript(module.Holder, "OnUpdate", seconds) end
    local ok, reason = pcall(function()
        local module = load()
        local holder, group = module.Holder, RikUI.Layout.Groups.questtimers
        check("the list registers with the layout under key questtimers above the quest tracker", holder and group
            and group.frames[1] == holder and group.defaults.point == "TOPRIGHT")
        check("no timed quest shows nothing and runs no ticker", #module.Rows == 0
            and holder:GetScript("OnUpdate") == nil)

        update({ { questID = 101, questTimer = 125 } })
        local row = module.Rows[1]
        check("a timed quest gets a flat row with its title and the time as minutes and seconds",
            row.shown == true and #row.rikBorder == 4 and row.title.text == "The Escort" and row.time.text == "2:05"
            and row.title.fontPath == RikUI.Media.font)
        check("the row fades in and the ticker starts", row.fade.plays == 1 and holder:GetScript("OnUpdate") ~= nil)
        local reads = stub.reads
        tick(module, 0.4)
        check("the list is not re-read before a second has passed", stub.reads == reads)
        stub.timers = { { questID = 101, questTimer = 124 } }
        tick(module, 0.7)
        check("after a second the time is read again and the row does not fade in twice",
            row.time.text == "2:04" and row.fade.plays == 1)

        update({ { questID = 101, questTimer = 29 }, { questID = 202, questTimer = 3725 } })
        check("the last thirty seconds pulse red", row.time.text == "0:29" and row.pulse.playing == true)
        local second = module.Rows[2]
        check("a second timer stacks under the first and an hour shows as h:mm:ss", second.shown == true
            and second.title.text == "Race Against Time" and second.time.text == "1:02:05"
            and second.points[1][5] < row.points[1][5] and second.pulse.playing ~= true)
        update({ { questID = 999, questTimer = 40 } })
        check("a quest without a title still shows its time, the pulse stops and the spare row hides",
            row.title.text == "" and row.time.text == "0:40" and row.pulse.playing == false and second.shown == false)

        update({})
        check("when the last timer ends the rows hide and the ticker stops", row.shown == false
            and holder:GetScript("OnUpdate") == nil)
        check("a clean run prints nothing", #env.printed == 0)
        stub.error = "timers refused"
        env.fire("QUEST_LOG_UPDATE")
        env.fire("QUEST_LOG_UPDATE")
        check("a failing read hides the list and is reported once", row.shown == false
            and widgets.printedContains(env, "Quest timers read") and #env.printed == 1)
        stub.error = nil
        env.inCombat = true
        update({ { questID = 101, questTimer = 60 } })
        env.inCombat = false
        check("a timer that starts in combat shows without a protected write", row.shown == true and #env.printed == 1)
        local many = {}
        for index = 1, 8 do many[index] = { questID = 101, questTimer = 60 + index } end
        update(many)
        check("the list is capped at five rows", #module.Rows == 5)
        SlashCmdList.RIKUI("debug")
        check("debug reports the list", widgets.printedContains(env, "Quest timers holder=true shown=5"))

        module = load(nil, true)
        check("a combat login builds nothing yet", module.Holder == nil)
        env.inCombat = false
        stub.timers = { { questID = 202, questTimer = 90 } }
        env.fire("PLAYER_REGEN_ENABLED")
        check("the list is built when combat ends and shows a timer that was already running",
            module.Holder ~= nil and module.Rows[1].time.text == "1:30")

        module = load(nil, false, function() C_QuestLog.GetQuestTimers = nil end)
        check("a client without quest timers builds nothing", module.Holder == nil and #env.printed == 0)

        module = load({ modules = { questtimers = false } })
        check("a disabled module builds nothing", module.Holder == nil and RikUI.Layout.Groups.questtimers == nil)
    end)
    restore()
    C_QuestLog = saved
    env.inCombat = false
    check("quest timer suite completes", ok, reason)
end
