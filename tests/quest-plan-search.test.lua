-- Independent finite mechanics and oracle; fixtures are synthetic, not world evidence.
return function(check)
    local saved=RikUI
    RikUI={}
    RikUI["Secret"]={IsSecret=function() return false end}
    local ok,err=pcall(function()
        for _,name in ipairs({"schema","preferences","plan-transitions","plan-learning","plan-costs","plan-search"}) do
            dofile("src/modules/questplanner/quest-"..name..".lua")
        end
        local p=RikUI.QuestPlanner
        local function state()
            return {fresh=true,identity={product="fixture",build="1",locale="enUS"},generation=1,level=10,xp=0,xpMax=1000,
                xpThresholds={},active={},completed={},failed={},objectivesComplete={},progress={},conditionalObjectives={},
                conditionalCompleted={},applied={},branchLocks={},inventory={},bank={},equipped={},logComplete=true,
                logCount=0,logCapacity=1,partySize=1,bagFree=4,money=0,elapsed=0,upperElapsed=0,xpGained=0,unknownXP=0,
                skills={},spells={},reputation={},capabilities={},assumptions={},live={},visited={},recent={}}
        end
        local policy=assert(p.Preferences.Normalize({flavor="Efficient",readingSeconds=0,strictSession=true}))
        local s=state()
        check("unknown completion remains unknown",p.PlanTransitions.Condition({op="completed",questID=9},s)==nil)
        check("not unknown stays unknown",p.PlanTransitions.Condition({op="not",arg={op="completed",questID=9}},s)==nil)
        s.completed[8]=true
        check("OR true dominates unknown",p.PlanTransitions.Condition({op="any",args={{op="completed",questID=9},{op="completed",questID=8}}},s)==true)
        check("AND unknown stays unknown",p.PlanTransitions.Condition({op="all",args={{op="completed",questID=9},{op="completed",questID=8}}},s)==nil)
        s.inventory[7]=1;s.bank[7]=99;s.equipped[7]=99;s.active[1]=true;s.objectivesComplete[1]=true;s.logCount=1
        local turn={id="turn1",kind="turnin",questID=1,consumes={{itemID=7,count=1},{itemID=7,count=1}}}
        check("duplicate consumption cannot overspend",p.PlanTransitions.Check(turn,s,policy)==false)
        turn.consumes={{itemID=7,count=1}}
        local after=assert(p.PlanTransitions.Apply(turn,s,policy,{seconds=1,upper=1,xp=10,xpAuthority="observed"}))
        check("resource consumption detached",after.inventory[7]==0 and s.inventory[7]==1)
        after.active[2]=true;after.objectivesComplete[2]=true;turn.id="turn2";turn.questID=2
        check("bank and equipment cannot pay second turnin",p.PlanTransitions.Check(turn,after,policy)==false)
        after.inventory[7]=nil
        check("unknown carried items not banked items",p.PlanTransitions.Check(turn,after,policy)==nil)
        local pickup={id="pick",kind="pickup",questID=2,initialProgress={a=-1},gains={{itemID=7,count=1,source=true}}}
        s=state();s.inventory[7]=1;s.completed[2]=false
        after=assert(p.PlanTransitions.Apply(pickup,s,policy,{seconds=1,upper=1,xp=0,xpAuthority="observed"}))
        check("source item not duplicated",after.inventory[7]==1)
        local objective={id="obj",kind="objective",questID=2,objectiveKey="a",countUnknown=true}
        local conditional=assert(p.PlanTransitions.Apply(objective,after,policy,{seconds=10,upper=100,xp=0,xpAuthority="observed"}))
        check("unknown quantity preserved and conditional",conditional.progress[2].a==-1 and conditional.conditionalObjectives[2].a and conditional.conditional)
        s=state();s.completed[2]=false;s.completed[3]=true;pickup.excludes={3}
        check("pickup exclusion enforced",p.PlanTransitions.Check(pickup,s,policy)==false)
        s.active[2]=true;s.objectivesComplete[2]=true;s.logCount=1
        check("pickup-only exclusion does not block active turnin",p.PlanTransitions.Check({id="t",kind="turnin",questID=2,excludes={3}},s,policy)==true)
        s=state();s.active[1]=true;s.active[2]=true;s.progress={[1]={kill=3},[2]={kill=5}}
        objective={id="wolf",kind="objective",questID=1,objectiveKey="kill",sharedCredit="wolf",
            credits={{questID=2,key="kill"},{questID=2,key="kill"}}}
        after=assert(p.PlanTransitions.Apply(objective,s,policy,{seconds=3,upper=3,xp=0,xpAuthority="observed"}))
        check("shared kills credited exactly once",after.progress[1].kill==0 and after.progress[2].kill==2)
        objective.sharedCredit=nil
        after=assert(p.PlanTransitions.Apply(objective,s,policy,{seconds=3,upper=3,xp=0,xpAuthority="observed"}))
        check("co-located drops never share credit",after.progress[2].kill==5)
        local reward={kind="turnin",questID=1,reward={level=9,baseXP=780}}
        s.level=15;check("pinned XP adjustment and rounding",p.PlanCosts.Reward(reward,s)==625)
        reward.reward=nil;check("unknown reward not known zero",p.PlanCosts.Reward(reward,s)==nil)
        local learning=p.PlanLearning
        learning.Bind(s.identity,"one")
        check("AFK excluded from learning",not learning.Observe("combat","wolf",600,1,{afk=true}))
        for n=1,50 do learning.Observe("combat","wolf",20+n,1) end
        local estimate=learning.Estimate("combat","wolf")
        check("learning bounded with sample evidence",estimate.samples==32 and estimate.totalSamples==50 and estimate.minimum==39)
        local exported=learning.Export();learning.Reset()
        check("learning restore roundtrip",learning.Restore(exported) and learning.Estimate("combat","wolf").samples==32)
        learning.Bind(s.identity,"two");check("different character cannot inherit calibration",not learning.Restore(exported))
        local function graph(quests)
            local g={status="ready",revision=1,actions={},byQuest={},coverage={}}
            for _,q in ipairs(quests) do
                local rows={
                    {id=q.id..":pickup",kind="pickup",questID=q.id,initialProgress={work=1},
                        prerequisite=q.pre and {op="completed",questID=q.pre},excludes=q.excludes,cost={seconds=0,authority="authored"}},
                    {id=q.id..":objective",kind="objective",questID=q.id,objectiveKey="work",cost={seconds=q.work,authority="authored"}},
                    {id=q.id..":complete",kind="complete",questID=q.id,cost={seconds=0,authority="authored"}},
                    {id=q.id..":turnin",kind="turnin",questID=q.id,cost={seconds=q.turn,authority="authored"},reward={level=10,baseXP=q.xp}},
                }
                g.byQuest[q.id]=rows
                for _,row in ipairs(rows) do g.actions[#g.actions+1]=row end
            end
            return g
        end
        -- Independent oracle operates on whole finite quest jobs, not production transition/scoring code.
        local function exact(quests,horizon)
            local best,states=0,0
            local function visit(done,time,xp)
                states=states+1;best=math.max(best,xp)
                for _,q in ipairs(quests) do
                    if not done[q.id] and (not q.pre or done[q.pre]) and time+q.work+q.turn<=horizon then
                        local allowed=true
                        for _,id in ipairs(q.excludes or {}) do if done[id] then allowed=false end end
                        if allowed then
                            local nextDone={};for id,v in pairs(done) do nextDone[id]=v end;nextDone[q.id]=true
                            visit(nextDone,time+q.work+q.turn,xp+q.xp)
                        end
                    end
                end
            end
            visit({},0,0);return best,states
        end
        local function run(g,initial,preferences,environment)
            local job=assert(p.PlanSearch.Begin(g,initial,preferences,environment))
            local result
            for _=1,1000 do result=job:Step(64);if result then break end end
            check("search terminates within budget",result and result.status=="ready" and result.metrics.work<=48000,result and result.reason)
            return result,job
        end
        local quests={{id=1,work=4,turn=1,xp=50},{id=2,work=3,turn=1,xp=5},{id=3,pre=2,work=4,turn=1,xp=150}}
        local oracle,states=exact(quests,10)
        check("independent delayed chain oracle",oracle==155 and states>1)
        for _,flavor in ipairs(p.Preferences.Flavors()) do
            policy=assert(p.Preferences.Normalize({flavor=flavor,readingSeconds=0,strictSession=true}));policy.maxSeconds=10
            s=state();for _,q in ipairs(quests) do s.completed[q.id]=false end
            local result=run(graph(quests),s,policy)
            check("delayed chain oracle agreement "..flavor,result.xp==oracle and result.actions[1].questID==2,result.xp)
            check("search leaves observed state unchanged "..flavor,s.xpGained==0 and not s.active[2])
        end
        local branches={{id=1,work=2,turn=1,xp=10,excludes={3}},{id=2,pre=1,work=2,turn=1,xp=100,excludes={3}},
            {id=3,work=2,turn=1,xp=60,excludes={1,2}}}
        policy.maxSeconds=6;s=state();for _,q in ipairs(branches) do s.completed[q.id]=false end
        local result=run(graph(branches),s,policy)
        check("exclusive chain oracle agreement",result.xp==exact(branches,6) and result.xp==110,result.xp)
        local long={}
        for n=1,18 do long[n]={id=n,pre=n>1 and n-1 or nil,work=1,turn=1,xp=n==18 and 1000 or 0} end
        policy.maxSeconds=40;s=state();for _,q in ipairs(long) do s.completed[q.id]=false end
        result=run(graph(long),s,policy)
        check("long supported chain beyond shallow horizon",result.xp==1000 and #result.actions==72,result.xp)
        local job=p.PlanSearch.Begin(graph(quests),s,policy);job:Step(1);job:Cancel()
        check("pending search cancellation",job:Step(1).status=="cancelled")
        -- Full log: a legal turn-in must precede a future pickup.
        policy=assert(p.Preferences.Normalize({flavor="Efficient",readingSeconds=0,strictSession=true}));policy.maxSeconds=20
        s=state();s.active[9]=true;s.objectivesComplete[9]=true;s.logCount=1;s.completed[1]=false
        local g=graph({{id=1,work=2,turn=1,xp=100}})
        local free={id="9:turnin",kind="turnin",questID=9,cost={seconds=1,authority="authored"},reward={level=10,baseXP=5}}
        g.byQuest[9]={free};g.actions[#g.actions+1]=free
        result=run(g,s,policy)
        check("full log makes a capacity plan",result.xp==105 and result.actions[1].questID==9,result.xp)
        -- Greedy local method loses the key: primitives must preserve the alternative.
        g=graph({{id=1,work=2,turn=1,xp=10},{id=2,pre=1,work=2,turn=1,xp=100}})
        g.byQuest[1][2].consumes={{itemID=7,count=1}}
        local slow=p.Schema.Clone(g.byQuest[1][2]);slow.id="1:slower";slow.cost.seconds=3;slow.consumes=nil
        g.actions[#g.actions+1]=slow;g.byQuest[1][#g.byQuest[1]+1]=slow
        g.byQuest[2][2].preconditions={{op="item",itemID=7,count=1}}
        s=state();s.completed[1]=false;s.completed[2]=false;s.inventory[7]=1
        result=run(g,s,policy)
        check("search preserves resource-saving method",result.xp==110,result.xp)
        -- Service effects require observed support and bounded one-time use.
        s=state();s.bagFree=0;s.active[1]=true;s.progress[1]={work=1};s.inventory[7]=0
        local collect={id="collect",kind="objective",questID=1,objectiveKey="work",itemID=7,gains={{itemID=7,count=1}}}
        check("full bags block unsupported collection",p.PlanTransitions.Check(collect,s,policy)==false)
        local service={id="vendor",kind="service",questID=0,supported=true,freesSlots=2}
        after=assert(p.PlanTransitions.Apply(service,s,policy,{seconds=5,upper=5,xp=0,xpAuthority="observed"}))
        check("supported service frees capacity",after.bagFree==2 and p.PlanTransitions.Check(collect,after,policy)==true)
        check("service cannot generate unlimited capacity",p.PlanTransitions.Check(service,after,policy)==false)
        g=graph({{id=1,work=4,turn=2,xp=100},{id=2,work=4,turn=3,xp=150}})
        s=state();s.completed[1]=false;s.completed[2]=false;policy.maxSeconds=6
        result=run(g,s,policy)
        check("short session includes turnin stopping time",result.xp==100 and result.seconds==6,result.xp)
        policy.maxSeconds=7
        result=run(g,s,policy)
        check("longer session changes suitable milestone",result.xp==150 and result.seconds==7,result.xp)
        g=graph({{id=1,pre=2,work=1,turn=1,xp=100},{id=2,pre=1,work=1,turn=1,xp=100}})
        result=run(g,s,policy)
        check("dependency cycle never manufactures reward",#result.actions==0)
        -- Preferences trade small rate differences in the shared 2%-of-level currency.
        local rateNode={state=state(),actions={{kind="turnin",questID=1,breadcrumbFor=2}},costs={{pressure=0}}}
        rateNode.state.elapsed=600;rateNode.state.xpGained=100;rateNode.state.finished=1
        local ratePolicy=p.Preferences.Normalize({flavor="Story"})
        local fast=p.PlanSearch.Score(rateNode,state(),ratePolicy)
        rateNode.state.elapsed=1200
        local slow=p.PlanSearch.Score(rateNode,state(),ratePolicy)
        check("travel time dilutes XP and breadcrumb value equally",math.abs(fast-2*slow)<1e-9)
        check("score uses two-percent-level bonus currency",math.abs(fast-(100+(6+.5)*20)/1000*6)<1e-9)
        rateNode.costs[1].pressure=1
        check("pressure multiplicatively reduces a positive rate",p.PlanSearch.Score(rateNode,state(),ratePolicy)>0
            and p.PlanSearch.Score(rateNode,state(),ratePolicy)<slow)
        ratePolicy.pins[1]=true
        check("explicit pin remains dominant",p.PlanSearch.Score(rateNode,state(),ratePolicy)>1000000)
        local flavorPlans={
            Efficient={xp=1000,types={"kill"},pressure=.5},
            Balanced={xp=980,types={"kill","talk","explore"},pressure=.5},
            Story={xp=945,types={"kill"},pressure=.5,chain=true},
            Explorer={xp=960,types={"kill"},pressure=.5,discovery=1},
            Relaxed={xp=925,types={"kill"},pressure=0},
            Challenge={xp=960,types={"kill"},pressure=.5,difficulty=2},
        }
        for _,flavor in ipairs(p.Preferences.Flavors()) do
            local pref=p.Preferences.Normalize({flavor=flavor})
            local winner,score
            for name,case in pairs(flavorPlans) do
                local node={state=state(),actions={},costs={}}
                node.state.elapsed=600;node.state.xpGained=case.xp;node.state.finished=case.chain and 2 or 1
                node.state.discoveries=case.discovery
                for _,activity in ipairs(case.types) do
                    node.actions[#node.actions+1]={kind="objective",questID=1,activity=activity}
                    node.costs[#node.costs+1]={pressure=case.pressure,difficulty=case.difficulty,capabilityKnown=case.difficulty~=nil}
                end
                node.actions[#node.actions+1]={kind="turnin",questID=1};node.costs[#node.costs+1]={pressure=case.pressure}
                if case.chain then
                    node.actions[#node.actions+1]={kind="turnin",questID=2,chainPredecessors={[1]=true}}
                    node.costs[#node.costs+1]={pressure=case.pressure}
                end
                local utility=p.PlanSearch.Score(node,state(),pref)
                if not score or utility>score then score,winner=utility,name end
            end
            check("material fixed-scale preference "..flavor,winner==flavor,winner)
        end
        s=state();s.skills[164]=75;s.reputation[10]=3000;s.spells[9]=false
        check("compiled skill field is consumed",p.PlanTransitions.Condition({op="skill",id=164,value=75},s)==true)
        check("compiled reputation maximum is strict",p.PlanTransitions.Condition({op="reputationMax",id=10,value=3000},s)==false)
        check("negative required spell uses observed absence",p.PlanTransitions.Condition({op="spell",id=9,value=false},s)==true)
        s.completed[2]=false;pickup.excludes=nil;s.inventory[7]=nil
        after=assert(p.PlanTransitions.Apply(pickup,s,policy,{seconds=0,upper=0,xp=0,xpAuthority="observed"}))
        check("unknown total source item only creates lower bound",after.inventory[7]==nil and after.inventoryLower[7]==1)
        s=state();s.active[1]=true;s.progress[1]={work=7};s.conditionalObjectives[1]={work=true}
        check("stale conditional proof cannot complete live work",p.PlanTransitions.Check({id="c",kind="complete",questID=1},s,policy)==false)
        s.progress[1].work=0
        after=assert(p.PlanTransitions.Apply({id="c",kind="complete",questID=1,gains={{itemID=7,count=99}}},s,policy,
            {seconds=0,upper=0,xp=999,xpAuthority="observed"}))
        check("completion milestone cannot award XP or items",after.xpGained==0 and after.inventory[7]==nil)
        s=state();s.inventory[7]=1;s.stackSizes={[7]=20,[8]=20};s.stackRoom={[7]=19};s.genericStacks={[7]=1};s.bagFree=0
        local sell={id="sell",questID=0,kind="service",supported=true,freesSlots=1,consumes={{itemID=7,count=1}},
            discardStackRoom={{itemID=7}},saleSlots={"0:1"},saleInventory={[7]=1},conditionalService=true}
        after=assert(p.PlanTransitions.Apply(sell,s,policy,{seconds=1,upper=1,xp=0}))
        check("sale removes carried items and old headroom",after.inventory[7]==0 and after.stackRoom[7]==nil and after.bagFree==1 and after.conditional)
        local alias=p.Schema.Clone(sell);alias.id="sale-alias"
        check("same stack cannot be sold twice through aliases",p.PlanTransitions.Check(alias,after,policy)==false)
        s.inventory[7]=2
        check("changed inventory invalidates sale proof",p.PlanTransitions.Check(sell,s,policy)==nil)
        after.active[1]=true;after.active[2]=true;after.progress={[1]={a=19},[2]={b=1}}
        local gainA={id="a",questID=1,kind="objective",objectiveKey="a",itemID=7,gains={{itemID=7,count=19}}}
        check("repeated capacity checks do not mutate",p.PlanTransitions.Check(gainA,after,policy)==true
            and p.PlanTransitions.Check(gainA,after,policy)==true and after.bagFree==1 and after.stackRoom[7]==nil)
        local gained=assert(p.PlanTransitions.Apply(gainA,after,policy,{seconds=1,upper=1,xp=0}))
        check("new stack consumes freed generic slot",gained.bagFree==0 and gained.stackRoom[7]==1)
        check("second item cannot reuse sold stack capacity",p.PlanTransitions.Check({id="b",questID=2,kind="objective",
            objectiveKey="b",itemID=8,gains={{itemID=8,count=1}}},gained,policy)==false)
        s=state();s.bagFree=0;s.inventory[7]=5;s.genericStacks={[7]=1};s.stackRoom={[7]=15}
        s.active[1]=true;s.objectivesComplete[1]=true;s.logCount=1
        after=assert(p.PlanTransitions.Apply({id="full-stack-turnin",questID=1,kind="turnin",consumes={{itemID=7,count=5}}},s,policy,{seconds=1,upper=1,xp=0}))
        check("known whole-stack turnin releases actual slot",after.bagFree==1 and after.stackRoom[7]==nil)
        s=state();s.live[1]={};s.active[1]=true;s.progress[1]={a=0};s.objectivesComplete[1]=false
        check("zero counters cannot contradict live incomplete flag",p.PlanTransitions.Check({id="t",questID=1,kind="turnin"},s,policy)==false)
        -- More than 96 feasible first decisions cannot prune the committed one.
        local crowded={status="ready",actions={},byQuest={},coverage={}}
        s=state();s.logCapacity=128;s.logCount=110
        for id=1,110 do
            local a={id="crowd:"..id,kind="turnin",questID=id,cost={seconds=10,authority="authored"},
                reward={level=10,baseXP=id==1 and 1 or 100}}
            crowded.actions[#crowded.actions+1]=a;crowded.byQuest[id]={a}
            s.active[id]=true;s.objectivesComplete[id]=true
        end
        local committedPolicy=p.Preferences.Normalize({flavor="Efficient",readingSeconds=0,strictSession=true})
        committedPolicy.maxSeconds=20
        local env={previousID="crowd:1",incumbent={"missing","crowd:1","crowd:2"}}
        result=run(crowded,s,committedPolicy,env)
        check("prior sequence seeds before ordinary expansion",result.metrics.seeded==2)
        check("incumbent survives 96 first-step pruning",result.commitment and result.commitment.actions[1].id=="crowd:1"
            and #result.commitment.actions==2 and result.previousStatus=="feasible")
        s.active[1]=nil;s.completed[1]=true
        result=run(crowded,s,committedPolicy,env)
        check("completed incumbent steps are skipped and explained",result.previousStatus=="completed"
            and not result.commitment and result.metrics.seeded==1)
        dofile("src/modules/questplanner/quest-plan-runtime.lua")
        local prior={actionID="old",flavor="Efficient",selected={questID=1}}
        local proposed={actions={{id="new",questID=2}},score=1.249,previousStatus="feasible",
            commitment={actions={{id="old",questID=1}},score=1,features={efficiency=0}}}
        local picked,retained,reason=p.PlanRuntime.SelectResult(proposed,committedPolicy,prior)
        check("commitment retains below 25 percent despite baseline envelope",retained and picked.actions[1].id=="old")
        proposed.score=1.25
        picked,retained,reason=p.PlanRuntime.SelectResult(proposed,committedPolicy,prior)
        check("25 percent real rate gain permits switch",not retained and reason=="better" and picked.actions[1].id=="new")
        prior.nearDestination=true;proposed.score=1.499
        check("near destination requires 50 percent gain",select(2,p.PlanRuntime.SelectResult(proposed,committedPolicy,prior))==true)
        proposed.score=1.5
        check("50 percent gain permits near destination switch",select(3,p.PlanRuntime.SelectResult(proposed,committedPolicy,prior))=="better")
        prior.nearDestination=false;proposed.commitment.score=.01;proposed.score=.04
        check("tiny relative improvement also needs absolute margin",select(2,p.PlanRuntime.SelectResult(proposed,committedPolicy,prior))==true)
        proposed.score=.061
        check("absolute margin is measured in level fraction per hour",select(3,p.PlanRuntime.SelectResult(proposed,committedPolicy,prior))=="better")
        proposed.score=0;committedPolicy.pins[2]=true
        check("explicit new pin overrides commitment",select(3,p.PlanRuntime.SelectResult(proposed,committedPolicy,prior))=="pinned")
        committedPolicy.pins[2]=nil
        for _,status in ipairs({"invalid","completed"}) do
            proposed.previousStatus=status
            check(status.." prior releases commitment",select(3,p.PlanRuntime.SelectResult(proposed,committedPolicy,prior))==status)
        end
        print("Adaptive exact oracle: delayed "..oracle.." XP; branch110 XP; long18-quest continuation1000 XP")
    end)
    RikUI=saved
    check("adaptive search suite completes",ok,err)
end
