-- End-to-end sliced terrain controller replay, including motion through a calculated corridor.
return function(check)
    local env=require("wow_stub")
    local previous,frames=RikUI,env.frames
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
        assert(p.Terrain.Install(meta,shards))
        p.Terrain.Start()
        local driver=env.frames[1]
        local function tick(count) for _=1,count or 10 do env.runScript(driver,"OnUpdate",.2) end end
        tick()
        local guidance=assert(p.Terrain.Guidance())
        check("installed region produces live modeled corridor",guidance.status=="modeled" and not guidance.nativeVerified)
        check("bearing target is next portal instead of destination through wall",guidance.next.x==.9 and guidance.next.y==.95)
        local initial=guidance.meters
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
        assert(p.Terrain.Install(meta,shards)); tick()
        position.x,position.y=.85,.95; tick()
        guidance=assert(p.Terrain.Guidance())
        check("motion trims corridor by polygon membership",guidance.meters<initial and guidance.next.x==.85 and guidance.next.y==.9)
        position.x,position.y=.81,.81; tick()
        check("arrival does not turn in or complete quest",model.selected.questID==10 and p.Terrain.Guidance().meters<.00001)
        model.status="paused"; model.selected=nil; tick()
        check("pause clears terrain guidance",p.Terrain.Guidance()==nil)
        model={status="observed",selected={questID=11,destination={mapID=1426,x=.99,y=.81}}}
        tick()
        check("unknown target cannot create direct route",p.Terrain.Guidance()==nil and p.Terrain.Status().status=="unknown-target")
        p.Terrain.Invalidate()
        check("material invalidation immediately clears corridor",p.Terrain.Guidance()==nil)
        identity.build="changed"; tick()
        check("build changes reject installed terrain",p.Terrain.Status().status=="unavailable")
        p.enabled=false; tick()
        check("disabled module publishes no path",p.Terrain.Guidance()==nil)
    end)
    RikUI,env.frames=previous,frames
    check("terrain guidance fixture completes",ok,reason)
end
