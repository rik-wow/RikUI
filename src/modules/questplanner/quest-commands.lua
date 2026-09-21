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
        core:Print("Quest guidance: "..model.status..". "..(model.detail or ""))
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
        local timing=stats.timingSamples>0 and string.format("%.2fms (observed this session)",stats.maxSliceMS) or "not measured"
        core:Print("Planner replans="..stats.replans.." max-slice="..timing)
        if planner.Navigation.lastError then core:Print("Quest map guidance: "..planner.Navigation.lastError) end
        return
    elseif verb=="show" then planner.View.Open(); return
    elseif verb=="reset" then controller.Clear(); return
    elseif verb=="map" then planner.Navigation.Open(); return
    elseif verb=="export" then planner.TransferView.Open(false); return
    elseif verb=="inspect" then planner.TransferView.Open(true); return
    elseif verb=="pause" or verb=="resume" then ok,reason=controller.Set("paused",verb=="pause")
    elseif verb=="pin" or verb=="skip" or verb=="avoid" then
        local names={pin="pins",skip="skips",avoid="avoids"}
        ok,reason=controller.Toggle(names[verb],tonumber(value))
    elseif verb=="arrow" or verb=="dungeons" then
        if value~="on" and value~="off" then reason="Use on or off."
        else ok,reason=controller.Set(verb,value=="on") end
    else
        core:Print("/rik quests show | map | pause | resume | pin <questID> | skip <questID> | avoid <mapID>")
        core:Print("/rik quests arrow on|off | dungeons on|off | export | inspect | reset | status")
        return
    end
    if not ok then core:Print("Quest planner: "..(reason or "command unavailable")) end
end
