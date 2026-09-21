-- Independent graph/geometry fixtures; actual extracted-data checks run through the offline gate.
return function(check)
    local previous=RikUI
    RikUI={Secret={IsSecret=function() return false end}}
    local ok,reason=pcall(function()
        for _,name in ipairs({"schema","nav-geometry","nav-search","navmesh"}) do dofile("src/modules/questplanner/quest-"..name..".lua") end
        local p=RikUI.QuestPlanner
        local identity={product="forever",build="1.60.1.69913",locale="enUS"}
        local meta={format="rikui-navmesh-v1",identity=identity,revision="fixture-v1",modeledMaxStep=.3,uiMapID=1426,worldMapID=0,bounds={0,0,20,20},
            source={sha256=string.rep("a",64),parser="original-fixture"},
            projection={originX=100,originY=100,width=100,height=100},counts={polygons=3,portals=4},exclusions={}}
        local function square(id,x,z,height)
            height=height or 0
            return {id=id,points={{x,height,z},{x+10,height,z},{x+10,height,z+10},{x,height,z+10}},portals={}}
        end
        local a,b,c=square(1,0,0),square(2,10,0),square(3,10,10)
        a.portals={{to=2,left={10,0,0},right={10,0,10}}}
        b.portals={{to=1,left={10,0,10},right={10,0,0}},{to=3,left={10,0,10},right={20,0,10}}}
        c.portals={{to=2,left={20,0,10},right={10,0,10}}}
        local shards={{identity=identity,polygons={a,b,c}}}
        local function load(m,s,budget)
            local job,issue=p.NavMesh.Begin(m or meta,s or shards)
            if not job then return nil,issue end
            while true do
                local data,problem,done=job:Step(budget or 1)
                if done then return data,problem end
            end
        end
        check("scalar manifest fails without throwing",not p.NavMesh.Begin(42,{}))
        local mesh=assert(load())
        check("scalar navigation policy rejected",not mesh:Begin({x=1,z=1},{x=2,z=2},true))
        local mutations={
            function(v) v.extra={} end,
            function(v) v.points[1][1]=0/0 end,
            function(v) v.points[1][4]=0 end,
            function(v) v.points[2]=nil end,
            function(v) v.points[1]=v.points end,
            function(v) setmetatable(v.points[1],{}) end,
            function(v) v.portals[1].extra={} end,
            function(v) v.portals[1].left[1]=math.huge end,
            function(v) v.id=2147483648 end,
            function(v) v.portals[1].to=2147483648 end,
        }
        for index,mutate in ipairs(mutations) do
            local invalid=p.Schema.Clone(shards);mutate(invalid[1].polygons[1])
            check("fixed-shape polygon parsing rejects malformed input "..index,not load(meta,invalid))
        end
        local stopped=assert(p.NavMesh.Begin(meta,shards));stopped:Step(1);stopped:Cancel()
        local value,problem,done=stopped:Step(64)
        check("cancelled preparation never publishes partial mesh",not value and problem=="cancelled" and done)
        local start,goal={x=1,z=1},{x=19,z=19}
        local function path(graph,from,to,options,budget)
            local job,issue=graph:Begin(from,to,options)
            if not job then return nil,issue end
            while true do local result=job:Step(budget or 1); if result then return result end end
        end
        local function approach(graph,from,to,budget)
            local job,issue=graph:BeginMarkerApproach(from,to)
            if not job then return nil,issue end
            for _=1,10000 do local result=job:Step(budget or 1); if result then return result end end
            error("approach exceeded bounded fixture work")
        end
        local near={x=9.6,z=15}
        check("exact search still rejects uncovered marker",not mesh:Begin(start,near))
        local approached=assert(approach(mesh,start,near))
        check("marker approach stops on modeled ground",approached.status=="modeled"
            and approached.approach.gap<=1 and approached.points[#approached.points][1]>10
            and approached.approach.marker.x==near.x and approached.approach.finalLegVerified==false)
        check("approach slicing preserves endpoint and cost",approach(mesh,start,near,128).meters==approached.meters)
        check("marker outside bounded radius stays unknown",approach(mesh,start,{x=8,z=15}).status=="unknown-target")
        local vicinity=assert(mesh:BeginMarkerApproach(start,{x=6,z=15},{markerRadius=8}))
        local vicinityResult
        repeat vicinityResult=vicinity:Step(1) until vicinityResult
        check("quest vicinity stops on a connected surface without drawing the final gap",
            vicinityResult.status=="modeled" and vicinityResult.approach.gap>4
            and vicinityResult.approach.radius==8 and vicinityResult.approach.finalLegVerified==false)
        check("vicinity cannot expand without bound",
            not mesh:BeginMarkerApproach(start,near,{markerRadius=9}))
        check("marker outside source bounds cannot pull a route outward",not mesh:BeginMarkerApproach(start,{x=20.1,z=15}))
        check("connected boundary marker uses an exact route",approach(mesh,start,{x=10,z=5}).approach==nil)
        check("missing start is never snapped",not mesh:BeginMarkerApproach({x=9.6,z=15},goal))
        local cancelled=assert(mesh:BeginMarkerApproach(start,near)); cancelled:Cancel()
        check("endpoint resolver cancellation publishes no route",cancelled:Step().status=="cancelled")
        local route=assert(path(mesh,start,goal))
        check("portal path follows L corridor around missing quadrant",route.status=="modeled" and #route.points==7)
        local aim,crossed,last=p.NavGeometry.CorridorAim(route,{1,0,9},1)
        check("occluded destination uses visible portal interval beyond the bend",last==3 and aim[1]>10 and aim[3]>10)
        check("anticipation crosses both real portals in order",#crossed==2
            and crossed[1][1]==10 and crossed[1][3]>0 and crossed[1][3]<10
            and crossed[2][3]==10 and crossed[2][1]>10 and crossed[2][1]<20)
        local fromNext=p.NavGeometry.CorridorAim(route,{15,0,5},2)
        check("steering advances beyond boundary toward final endpoint",fromNext==route.points[#route.points])
        local atEnd,_,endIndex=p.NavGeometry.CorridorAim(route,{18,0,18},3)
        check("steering stays at approach in final polygon",atEnd==route.points[#route.points] and endIndex==3)
        local legacy=p.Schema.Clone(route);legacy.portals=nil
        local safe,_,safeIndex=p.NavGeometry.CorridorAim(legacy,{1,0,9},1)
        check("missing corridor proof cannot enable a direct shortcut",safe==legacy.points[3] and safeIndex==1)
        local straight=assert(path(mesh,{x=1,z=5},{x=19,z=5}))
        local ahead,gates,final=p.NavGeometry.CorridorAim(straight,{9.8,0,5},1)
        check("near portal points beyond it instead of back to midpoint",ahead[1]==19 and final==2 and #gates==1)
        local corner,cornerGates,cornerIndex=p.NavGeometry.CorridorAim(route,{1,0,1},1)
        check("anticipation bypasses the corner vertex through portal interiors",cornerIndex==3 and #cornerGates==2
            and cornerGates[1][3]<10 and cornerGates[2][1]>10 and corner[3]>10)
        local contained=true
        for x=.1,9.9,.7 do for z=.1,9.9,.7 do
            local target,proof,reached=p.NavGeometry.CorridorAim(route,{x,0,z},1)
            contained=contained and #proof==reached-1
            for step=0,100 do
                local tx,tz=x+(target[1]-x)*step/100,z+(target[3]-z)*step/100
                contained=contained and tx>=0 and tx<=20 and tz>=0 and tz<=20
                    and (tx>=10 or tz<=10)
            end
        end end
        check("off-center approaches never cross missing L-corridor quadrant",contained)
        local reversed=p.Schema.Clone(route)
        for _,gate in ipairs(reversed.portals) do gate.left,gate.right=gate.right,gate.left end
        local reversedAim,reversedProof=p.NavGeometry.CorridorAim(reversed,{1,0,9},1)
        check("visible interval does not depend on portal endpoint winding",
            p.NavGeometry.Distance(aim,reversedAim)<.00001 and #reversedProof==#crossed)
        -- Same open strip split into many tiny polygons must not become node chasing.
        local dense={corridor={},surfaces={},portals={},points={{.05,0,2}}}
        for index=1,100 do
            local x=(index-1)*.1
            dense.corridor[index]=index
            dense.surfaces[index]={{x,0,0},{x+.1,0,0},{x+.1,0,10},{x,0,10}}
            dense.points[#dense.points+1]={x+.05,0,5}
            if index<100 then
                local gate={left={x+.1,0,0},right={x+.1,0,10},midpoint={x+.1,0,5}}
                dense.portals[index]=gate;dense.points[#dense.points+1]=gate.midpoint
            end
        end
        dense.points[#dense.points+1]={9.95,0,2}
        local far,proof,reached=p.NavGeometry.CorridorAim(dense,{.05,0,2},1)
        check("dense corridor aims several yards ahead without touching centers",far[1]>.05+6 and reached>12 and #proof==reached-1)
        local passed,passedProof,passedIndex=p.NavGeometry.CorridorAim(dense,{1.47,0,8},15)
        check("off-center progress advances from current polygon without reaching old aim",
            passed[1]>1.47+6 and passedIndex>reached and #passedProof==passedIndex-15)
        check("open corridor preserves goal-aligned lateral position instead of seeking center",math.abs(far[3]-2)<.00001)
        check("off-center corridor aims toward goal instead of center node",passed[3]<8 and math.abs(passed[3]-5)>.1)
        check("dense lookahead remains bounded",reached<=65 and passedIndex<=79)
        local broad=p.Schema.Clone(dense)
        for _,surface in ipairs(broad.surfaces) do for _,point in ipairs(surface) do point[1]=point[1]*100 end end
        for _,point in ipairs(broad.points) do point[1]=point[1]*100 end
        for _,gate in ipairs(broad.portals) do
            gate.left[1]=gate.left[1]*100;gate.right[1]=gate.right[1]*100;gate.midpoint[1]=gate.midpoint[1]*100
        end
        local _,_,broadLast=p.NavGeometry.CorridorAim(broad,{5,0,2},1)
        check("spatial horizon preserves existing broad-polygon anticipation",broadLast==13)
        local exact=2*math.sqrt(32)+20
        check("center-graph distance matches independent geometry",math.abs(route.meters-exact)<.000001)
        check("derived path never claims native or continuous global optimality",route.nativeVerified==false and not route.globalOptimal)
        check("path slice sizes preserve deterministic cost",path(mesh,start,goal,nil,128).meters==route.meters)
        check("location outside polygons never snaps to nearest",not mesh:Locate({x=1,z=19}))
        check("connected same-floor shared boundary resolves deterministically",mesh:Locate({x=10,z=5}).id==1)
        check("connected junction resolves through incident portals",mesh:Locate({x=10,z=10}).id==1)
        local split=p.Schema.Clone(shards);split[1].polygons[1].portals={}
        split[1].polygons[2].portals={split[1].polygons[2].portals[2]}
        local splitMeta=p.Schema.Clone(meta);splitMeta.counts.portals=2
        local splitMesh=assert(load(splitMeta,split))
        check("coincident unlinked boundary cannot establish walkability",not splitMesh:Locate({x=10,z=5}))
        local stacked=p.Schema.Clone(shards);stacked[1].polygons[4]=square(4,0,0)
        local stackedMeta=p.Schema.Clone(meta);stackedMeta.counts.polygons=4
        check("coincident overlapping interiors stay ambiguous",not assert(load(stackedMeta,stacked)):Locate(start))
        local projected=mesh:Project(1426,.8,.9)
        check("map projection respects world axis swap",projected.x==20 and math.abs(projected.z-10)<.000001)
        local unprojected=mesh:Unproject({20,0,10})
        check("map projection roundtrip",unprojected.x==.8 and unprojected.y==.9)
        check("different map has no projection",mesh:Project(999,.8,.9)==nil)
        local same=path(mesh,{x=1,z=1},{x=9,z=9})
        check("same convex polygon uses direct contained segment",#same.points==2 and math.abs(same.meters-math.sqrt(128))<.000001)
        -- A wide finite graph needs more total work, not more work in one frame.
        local broadSearch={meta={revision="wide-search"},polygons={}}
        local edgeCount=18000
        for id=1,edgeCount+1 do
            broadSearch.polygons[id]={center={0,0,0},points={},portals={}}
            if id>1 then
                broadSearch.polygons[1].portals[id-1]={to=id,meters=1,midpoint={0,0,0}}
            end
        end
        local function locateSearch(_,point) return {id=point.id,point={0,0,0}} end
        local function wideJob(limit)
            return assert(p.NavSearch.Begin(broadSearch,{id=1},{id=edgeCount+1},
                {maxWork=limit},locateSearch))
        end
        local truncated=wideJob(32768)
        local limitedWide
        repeat limitedWide=truncated:Step(128) until limitedWide
        check("old live budget reproduces premature failure",limitedWide.status=="budget-exhausted")
        local completeWide=wideJob(2*edgeCount+1)
        check("larger total budget still yields on the first small slice",completeWide:Step(1)==nil)
        local wideResult
        repeat wideResult=completeWide:Step(128) until wideResult
        check("graph-derived work bound finishes a route beyond the old cap",
            wideResult.status=="modeled" and wideResult.metrics.work==2*edgeCount+1)
        local cancelWide=wideJob(2*edgeCount+1)
        cancelWide:Step(128);cancelWide:Cancel()
        check("large in-progress searches remain cancellable",cancelWide:Step(128).status=="cancelled")
        local limited=path(mesh,start,goal,{maxWork=1})
        check("bounded search does not return partial path as complete",limited.status=="budget-exhausted" and limited.points==nil and limited.metrics.work==1)
        local job=assert(mesh:Begin(start,goal)); job:Cancel()
        check("cancelled path cannot publish",job:Step().status=="cancelled")
        local disconnected=p.Schema.Clone(shards); disconnected[1].polygons[2].portals={disconnected[1].polygons[2].portals[1]}
        disconnected[1].polygons[3].portals={}
        local less=p.Schema.Clone(meta); less.counts.portals=2
        check("nearby polygons without portals stay disconnected",path(assert(load(less,disconnected)),start,goal).status=="no-known-path")
        local function reachable(graph,from,to,settings)
            local pending=assert(graph:BeginMarkerApproach(from,to,settings or {markerRadius=8,reachableApproach=true}))
            local result
            repeat result=pending:Step(1) until result
            return result
        end
        -- Two real ramp-connected floors share the foyer, but the marker gives no floor.
        local floorPolys={square(1,0,0),square(2,10,0),square(3,20,0),
            square(4,10,10),square(5,10,20,10),square(6,20,20,10),
            square(7,20,10,10),square(8,20,0,10)}
        floorPolys[4].points[3][2]=10;floorPolys[4].points[4][2]=10
        local function link(from,to,left,right)
            table.insert(floorPolys[from].portals,{to=to,left=left,right=right})
            table.insert(floorPolys[to].portals,{to=from,left=right,right=left})
        end
        link(1,2,{10,0,0},{10,0,10});link(2,3,{20,0,0},{20,0,10})
        link(2,4,{10,0,10},{20,0,10});link(4,5,{10,10,20},{20,10,20})
        link(5,6,{20,10,20},{20,10,30});link(6,7,{20,10,20},{30,10,20})
        link(7,8,{20,10,10},{30,10,10})
        local floorMeta=p.Schema.Clone(meta)
        floorMeta.bounds={0,0,30,30};floorMeta.counts={polygons=8,portals=14}
        local floorMesh=assert(load(floorMeta,{{identity=identity,polygons=floorPolys}}))
        local marker={x=25,z=5}
        local function walkFloors(points)
            local prior=assert(floorMesh:Locate({x=15,z=5}))
            for _,target in ipairs(points) do
                local origin=prior.point
                local steps=math.ceil(math.sqrt((target[1]-origin[1])^2+(target[2]-origin[3])^2))
                for step=1,steps do
                    local nextPoint={x=origin[1]+(target[1]-origin[1])*step/steps,
                        z=origin[3]+(target[2]-origin[3])*step/steps}
                    prior=assert(floorMesh:LocateContinued(nextPoint,prior))
                end
            end
            return prior
        end
        local upstairs=walkFloors({{15,25},{25,25},{25,5}})
        check("connected ascent retains the upper floor over the lower room",
            upstairs.id==8 and upstairs.point[2]==10)
        local downstairs=walkFloors({{15,25},{25,25},{25,5},{25,25},{15,25},{15,5},{25,5}})
        check("descending the same staircase returns to the lower floor",
            downstairs.id==3 and downstairs.point[2]==0)
        check("strict destination never chooses a marker floor",not floorMesh:Begin(start,marker))
        check("common floor approach requires explicit marker policy",not floorMesh:BeginMarkerApproach(start,marker))
        local shared=reachable(floorMesh,start,marker,{commonApproach=true,markerRadius=8})
        check("floor ambiguity retains only the common connected foyer approach",
            shared.status=="modeled" and #shared.corridor==2 and shared.corridor[2]==2
            and shared.approach.kind=="observed-marker-common-approach" and shared.approach.floorCount==2)
        check("common approach keeps marker floor and interaction unresolved",
            shared.approach.marker.x==25 and not shared.approach.finalLegVerified
            and not shared.approach.interactionVerified and shared.points[#shared.points][1]==15)
        check("shared route never guesses player altitude",
            not floorMesh:BeginMarkerApproach(marker,start,{commonApproach=true}))
        local sharedPending=assert(floorMesh:BeginMarkerApproach(start,marker,{commonApproach=true}))
        check("common approach search yields before completion",sharedPending:Step(1)==nil)
        sharedPending:Cancel()
        check("common approach cancellation publishes no corridor",sharedPending:Step().status=="cancelled")
        check("common approach does not publish a partially searched floor set",
            reachable(floorMesh,start,marker,{commonApproach=true,maxWork=1}).status=="budget-exhausted")
        local missingFloor=p.Schema.Clone(floorPolys)
        missingFloor[7].portals={missingFloor[7].portals[1]};missingFloor[8].portals={}
        local missingMeta=p.Schema.Clone(floorMeta);missingMeta.counts.portals=12
        check("unreachable competing floor cannot be discarded to select the other",
            reachable(assert(load(missingMeta,{{identity=identity,polygons=missingFloor}})),
                start,marker,{commonApproach=true}).status=="unknown-target")
        local broken=assert(load(less,disconnected))
        local vicinityGoal={x=15,z=15}
        local partial=reachable(broken,start,vicinityGoal)
        check("disconnected marker can retain a real route to nearby reachable ground",
            partial.status=="modeled" and partial.approach.kind=="observed-marker-reachable-vicinity"
            and partial.approach.gap>5 and partial.approach.gap<5.01
            and partial.corridor[#partial.corridor]==2
            and partial.points[#partial.points][3]<10)
        check("reachable approach never fabricates the missing final connection",
            partial.approach.finalLegVerified==false and partial.approach.interactionVerified==false
            and partial.approach.marker.z==15)
        local exactPreferred=reachable(mesh,start,vicinityGoal)
        check("connected exact marker remains preferred to nearby candidates",
            exactPreferred.status=="modeled" and exactPreferred.approach==nil)
        local pendingReachable=assert(broken:BeginMarkerApproach(start,vicinityGoal,
            {markerRadius=8,reachableApproach=true}))
        check("reachable candidate collection yields",pendingReachable:Step(1)==nil)
        pendingReachable:Cancel()
        check("reachable candidate cancellation publishes no approach",
            pendingReachable:Step(128).status=="cancelled")
        check("reachable approach stays within its finite vicinity",
            reachable(broken,start,{x=15,z=19}).status=="no-known-path")
        check("explicit target altitude disables approximate reachable approach",
            reachable(broken,start,{x=15,z=15,height=0}).status=="no-known-path")
        check("exhausted work cannot publish a partial search as a reachable approach",
            reachable(broken,start,vicinityGoal,{markerRadius=8,reachableApproach=true,maxWork=1}).status=="budget-exhausted")
        local higher=p.Schema.Clone(disconnected)
        higher[1].polygons[3]=square(3,10,10,10)
        check("reachable approach cannot choose ground on a different floor",
            reachable(assert(load(less,higher)),start,vicinityGoal).status=="no-known-path")
        local exclusionMeta=p.Schema.Clone(less);exclusionMeta.exclusions={{7.5,14,8,15}}
        check("excluded marker vicinity cannot enable reachable approach",
            reachable(assert(load(exclusionMeta,disconnected)),start,vicinityGoal).status=="no-known-path")
        local layers=p.Schema.Clone(shards); layers[1].polygons[#layers[1].polygons+1]=square(4,0,0,10)
        local taller=p.Schema.Clone(meta); taller.counts.polygons=4
        local layered=assert(load(taller,layers))
        check("2D location cannot choose overlapping floors",not layered:Locate(start))
        local previousFloor={id=2,point={11,0,5}}
        local continued=layered:LocateContinued({x=9,z=5},previousFloor)
        check("short portal-crossing motion retains the previous modeled floor",
            continued and continued.id==1 and continued.floorSource=="modeled-continuity")
        check("continuity cannot bootstrap an ambiguous starting floor",
            not layered:LocateContinued(start,nil))
        check("continuity cannot choose a floor after a large displacement",
            not layered:LocateContinued(start,previousFloor))
        check("explicit observed height overrides modeled continuity",
            layered:LocateContinued({x=9,z=5,height=10},previousFloor).id==4)
        check("invalid continuation point returns a failure",not layered:LocateContinued(false,previousFloor))
        local disconnectedLayers=p.Schema.Clone(layers)
        disconnectedLayers[1].polygons[1].portals={}
        disconnectedLayers[1].polygons[2].portals={disconnectedLayers[1].polygons[2].portals[2]}
        local disconnectedMeta=p.Schema.Clone(taller);disconnectedMeta.counts.portals=2
        local ledgePolys={square(1,0,0,10),square(2,10,0,0)}
        local ledgeMeta=p.Schema.Clone(meta);ledgeMeta.counts={polygons=2,portals=0}
        local ledgeMesh=assert(load(ledgeMeta,{{identity=identity,polygons=ledgePolys}}))
        check("short motion cannot jump off the tracked floor to uniquely visible lower ground",
            not ledgeMesh:LocateContinued({x=10.1,z=5},{id=1,point={9.9,10,5}}))
        check("unique cold start still resolves without a previous floor",ledgeMesh:LocateContinued({x=10.1,z=5}).id==2)
        local cornerPolys={
            {id=1,points={{.75,0,.25},{0,0,0},{-1.25,0,.5}},
                portals={{to=2,left={0,0,0},right={-1.25,0,.5}}}},
            {id=2,points={{-1.5,0,-.5},{-1.25,0,.5},{0,0,0},{0,0,-1.25}},
                portals={{to=1,left={-1.25,0,.5},right={0,0,0}}}},
        }
        local cornerMeta=p.Schema.Clone(meta);cornerMeta.bounds={-2,-2,2,2};cornerMeta.counts={polygons=2,portals=2}
        local cornerMesh=assert(load(cornerMeta,{{identity=identity,polygons=cornerPolys}}))
        local beforeCorner={id=1,point={.00277,0,.00119}}
        local afterCorner={x=-.0922,z=-.08766}
        check("corner fixture has no straight portal crossing",
            #p.NavGeometry.FollowSurface({polygons=cornerPolys},beforeCorner,afterCorner,3)==0)
        check("short sampled turn follows a real neighboring portal",
            cornerMesh:LocateContinued(afterCorner,beforeCorner).id==2)
        cornerPolys[1].portals={};cornerPolys[2].portals={};cornerMeta.counts.portals=0
        check("the same short turn cannot cross an unlinked corner",
            not assert(load(cornerMeta,{{identity=identity,polygons=cornerPolys}})):LocateContinued(afterCorner,beforeCorner))
        check("continuity cannot cross an unlinked wall",
            not assert(load(disconnectedMeta,disconnectedLayers)):LocateContinued({x=9,z=5},previousFloor))
        check("approach cannot resolve a competing player floor",not layered:BeginMarkerApproach(start,near))
        local targetLayers=p.Schema.Clone(shards)
        targetLayers[1].polygons[4]=square(4,10,10,10)
        local targetMesh=assert(load(taller,targetLayers))
        local ambiguous=approach(targetMesh,start,near)
        check("competing approach floors remain ambiguous",ambiguous.status=="unknown-target"
            and ambiguous.detail:find("ambiguous",1,true)~=nil)
        check("uncertain vicinity never chooses an overlapping endpoint",
            reachable(targetMesh,start,near,{uncertainVicinity=true}).status=="unknown-target")
        local nearbyLayers=p.Schema.Clone(targetLayers)
        nearbyLayers[1].polygons[4].points[1][1]=10.2
        nearbyLayers[1].polygons[4].points[4][1]=10.2
        local nearbyFloors=assert(load(taller,nearbyLayers))
        check("nearby competing floor retains strict default",approach(nearbyFloors,start,near).status=="unknown-target")
        local possible=reachable(nearbyFloors,start,near,{uncertainVicinity=true})
        check("explicit vicinity policy can guide to uniquely located nearby ground",
            possible.status=="modeled" and possible.approach.kind=="observed-marker-uncertain-vicinity"
            and possible.approach.gap<=1 and nearbyFloors:Locate({x=possible.points[#possible.points][1],
                z=possible.points[#possible.points][3]}).id==3)
        check("possible vicinity does not resolve quest floor or interaction",
            possible.approach.reason=="nearby-marker-floors-ambiguous"
            and not possible.approach.finalLegVerified and not possible.approach.interactionVerified)
        check("invalid shared-approach destination fails without throwing",
            not nearbyFloors:BeginMarkerApproach(start,42,{commonApproach=true}))
        check("exact stacked target never falls back",not targetMesh:BeginMarkerApproach(start,goal))
        check("reachable policy cannot resolve an ambiguous target floor",
            not targetMesh:BeginMarkerApproach(start,goal,{markerRadius=8,reachableApproach=true}))
        check("disconnected nearest approach cannot invent a portal",
            approach(assert(load(less,disconnected)),start,near).status=="no-known-path")
        local excluded=p.Schema.Clone(meta); excluded.exclusions={{8.8,14,9,16}}
        check("excluded marker neighborhood cannot be bridged",
            not assert(load(excluded)):BeginMarkerApproach(start,near))
        check("invalid approach policy rejected",not mesh:BeginMarkerApproach(start,near,{maxWork=0}))
        local changed={x=near.x,z=near.z}
        local detached=assert(mesh:BeginMarkerApproach(start,changed));changed.x=1
        local detachedResult
        repeat detachedResult=detached:Step(64) until detachedResult
        check("pending marker coordinates are detached",detachedResult.approach.marker.x==near.x)
        check("readable height resolves matching floor",layered:Locate({x=1,z=1,height=10}).id==4)
        check("unmatched height remains unknown",not layered:Locate({x=1,z=1,height=5}))
        local bad=p.Schema.Clone(shards); bad[1].polygons[1].portals[1].to=999
        check("dangling portals prevent publication",not load(meta,bad))
        bad=p.Schema.Clone(shards); bad[1].polygons[1].portals[1].left={5,0,5}
        check("interior pseudo-portal is rejected",not load(meta,bad))
        bad=p.Schema.Clone(shards); bad[1].identity.build="other"
        check("cross-build shards rejected",not load(meta,bad))
        bad=p.Schema.Clone(meta); bad.counts.polygons=4
        check("partial datasets cannot publish",not load(bad))
        bad=p.Schema.Clone(meta); bad.exclusions={{1,1,2,2}}
        check("uncertain geometry exclusion cannot be entered",not load(bad))
        bad=p.Schema.Clone(meta); bad.bounds={0,0,19,20}
        check("collision polygons cannot expand acquired terrain coverage",not load(bad))
        local star={{0,0,3},{2,0,-3},{-3,0,1},{3,0,1},{-2,0,-3}}
        check("self intersecting star is not accepted as convex",not p.NavGeometry.Convex(star))
        bad=p.Schema.Clone(meta); bad.modeledMaxStep=nil
        check("undeclared step model rejected",not load(bad))
        bad=p.Schema.Clone(shards)
        for _,point in ipairs(bad[1].polygons[2].points) do point[2]=100 end
        check("horizontal adjacency cannot connect different floors",not load(meta,bad))
        bad=p.Schema.Clone(shards); bad[1].polygons[1].portals[1].left[2]=100
        check("portal height must match source edge",not load(meta,bad))
        check("boundary tolerance includes quantized endpoint extension",
            p.NavGeometry.OnBoundary({{0,0,0},{1,0,0},{1,0,1}}, {1.005,0,0}, .01))
        a.points[1][1]=-500
        check("published geometry detached from source",mesh:Locate(start).id==1)
        local details=mesh:Metadata(); details.identity.build="mutated"
        check("published metadata detached",mesh:Metadata().identity.build==identity.build)
    end)
    RikUI=previous
    check("navigation fixture completes",ok,reason)
end
