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
    check("status reserves wrapped two-line height",summary.status.wordWrap==true and summary.status:GetHeight()==29
        and summary:GetHeight()==110)
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
    check("material log update clears terrain before next frame",invalidations==1 and route==nil
        and p.Controller.Get().selected.title:find("changed",1,true)~=nil)
    check("new selection cannot show old terrain status",summary.status:GetText()=="Updating walking route")
    local retries=0
    p.Terrain.Retry=function() retries=retries+1;return true end
    p.Command("retry")
    check("retry command reaches terrain service",retries==1)
    check("details offers explicit retry control",p.View.Window.retry~=nil)
    if p.View.Window.retry then env.click(p.View.Window.retry) end
    check("retry button reaches terrain service",retries==2)
    C_QuestLog.GetInfo=oldInfo;p.Terrain=nil;p.Refresh()
end
