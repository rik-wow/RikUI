-- End-to-end production search over adversarial source graphs; native play remains separate.
return function(check)
    local saved=RikUI
    RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
    local ok,err=pcall(function()
        for _,name in ipairs({"schema","preferences","plan-graph","plan-transitions","plan-learning","plan-rewards","plan-costs","plan-search"}) do
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
        local function run(g,s,pref)
            local job=assert(p.PlanSearch.Begin(g,s,pref,environment));local result
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
        for _,flavor in ipairs({"Efficient","Balanced","Story"}) do
            pref=p.Preferences.Normalize({flavor=flavor,readingSeconds=0});pref.maxSeconds=180
            g=graph(records,s,pref,durations)
            for _,a in ipairs(g.actions) do
                local family=families[math.floor(a.questID/100)]
                a.cost.lower=a.cost.seconds;a.cost.upper=a.cost.seconds+family.pressure*600
            end
            result=run(g,s,pref)
            local selectedFamily=math.floor(result.actions[1].questID/100)*100
            check("S15 production tradeoff "..flavor,selectedFamily==expected[flavor] and result.xp==300,
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
                if action.kind=="objective" then action.encounter={minLevel=action.questID==base and 10 or harder and 12 or 8};action.rank=0 end
            end
            result=run(g,s,pref)
            local expected=(flavor=="Relaxed" or flavor=="Challenge") and other or base
            check("production encounter preference "..flavor..":"..tostring(harder),result.actions[1].questID==expected,result.actions[1].questID)
            if flavor=="Challenge" then
                s.capabilities.combat=nil;local unknown=run(g,s,pref)
                check("unknown capability earns no Challenge fit claim",unknown.actions[1].questID==base)
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
