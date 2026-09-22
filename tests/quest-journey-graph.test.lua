return function(check)
    local previous=RikUI;RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
    local ok,reason=pcall(function()
        for _,name in ipairs({"schema","elevators","travel","journey-graph"}) do dofile("src/modules/questplanner/quest-"..name..".lua") end
        local p=RikUI.QuestPlanner
        local identity={product="forever",build="1.60.1.69913",locale="enUS"}
        local source=p.Schema.Clone(identity);source.id="fixture";source.authority="verified"
        local base=assert(p.Travel.New(identity,"v1",{{id="pier",zoneID=1426},{id="end",zoneID=1426}},{
            {id="boat",from="pier",to="end",mode="transport",seconds=10,period=30,offset=0,transport="boat",
                risk=0,uncertainty=0,zones={1426},source=source}}))
        local valid,calls=true,0
        local origin={id="player-origin",revision="r1",identity=identity,valid=function() return valid end}
        local anchor={node="pier",mapID=1426,source=source,terrain={revision="mesh"}}
        local function bridge()
            calls=calls+1
            return {Step=function() return {status="modeled",revision="mesh",seconds=5,meters=35,uncertainty=.1} end}
        end
        local graph=p.JourneyGraph.New(base,origin,{anchor},bridge)
        local state={identity=identity,departure=10,transport={boat=true},flights={}}
        local policy={maxSeconds=40,maxRisk=1,maxUncertainty=1}
        local route=graph:Estimate(origin.id,"end",state,policy)
        check("normal movement adds an explicit walking leg",route.status=="known" and route.path[1].mode=="walk" and #route.path==2)
        check("downstream transport wait uses actual walking arrival",route.path[2].wait==15 and route.seconds==30)
        check("prefix does not mutate character departure",state.departure==10)
        graph:Estimate(origin.id,"end",state,policy)
        check("same origin reuses computed walking prefix",calls==1)
        local denied=p.Schema.Clone(state);denied.transport.boat=false
        check("walking to transport never grants character access",graph:Estimate(origin.id,"end",denied,policy).seconds==nil)
        local short=p.Schema.Clone(policy);short.maxSeconds=29
        check("whole journey obeys remaining time budget",graph:Estimate(origin.id,"end",state,short).seconds==nil)
        valid=false
        check("stale origin rejects cached connection",graph:Estimate(origin.id,"end",state,policy).seconds==nil)
        valid=true
        local direct=graph:Estimate("pier","end",state,policy)
        check("existing graph queries retain their original behavior",direct.seconds==30 and #direct.path==1)
        local partial=p.JourneyGraph.New(base,origin,{anchor},function()
            return {Step=function() return {status="partial",seconds=1,revision="mesh"} end}
        end):Estimate(origin.id,"end",state,policy)
        check("partial walking path never becomes a complete graph connection",partial.seconds==nil and partial.status=="budget-exhausted")
        local tiny=p.Schema.Clone(policy);tiny.maxWork=1
        local limited=graph:Estimate(origin.id,"end",state,tiny)
        check("bounded attachment reports exhaustion without invented cost",limited.status=="budget-exhausted" and limited.seconds==nil and limited.metrics.work<=1)
        local changed=p.Schema.Clone(state);changed.identity.build="different"
        check("attachment rejects incompatible character identity",graph:Estimate(origin.id,"end",changed,policy).seconds==nil)
    end)
    RikUI=previous
    check("walking attachment scenarios complete",ok,reason)
end
