return function(check)
    local previous=RikUI
    RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
    local ok,problem=pcall(function()
        for _,name in ipairs({"schema","journey","journey-live"}) do dofile("src/modules/questplanner/quest-"..name..".lua") end
        local p=RikUI.QuestPlanner;local J=p.Journey
        local identity={product="forever",build="1.60.1.69913",locale="enUS"}
        local nodes={a={id="a",mapID=1426,x=.1,y=.1,instanceID=0,floor="ground",anchorRevision=1},
            b={id="b",mapID=1426,x=.2,y=.2,instanceID=0,floor="ground",anchorRevision=1},
            c={id="c",mapID=1426,x=.3,y=.3,instanceID=0,floor="ground",anchorRevision=1}}
        local function leg(mode,from,to,id)
            return {id=id or "leg1",mode=mode,from=from or "a",to=to or "b",
                source={product=identity.product,build=identity.build,locale=identity.locale,authority="verified",id="synthetic-journey"}}
        end
        local function new(mode,path) return assert(J.New(identity,"g1",path or {leg(mode)},function(id) return nodes[id] end)) end
        local function anchor(id,seq,changes)
            local n=nodes[id];local a={sequence=seq,anchorVerified=true,connected=true,partial=false,mapID=n.mapID,
                instanceID=n.instanceID,floor=n.floor,anchorRevision=n.anchorRevision,distance=0}
            for k,v in pairs(changes or {}) do a[k]=v end
            return a
        end
        local function observe(c,seq,time,taxi,arrivals,extra)
            local e={identity=identity,generation="g1",sequence=seq,time=time,taxi=taxi,arrivals=arrivals or {}}
            for k,v in pairs(extra or {}) do e[k]=v end
            return c:Observe(e)
        end
        local function transition(seq,extra)
            local t={sequence=seq,verified=true,index=1,legID="leg1",mode="transport",from="a",to="b"}
            for k,v in pairs(extra or {}) do t[k]=v end
            return t
        end
        local bad=leg("flight");bad.source.build="other"
        check("journey rejects other build",not J.New(identity,"g1",{bad},function(id) return nodes[id] end))
        bad=leg("flight");bad.source.authority="reference"
        check("journey rejects reference-only travel",not J.New(identity,"g1",{bad},function(id) return nodes[id] end))
        check("journey rejects discontinuous legs",not J.New(identity,"g1",{leg("walk","a","b"),leg("walk","c","a","leg2")},function(id) return nodes[id] end))
        local c=new("walk");local v=c:Snapshot();v.destination.x=.99;v.source.id="changed"
        check("journey copy boundary",c:Snapshot().destination.x==.2 and c:Snapshot().source.id=="synthetic-journey")
        for i,change in ipairs({{floor="basement"},{partial=true},{sequence=1},{anchorVerified=false},{connected=false},{mapID=1},{anchorRevision=2}}) do
            check("arrival proof guard "..i,not observe(c,i,i,false,{b=anchor("b",i,change)}).complete)
        end
        check("qualified walking arrival advances",observe(c,8,8,false,{b=anchor("b",8)}).complete)
        c=new("flight")
        check("flight waits at departure",observe(c,1,1,false,{a=anchor("a",1)}).phase=="waiting")
        v=observe(c,2,1.1,true)
        check("correlated taxi boarding suppresses walking",v.boarded and v.phase=="riding" and v.suppressSteering and not v.destination)
        v=observe(c,3,2,false,{b=anchor("b",3,{floor="basement"})})
        check("taxi exit alone does not finish",v.exited and not v.complete)
        check("taxi exit and correct anchor completes travel",observe(c,4,2.1,false,{b=anchor("b",4)}).complete)
        c=new("flight");v=observe(c,1,10,true)
        check("reload on taxi has unknown boarding",not v.boarded and v.phase=="riding-unknown")
        v=observe(c,2,11,false,{b=anchor("b",2)})
        check("uncorrelated ride requests recovery",not v.complete and v.needsReplan and not v.destination)
        c=new("flight");observe(c,1,1,false,{a=anchor("a",1)})
        check("long sampling gap cannot establish boarding",not observe(c,2,10,true,{a=anchor("a",2)}).boarded)
        c=new("flight");observe(c,1,1,false,{a=anchor("a",1)});observe(c,2,1.1,nil)
        check("missing taxi observation breaks continuity",not observe(c,3,1.2,true).boarded)
        c=new("walk");observe(c,1,5,false)
        check("stale journey generation rejected",not observe(c,2,6,false,{b=anchor("b",2)},{generation="old"}).complete)
        check("duplicate observation rejected",not observe(c,1,6,false,{b=anchor("b",1)}).complete)
        check("past observation rejected",not observe(c,2,4,false,{b=anchor("b",2)}).complete)
        check("fresh observation after stale results works",observe(c,2,6,false,{b=anchor("b",2)}).complete)
        c=new("flight");observe(c,1,1,false,{a=anchor("a",1)},{paused=true})
        v=observe(c,2,1.1,true,nil,{paused=true})
        check("pause retains observed boarding",v.boarded and v.paused and v.suppressSteering)
        v=observe(c,3,2,false,{b=anchor("b",3)},{paused=true})
        check("pause retains observed arrival",v.complete and v.paused)
        c=new("transport");observe(c,1,1,false,{a=anchor("a",1)})
        check("boat does not advance on elapsed time",not observe(c,2,100,false).complete)
        v=observe(c,3,101,false,{b=anchor("b",3)})
        check("boat proximity without transition requires recovery",not v.complete and v.needsReplan)
        c=new("transport");observe(c,1,1,false,{a=anchor("a",1)})
        v=observe(c,2,1.1,false,nil,{transition=transition(2,{started=true,legID="other"})})
        check("transition must match actual leg",not v.boarded)
        v=observe(c,3,1.2,false,nil,{transition=transition(3,{started=true})})
        check("verified transport boarding advances phase",v.boarded)
        check("transport needs exit and destination",observe(c,4,2,false,{b=anchor("b",4)},{transition=transition(4,{ended=true})}).complete)
        c=new("walk",{leg("walk","a","b"),leg("walk","b","c","leg2")})
        v=observe(c,1,1,false,{b=anchor("b",1),c=anchor("c",1)})
        check("one travel leg per observation",not v.complete and v.index==2 and v.destination.id=="c")
        -- Live adapter preserves the final action and does not reuse its target identity at a waypoint.
        local data={Revision=function()return "r1" end,Identity=function()return identity end,Node=function(_,id)return nodes[id] end}
        local model={selected={questID=310,kind="turnin",targetHint={id="barrel"},destination=nodes.b},stops={{}}}
        local result={actions={{id="turnin310",node="b",travel={path={leg("flight")}}}}}
        p.Context={Frame=function()return {time=1,taxi=false} end}
        p.Terrain={Arrival=function(node,_,seq) if node.id=="a" then return anchor("a",seq) end end}
        local state=assert(p.JourneyLive.Attach(model,result,data,{},nil))
        assert(p.JourneyLive.Tick(state,model,false))
        check("live travel selects departure and retains quest action",model.selected.destination.id=="a" and model.selected.actionKind=="turnin" and not model.selected.targetHint)
        check("same journey survives planner revisions",p.JourneyLive.Attach(model,result,data,{},nil,state)==state)
        check("rebinding travel row retains original action",state.base.kind=="turnin")
        local fresh={selected=p.Schema.Clone(state.base),stops={{}}}
        assert(p.JourneyLive.Attach(fresh,result,data,{},nil,state)==state)
        check("refresh renders travel without another sample",p.JourneyLive.Tick(state,fresh,false)
            and fresh.selected.kind=="travel" and fresh.selected.destination.id=="a" and state.sequence==1)
        p.JourneyLive.Detach(state)
        local replacement={status="updating"}
        p.Context.Frame=function()return {time=1.2,taxi=true}end
        check("detached travel observes boarding without restoring selection",not p.JourneyLive.Tick(state,replacement,false)
            and not replacement.selected and state.view.phase=="riding")
        fresh={selected=p.Schema.Clone(state.base)}
        assert(p.JourneyLive.Attach(fresh,result,data,{},nil,state)==state)
        check("rebound ride suppresses stale walking immediately",p.JourneyLive.Tick(state,fresh,false)
            and fresh.selected.suppressSteering and not fresh.selected.destination)
        p.JourneyLive.Detach(state)
        p.Context.Frame=function()return {time=2,taxi=false}end
        p.Terrain.Arrival=function(node,_,seq)if node.id=="b" then return anchor("b",seq)end end
        check("paused travel observes completion without actionable row",not p.JourneyLive.Tick(state,replacement,true)
            and state.view.complete and not replacement.selected)
        fresh={selected=p.Schema.Clone(state.base)}
        assert(p.JourneyLive.Attach(fresh,result,data,{},nil,state)==state)
        check("resume restores final action without completing quest",p.JourneyLive.Tick(state,fresh,false)
            and fresh.selected.kind=="turnin" and fresh.selected.targetHint.id=="barrel")
        result.actions[1].node="c"
        check("partial travel cannot masquerade as action arrival",not p.JourneyLive.Attach(fresh,result,data,{},nil)
            and fresh.selected.suppressSteering and not fresh.selected.destination)
    end)
    RikUI=previous
    check("journey evidence suite",ok,problem)
end
