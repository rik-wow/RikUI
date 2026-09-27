-- End-to-end production search over adversarial source graphs; native play remains separate.
return function(check)
    local saved=RikUI
    RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
    local ok,err=pcall(function()
        for _,name in ipairs({"schema","preferences","recommendations","guidance","plan-state","waypoints","plan-graph","plan-transitions",
            "plan-learning","plan-rewards","plan-costs","plan-search","plan-runtime"}) do
            dofile("src/modules/questplanner/quest-"..name..".lua")
        end
        local p=RikUI.QuestPlanner
        local function initial(ids)
            local s={fresh=true,identity={product="fixture",build="1",locale="enUS"},generation=1,level=10,xp=0,xpMax=1000,
                class=1,race=3,faction="Alliance",xpThresholds={},active={},completed={},failed={},objectivesComplete={},progress={},
                objectiveInfo={},conditionalObjectives={},conditionalCompleted={},applied={},branchLocks={},inventory={},bank={},equipped={},
                logComplete=true,logCount=0,logCapacity=20,partySize=1,bagFree=10,money=0,elapsed=0,upperElapsed=0,
                xpGained=0,unknownXP=0,skills={},spells={},reputation={},capabilities={},assumptions={},live={},visited={},recent={},
                position={mapID=1,x=0,y=0}}
            for _,id in ipairs(ids) do s.completed[id]=false end
            return s
        end
        local function source(id,x,xp,pre)
            local function location(kind,target,where)
                return {kind=kind,targetKind="npc",targetID=target,name="Target "..target,
                    areas={{id="area:"..target,mapID=1,x=where,y=0,access=true}}}
            end
            return {id=id,title="Quest "..id,objectives={{id="work",type="monster",targetID=id+100,required=1,
                methods={location("kill",id+100,x)}}},starts={location("start",id+200,0)},ends={location("finish",id+200,0)},
                planning={version=1,requirements=pre and {op="completed",questID=pre} or {op="always"}},
                reward={level=10,baseXP=xp},eligibility={questLevel=10},provenance={revision="fixture"}}
        end
        local function graph(records,s,pref,durations)
            local job=assert(p.PlanGraph.Begin(s,records,{},pref));local g
            for _=1,100 do g=job:Step(4);if g then break end end
            assert(g)
            for _,a in ipairs(g.actions) do
                a.cost={seconds=a.kind=="objective" and durations[a.questID] or a.kind=="complete" and 0 or 1,authority="authored"}
            end
            return g
        end
        local environment={travel=function(from,to)
            local seconds=math.abs(from.x-to.x)*1000
            return {seconds=seconds,lower=seconds,upper=seconds,status="authored"}
        end}
        local function run(g,s,pref,env)
            local job=assert(p.PlanSearch.Begin(g,s,pref,env or environment));local result
            for _=1,1000 do result=job:Step(64);if result then break end end
            check("adversarial search bounded",result and result.status=="ready" and result.metrics.work<=48000)
            return result
        end
        local s=initial({1,2,3})
        local pref=p.Preferences.Normalize({flavor="Efficient",readingSeconds=0,strictSession=true});pref.maxSeconds=300
        local records={[1]=source(1,.1,100),[2]=source(2,.11,100),[3]=source(3,.12,100)}
        local g=graph(records,s,pref,{[1]=10,[2]=10,[3]=10})
        local result=run(g,s,pref)
        local pickups=0
        for _,a in ipairs(result.actions) do if a.kind=="objective" then break end;if a.kind=="pickup" then pickups=pickups+1 end end
        check("S01 batch three pickups before leaving hub",pickups==3,result.xp..":"..result.seconds..":"..pickups)
        check("S01 exact spatial optimum 300XP in276s",result.xp==300 and result.seconds==276,result.xp..":"..result.seconds)
        print("S01 production batch",result.xp,result.seconds,pickups)
        records={[11]=source(11,0,5),[12]=source(12,0,100)}
        records[11].planning.breadcrumbFor=12;records[11].planning.blockedBy={12}
        s=initial({11,12})
        local efficient=p.Preferences.Normalize({flavor="Efficient",readingSeconds=0,strictSession=true});efficient.maxSeconds=120
        local story=p.Preferences.Normalize({flavor="Story",readingSeconds=0,strictSession=true});story.maxSeconds=120
        g=graph(records,s,efficient,{[11]=18,[12]=78})
        local fast=run(g,s,efficient);local coherent=run(g,s,story)
        check("S03 efficient takes direct target",fast.actions[1].questID==12 and fast.xp==100,fast.xp)
        local completedBreadcrumb=false
        for _,a in ipairs(coherent.actions) do if a.questID==11 and a.kind=="turnin" then completedBreadcrumb=true end end
        check("S03 Story preserves optional missable step",coherent.actions[1].questID==11 and completedBreadcrumb and coherent.xp==105,
            coherent.actions[1].questID..":"..coherent.xp)
        check("S03 breadcrumb explanation and detour shown",coherent.reason:find("missable",1,true) and coherent.efficiencyCost>0)
        story.defers[11]=true
        local deferred=run(g,s,story)
        check("S03 manual defer overrides continuity",deferred.actions[1].questID==12 and deferred.xp==100)
        -- Three exclusive families: throughput, variety and linked continuity.
        local families={{base=100,work=28,pressure=.1},{base=200,work=34,pressure=.02},{base=300,work=37,pressure=.05}}
        local ids,durations={},{};records={}
        for _,family in ipairs(families) do
            for n=1,3 do
                local id=family.base+n;ids[#ids+1]=id;durations[id]=family.work
                local record=source(id,0,100,family.base==300 and n>1 and id-1 or nil)
                local conflicts={}
                for _,other in ipairs(families) do
                    if other~=family then for k=1,3 do conflicts[#conflicts+1]=other.base+k end end
                end
                record.planning.blockedBy=conflicts;record.planning.exclusiveWith=conflicts
                if family.base==200 then record.objectives[1].methods[1].kind=({"kill","talk","explore"})[n] end
                records[id]=record
            end
        end
        s=initial(ids);s.xpMax=6000
        local expected={Efficient=100,Balanced=200,Story=300}
        -- Rates favor a completed prefix once variety saturates; Story gains another chain link.
        local expectedXP={Efficient=200,Balanced=200,Story=300}
        for _,flavor in ipairs({"Efficient","Balanced","Story"}) do
            pref=p.Preferences.Normalize({flavor=flavor,readingSeconds=0});pref.maxSeconds=180
            g=graph(records,s,pref,durations)
            for _,a in ipairs(g.actions) do
                local family=families[math.floor(a.questID/100)]
                a.cost.lower=a.cost.seconds;a.cost.upper=a.cost.seconds+family.pressure*600
            end
            result=run(g,s,pref)
            local selectedFamily=math.floor(result.actions[1].questID/100)*100
            check("S15 production tradeoff "..flavor,selectedFamily==expected[flavor] and result.xp==expectedXP[flavor],
                selectedFamily..":"..result.xp..":"..result.seconds)
            check("S15 bounded efficiency envelope "..flavor,result.efficiencyCost<=pref.detour/(1+pref.detour)+.000001)
            print("S15 production",flavor,selectedFamily,result.xp,result.seconds,result.efficiencyCost)
        end

        -- The same feasible encounter alternatives exercise actual flavor selection.
        for _,case in ipairs({{"Relaxed",false},{"Efficient",false},{"Challenge",true},{"Efficient",true}}) do
            local flavor,harder=case[1],case[2];local base,other=9301,case[2] and 9303 or 9302
            s=initial({base,other});s.capabilities.combat={maxHealth=500};s.visited[1]=true
            records={[base]=source(base,0,100),[other]=source(other,0,100)}
            records[base].planning.blockedBy={other};records[base].planning.exclusiveWith={other}
            records[other].planning.blockedBy={base};records[other].planning.exclusiveWith={base}
            pref=p.Preferences.Normalize({flavor=flavor,readingSeconds=0,strictSession=true});pref.maxSeconds=120
            g=graph(records,s,pref,{[base]=98,[other]=harder and 108 or 103})
            for _,action in ipairs(g.actions) do
                if action.kind=="objective" then
                    action.encounter={minLevel=action.questID==base and 10 or harder and 12 or 8};action.rank=0
                    for sample=1,3 do p.PlanLearning.Observe("combat",p.PlanCosts.Context(action,s),10,1) end
                end
            end
            result=run(g,s,pref)
            local expected=(flavor=="Relaxed" or flavor=="Challenge") and other or base
            check("production encounter preference "..flavor..":"..tostring(harder),result.actions[1].questID==expected,result.actions[1].questID)
            if flavor=="Challenge" then
                s.capabilities.combat=nil;local unknown=run(g,s,pref)
                check("unknown capability earns no Challenge fit claim",unknown.actions[1].questID==base)
            end
        end



        -- An inaccessible future exploration trigger is not a standalone attraction.
        records={[501]=source(501,0,100),[502]=source(502,.005,0,503)}
        records[502].objectives[1].methods[1].kind="explore"
        s=initial({501,502,503});s.visited[1]=true
        for _,flavor in ipairs({"Balanced","Efficient","Story","Explorer","Relaxed","Challenge"}) do
            pref=p.Preferences.Normalize({flavor=flavor,readingSeconds=0,strictSession=true});pref.maxSeconds=120
            g=graph(records,s,pref,{[501]=98,[502]=1})
            local fabricated=false
            for _,a in ipairs(g.actions) do if a.optionalExploration then fabricated=true end end
            check("no invented exploration attraction "..flavor,not fabricated)
            result=run(g,s,pref)
            local unrelated=false
            for _,a in ipairs(result.actions) do if a.questID==502 then unrelated=true end end
            check("unavailable exploration quest never sends player to empty point "..flavor,not unrelated and result.xp==100)
        end

        -- Seasonal source references need an exact currently observed offer, even when pinned.
        records={[8653]=source(8653,0,100)}
        records[8653].title="Goldwell the Elder";records[8653].zoneOrSort=-366
        records[8653].starts[1].targetID=15569
        for _,flavor in ipairs({"Balanced","Efficient","Story","Explorer","Relaxed","Challenge"}) do
            s=initial({8653})
            pref=p.Preferences.Normalize({flavor=flavor,readingSeconds=0});pref.pins[8653]=true
            g=graph(records,s,pref,{[8653]=1})
            local pickup
            for _,a in ipairs(g.actions) do if a.kind=="pickup" then pickup=a;break end end
            check("Goldwell is seasonal "..flavor,pickup and pickup.seasonal==true)
            check("seasonal source reference cannot authorize pickup "..flavor,p.PlanTransitions.Check(pickup,s,pref)==nil)
            result=run(g,s,pref)
            check("pinned seasonal quest cannot bypass availability "..flavor,#result.actions==0)
            s.questOffers={[8653]={offered=true,npcID=15569}}
            check("exact live giver offer permits seasonal pickup "..flavor,p.PlanTransitions.Check(pickup,s,pref)==true)
            s.questOffers={[8654]={offered=true,npcID=15569}}
            check("one elder offer does not activate all elders "..flavor,p.PlanTransitions.Check(pickup,s,pref)==nil)
            s.questOffers={[8653]={offered=true,npcID=999}}
            check("different giver does not prove source location "..flavor,p.PlanTransitions.Check(pickup,s,pref)==nil)
            s.active[8653]=true;s.logCount=1;s.objectivesComplete[8653]=true
            local turnin
            for _,a in ipairs(g.actions) do if a.kind=="turnin" then turnin=a;break end end
            check("active seasonal quest is retained "..flavor,p.PlanTransitions.Check(turnin,s,pref)==true)
        end
        records[8653].zoneOrSort=-284;records[8653].planning.seasonalEvent="ChildrensWeek"
        s=initial({8653});g=graph(records,s,pref,{[8653]=1})
        local pickup
        for _,a in ipairs(g.actions) do if a.kind=="pickup" then pickup=a;break end end
        check("membership gates holiday with ordinary category",pickup.seasonal==true)
        records[8653].planning.seasonalEvent=nil;records[8653].planning.specialFlags=2
        g=graph(records,s,pref,{[8653]=1})
        for _,a in ipairs(g.actions) do if a.kind=="pickup" then pickup=a;break end end
        check("script completion flag is not a holiday",not pickup.seasonal and p.PlanTransitions.Check(pickup,s,pref)==true)

        -- Deathknell screenshot: level-1 Paladin, active quest 364 at 31.6,66.0.
        -- Source shape/positions: QuestieDB baa0998d; AH includes neutral NPCs.
        -- Counts are live quest-log evidence. Source rewards/availability stay unknown.
        do
            local function npc(kind,id,name,x,y,faction,level)
                return {kind=kind,targetKind="npc",targetID=id,name=name,dispositionKnown=true,friendlyToFaction=faction,
                    eligibility={minLevel=level,maxLevel=level},rank=0,
                    areas={{id="npc:"..id,mapID=1420,x=x,y=y}}}
            end
            local calvin=npc("start",6784,"Calvin Montague",.3823,.5679,"H",5)
            local sarvis=npc("finish",1569,"Shadow Priest Sarvis",.3084,.662,"H",5)
            local zombies={
                {id="monster:1501:1",type="monster",targetID=1501,methods={npc("kill",1501,"Mindless Zombie",.3228,.6363,"AH",1)}},
                {id="monster:1502:2",type="monster",targetID=1502,methods={npc("kill",1502,"Wretched Zombie",.3258,.6276,"AH",2)}},
            }
            local deathknell={
                [364]={id=364,title="The Mindless Ones",objectives=zombies,starts={},ends={sarvis},
                    eligibility={questLevel=2,requiredLevel=1},planning={version=1,requirements={op="minLevel",value=1}}},
                [8]={id=8,title="A Rogue's Deal",objectives={},starts={calvin},
                    ends={npc("finish",5688,"Innkeeper Renee",.6172,.5205,"H",30)},providedItemID=7628,
                    eligibility={questLevel=5,requiredLevel=1},planning={version=1,blockedBy={590},
                        requirements={op="all",args={{op="minLevel",value=1},{op="raceMask",value=178}}}}},
                [590]={id=590,title="A Rogue's Deal",objectives={{id="event:590:1",type="event",
                    methods={{kind="explore",targetKind="event",targetID=590,name="Defeat Calvin Montague",
                        areas={{id="event:590",mapID=1420,x=.3819,y=.5674}}}}}},starts={calvin},
                    ends={npc("finish",6784,"Calvin Montague",.3823,.5679,"H",5)},
                    eligibility={questLevel=5,requiredLevel=1},planning={version=1,requirements={op="completed",questID=8}}},
            }
            local starter=initial({364,8,590})
            starter.identity={product="forever",build="1.60.1.69913",locale="enUS"}
            starter.level=1;starter.class=2;starter.classMask=2;starter.race=5;starter.raceMask=16;starter.faction="Horde"
            starter.position={mapID=1420,x=.316,y=.66};starter.active[364]=true;starter.logCount=1
            starter.live[364]={title="The Mindless Ones",level=2,objectivesComplete=false,hasPlanningRecord=true}
            starter.progress[364]={};starter.objectiveInfo[364]={}
            for _,objective in ipairs(zombies) do
                starter.progress[364][objective.id]=8
                starter.objectiveInfo[364][objective.id]={required=8,fulfilled=0,bound=true}
            end
            local env={mapSizes={[1420]={4518.75,3012.5}}}
            for _,flavor in ipairs({"Balanced","Efficient","Story","Explorer","Relaxed","Challenge"}) do
                local policy=p.Preferences.Normalize({flavor=flavor})
                local g=graph(deathknell,starter,policy,{[364]=1,[590]=1})
                local pickup,followup
                for _,action in ipairs(g.actions) do
                    action.cost=nil
                    if action.questID==364 and action.kind=="objective" and not action.liveFallback then
                        check("active neutral zombie remains feasible "..flavor..":"..action.target.id,
                            p.PlanTransitions.Check(action,starter,policy)==true)
                    elseif action.kind=="pickup" and action.questID==8 then pickup=action
                    elseif action.kind=="pickup" and action.questID==590 then followup=action end
                end
                check("quest title does not impose Rogue class restriction "..flavor,p.PlanTransitions.Check(pickup,starter,policy)==true)
                check("Calvin combat followup needs its prerequisite "..flavor,p.PlanTransitions.Check(followup,starter,policy)==false)
                local result=run(g,starter,policy,env)
                local observed={{questID=364,kind="objective",destination={mapID=1420,x=.3228,y=.6363},
                    semantic={objectiveKey="monster:1501:1"},recommendation={distance=78}}}
                local inputs={observed=observed,destinations={},mapSize=env.mapSizes[1420],
                    localQuests=p.Recommendations.Capture(observed,starter,policy,g)}
                local projected,_,decision=p.PlanRuntime.ProjectDecision(result,policy,nil,starter,inputs)
                check("nearby active starter work precedes Calvin pickup "..flavor,
                    decision.displayed.selected and decision.displayed.selected.questID==364,
                    decision.displayed.selected and decision.displayed.selected.questID or "no action")
                check("active-work override explains unconfirmed pickup without speculative rewards "..flavor,
                    decision.mode=="local" and projected.reason:find("unconfirmed",1,true)
                    and projected.score==nil and projected.xp==nil and #projected.actions==0)
                p.Context={Frame=function() return {position=starter.position,width=4518.75,height=3012.5} end}
                local model=p.PlanRuntime.Result({actions={pickup},score=42,xp=900,seconds=500,status="refining",
                    decisionKind="continuity",replayGraph=g},observed,{destinations={}},policy,nil,starter)
                check("published starter guidance clears speculative itinerary "..flavor,
                    model.selected.questID==364 and model.localGuidance and model.score==nil and model.estimate.xp==nil
                    and model.estimate.seconds==nil and #model.upNext==0 and #model.actionIDs==0)
                local trace=p.PlanRuntime.Replay()
                local replay=trace and p.PlanRuntime.RerunReplay(trace,trace.source)
                check("starter choice replays offline "..flavor,replay and replay.status=="match",
                    replay and (replay.reason or replay.phase))
                local choice=p.Recommendations.UnconfirmedPickupChoice
                starter.questOffers={[8]={offered=true,npcID=6784}}
                check("exact observed offer retains pickup planning "..flavor,choice(pickup,inputs.localQuests,starter,policy,inputs.mapSize)==nil)
                starter.questOffers={[8]={offered=true,npcID=999}}
                check("wrong giver cannot confirm pickup "..flavor,choice(pickup,inputs.localQuests,starter,policy,inputs.mapSize)~=nil)
                starter.questOffers=nil
                policy.pins[8]=true
                local _,_,pinned=p.PlanRuntime.ProjectDecision(result,policy,nil,starter,inputs)
                check("explicit future quest pin retains user choice "..flavor,pinned.displayed.selected.questID==8)
                policy.pins[8]=nil
                local nearby=p.Schema.Clone(pickup);nearby.destination={mapID=1420,x=.317,y=.66}
                check("nearby pickup still fits current work "..flavor,choice(nearby,inputs.localQuests,starter,policy,inputs.mapSize)==nil)
                check("unknown distances cannot manufacture an active-work override "..flavor,choice(pickup,inputs.localQuests,starter,policy,nil)==nil)
                policy.skips[364]=true
                check("skipped active work cannot override pickup "..flavor,choice(pickup,inputs.localQuests,starter,policy,inputs.mapSize)==nil)
                policy.skips[364]=nil
                inputs.localQuests[1].blocked=true
                check("blocked active work cannot override pickup "..flavor,choice(pickup,inputs.localQuests,starter,policy,inputs.mapSize)==nil)
                check("source planning does not fabricate offer or progress "..flavor,
                    starter.questOffers==nil and starter.progress[364]["monster:1501:1"]==8 and not starter.active[8])
                local neutral=p.Schema.Clone(g.byQuest[364][1])
                for _,a in ipairs(g.byQuest[364]) do if a.method=="kill" then neutral=p.Schema.Clone(a);break end end
                neutral.method="drop"
                check("neutral drop source remains feasible "..flavor,p.PlanTransitions.Check(neutral,starter,policy)==true)
                neutral.friendlyToFaction="H"
                check("same faction label alone cannot veto scripted objective "..flavor,p.PlanTransitions.Check(neutral,starter,policy)==true)
                neutral.preconditions={{op="item",itemID=999,count=1}}
                starter.inventory[999]=0
                check("scripted objective still needs its setup "..flavor,p.PlanTransitions.Check(neutral,starter,policy)==false)
                local interaction=p.Schema.Clone(pickup);interaction.friendlyToFaction="A"
                check("opposing faction giver remains excluded "..flavor,p.PlanTransitions.Check(interaction,starter,policy)==false)
                interaction.friendlyToFaction="AH"
                check("neutral giver remains usable "..flavor,p.PlanTransitions.Check(interaction,starter,policy)==true)
                starter.completed[8]=nil
                check("neutral giver cannot bypass unknown history "..flavor,p.PlanTransitions.Check(interaction,starter,policy)==nil)
                starter.completed[8]=false
            end
        end

        -- R06 signed reputation and explicit non-XP reward preferences.
        records={[401]=source(401,0,100),[402]=source(402,0,100)}
        records[401].planning.blockedBy={402};records[401].planning.exclusiveWith={402}
        records[402].planning.blockedBy={401};records[402].planning.exclusiveWith={401}
        records[402].reputationReward={{47,1000},{87,-1000}}
        s=initial({401,402});s.reputation[47]=0;s.reputation[87]=0
        pref=p.Preferences.Normalize({flavor="Balanced",readingSeconds=0,rewardFocus="reputation",rewardTarget=47})
        pref.maxSeconds=120
        g=graph(records,s,pref,{[401]=98,[402]=108});result=run(g,s,pref)
        check("R06 explicit faction reward changes whole search",result.actions[1].questID==402 and result.xp==100)
        local projected=p.PlanTransitions.Fork(s)
        for index,a in ipairs(result.actions) do projected=assert(p.PlanTransitions.Apply(a,projected,pref,result.costs[index])) end
        check("R06 reputation stays projected until live standing",projected.reputation[47]==0
            and projected.projectedRewards.reputation[47]==1000 and projected.projectedRewards.reputation[87]==-1000)
        check("R06 source reputation cannot unlock hard prerequisite",p.PlanTransitions.Condition({op="reputationMin",id=47,value=500},projected)==false)
        s.live[402]={reward={money=500,items={{itemID=77,count=1,equipment=true,usable=true}},
            choices={{itemID=78,count=1},{itemID=79,count=1}},spells={123}}}
        s.inventory[77]=0;s.inventory[78]=0;s.inventory[79]=0;s.stackSizes={[77]=1,[78]=1,[79]=1}
        s.active[402]=true;s.logCount=1;s.objectivesComplete[402]=true
        pref.rewardTarget=79
        g=graph(records,s,pref,{[401]=98,[402]=108})
        local turnin
        for _,a in ipairs(g.byQuest[402]) do if a.kind=="turnin" then turnin=a;break end end
        local offered=assert(p.PlanTransitions.Apply(turnin,s,pref,p.PlanCosts.Estimate(turnin,s,pref,environment)))
        check("R06 exactly one choice and guaranteed item granted",offered.inventory[77]==1 and offered.inventory[79]==1 and offered.inventory[78]==0)
        check("R06 money and explicitly learned spell projected once",offered.money==500 and offered.spells[123]==true
            and p.PlanTransitions.Check(turnin,offered,pref)==false)
        check("R06 reward branches do not mutate observation",s.money==0 and s.spells[123]==nil and s.inventory[77]==0)
        local sibling=p.PlanTransitions.Fork(offered);sibling.projectedRewards.money=7;sibling.spells[123]=false
        check("R06 projected rewards isolated across branches",offered.projectedRewards.money==500 and offered.spells[123]==true)

    end)
    RikUI=saved
    check("adversarial acceptance suite completes",ok,err)
end
