-- Content admission and uncertainty boundaries; actual mesh traversal is replayed separately.
return function(check)
    local previous=RikUI
    RikUI={}
    RikUI["Secret"]={IsSecret=function() return false end}
    dofile("src/modules/questplanner/quest-schema.lua")
    dofile("src/modules/questplanner/quest-targets.lua")
    dofile("src/modules/questplanner/quest-guidance.lua")
    local p=RikUI.QuestPlanner
    local ok,reason=pcall(function()
        local point={mapID=1426,x=.47717434167861938,y=.5268782377243042,
            api="C_QuestLog.GetQuestsOnMap",scope="current-map-quest-poi"}
        local snapshot={identity={product="forever",build="1.60.1.69913",locale="enUS"},order={310},
            quests={[310]={id=310,title="Bitter Rivals",objectivesComplete=true,objectives={{
                text="In the basement of the Thunderbrew Distillery in Kharanos, replace a barrel of Thunder Ale with a Barrel of Barleybrew Scalder.",
                type="log",numRequired=1,numFulfilled=1,finished=true}}}}}
        local hint=assert(p.Targets.Match(snapshot,310,point))
        check("reported sequence stays conditional and separate from actions",hint.instructions:find("If Jarven",1,true)
            and hint.instructionsSource=="user-reported-sequence" and hint.actions==nil and hint.height==nil)
        local clone=p.Schema.Clone
        for _,key in ipairs({"product","build","locale"}) do
            local changed=clone(snapshot);changed.identity[key]="other"
            check("target annotation rejects changed "..key,not p.Targets.Match(changed,310,point))
        end
        for _,change in ipairs({
            function(q) q.title="Different quest" end,
            function(q) q.objectivesComplete=false end,
            function(q) q.failed=true end,
            function(q) q.objectives[1].text="Go upstairs" end,
            function(q) q.objectives[1].type="item" end,
            function(q) q.objectives[1].numRequired=2 end,
            function(q) q.objectives[1].finished=false end,
            function(q) q.objectives[2]=clone(q.objectives[1]) end,
        }) do
            local changed=clone(snapshot);change(changed.quests[310])
            check("changed quest stage cannot inherit basement inference",not p.Targets.Match(changed,310,point))
        end
        check("matching title alone cannot identify quest",not p.Targets.Match(snapshot,308,point))
        for _,key in ipairs({"mapID","api","scope","x","y"}) do
            local changed=clone(point);changed[key]=type(changed[key])=="number" and changed[key]+.001 or "different"
            check("target annotation rejects changed marker "..key,not p.Targets.Match(snapshot,310,changed))
        end
        local revision="d1981b5ac045133c7f2db478e91774432a3eaa82c4e93295478a43bfea5e118e"
        local choices={{height=393.09662169989,label="Lower floor"},{height=399.3549,label="Upper floor"}}
        local floor=assert(p.Targets.Floor(hint,revision,choices,point))
        check("basement is an explicit model inference",floor.index==1 and floor.label=="Basement"
            and floor.source=="quest-text-model-inference" and floor.questTargetVerified==false)
        check("changed terrain revision cannot retain annotation",not p.Targets.Floor(hint,"changed",choices,point))
        check("absent annotation cannot choose floor",not p.Targets.Floor(nil,revision,choices,point))
        for _,change in ipairs({
            function(c) c[1].height=394 end,
            function(c) c[2].height=400 end,
            function(c) c[3]={height=405} end,
            function(c) c[2]=nil end,
            function(c) c[1].height=nil end,
        }) do
            local changed=clone(choices);change(changed)
            check("changed or competing surfaces reject inferred floor",not p.Targets.Floor(hint,revision,changed,point))
        end
        floor.height=999;hint.instructions="changed"
        check("published annotations cannot modify private content",p.Targets.Match(snapshot,310,point).instructions~="changed"
            and p.Targets.Floor(hint,revision,choices,point).height==choices[1].height)
        local ctx={destinations={[310]=point},rewards={},history={},attributes={}}
        local signature=p.Guidance.Signature(snapshot,{state="current"},ctx)
        for _,key in ipairs({"api","scope","x"}) do
            local changed=clone(ctx)
            changed.destinations[310][key]=key=="x" and point.x+.0000002 or "changed"
            check("controller invalidates changed target binding "..key,signature~=p.Guidance.Signature(snapshot,{state="current"},changed))
        end
        local rows=p.Guidance.Observed(snapshot,ctx,{skips={},avoids={},pins={}})
        check("observed selection carries actionable target annotation",rows[1].targetHint and rows[1].detail=="Basement barrel; check Jarven")
        check("annotation does not alter observed state",snapshot.quests[310].objectivesComplete and ctx.destinations[310].height==nil)
        local result=p.Guidance.Result({status="insufficient-data",actions={},unknownXP=0},rows,ctx,nil,nil,{pins={},skips={},avoids={}})
        check("annotation never masquerades as calculated leveling",not result.calculated and result.seconds==nil and result.xp==nil)
        local endHint=p.Guidance.Instruction({next=point,meters=0,destinationFloor=p.Targets.Floor(hint,revision,choices,point)},point,0,4925,3283)
        check("inferred arrival does not claim target or quest completion",endHint.text=="Basement approach reached" and endHint.subtext=="Check the quest target")
    end)
    RikUI=previous
    check("target annotation fixture completes",ok,reason)
end
