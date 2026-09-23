-- Status precedence and actual widget refresh under the live controller fixture.
return function(check,p,env)
    local observed=p.Controller.Get()
    local function status(state,detail)
        return p.Guidance.RouteStatus(observed,{status=state,detail=detail})
    end
    check("missing terrain is explicit",p.Guidance.RouteStatus(observed,nil)=="Terrain datasource is not installed")
    check("installed service distinguishes missing datasource",status("unavailable","Terrain datasource is not installed")=="Terrain datasource is not installed")
    check("missing player position is distinct",status("unavailable-position")=="Your position is unavailable")
    check("uncovered player is distinct",status("unknown-location","outside known navigation polygons")=="Your position is outside the walking model")
    check("ambiguous floor does not claim uncovered player",status("unknown-location","Floor or polygon boundary is ambiguous")=="Your floor is uncertain")
    check("inconsistent coordinates do not claim uncovered player",status("unknown-location","Map and world positions disagree")=="Player location is inconsistent")
    check("ambiguous target does not claim missing polygon",status("unknown-target","Floor or polygon boundary is ambiguous")=="Quest marker floor is uncertain")
    check("limited search is distinct from disconnected model",status("budget-exhausted"):find("limit",1,true)
        and status("no-known-path"):find("terrain model",1,true))
    check("modeled success retains estimate wording",status("modeled")=="Terrain route estimate")
    for _,state in ipairs({"constraint-conflict","updating","unavailable"}) do
        check(state.." overrides stale terrain",p.Guidance.RouteStatus({status=state,detail="Specific model reason"},
            {status="modeled"})=="Specific model reason")
    end
    check("calculated model keeps its own evidence",p.Guidance.RouteStatus({status="feasible",calculated=true,
        detail="XP estimate incomplete"},{status="unknown-location"})=="XP estimate incomplete")
    check("pause overrides stale terrain",p.Guidance.RouteStatus({status="paused"},{status="modeled"})=="Paused")
    local noPoint=p.Schema.Clone(observed);noPoint.selected.destination=nil;noPoint.detail="Quest location is unavailable"
    check("missing destination keeps quest reason",p.Guidance.RouteStatus(noPoint,{status="modeled"})==noPoint.detail)
    local terrainState,route={status="unknown-location",detail="outside known navigation polygons"},nil
    local invalidations=0
    p.Terrain={Status=function() return terrainState end,Guidance=function() return route end,
        Invalidate=function() invalidations=invalidations+1;route=nil;terrainState={status="updating",detail="Updating walking route"} end}
    p.View.Refresh()
    local summary=p.View.Window.summary
    check("status reserves wrapped two-line height",summary.status.wordWrap==true and summary.status:GetHeight()==38
        and summary:GetHeight()==124)
    check("approach status discloses final gap",status("modeled-approach")=="Approach estimate; final gap unverified")
    check("details show the actual uncovered position",summary.status:GetText()=="Your position is outside the walking model")
    local oldLine,lines=GameTooltip.AddLine,{}
    GameTooltip.AddLine=function(_,line) lines[#lines+1]=line end
    env.runScript(summary,"OnEnter")
    check("tooltip retains exact failure",table.concat(lines,"\n"):find("outside known navigation polygons",1,true)~=nil)
    terrainState={status="modeled",detail="Terrain estimate; traversal unverified"}
    route={meters=70,seconds=10};p.View.Refresh();lines={}
    env.runScript(summary,"OnEnter")
    check("successful tooltip retains native uncertainty",table.concat(lines,"\n"):find("traversal unverified",1,true)~=nil)
    GameTooltip.AddLine=oldLine
    p.Command("status")
    check("command shares modeled estimate status",require("widget_stub").printedContains(env,"Quest guidance: observed. Terrain route estimate"))
    p.Refresh()
    check("unchanged signature preserves existing terrain request",invalidations==0 and route~=nil)
    local oldInfo=C_QuestLog.GetInfo
    C_QuestLog.GetInfo=function(index) local row=oldInfo(index);row.title=row.title.." changed";return row end
    p.Refresh()
    check("title-only update retains terrain and refreshes quest text",invalidations==0 and route~=nil
        and p.Controller.Get().selected.title:find("changed",1,true)~=nil)
    check("same destination retains modeled terrain status",summary.status:GetText()~="Updating walking route")
    local full=p.Schema.Clone(observed)
    full.selected.targetHint={instructions="Give the ale only if the guard is present.",instructionsSource="user-reported-sequence"}
    local snapshot=p.GetSnapshot()
    snapshot.quests[full.selected.questID].objectives={{text=string.rep("Long objective ",30).."END",finished=false}}
    local content=p.Guidance.Details and p.Guidance.Details(full,snapshot,{destinationFloor={basis="Lower surface is inferred."}})
    check("details retain full objective beyond compact text",content and content:find("END",1,true))
    check("details use actual line breaks",content and content:find("\n",1,true) and not content:find("\\n",1,true))
    check("details label reported sequence and unknown access",content and content:find("Reported interaction",1,true)
        and content:find("unverified",1,true) and content:find("Lower surface is inferred.",1,true))
    local originalModel,originalSnapshot=p.Controller.Get,p.GetSnapshot
    p.Controller.Get=function() return full end
    p.GetSnapshot=function() return snapshot,{state="current"} end
    p.View.Refresh()
    local win=p.View.Window
    check("planner opens with quest browsing and hides detailed diagnostics",win.questList:IsShown()
        and win.selection:IsShown() and not win.details:IsShown())
    check("quest panes remain inside the window",win.questList:GetWidth()+win.selection:GetWidth()+48==win:GetWidth()
        and win.questList:GetHeight()+194<win:GetHeight())
    check("quest detail text is clipped independently from actions",win.selection.scroll.view.clips
        and win.selection.scroll:GetHeight()==146 and win.selection.route:GetParent()==win.selection)
    local selectedID=win.selection.quest.questID
    snapshot.quests[selectedID].objectives={{text="|cffff0000A guarded objective|r",finished=false}}
    local oldMeasure=win.selection.body.GetStringHeight
    win.selection.body.GetStringHeight=function() return 500 end
    p.View.Refresh()
    check("selected objectives are sanitized before display",not win.selection.body:GetText():find("|",1,true)
        and win.selection.body:GetText():find("A guarded objective",1,true))
    check("long selected objectives have scrollable space",win.selection.scroll.range==362)
    RikUI.Scroll.SetOffset(win.selection.scroll,999)
    check("selected objective scroll clamps at its end",win.selection.scroll.offset==362)
    win.selection.body.GetStringHeight=function() return 12 end
    p.View.Refresh()
    check("shorter objectives clear stale scroll",win.selection.scroll.offset==0 and win.selection.scroll.range==0)
    win.selection.body.GetStringHeight=oldMeasure
    check("native details pane presents full interaction text",win.instructions and win.instructions:GetText():find("guard is present",1,true)
        and win.instructions.wordWrap==true)
    if win.instructionScroll then
        p.View.ToggleDetails()
        win.instructions.GetStringHeight=function() return 700 end
        p.View.Refresh()
        RikUI.Scroll.SetOffset(win.details.scroll, 0)
        local scrollValue
        win.instructionScroll.SetVerticalScroll=function(_,value) scrollValue=value end
        env.runScript(win.instructionScroll,"OnMouseWheel",-1)
        check("details scroll remains bounded",scrollValue and scrollValue>0 and scrollValue<=win.details.scroll.range)
        p.View.ToggleDetails()
    else check("details can scroll long instructions",false) end
    p.Controller.Get,p.GetSnapshot=originalModel,originalSnapshot;p.View.Refresh()
    local retries=0
    p.Terrain.Retry=function() retries=retries+1;return true end
    p.Command("retry")
    check("retry command reaches terrain service",retries==1)
    check("details offers explicit retry control",p.View.Window.retry~=nil)
    if p.View.Window.retry then env.click(p.View.Window.retry) end
    check("retry button reaches terrain service",retries==2)
    C_QuestLog.GetInfo=oldInfo;p.Terrain=nil;p.Refresh()
end
