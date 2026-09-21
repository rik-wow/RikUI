-- End-to-end sliced terrain controller replay, including motion through a calculated corridor.
return function(check)
    local env=require("wow_stub")
    local previous,frames,previousClock=RikUI,env.frames,debugprofilestop
    RikUI={Secret={IsSecret=function() return false end}}
    env.frames={}
    local ok,reason=pcall(function()
        for _,name in ipairs({"schema","nav-geometry","nav-search","navmesh","terrain"}) do dofile("src/modules/questplanner/quest-"..name..".lua") end
        local p=RikUI.QuestPlanner
        local identity={product="forever",build="1.60.1.69913",locale="enUS"}
        local meta={format="rikui-navmesh-v1",identity=identity,revision="fixture-v1",modeledMaxStep=.3,uiMapID=1426,worldMapID=0,bounds={0,0,20,20},
            source={sha256=string.rep("a",64),parser="fixture"},counts={polygons=3,portals=4},blockers={},
            projection={originX=100,originY=100,width=100,height=100}}
        local shards={{identity=identity,polygons={
            {id=1,points={{0,0,0},{10,0,0},{10,0,10},{0,0,10}},portals={{to=2,left={10,0,0},right={10,0,10}}}},
            {id=2,points={{10,0,0},{20,0,0},{20,0,10},{10,0,10}},portals={
                {to=1,left={10,0,10},right={10,0,0}},{to=3,left={10,0,10},right={20,0,10}}}},
            {id=3,points={{10,0,10},{20,0,10},{20,0,20},{10,0,20}},portals={{to=2,left={20,0,10},right={10,0,10}}}},
        }}}
        local position={mapID=1426,x=.99,y=.99}
        local model={status="observed",selected={questID=10,destination={mapID=1426,x=.81,y=.81}}}
        p.Context={Position=function() return p.Schema.Clone(position) end}
        p.Controller={Get=function() return p.Schema.Clone(model) end}
        p.GetSnapshot=function() return {identity=identity} end
        p.enabled=true
        local refreshes,staleDuringRefresh=0,false
        p.View={Refresh=function()
            refreshes=refreshes+1
            if p.Terrain.Status().status~="modeled" and p.Terrain.Status().status~="modeled-approach" and p.Terrain.Guidance() then staleDuringRefresh=true end
        end}
        assert(p.Terrain.Install(meta,shards))
        check("terrain installation immediately publishes loading",p.Terrain.Status().status=="loading" and refreshes==1)
        p.Terrain.Start()
        local driver=env.frames[1]
        local function tick(count) for _=1,count or 10 do env.runScript(driver,"OnUpdate",.2) end end
        tick()
        local guidance=assert(p.Terrain.Guidance())
        check("installed region produces live modeled corridor",guidance.status=="modeled" and not guidance.nativeVerified)
        check("bearing anticipates beyond bend while retaining portal crossings",guidance.next.x<.9 and guidance.next.y<.9
            and guidance.points[2].y>.9 and guidance.points[3].x<.9)
        local oldStart=guidance.points[1].x
        position.x=.98
        env.runScript(driver,"OnUpdate",.016)
        check("steering observes lateral motion on the next frame",p.Terrain.Guidance().points[1].x~=oldStart)
        position.x=.99;tick()
        local initial=guidance.meters
        local unchangedRefreshes=refreshes; tick()
        check("unchanged modeled state does not refresh widgets",refreshes==unchangedRefreshes)
        local savedPosition=position; position=nil; tick()
        check("missing position is distinct from absent destination",p.Terrain.Status().status=="unavailable-position" and not p.Terrain.Guidance())
        position=savedPosition; tick()
        position.mapID=999; tick()
        check("leaving terrain map clears corridor and modeled status",
            not p.Terrain.Guidance() and p.Terrain.Status().status=="outside-coverage")
        position.mapID=1426; tick()
        check("returning to coverage recalculates guidance",p.Terrain.Guidance()~=nil)
        p.Context.WorldPosition=function() return {mapID=0,x=500,z=500,height=0} end
        tick()
        check("world disagreement cancels stale guidance",not p.Terrain.Guidance()
            and p.Terrain.Status().status=="unknown-location")
        p.Context.WorldPosition=nil; tick()
        check("recovered world location rebuilds guidance",p.Terrain.Guidance()~=nil)
        p.Context.WorldPosition=function() return {mapID=0,x=1,z=1,height=-100,rawReportedZ=0,verticalStatus="unestablished"} end
        p.Terrain.Invalidate(); tick()
        check("unestablished altitude cannot override unique horizontal grounding",p.Terrain.Guidance()~=nil)
        local stacked=p.Schema.Clone(shards)
        stacked[1].polygons[4]={id=4,points={{0,10,0},{10,10,0},{10,10,10},{0,10,10}},portals={}}
        local stackMeta=p.Schema.Clone(meta); stackMeta.counts.polygons=4
        assert(p.Terrain.Install(stackMeta,stacked)); tick()
        check("indoor raw zero cannot choose between stacked floors",not p.Terrain.Guidance()
            and p.Terrain.Status().status=="unknown-location"
            and p.Terrain.Status().detail:find("ambiguous",1,true)~=nil)
        p.Context.WorldPosition=function() return {mapID=0,x=1,z=1,height=0,verticalStatus="observed-altitude"} end
        tick()
        check("explicit established height can disambiguate modeled floor",p.Terrain.Guidance()~=nil)
        p.Context.WorldPosition=nil
        position.x,position.y=.89,.95; tick()
        position.x=.91;env.runScript(driver,"OnUpdate",.05)
        check("live motion preserves established floor under overlapping geometry",p.Terrain.Guidance()~=nil)
        p.Terrain.Invalidate();env.runScript(driver,"OnUpdate",.05);tick()
        check("quest refresh retains established floor inside overlapping geometry",p.Terrain.Guidance()~=nil)
        model.selected.questID=12;tick()
        check("changing selected quest retains the same observed floor",p.Terrain.Guidance()~=nil)
        model.status="paused";tick()
        check("pause removes route while continuing floor observation",p.Terrain.Guidance()==nil)
        model.status="observed";tick()
        check("resuming guidance does not forget an observed indoor floor",p.Terrain.Guidance()~=nil)
        env.runScript(driver,"OnUpdate",.6)
        check("stale continuity cannot choose an overlapping floor after a pause",not p.Terrain.Guidance()
            and p.Terrain.Status().status=="unknown-location")
        position.x,position.y=.99,.99
        model.selected.questID=10
        assert(p.Terrain.Install(meta,shards)); tick()
        position.x,position.y=.85,.95; tick()
        guidance=assert(p.Terrain.Guidance())
        check("motion advances through remaining corridor toward visible endpoint",guidance.meters<initial and guidance.next.x==.81 and guidance.next.y==.81)
        position.x,position.y=.81,.81; tick()
        check("arrival does not turn in or complete quest",model.selected.questID==10 and p.Terrain.Guidance().meters<.00001)
        model.status="paused"; model.selected=nil; tick()
        check("pause clears terrain guidance",p.Terrain.Guidance()==nil)
        model={status="observed",selected={questID=11,destination={mapID=1426,x=.99,y=.81}}}
        tick()
        check("unknown target cannot create direct route",p.Terrain.Guidance()==nil and p.Terrain.Status().status=="unknown-target")
        model.selected.destination={mapID=1426,x=.904,y=.85,scope="current-map-quest-poi",api="C_QuestLog.GetQuestsOnMap"}
        tick()
        local approach=assert(p.Terrain.Guidance())
        check("observed POI uses bounded approach",p.Terrain.Status().status=="modeled-approach"
            and approach.approach.gap<=1 and approach.approach.provenance.api=="C_QuestLog.GetQuestsOnMap")
        check("display stops before observed marker",approach.points[#approach.points].x<.9
            and approach.approach.marker.x==.904 and approach.approach.finalLegVerified==false)
        position=approach.points[#approach.points];tick()
        check("approach arrival keeps quest selected and gap unresolved",model.selected.questID==11
            and p.Terrain.Guidance().approach.interactionVerified==false and p.Terrain.Guidance().meters<.0001)
        model.selected.destination.scope=nil;tick()
        check("scope change clears approach even at same coordinates",not p.Terrain.Guidance()
            and p.Terrain.Status().status=="unknown-target")
        p.Terrain.Invalidate()
        check("material invalidation immediately clears corridor and status",p.Terrain.Guidance()==nil and p.Terrain.Status().status=="updating")
        local invalidatedRefreshes=refreshes;p.Terrain.Invalidate()
        check("repeated invalidation has no duplicate notification",refreshes==invalidatedRefreshes)
        identity.build="changed"; tick()
        check("build changes reject installed terrain",p.Terrain.Status().status=="unavailable")
        p.enabled=false; tick()
        check("disabled module publishes no path",p.Terrain.Guidance()==nil and p.Terrain.Status().status=="disabled")
        check("notifications never expose stale corridor",not staleDuringRefresh)
        local calls,time=0,0
        p.NavMesh.Begin=function() return {
            Step=function(_,budget) calls=calls+1;assert(budget==64) end,
            Cancel=function() end,
        } end
        debugprofilestop=function() time=time+5;return time end
        p.enabled=true;assert(p.Terrain.Install(meta,shards));p.Terrain.Step()
        check("loader yields once measured frame budget is spent",calls==1)
        debugprofilestop=nil;p.Terrain.Step()
        check("loader has a hard work bound without a native clock",calls==5)
        debugprofilestop=function() return 0 end;p.Terrain.Step()
        check("fast loading uses available budget but retains hard cap",calls==37)
        local before=calls;p.Terrain.Invalidate();p.Terrain.Step()
        check("quest invalidation continues existing terrain preparation",calls==before+32)
        p.enabled=false;before=calls;p.Terrain.Step()
        check("disabled planner performs no terrain validation",calls==before)
    end)
    RikUI,env.frames,debugprofilestop=previous,frames,previousClock
    check("terrain guidance fixture completes",ok,reason)
end
