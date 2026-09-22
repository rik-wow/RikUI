-- Live travel capability and useful exploration, with unavailable API fallbacks.
return function(check)
    local names={"RikUI","C_Container","GetItemCooldown","GetBindLocation","C_TaxiMap","TaxiNodeCost"}
    local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
    local ok,err=pcall(function()
        RikUI={}
        RikUI["Secret"]={IsSecret=function(v) return v=="secret" end,Read=function(fn,...) return pcall(fn,...) end}
        for _,name in ipairs({"schema","preferences","plan-state","plan-graph","plan-transitions","plan-costs","plan-search","plan-context","plan-travel"}) do
            dofile("src/modules/questplanner/quest-"..name..".lua")
        end
        local p=RikUI.QuestPlanner
        p.Context={Call=function(fn,...)
            if type(fn)~="function" then return false end
            return pcall(fn,...)
        end}
        local ctx={origin="live",observedAt=100,inventory={[55]=1,[6948]=1},
            attributes={class=1,race=3,faction="Alliance",level=10,xpMax=1000,logCapacity=20},
            position={mapID=1426,x=.5,y=.5},bagFree=10,history={}}
        local records={[1]={providedItemID=55}}
        local enabled=1
        C_Container={GetItemCooldown=function(id) return id==55 and 90 or 0,id==55 and 30 or 0,enabled end}
        GetBindLocation=function() return "Home" end
        local function node(id,unknown,faction,x)
            return {nodeID=id,name="Flight "..id,isUndiscovered=unknown,faction=faction,
                position={GetXY=function() return x or .51,.5 end}}
        end
        local rows={node(1,true,2),node(2,false,2),node(3,true,1),node(4,nil,2),node(5,true,0)}
        C_TaxiMap={GetTaxiNodesForMap=function() return rows end}
        ctx.cooldowns,ctx.travel=p.PlanTravel.Read(ctx,records)
        check("carried item cooldown is relative to observed time",ctx.cooldowns["item:55"]==20 and ctx.cooldowns["item:6948"]==0)
        check("binding label never invents a destination",ctx.travel.bindLabel=="Home" and ctx.travel.bindDestinationStatus=="unknown" and not ctx.travel.bindDestination)
        local before=p.PlanContext.Signature(ctx)
        ctx.observedAt=101;ctx.cooldowns,ctx.travel=p.PlanTravel.Read(ctx,records)
        check("countdown does not continuously invalidate planning",p.PlanContext.Signature(ctx)==before)
        ctx.observedAt=121;ctx.cooldowns,ctx.travel=p.PlanTravel.Read(ctx,records)
        check("cooldown readiness changes planning signature",ctx.cooldowns["item:55"]==0 and p.PlanContext.Signature(ctx)~=before)
        p.PlanTravel.OnEvent("HEARTHSTONE_BOUND")
        local _,rebound=p.PlanTravel.Read(ctx,records)
        check("same-name rebinding invalidates prior binding evidence",rebound.bindingRevision==1 and rebound.bindLabel=="Home")
        enabled=0;ctx.cooldowns,ctx.travel=p.PlanTravel.Read(ctx,records)
        check("disabled cooldown is not ready",ctx.cooldowns["item:55"]==nil and ctx.travel.items[55].enabled==false)
        enabled=1;ctx.inventory[55]=nil
        ctx.cooldowns,ctx.travel=p.PlanTravel.Read(ctx,records)
        check("bank-only or absent item cannot supply usable cooldown",ctx.cooldowns["item:55"]==nil)
        ctx.inventory[55]=1
        GetItemCooldown=nil;C_Container={}
        ctx.cooldowns,ctx.travel=p.PlanTravel.Read(ctx,records)
        check("missing cooldown API remains unknown",ctx.cooldowns["item:55"]==nil)
        ctx.explorationOffers=p.PlanTravel.Exploration(ctx)
        check("exploration requires explicitly unknown friendly or neutral flight point",#ctx.explorationOffers==2
            and ctx.explorationOffers[1].discoveryNode==1 and ctx.explorationOffers[2].discoveryNode==5)
        check("known or unknown-status flight points are not exploration offers",ctx.travel.flightNodes[2]
            and not ctx.travel.flightNodes[3] and not ctx.travel.flightNodes[4])
        local snapshot={identity={product="forever",build="test",locale="enUS"},generation=1,order={},quests={},reportedCount=0,coverage="log-complete"}
        local policy=assert(p.Preferences.Normalize({flavor="Explorer",strictSession=true,explorationMinutes=5}))
        local state=assert(p.PlanState.Build(snapshot,{state="current"},ctx,{},policy))
        local graph=p.PlanGraph.Begin(state,{}, {},policy):Step(1)
        local action=graph.actions[1]
        check("live useful exploration enters ordinary action graph",#graph.actions==2 and action.title=="Discover flight point: Flight 1"
            and action.completionEvidence:find("taxi API",1,true)~=nil)
        local cost=p.PlanCosts.Estimate(action,state,policy,{mapSizes={[1426]={1000,1000}}})
        check("optional flight visit budgets outbound and return travel",cost.components.returnTravel and cost.upper>=240)
        local simulated=p.PlanTransitions.Apply(action,state,policy,cost)
        check("simulated exploration never unlocks flight or claims XP",simulated.travel.flightNodes[1].undiscovered
            and simulated.xpGained==0 and simulated.position.x==state.position.x and simulated.optionalVisits[action.visitKey])
        policy.explorationMinutes=0
        check("declining exploration excludes real flight offers too",p.PlanTransitions.Check(action,state,policy)==false)
        policy.explorationMinutes=5;state.travel.flightNodes[1].undiscovered=false
        check("freshly unlocked flight invalidates current exploration",p.PlanTransitions.Check(action,state,policy)==false)
        state.travel.flightNodes[1].undiscovered=true
        policy.explorationMinutes=1
        local job=assert(p.PlanSearch.Begin(graph,state,policy,{mapSizes={[1426]={1000,1000}}}))
        local result
        for _=1,100 do result=job:Step(64);if result then break end end
        check("out-and-back upper cost enforces exploration budget",result and #result.actions==0)
        rows={node(1,true,2),node(1,false,2)}
        local _,duplicate=p.PlanTravel.Read(ctx,records)
        check("conflicting duplicate node observations are rejected",duplicate.flightNodes[1]==nil)
        rows={node(1,"secret",2),node(2,true,"secret"),node(3,true,2,2)}
        local _,invalid=p.PlanTravel.Read(ctx,records)
        check("secret fields and out-of-range positions are rejected",next(invalid.flightNodes)==nil)
        C_TaxiMap.GetAllTaxiNodes=function() return {{nodeID=1,state=1,slotIndex=2},{nodeID=2,state=2,slotIndex=3}} end
        TaxiNodeCost=function(slot) return slot==2 and 50 or error("unreachable node queried") end
        p.PlanTravel.OnEvent("TAXIMAP_OPENED")
        local _,flights=p.PlanTravel.Read(ctx,records)
        check("only current-master reachable fares are observed",#flights.offeredFlights==1 and flights.offeredFlights[1].moneyCost==50
            and flights.offeredFlights[1].durationStatus=="unknown")
        p.PlanTravel.OnEvent("TAXIMAP_CLOSED")
        local _,closed=p.PlanTravel.Read(ctx,records)
        check("closed flight map invalidates temporary access",#closed.offeredFlights==0)
        C_TaxiMap=nil
        local _,absent=p.PlanTravel.Read(ctx,records)
        check("missing taxi API produces no invented attractions",next(absent.flightNodes)==nil)
    end)
    for _,name in ipairs(names) do _G[name]=saved[name] end
    check("guarded travel fixture completes",ok,err)
end
