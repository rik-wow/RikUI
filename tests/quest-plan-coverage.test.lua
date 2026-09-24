-- Coverage selection uses captured live quest positions; no quest progress is simulated.
return function(check)
    local saved=RikUI
    RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
    local ok,err=pcall(function()
        for _,name in ipairs({"schema","preferences","recommendations","guidance","plan-state","plan-transitions",
            "plan-learning","plan-costs","plan-search","plan-runtime","transfer"}) do
            dofile("src/modules/questplanner/quest-"..name..".lua")
        end
        local p=RikUI.QuestPlanner
        local policy=assert(p.Preferences.Normalize({skips={[96408]=true}}))
        local position={mapID=1426,x=.2933368682861328,y=.4512476325035095}
        local frame={position=position,width=4897.5,height=3265}
        p.Context={Frame=function() return frame end,History=function() return {} end}
        local identity={product="forever",build="1.60.1.69913",locale="enUS"}
        local quests={
            {412,"Operation Recombobulation",.259509325,.405659914,false,true},
            {413,"Shimmer Stout",.862758040,.488197982,true,true},
            {1681,"Ironband's Compound",.779712379,.621599019,false,true},
            {98319,"Secure the Mountain",.418291092,.492461979,false,false},
            {98326,"Frosthowl",.393316448,.487893462,false,false},
            {99159,"Finding Warmth",.557783484,.519263983,false,false},
            {96408,"A Visitor to Dun Morogh",.648747921,.584746242,true,false},
        }
        local snapshot={identity=identity,order={},quests={},coverage="log-complete",reportedCount=#quests}
        local ctx={origin="live",attributes={},position=position,destinations={},history={},rewards={}}
        local records={}
        for _,q in ipairs(quests) do
            snapshot.order[#snapshot.order+1]=q[1]
            snapshot.quests[q[1]]={id=q[1],title=q[2],objectivesComplete=q[5],objectives={}}
            ctx.destinations[q[1]]={mapID=1426,x=q[3],y=q[4]}
            if q[6] then records[q[1]]={id=q[1],title=q[2],objectives={}} end
        end
        local state=assert(p.PlanState.Build(snapshot,{state="current"},ctx,records,policy))
        check("live state distinguishes source coverage from map markers",state.live[412].hasPlanningRecord==true
            and state.live[98326].hasPlanningRecord==false and state.live[98326].destination~=nil)
        local far={id="413:turnin",questID=413,kind="turnin",title="Shimmer Stout",destination=ctx.destinations[413]}
        local near={id="412:objective:source",questID=412,kind="objective",objectiveKey="item"}
        state.progress[412]={item=8}
        local graph={actions={near,far}}
        local prior={actionID=far.id,selected={questID=413},flavor=policy.flavor}
        local function project(preferences,previous)
            local rows=p.Guidance.Observed(snapshot,ctx,preferences,previous and previous.selected.questID,false,previous and previous.selected)
            local raw={actions={far},reason="Continue the current feasible action",score=1.322,seconds=1223,xp=2740,
                status="refining",decisionKind="continuity",replayGraph=graph,alternatives={{action=far,score=1.322}}}
            return p.PlanRuntime.Result(raw,rows,ctx,preferences,previous,state),rows
        end
        local model=project(policy,prior)
        check("reported Shimmer trip yields to closest active work",model.localGuidance and model.selected.questID==412)
        check("partial coverage never inherits unrelated rollout rewards",model.score==nil and model.estimate.seconds==nil
            and model.estimate.xp==nil and #model.upNext==0 and #model.actionIDs==0)
        check("coverage reason names navigable missing quests",model.localCoverage and #model.localCoverage.missing==3)
        local trace=p.PlanRuntime.Replay()
        local replay=trace and p.PlanRuntime.RerunReplay(trace,trace.source)
        check("local decision has exact offline replay",replay and replay.status=="match",replay and (replay.reason or replay.phase))
        local rows=p.Guidance.Observed(snapshot,ctx,policy)
        local source={id="412:objective:source",questID=412,kind="objective",objectiveKey="item",preconditions={{op="item",itemID=7,count=1}}}
        state.inventory[7]=0
        local input=p.Recommendations.Capture(rows,state,policy,{actions={source}})
        local choice=p.Recommendations.LocalChoice(input,state,policy)
        check("known resource gate is preserved in proximity mode",choice and choice.questID~=412)
        local fallback=p.PlanRuntime.Result({actions={},status="refining",decisionKind="fallback"},rows,ctx,policy,prior,state)
        check("cold decision cannot bypass unchecked source prerequisites",fallback.localGuidance and fallback.selected.questID==98326)
        rows[1].semantic={objectiveKey="item"}
        local other={id="412:objective:other",questID=412,kind="objective",objectiveKey="other"}
        state.progress[412].other=1
        choice=p.Recommendations.LocalChoice(p.Recommendations.Capture(rows,state,policy,{actions={source,other}}),state,policy)
        check("another objective cannot excuse a blocked observed target",choice and choice.questID~=412)
        rows[1].semantic=nil
        check("guide selection cannot simulate completion",not model.selected.planAction and state.active[412]
            and not state.objectivesComplete[412] and state.xpGained==0)

        policy.pins[413]=true
        model=project(policy,prior)
        check("explicit pin wins in incomplete coverage",model.selected.questID==413)
        policy.pins[413]=nil
        local future={id="99:pickup",questID=99,kind="pickup",title="Pinned future",destination=ctx.destinations[413]}
        state.completed[99]=false;state.logCapacity=40;policy.pins[99]=true
        local rows=p.Guidance.Observed(snapshot,ctx,policy)
        model=p.PlanRuntime.Result({actions={future},score=2,status="ready"},rows,ctx,policy,prior,state)
        check("modeled future pin is not overridden by local coverage",model.selected.questID==99 and not model.localGuidance)
        local precursor={id="98:pickup",questID=98,kind="pickup",title="Pinned prerequisite",destination=ctx.destinations[413]}
        state.completed[98]=false
        model=p.PlanRuntime.Result({actions={precursor,future},score=2,status="ready"},rows,ctx,policy,prior,state)
        check("pinned chain keeps its unpinned prerequisite",model.selected.questID==98 and not model.localGuidance)
        policy.pins[99]=nil
        future.destination={mapID=1426,x=position.x+.002,y=position.y}
        local pickupResult={actions={future},score=2,status="refining",decisionKind="continuity"}
        model=p.PlanRuntime.Result(pickupResult,rows,ctx,policy,prior,state)
        check("nearby eligible pickup survives partial active-quest coverage",model.selected.questID==99 and not model.localGuidance)
        local pickupTrace=p.PlanRuntime.Replay()
        local pickupReplay=pickupTrace and p.PlanRuntime.RerunReplay(pickupTrace,pickupTrace.source)
        check("nearby pickup coverage decision replays exactly",pickupReplay and pickupReplay.status=="match",
            pickupReplay and pickupReplay.reason)
        state.completed[99]=nil
        model=p.PlanRuntime.Result(pickupResult,rows,ctx,policy,prior,state)
        check("unknown pickup eligibility retains active-quest guidance",model.localGuidance and model.selected.questID~=99)
        state.completed[99]=false;policy.skips[99]=true
        model=p.PlanRuntime.Result(pickupResult,rows,ctx,policy,prior,state)
        check("skipped pickup cannot bypass coverage safeguards",model.localGuidance and model.selected.questID~=99)
        policy.skips[99]=nil;future.destination=ctx.destinations[413]
        model=p.PlanRuntime.Result(pickupResult,rows,ctx,policy,prior,state)
        check("distant pickup still yields to closer active work",model.localGuidance and model.selected.questID~=99)
        future.destination={mapID=1426,x=position.x+.002,y=position.y}
        frame.width=nil
        model=p.PlanRuntime.Result(pickupResult,rows,ctx,policy,prior,state)
        check("unknown map scale cannot rank pickup ahead of local work",model.localGuidance and model.selected.questID~=99)
        frame.width=4897.5
        policy.skips[412]=true
        model=project(policy,prior)
        check("live-only Frosthowl can be selected directly",model.localGuidance and model.selected.questID==98326)
        state.failures["98326:live:objective"]=2
        model=project(policy,prior)
        check("unavailable live action is not reselected",model.selected.questID~=98326)
        state.failures["98326:live:objective"]=nil
        state.failures["98326:objective:source"]=2
        model=project(policy,prior)
        check("source failure cannot be bypassed by local action identity",model.selected.questID~=98326)
        state.failures["98326:objective:source"]=nil
        model=project(policy,prior)
        local livePrior=model
        frame.position={mapID=1426,x=.392,y=.488};ctx.position=frame.position;state.position=frame.position
        local a=project(policy,livePrior)
        local b=project(policy,a)
        check("live guidance remains stable through repeated replans",a.actionID==livePrior.actionID and b.actionID==a.actionID)
        check("arrival never completes live work",state.objectivesComplete[98326]==false)
        local capture=p.Recommendations.Capture(p.Guidance.Observed(snapshot,ctx,policy))
        state.live[98326].objectivesComplete=true
        local choice=p.Recommendations.LocalChoice(capture,state,policy)
        check("objective to turnin invalidates stale local guidance",not choice or choice.questID~=98326)
        state.live[98326].objectivesComplete=false
        policy.defers[98326]=true
        model=project(policy,b)
        check("deferral immediately excludes live incumbent",model.selected.questID~=98326)
        policy.defers[98319]=true;policy.defers[99159]=true
        model=project(policy,b)
        check("excluded missing data does not disable modeled planning",not model.localGuidance and model.selected.questID==413)
        policy.defers={};policy.skips[412]=nil
        for _,id in ipairs({98319,98326,99159}) do state.live[id].dungeon=true end
        model=project(policy,prior)
        check("disabled dungeon data does not force local mode",not model.localGuidance)
        for _,id in ipairs({98319,98326,99159}) do
            state.live[id].dungeon=nil;state.live[id].requiredParty=5
        end
        model=project(policy,prior)
        check("solo constraints apply before coverage arbitration",not model.localGuidance)
        for _,id in ipairs({98319,98326,99159}) do
            state.live[id].requiredParty=nil;state.live[id].hasPlanningRecord=true
        end
        model=project(policy,prior)
        check("modeled coverage restores adaptive planning",not model.localGuidance and model.score==1.322)
        state.live[98326].hasPlanningRecord=false
        ctx.destinations[98326]=nil
        model=project(policy,prior)
        check("missing location cannot force an unsupported detour",not model.localGuidance)
    end)
    RikUI=saved
    check("coverage regression completes",ok,err)
end
