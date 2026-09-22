return function(check)
    local old,oldAddOns,oldCombat,oldClock,oldTime=RikUI,C_AddOns,InCombatLockdown,debugprofilestop,GetTime
    local ok,problem=pcall(function()
        local function eq(a,b,label) assert(a==b,(label or "value")..": "..tostring(a).." ~= "..tostring(b)) end
        local function square(id,x0,x1,h,target,owner)
            local f={id,4,target and 1 or 0,x0,h,0,x1,h,0,x1,h,10,x0,h,10}
            if target then for _,v in ipairs({target,owner,x1,h,0,x1,h,10}) do f[#f+1]=v end end
            for i=1,#f do f[i]=tostring(f[i]) end
            return table.concat(f,",").."\n"
        end
        local function fixture(configure)
            RikUI={};RikUI["Secret"]={IsSecret=function()return false end}
            for _,n in ipairs({"schema","nav-geometry","nav-funnel","nav-follow","nav-search","region-codec","regions","navmesh"}) do
                dofile("src/modules/questplanner/quest-"..n..".lua")
            end
            local p=RikUI.QuestPlanner
            local f={p=p,calls={},totalCalls=0,combat=false,time=0,
                lines={square(1,0,10,0,2,2),square(2,10,20,0,3,3),square(3,20,30,0)}}
            f.identity={product="forever",build="1.60.1.69913",locale="enUS"}
            f.position={mapID=1426,x=.99,y=.99};f.destination={mapID=1426,x=.71,y=.99}
            f.catalog={format="rikui-region-catalog-v1",revision=string.rep("b",64),graphSHA256=string.rep("c",64),sourceBytes=0,regions={},
                meta={format="rikui-navmesh-v1",identity=f.identity,revision="fixture",modeledMaxStep=.3,uiMapID=1426,worldMapID=0,
                bounds={0,0,30,10},blockers={},source={sha256=string.rep("a",64),parser="fixture"},counts={polygons=3,portals=2},
                projection={originX=100,originY=100,width=100,height=100}}}
            for i=1,3 do
                f.catalog.regions[i]={id=i,addon=string.format("RikUIQuestTerrain_R%03d",i),polygons=1,portals=i<3 and 1 or 0,
                    pages=1,bytes=#f.lines[i],bounds={(i-1)*10,0,i*10,10},neighbors=i<3 and {i+1} or {},edgeCounts=i<3 and {[i+1]=1} or {}}
                f.catalog.sourceBytes=f.catalog.sourceBytes+#f.lines[i]
            end
            InCombatLockdown=function()return f.combat end
            GetTime=function()return f.time end
            debugprofilestop=function()f.time=f.time+.0001;return f.time*1000 end
            C_AddOns={LoadAddOn=function(name)
                local id=assert(tonumber(name:match("_R(%d+)$")))
                f.calls[id],f.totalCalls=(f.calls[id] or 0)+1,f.totalCalls+1
                if f.onLoad then f.onLoad(id) end
                if not f.omitPage then p.Regions.RegisterPage(f.catalog.revision,id,1,f.lines[id]) end
                return true
            end}
            if configure then configure(f) end
            assert(p.Regions.Install(f.catalog))
            return f
        end
        local function prepare(f)
            local why
            for _=1,128 do
                f.time=f.time+.1;local before=f.totalCalls
                local packet,reason=f.p.Regions.Prepare(f.identity,f.position,f.destination)
                assert(f.totalCalls-before<=1,"more than one synchronous addon load")
                if packet then return packet end
                why=reason
            end
            error("Prepare did not produce packet: "..tostring(why))
        end
        local function ingest(f,packet)
            local loader,reason=f.p.NavMesh.Begin(packet.meta,packet.stream)
            if not loader then return nil,reason end
            for _=1,4096 do local mesh,why,done=loader:Step(32);if done then return mesh,why end end
            error("stream exceeded budget")
        end
        local function route(mesh,a,b)
            local job=assert(mesh:Begin(a,b,{maxWork=4096}))
            for _=1,4096 do local result=job:Step(32);if result then return result end end
            error("query exceeded budget")
        end
        local f=fixture();local packet=prepare(f)
        assert(f.p.Regions.Current(packet.token))
        assert(not f.p.Regions.Prepare(f.identity,f.position,f.destination),"published validating packet twice")
        local mesh,why=ingest(f,packet);assert(mesh,why)
        eq(route(mesh,{x=1,z=1,height=0},{x=29,z=1,height=0}).status,"modeled","directed seam route")
        eq(route(mesh,{x=29,z=1,height=0},{x=1,z=1,height=0}).status,"no-known-path","reverse seam")
        assert(f.p.Regions.Accept(packet.token));for i=1,3 do eq(f.calls[i],1) end
        check("regional streamed directed topology validated",true)
        local windows,calls=f.p.Regions.Stats().windows,f.totalCalls
        local _,nearby=f.p.Regions.Prepare(f.identity,f.position,{mapID=1426,x=.95,y=.99})
        check("nearby changed goal reuses accepted terrain window",nearby=="ready"
            and f.p.Regions.Stats().windows==windows and f.totalCalls==calls)
        f=fixture(function(v)v.destination={mapID=1426,x=.95,y=.99}end)
        packet=prepare(f);assert(ingest(f,packet));assert(f.p.Regions.Accept(packet.token))
        local _,outside=f.p.Regions.Prepare(f.identity,f.position,{mapID=1426,x=.75,y=.99})
        check("unloaded goal region still requires a new window",outside~="ready")
        f=fixture()
        local row,all=f.p.RegionCodec.Decode(f.lines[1]:sub(1,-2),{[1]=true,[2]=true},3)
        assert(row and #row.portals==1 and all==1)
        row,all=f.p.RegionCodec.Decode(f.lines[1]:sub(1,-2),{[1]=true},3);assert(row and #row.portals==0 and all==1)
        assert(not f.p.RegionCodec.Decode(square(1,0,10,0,2,4):sub(1,-2),{[1]=true},3))
        assert(not f.p.RegionCodec.Decode(f.lines[1]:gsub("^1,","1e309,"),{[1]=true},3))
        check("regional codec filters inactive seams and rejects malformed records",true)
        assert(not f.p.Regions.RegisterPage(string.rep("d",64),1,1,f.lines[1]))
        assert(not f.p.Regions.RegisterPage(f.catalog.revision,1,2,f.lines[1]))
        assert(f.p.Regions.RegisterPage(f.catalog.revision,1,1,f.lines[1]))
        assert(not f.p.Regions.RegisterPage(f.catalog.revision,1,1,f.lines[1]))
        check("regional pages reject stale revisions, bounds and duplicates",true)
        f=fixture(function(v)v.lines[3]=square(3,20,30,8);eq(#v.lines[3],v.catalog.regions[3].bytes)end)
        mesh,why=ingest(f,prepare(f));assert(not mesh and why,"wrong-floor seam became walkable")
        check("regional vertical seam rejected",true)
        f=fixture(function(v)for _,r in ipairs(v.catalog.regions)do r.bounds={0,0,30,10}end;v.destination={mapID=1426,x=.95,y=.95}end)
        prepare(f);for i=1,3 do eq(f.calls[i],1,"overlapping region omitted")end
        f=fixture();f.combat=true
        for _=1,4 do assert(not f.p.Regions.Prepare(f.identity,f.position,f.destination))end
        eq(f.totalCalls,0);f.combat=false;prepare(f);eq(f.totalCalls,3)
        check("regional combat loading defers and resumes",true)
        f=fixture();f.onLoad=function()
            local before=f.totalCalls;assert(not f.p.Regions.Prepare(f.identity,f.position,f.destination));eq(f.totalCalls,before)
        end
        prepare(f)
        check("regional synchronous reentrancy cannot double-load",true)
        f=fixture();f.onLoad=function()f.p.Regions.Suspend()end
        assert(not f.p.Regions.Prepare(f.identity,f.position,f.destination));eq(f.totalCalls,1)
        f.onLoad=nil;f.p.Regions.Retry();assert(f.p.Regions.Current(prepare(f).token))
        f=fixture();local stale=prepare(f)
        f.destination={mapID=1426,x=.75,y=.99};f.p.Regions.Prepare(f.identity,f.position,f.destination)
        assert(not f.p.Regions.Current(stale.token) and not f.p.Regions.Accept(stale.token))
        f.p.Regions.Suspend();packet=prepare(f);f.p.Regions.Suspend()
        assert(not f.p.Regions.Accept(packet.token))
        check("regional changed goals and suspension reject stale publication",true)
        f=fixture();packet=prepare(f);f.p.Regions.Accept(packet.token,"invalid polygon")
        local before=f.totalCalls
        for _=1,12 do assert(not f.p.Regions.Prepare(f.identity,f.position,f.destination))end
        eq(f.totalCalls,before)
        for _,kind in ipairs({"bytes","missing"})do
            f=fixture(function(v)if kind=="bytes"then v.catalog.regions[1].bytes=v.catalog.regions[1].bytes+1;v.catalog.sourceBytes=v.catalog.sourceBytes+1 end end)
            f.omitPage=kind=="missing"
            for _=1,16 do assert(not f.p.Regions.Prepare(f.identity,f.position,f.destination))end
            eq(f.totalCalls,1,"bad page retried")
        end
        check("regional invalid revisions do not retry each frame",true)
        f=fixture();f.catalog.meta.projection.width=0;assert(not f.p.Regions.Install(f.catalog));eq(f.totalCalls,0)
        f.catalog.meta.projection.width=100;f.catalog.regions[1].edgeCounts[2]=2;assert(not f.p.Regions.Install(f.catalog))
        f=fixture();for _=1,5 do f.p.Regions.Expand()end;eq(f.totalCalls,0);prepare(f);eq(f.totalCalls,3)
        check("regional metadata and expansion remain bounded",true)
        f=fixture(function(v)
            v.catalog.regions[1].polygons=2
        end)
        packet=prepare(f);mesh,why=ingest(f,packet)
        assert(not mesh and why,"declared polygon count mismatch accepted")
        check("regional streamed counts are verified",true)
    end)
    RikUI,C_AddOns,InCombatLockdown,debugprofilestop,GetTime=old,oldAddOns,oldCombat,oldClock,oldTime
    check("regional lifecycle suite",ok,problem)
end
