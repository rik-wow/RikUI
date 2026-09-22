return function(check)
    local old=RikUI
    RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
    local ok,reason=pcall(function()
        for _,name in ipairs({"schema","objectives","steps","step-bindings","guide-data","observed-steps",
            "hunts","guidance","nav-geometry","nav-funnel","nav-follow","nav-search","navmesh"}) do
            dofile("src/modules/questplanner/quest-"..name..".lua")
        end
        local p=RikUI.QuestPlanner
        local identity={product="forever",build="1.60.1.69913",locale="enUS"}
        local snapshot={identity=identity,order={313},quests={[313]={title="The Grizzled Den",objectivesComplete=false,
            objectives={{text="3/8 Wendigo Mane",type="item",numFulfilled=3,numRequired=8,finished=false}}}}}
        local marker={mapID=1426,x=.2,y=.5,scope="current-map-quest-poi"}
        local ctx={origin="live",observedAt=10,position={mapID=1426,x=.21,y=.5},destinations={[313]=marker},rewards={},history={}}
        local policy={pins={},skips={},avoids={}}
        local function row() return p.Guidance.Observed(snapshot,ctx,policy)[1] end
        check("Wendigo item collection is a hunt without a fabricated target",row().hunt.radius==120 and row().hunt.source=="user-reported"
            and row().step.active.targetIdentityKnown==false)
        marker.scope="current-waypoint"
        check("explicit client access waypoint is not relaxed",not row().hunt)
        marker.scope="current-map-quest-poi"
        local frame={position=ctx.position,width=1000,height=1000,taxi=false,world={mapID=0}}
        local anchor={mapID=1426,x=.21,y=.5,scope="observed-hunt-area",terrainHeight=0,polygon=1,instanceID=0,corpusRevision="fixture"}
        local connected=true
        p.Context={Frame=function() return frame end}
        p.Terrain={ProgressAnchor=function() return p.Schema.Clone(anchor) end,ProgressConnected=function(a,b) return a and b and connected end}
        local function progress(count,time)
            ctx.observedAt=time
            local o=snapshot.quests[313].objectives[1]
            o.numFulfilled,o.text=count,count.."/8 Wendigo Mane"
            p.Hunts.Observe(snapshot,ctx)
        end
        progress(3,10)
        check("initial count does not invent a productive area",row().destination.scope=="current-map-quest-poi")
        progress(4,12)
        check("recent live count gain retains a modeled collection area",row().destination.scope=="observed-hunt-area"
            and row().hunt.radius==25 and row().hunt.source=="observed-progress")
        local revision=p.Hunts.Revision()
        anchor.x=.22;progress(5,14)
        check("nearby progress refreshes evidence without moving anchor",row().destination.x==.21 and p.Hunts.Revision()==revision)
        progress(5,315)
        check("old productive areas expire",row().destination.scope=="current-map-quest-poi")
        connected=false;progress(6,316)
        check("disconnected floor progress cannot create an area",row().destination.scope=="current-map-quest-poi")
        connected=true;frame.taxi=true;progress(7,317)
        check("taxi progress cannot create an area",row().destination.scope=="current-map-quest-poi")
        frame.taxi=false;ctx.origin="imported-untrusted";progress(7,318)
        check("imported progress cannot create an area",row().destination.scope=="current-map-quest-poi")
        ctx.origin="live";progress(7,319)
        progress(4,320);progress(5,321)
        check("new productive area can recover after count decrease",row().destination.scope=="observed-hunt-area")
        local evidenceRevision=p.Hunts.Revision()
        p.Hunts.Suspend();anchor.x=.3;progress(6,322)
        check("catch-up after stale snapshot cannot relocate a productive area",p.Hunts.Revision()==evidenceRevision)
        frame.world.mapID=1;progress(7,323)
        check("instance transition clears productive areas",row().destination.scope=="current-map-quest-poi")
        frame.world.mapID=0
        local q=snapshot.quests[313];q.objectives[1].finished=true;q.objectivesComplete=true
        progress(8,320)
        check("eight manes selects turn-in rather than a hunting arrival",not row().hunt and row().step.active.kind=="turnin"
            and row().step.state~="completed")
        q.objectives[1].finished=false;q.objectivesComplete=false
        snapshot.identity={product="forever",build="other",locale="enUS"}
        check("another build cannot inherit hunt definitions",not row().hunt)
        snapshot.identity=identity
        snapshot.order={287};snapshot.quests[287]={title="Frostmane Hold",objectives={
            {text="5/5 Frostmane Headhunter slain",type="monster",numFulfilled=5,numRequired=5,finished=true},
            {text="Fully explore Frostmane Hold",type="event",numFulfilled=0,numRequired=1,finished=false}}}
        ctx.destinations[287]=marker
        check("Frostmane exploration retains exact destination",not row().hunt and row().step.active.objectiveID=="q287.explore-hold")
        snapshot.quests[287].objectives[1].finished=false;snapshot.quests[287].objectives[1].numFulfilled=4
        snapshot.quests[287].objectives[1].text="4/5 Frostmane Headhunter slain"
        check("Frostmane kill stage supports area guidance",row().hunt and row().hunt.radius==40)

        local meta={format="rikui-navmesh-v1",identity=identity,revision="fixture",modeledMaxStep=.3,uiMapID=1426,worldMapID=0,
            bounds={0,0,200,20},source={sha256=string.rep("a",64),parser="fixture"},counts={polygons=2,portals=2},blockers={},
            projection={originX=200,originY=200,width=200,height=200}}
        local polys={
            {id=1,points={{0,0,0},{100,0,0},{100,0,20},{0,0,20}},portals={{to=2,left={100,0,0},right={100,0,20}}}},
            {id=2,points={{100,0,0},{200,0,0},{200,0,20},{100,0,20}},portals={{to=1,left={100,0,20},right={100,0,0}}}}}
        local loader=assert(p.NavMesh.Begin(meta,{{identity=identity,polygons=polys}}))
        local mesh
        repeat local v,why,done=loader:Step(64);if done then mesh=assert(v,why) end until mesh
        local function finish(job) for _=1,10000 do local v=job:Step(64,true);if v then return v end end;error("job exceeded bound") end
        local hint={radius=120,text="Collect Wendigo Manes",nearby="Look outside the cave first"}
        local function route(x,goal,radius)
            local value=finish(assert(mesh:Begin({x=x,z=10},{x=goal,z=10},{maxWork=1000})))
            value.huntHint=p.Schema.Clone(hint);value.huntHint.radius=radius or 120
            return finish(p.NavFollow.Begin(mesh,value,0))
        end
        local value=route(10,190)
        check("hunt approach shortens connected route by search distance",math.abs(value.meters-60)<.001 and #value.corridor==1
            and math.abs(value.walkPoints[#value.walkPoints][1]-70)<.001)
        local g=value.follow({id=1,point={10,0,10}},{speed=7})
        check("map and distance share shortened destination",not g.searching and math.abs(g.meters-60)<.001
            and g.path.tail[#g.path.tail].x==g.huntEndpoint.x)
        g=value.follow({id=1,point={69,0,10}},{speed=7})
        local instruction=p.Guidance.Instruction(g,{},nil,nil,nil)
        check("search arrival suppresses arrow without completing quest",g.searching and g.meters==0 and instruction.ending
            and instruction.text=="Collect Wendigo Manes" and not instruction.text:find("complete"))
        g=value.follow({id=1,point={65,0,10}},{speed=7})
        check("hunt entry and exit hysteresis avoids small corrections",g.searching)
        check("disconnected nearby polygon is not a hunting area",not p.Hunts.Display(mesh,value,{id=999,point={70,0,10}}))
        value=route(150,190)
        check("already inside search distance creates zero walking journey",value.meters<.001 and value.follow({id=2,point={150,0,10}},{}).searching)
        value=route(150,150)
        check("zero length hunt route remains usable",value.prepared and value.meters==0)
        value=route(10,190,90)
        check("clip on shared portal stays on connected floor",value.prepared and math.abs(value.meters-90)<.001)
        local from={id=1,point={99,0,10}}
        check("bounded progress check crosses a real portal",mesh:ConnectedNearby(from,{id=2,point={101,0,10}},3))
        check("bounded progress check rejects another floor",not mesh:ConnectedNearby(from,{id=2,point={101,10,10}},3))

        local full=finish(assert(mesh:Begin({x=10,z=10},{x=190,z=10},{maxWork=1000})))
        local partial=p.Schema.Clone(full)
        partial.approach={kind="observed-marker-common-approach",marker={x=190,z=10},gap=0}
        partial.huntHint=hint
        partial=finish(p.NavFollow.Begin(mesh,partial,2))
        check("uncertain floor approach never becomes hunt-area arrival",not partial.hunt and partial.approach
            and math.abs(partial.meters-full.meters)<.001)
        for _,point in ipairs(polys[2].points) do point[2]=.2 end
        for _,point in ipairs({polys[2].portals[1].left,polys[2].portals[1].right}) do point[2]=.2 end
        loader=assert(p.NavMesh.Begin(meta,{{identity=identity,polygons=polys}}));mesh=nil
        repeat local v,why,done=loader:Step(64);if done then mesh=assert(v,why) end until mesh
        value=route(10,190,40)
        check("hunt clipping preserves a mandatory elevation transition",value.prepared and #value.corridor==2
            and math.abs(value.walkPoints[#value.walkPoints][2]-.2)<.001)
        value=route(10,190,90.1)
        check("clip within a stair step grounds on its connected source floor",value.prepared
            and value.walkPoints[#value.walkPoints][2]==0)

    end)
    RikUI=old
    check("hunting area scenarios complete",ok,reason)
end
