-- Original scenario and baselines; no authored guide data.
return function(check)
    local previous = RikUI
    RikUI = { Secret = { IsSecret = function() return false end } }
    local ok, reason = pcall(function()
        for _, name in ipairs({"quest-schema","quest-evidence","quest-eligibility","quest-travel","quest-actions","quest-simulation","quest-optimizer"}) do
            dofile("src/modules/questplanner/" .. name .. ".lua")
        end
        local p = RikUI.QuestPlanner
        local identity = {product="forever",build="1.60.1.69913",locale="enUS"}
        local source = {id="original-fixture",product=identity.product,build=identity.build,locale=identity.locale,authority="verified"}
        local book = assert(p.Evidence.New(identity))
        local nodes = {{id="start",zoneID=1},{id="near",zoneID=1},{id="hub",zoneID=1},{id="far",zoneID=2}}
        local edges = {}
        local costs = { start={near=1,hub=8,far=20},near={start=1,hub=15,far=25},
            hub={start=8,near=15,far=1},far={start=20,near=25,hub=1} }
        for from, destinations in pairs(costs) do for to, seconds in pairs(destinations) do
            edges[#edges+1]={id=from.."-"..to,from=from,to=to,mode="walk",seconds=seconds,risk=0,uncertainty=0,zones={1,2},source=source}
        end end
        local graph = assert(p.Travel.New(identity,"scenario-1",nodes,edges))
        local function action(id, quest, kind, node, xp)
            return {id=id,questID=quest,kind=kind,node=node,zoneID=node=="far" and 2 or 1,
                duration={combat=0,looting=0,interaction=1,downtime=0},risk=0,uncertainty=0,source=source,xp=xp}
        end
        local rows = {action("near",1,"turnin","near",10),action("hub",2,"turnin","hub",90),action("far",3,"turnin","far",110)}
        local actions = assert(p.Actions.New(identity,rows))
        local function state()
            return {identity=identity,fresh=true,active={[1]=true,[2]=true,[3]=true},failed={[1]=false,[2]=false,[3]=false},
                objectivesComplete={[1]=true,[2]=true,[3]=true},turnedIn={},logComplete=true,logCount=3,logCapacity=25,
                class=1,race=3,faction="Alliance",level=7,xp=0,xpMax=1000,xpThresholds={[8]=1500},
                node="start",travel={identity=identity,departure=0,flights={},transport={}},
                objectives={},inventory={}}
        end
        local policy={depth=3,width=24,maxSeconds=100,maxRisk=.5,maxUncertainty=.5}
        local result = p.Optimizer.Plan(actions, state(), book, graph, policy)
        check("calculated route reaches downstream efficient cluster", result.status=="ready" and result.actions[1].id=="hub")
        check("route reward and elapsed are calculated", result.gainedXP==200 and result.seconds==11)
        check("result does not claim global optimality", result.globalOptimal==false)
        local sliced = assert(p.Optimizer.Begin(actions,state(),book,graph,policy))
        local sliceResult
        repeat sliceResult = sliced:Step(8) until sliceResult
        check("slice size preserves selected route", sliceResult.actions[1].id==result.actions[1].id and sliceResult.seconds==result.seconds)
        local cancelled=assert(p.Optimizer.Begin(actions,state(),book,graph,policy)); cancelled:Cancel()
        check("stale search can be cancelled", cancelled:Step(8).status=="cancelled")
        local limited=p.Optimizer.Plan(actions,state(),book,graph,{depth=3,width=24,maxTransitions=1,maxSeconds=100})
        check("transition cap is visible", limited.limited and limited.metrics.transitions<=1)
        local pinned=p.Optimizer.Plan(actions,state(),book,graph,{depth=3,width=24,pins={[1]=true},maxSeconds=100})
        check("pin is honored within horizon", #pinned.deferredPins==0 and pinned.state.turnedIn[1]==true)
        local conflict=p.Optimizer.Plan(actions,state(),book,graph,{pins={[3]=true},avoids={[2]=true}})
        check("pin and avoid conflict is explicit", conflict.status=="constraint-conflict")
        local skip=p.Optimizer.Plan(actions,state(),book,graph,{skips={[2]=true},depth=3,maxSeconds=100})
        for _, row in ipairs(skip.actions) do check("skip never abandons or executes skipped quest",row.questID~=2) end
        local retained=p.Optimizer.Plan(actions,state(),book,graph,{depth=3,width=24,maxSeconds=100,previousID="far",switchThreshold=1})
        check("valid current action retained inside material-change threshold",retained.actions[1].id=="far" and retained.retained)
        local noTransport=assert(p.Travel.New(identity,"disconnected",nodes,{}))
        check("missing travel never becomes a straight line",p.Optimizer.Plan(actions,state(),book,noTransport,policy).status=="insufficient-data")
        local repeatAction=actions:Get("near")
        local initial=state()
        local leg={status="known",seconds=1,risk=0,uncertainty=0,path={}}
        local nextState=assert(p.Actions.Apply(repeatAction,initial,leg,book,{maxSeconds=100,maxRisk=1,maxUncertainty=1}))
        check("simulation does not mutate observations",initial.active[1]==true and nextState.turnedIn[1]==true)
        check("same action cannot reward twice",not p.Actions.Apply(repeatAction,nextState,leg,book,{maxSeconds=100,maxRisk=1,maxUncertainty=1}))
        local shared=action("wolves",11,"objective","start")
        shared.sharedKey,shared.progress="wolf",2
        local sharedActions=assert(p.Actions.New(identity,{shared}))
        local sharedState=state()
        sharedState.active[11],sharedState.active[12],sharedState.failed[11]=true,true,false
        sharedState.objectivesComplete[11]=false; sharedState.failed[12]=false
        sharedState.objectives={[11]={wolf=2},[12]={wolf=1}}
        local progressed=assert(p.Actions.Apply(sharedActions:Get("wolves"),sharedState,{status="known",seconds=0,risk=0,uncertainty=0},book,{maxSeconds=100,maxRisk=1,maxUncertainty=1}))
        check("shared objective advances only matching active requirements",progressed.objectivesComplete[11] and progressed.objectivesComplete[12])
        local sharedPin=p.Optimizer.Plan(sharedActions,sharedState,book,nil,{depth=1,pins={[12]=true}})
        check("shared bundle advances indirectly pinned quest",sharedPin.state.objectivesComplete[12]==true)
        local trivial=action("trivial",12,"objective","start"); trivial.sharedKey,trivial.progress="other",1
        local choices=assert(p.Actions.New(identity,{shared,trivial}))
        sharedState.objectives[12]={wolf=2,other=1}
        local logicalPin=p.Optimizer.Plan(choices,sharedState,book,nil,{depth=1,pins={[12]=true}})
        check("pin progress counts work on quest instead of action ownership",logicalPin.actions[1].id=="wolves")
        initial=state(); initial.xp=950
        local leveled=assert(p.Actions.Apply(actions:Get("hub"),initial,leg,book,{maxSeconds=100,maxRisk=1,maxUncertainty=1}))
        check("known XP advances modeled level",leveled.level==8 and leveled.xp==40)
        local unknown=action("unknown",1,"turnin","near")
        local unknownActions=assert(p.Actions.New(identity,{unknown}))
        local unknownResult=p.Optimizer.Plan(unknownActions,state(),book,graph,policy)
        check("missing XP remains explicit",unknownResult.unknownXP>0 and unknownResult.status=="uncertain")
        local function advance(current,row,routeGraph)
            local route=routeGraph:Estimate(current.node,row.node,current.travel,{maxSeconds=100,maxRisk=1,maxUncertainty=1})
            return p.Actions.Apply(row,current,route,book,{maxSeconds=100,maxRisk=1,maxUncertainty=1})
        end
        local oracle,visited=0,0
        local function enumerate(current,depth)
            oracle=math.max(oracle,p.Optimizer.Score(current))
            if depth==0 then return end
            for _,row in ipairs(actions:List()) do
                local nextState=advance(current,row,graph)
                if nextState then visited=visited+1; enumerate(nextState,depth-1) end
            end
        end
        enumerate(state(),3)
        check("beam reaches exact optimum on small exhaustive fixture",math.abs(result.score-oracle)<.000000001 and visited==15)
        local nearest,nearBest=state(),0
        for _=1,3 do
            local choice,choiceState
            for _,row in ipairs(actions:List()) do
                local candidate=advance(nearest,row,graph)
                if candidate and (not choiceState or candidate.elapsed<choiceState.elapsed
                    or (candidate.elapsed==choiceState.elapsed and row.id<choice.id)) then choice,choiceState=row,candidate end
            end
            if not choiceState then break end
            nearest=choiceState; nearBest=math.max(nearBest,p.Optimizer.Score(nearest))
        end
        local authored,authoredBest=state(),0
        for _,id in ipairs({"near","far","hub"}) do
            authored=assert(advance(authored,actions:Get(id),graph))
            authoredBest=math.max(authoredBest,p.Optimizer.Score(authored))
        end
        check("lookahead outperforms nearest and original fixed-order baselines",result.score>nearBest and result.score>authoredBest)
        io.write(string.format("Quest fixture XP/s: lookahead %.3f exact %.3f nearest %.3f fixed %.3f; %d oracle states\n",
            result.score,oracle,nearBest,authoredBest,visited))
        local pickup=action("accept",20,"pickup","near")
        local objective=action("complete",20,"objective","near"); objective.completeQuest=true; objective.duration.combat=5
        local delivery=action("deliver",20,"turnin","near",500)
        assert(book:Add(20,"prerequisites",{op="completed",questID=1},source))
        assert(book:Add(20,"requirements",{op="always"},source))
        local chain=assert(p.Actions.New(identity,{rows[1],pickup,objective,delivery}))
        local full=state(); full.logCapacity=3; full.turnedIn[20]=false
        local chainPlan=p.Optimizer.Plan(chain,full,book,graph,{depth=4,width=24,maxSeconds=100})
        check("turn-in releases capacity before pickup and objective bundle",#chainPlan.actions==4 and chainPlan.actions[1].id=="near"
            and chainPlan.state.turnedIn[20] and chainPlan.state.logCount==2)
        local unknownChain=assert(p.Actions.New(identity,{pickup,objective,action("deliver",20,"turnin","near")}))
        local unknownStart=state(); unknownStart.turnedIn[1]=true; unknownStart.turnedIn[20]=false
        local unknownSequence=p.Optimizer.Plan(unknownChain,unknownStart,book,graph,{depth=3,maxSeconds=100})
        check("unknown reward does not strand a zero-value partial sequence",#unknownSequence.actions==3
            and unknownSequence.state.turnedIn[20] and unknownSequence.status=="uncertain")
        local skipped=p.Optimizer.Plan(chain,full,book,graph,{depth=4,skips={[1]=true},maxSeconds=100})
        check("skipped predecessor never fabricated complete",#skipped.actions==0)
        local unlock=action("learn",99,"unlock","near")
        unlock.unlock,unlock.requirement={kind="flight",key="far"},{op="always"}
        local unlockActions=assert(p.Actions.New(identity,{unlock,rows[3]}))
        local flight={id="flight",from="near",to="far",mode="flight",seconds=1,risk=0,uncertainty=0,zones={1,2},
            flightFrom="near",flightTo="far",source=source}
        local flyingEdges=p.Schema.Clone(edges); flyingEdges[#flyingEdges+1]=flight
        local flying=assert(p.Travel.New(identity,"unlock-scenario",nodes,flyingEdges))
        local flyer=state(); flyer.travel.flights.near=true
        local unlockPlan=p.Optimizer.Plan(unlockActions,flyer,book,flying,{depth=3,maxSeconds=100,unlockValue=0})
        check("downstream travel unlock beats walking without a policy bonus",unlockPlan.actions[1].id=="learn"
            and unlockPlan.gainedXP==110 and unlockPlan.seconds==4)
        local consumeA,consumeB=action("itemA",1,"turnin","near",10),action("itemB",2,"turnin","near",10)
        consumeA.consumes,consumeB.consumes={{itemID=5,count=2}},{{itemID=5,count=2}}
        local inventory=state(); inventory.inventory[5]=2
        local consumed=assert(p.Actions.Apply(consumeA,inventory,leg,book,{maxSeconds=100,maxRisk=1,maxUncertainty=1}))
        check("shared consumable cannot be spent for two turn-ins",not p.Actions.Apply(consumeB,consumed,leg,book,{maxSeconds=100,maxRisk=1,maxUncertainty=1}))
        local dungeon=action("dungeon",1,"turnin","near",1000); dungeon.category="dungeon"
        local dungeonActions=assert(p.Actions.New(identity,{dungeon}))
        check("dungeons are optional by default",#p.Optimizer.Plan(dungeonActions,state(),book,graph,policy).actions==0)
        check("dungeons can be included explicitly",#p.Optimizer.Plan(dungeonActions,state(),book,graph,{dungeons=true}).actions==1)
        local unknownLevel=state(); unknownLevel.levelProgressUnknown=true
        check("unknown XP cannot unlock a level condition",p.Eligibility.Condition({op="levelAtLeast",value=7},unknownLevel)=="unknown")
    end)
    RikUI=previous
    check("optimizer fixture completes",ok,reason)
end
