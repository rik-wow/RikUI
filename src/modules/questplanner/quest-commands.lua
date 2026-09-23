-- Small explicit controls. No quest acceptance, completion, watch changes or abandonment.
local core,planner=RikUI,RikUI.QuestPlanner
function planner.OpenQuest(id)
    if not planner.Schema.ID(id) then return end
    core.Combat.Queue(function()
        if type(QuestMapFrame_OpenToQuestDetails)~="function" then core:Print("Quest map is unavailable."); return end
        local ok,reason=pcall(QuestMapFrame_OpenToQuestDetails,id)
        if not ok then core:Print("Quest map: "..tostring(reason)) end
    end,"questplanner:open-quest")
end
function planner.Command(arguments)
    if not planner.enabled then return core:Print("Quest planner is disabled.") end
    local verb,value=(arguments or ""):match("^%s*(%S*)%s*(.-)%s*$")
    verb=verb:lower()
    local controller=planner.Controller
    local ok,reason
    if verb=="" or verb=="status" then
        planner:Debug()
        local model,stats=controller.Get(),controller.Stats()
        core:Print("Quest guidance: "..model.status..". "..planner.Guidance.RouteStatus(model,planner.Terrain and planner.Terrain.Status()))
        local snapshot=planner.GetSnapshot()
        local done,total,ready=0,0,0
        for _,id in ipairs(snapshot and snapshot.order or {}) do
            local row=snapshot.quests[id]
            if row.objectivesComplete then ready=ready+1 end
            for _,objective in ipairs(row.objectives or {}) do
                total=total+1; if objective.finished then done=done+1 end
            end
        end
        core:Print("Quest progress: "..done.."/"..total.." objectives finished; "..ready.." quests ready to turn in.")
        local journal=planner.Journal.Status()
        core:Print("Quest journal: "..journal.entries.." session events; latest log change: "..(journal.lastChange or "none")..".")
        local context=controller.Context()
        if context then
            local locations,rewards=0,0
            for _ in pairs(context.destinations or {}) do locations=locations+1 end
            for _ in pairs(context.rewards or {}) do rewards=rewards+1 end
            local map=context.mapPOIStatus
            core:Print("Quest locations="..locations.." reward-XP reads="..rewards
                .." map-POIs="..(map and map.state or "not checked"))
        end
        if planner.SemanticData then
            local corpus=planner.SemanticData.Status()
            local semantic=planner.SemanticGuidance.Status()
            core:Print("Quest corpus: "..corpus.state.."; "..corpus.loadedPartitions.." partitions loaded; "
                ..semantic.matched.." objectives matched; "..semantic.unknown.." unmatched.")
        end
        local timing=stats.timingSamples>0 and string.format("%.2fms (observed this session)",stats.maxSliceMS) or "not measured"
        if model.selected then
            local row=model.selected
            core:Print("Quest selection: "..row.title.." ("..row.questID.."); "..row.detail)
            if row.recommendation then core:Print("Next-step advice: "..(model.manual and "Selected by you" or row.recommendation.text)) end
        end
        core:Print("Quest sequence searches="..stats.replans.." max-slice="..timing)
        if model.adaptive then
            core:Print("Style="..(model.flavor or "?").." plan="..(model.planStatus or "?")
                .." total callback max="..string.format("%.2f",stats.maxCallbackMS or 0).."ms; source load max="..string.format("%.2f",stats.maxLoadMS or 0).."ms")
            local estimate=model.estimate
            if estimate and estimate.seconds then
                core:Print(string.format("Estimated sequence %.0f–%.0fs; %s XP; %s",
                    estimate.seconds,estimate.upper or estimate.seconds,estimate.unknownXP and estimate.unknownXP>0 and "incomplete" or tostring(estimate.xp or "?"),
                    estimate.conditional and "conditional projection" or "supported estimate"))
            end
        end
        if planner.Terrain and planner.Terrain.Stats then
            local walking=planner.Terrain.Stats()
            local regions=planner.Regions and planner.Regions.Stats()
            core:Print("Walking searches="..walking.plans.."; routes published="..walking.published
                .."; terrain windows started="..(regions and regions.windows or 0)
                .."; terrain addons loaded="..(regions and regions.loads or 0))
        end
        if planner.Terrain then local terrain=planner.Terrain.Status(); core:Print("Terrain guidance: "..terrain.status..". "..terrain.detail) end
        if planner.Navigation.lastError then core:Print("Quest map guidance: "..planner.Navigation.lastError) end
        return
    elseif verb=="preferences" or verb=="styles" then
        if planner.PlanControls then planner.PlanControls.Open() end
        return
    elseif verb=="flavor" then
        local chosen
        for _,name in ipairs(planner.Preferences and planner.Preferences.Flavors() or {}) do if name:lower()==value:lower() then chosen=name end end
        ok,reason=controller.Preference("flavor",chosen or value)
    elseif verb=="session" or verb=="exploration" or verb=="reading" then
        local names={session="sessionMinutes",exploration="explorationMinutes",reading="readingSeconds"}
        ok,reason=controller.Preference(names[verb],tonumber(value))
    elseif verb=="reward" then ok,reason=controller.Preference("rewardFocus",value)
    elseif verb=="reward-target" then
        if value=="any" or value=="" then ok,reason=controller.Preference("rewardTarget",nil)
        else ok,reason=controller.Preference("rewardTarget",tonumber(value)) end
    elseif verb=="difficulty" or verb=="group" or verb=="travel" or verb=="grind" then
        ok,reason=controller.Preference(verb,value=="local" and "localOnly" or value)
    elseif verb=="services" or verb=="spoilers" or verb=="strict-session" then
        if value~="on" and value~="off" then reason="Use on or off."
        else ok,reason=controller.Preference(verb=="strict-session" and "strictSession" or verb,value=="on") end
    elseif verb=="defer" or verb=="quest-goal" or verb=="zone-goal" then
        local names={defer="defers",["quest-goal"]="questGoals",["zone-goal"]="zoneGoals"}
        ok,reason=controller.Toggle(names[verb],tonumber(value))
    elseif verb=="retry-action" then ok,reason=controller.Feedback("retry")
    elseif verb=="waiting" or verb=="recovery" or verb=="unavailable" or verb=="reset-learning" or verb=="reset-history" then
        ok,reason=controller.Feedback(verb)
    elseif verb=="decline-exploration" then ok,reason=controller.Preference("explorationMinutes",0)
    elseif verb=="new-session" then
        ok,reason=controller.Preference("defers",{})
    elseif verb=="switches" then
        local rows=planner.PlanRuntime and planner.PlanRuntime.Switches() or {}
        if #rows==0 then core:Print("No plan switches recorded.") end
        local function label(row) return row and ((row.title or row.actionID).." ["..row.actionID.."]") or "none" end
        local function score(value) return type(value)=="number" and string.format("%.3f",value) or "?" end
        for i=math.max(1,#rows-9),#rows do
            local row=rows[i]
            core:Print(string.format("%.0f: %s -> %s; %s (%s -> %s)",row.time or 0,
                label(row.from),label(row.to),row.reason or "unknown",score(row.fromScore),score(row.toScore)))
        end
        return
    elseif verb=="plan" then
        local model=controller.Get()
        core:Print((model.flavor or "Balanced")..": "..(model.reason or model.detail or "Reading quest state"))
        for index,row in ipairs(model.upNext or {}) do core:Print("Up next "..index..": "..(row.detail or row.title)) end
        for index,row in ipairs(model.alternatives or {}) do core:Print("Alternative "..index..": "..(row.detail or row.title)) end
        return
    elseif verb=="show" then planner.View.Open(); return
    elseif verb=="reset" then controller.Clear(); return
    elseif verb=="map" then planner.Navigation.Open(); return
    elseif verb=="plan-export" then planner.TransferView.OpenPlan(); return
    elseif verb=="export" then planner.TransferView.Open(false); return
    elseif verb=="inspect" then planner.TransferView.Open(true); return
    elseif verb=="route" then
        if value=="auto" then ok,reason=controller.Select(nil)
        elseif planner.Schema.ID(tonumber(value)) then ok,reason=controller.Select(tonumber(value))
        else reason="Use route <questID> or route auto." end
    elseif verb=="retry" then
        if planner.Terrain then ok,reason=planner.Terrain.Retry()
        else reason="Terrain datasource is unavailable" end
    elseif verb=="floor" then
        if planner.Terrain then ok,reason=planner.Terrain.SelectFloor(value=="auto" and 0 or tonumber(value))
        else reason="Terrain datasource is unavailable" end
    elseif verb=="pause" or verb=="resume" then ok,reason=controller.Set("paused",verb=="pause")
    elseif verb=="pin" or verb=="skip" or verb=="avoid" then
        local names={pin="pins",skip="skips",avoid="avoids"}
        ok,reason=controller.Toggle(names[verb],tonumber(value))
    elseif verb=="arrow" or verb=="dungeons" then
        if value~="on" and value~="off" then reason="Use on or off."
        else ok,reason=controller.Set(verb,value=="on") end
    else
        core:Print("/rik quests preferences | flavor <name> | session <minutes> | plan | plan-export | switches | defer <questID> | unavailable")
        core:Print("/rik quests show | map | pause | resume | pin <questID> | skip <questID> | avoid <mapID>")
        core:Print("/rik quests arrow on|off | floor auto|<number> | dungeons on|off | export | inspect | retry | route <questID>|auto | reset | status")
        return
    end
    if not ok then core:Print("Quest planner: "..(reason or "command unavailable")) end
end
