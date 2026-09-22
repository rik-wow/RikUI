return function(check)
    local previous=RikUI
    RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
    local ok,reason=pcall(function()
        for _,name in ipairs({"schema","steps","observed-steps"}) do dofile("src/modules/questplanner/quest-"..name..".lua") end
        local p=RikUI.QuestPlanner
        local identity={product="forever",build="1.60.1.69913",locale="enUS"}
        local function copy(v) return p.Schema.Clone(v) end
        local defs={
            {id="enter",kind="travel",questID=310,location={coordinateSystem="normalized-map",mapID=1426,instanceID=0,
                x=.4,y=.5,floor="basement",anchorID="door"},completion={{kind="arrival",radius=2}}},
            {id="use",kind="interaction",questID=310,target={kind="object",id=1},completion={{kind="interaction",outcome="used"}}},
            {id="turn",kind="turnin",questID=310,prerequisites={{kind="quest-ready",questID=310}},completion={{kind="turned-in",questID=310}}}}
        local seq=assert(p.Steps.New(identity,defs))
        local e={identity=copy(identity),arrivals={enter={mapID=1426,instanceID=0,floor="basement",anchorID="door",connected=true,distance=1}},
            interactions={},questReady={[310]=true},turnedIn={[310]=false}}
        check("travel proximity advances only explicit connected anchor",seq:Evaluate(e).stepID=="use")
        e.arrivals.enter.partial=true
        check("partial route cannot complete travel",seq:Evaluate(e).stepID=="enter")
        e.arrivals.enter.partial=nil;e.arrivals.enter.floor="upper"
        check("wrong floor cannot complete travel",seq:Evaluate(e).stepID=="enter")
        e.arrivals.enter.floor="basement";e.items={[2]=1}
        check("item possession cannot complete an interaction",seq:Evaluate(e).stepID=="use")
        e.interactions.use={targetKind="object",targetID=2,outcome="used"}
        check("unrelated target evidence cannot advance interaction",seq:Evaluate(e).stepID=="use")
        e.interactions.use.targetID=1
        check("matching interaction selects turn-in without completing it",seq:Evaluate(e).stepID=="turn")
        e.turnedIn[310]=true
        check("observed turn-in completes sequence",seq:Evaluate(e).state=="completed")
        for _,field in ipairs({"product","build","locale"}) do
            local wrong=copy(e);wrong.identity[field]="wrong"
            check("step rejects mismatched "..field,seq:Evaluate(wrong).state=="unknown")
        end
        check("malformed evidence fails closed",seq:Evaluate(5).state=="unknown")
        local malformed=copy(defs);malformed[1].completion={true}
        check("scalar completion predicate rejected",not p.Steps.New(identity,malformed))
        malformed=copy(defs);malformed[1].prerequisites=false
        check("false prerequisites rejected",not p.Steps.New(identity,malformed))
        malformed=copy(defs);malformed[2].completion={{kind="arrival",radius=1}}
        check("interaction cannot be authored as proximity completion",not p.Steps.New(identity,malformed))
        defs[2].target.id=999
        check("step definitions detached from caller mutation",seq:Evaluate(e).state=="completed")
        local transport={id="boat",kind="transport",legID="pier-route",fromAnchorID="pier-a",
            location={coordinateSystem="normalized-map",mapID=1432,instanceID=0,x=.2,y=.3,floor=0,anchorID="pier-b"},
            completion={{kind="transport",radius=2}}}
        local journey=assert(p.Steps.New(identity,{transport}))
        local facts={identity=identity,transports={boat={legID="pier-route",fromAnchorID="pier-a",boarding=true}}}
        check("transport explicitly waits for boarding",journey:Evaluate(facts).phase=="boarding")
        facts.transports.boat.boarded=true
        check("transport distinguishes riding",journey:Evaluate(facts).phase=="riding")
        facts.transports.boat.exited=true
        facts.arrivals={boat={mapID=1426,instanceID=0,floor=0,anchorID="pier-b",connected=true,distance=0}}
        check("transport exit on wrong map remains incomplete",journey:Evaluate(facts).phase=="exiting")
        facts.arrivals.boat.mapID=1432
        check("matching transport exit and arrival complete leg",journey:Evaluate(facts).state=="completed")
        local snapshot={identity=identity,quests={[313]={title="Observed cave quest",objectivesComplete=false,objectives={
            {text="First 1/2",type="monster",numFulfilled=1,numRequired=2,finished=false},
            {text="Second 0/1",type="item",numFulfilled=0,numRequired=1,finished=false}}}}}
        local ctx={destinations={[313]={mapID=1426,x=.4,y=.5,scope="quest",api="fixture"}}}
        local observed=p.Steps.ObservedQuest(snapshot,313,ctx)
        check("first incomplete observed objective is explicit",observed.stepID=="313:observed-slot:1")
        check("quest marker does not become objective target identity",
            observed.questMarker.association=="quest" and not observed.questMarker.objectiveLocationKnown and not observed.active.location)
        snapshot.quests[313].objectives[1].finished=true
        check("objective evidence advances to next observed action",p.Steps.ObservedQuest(snapshot,313,ctx).stepID=="313:observed-slot:2")
        snapshot.quests[313].objectivesComplete=true
        local ready=p.Steps.ObservedQuest(snapshot,313,ctx)
        check("ready quest selects incomplete turn-in",ready.stepID=="313:turnin" and ready.state~="completed")

        for _,name in ipairs({"objectives","step-bindings","guide-data"}) do dofile("src/modules/questplanner/quest-"..name..".lua") end
        local real={identity=copy(identity),quests={[313]={title="The Grizzled Den",objectivesComplete=false,
            objectives={{text="3/8 Wendigo Mane",type="item",numFulfilled=3,numRequired=8,finished=false}}}}}
        check("reviewed objective gets stable identity",p.StepBindings.Match(real,313).ids[1]=="q313.wendigo-manes")
        real.quests[313].objectives[1].text="4/8 Wendigo Mane"
        real.quests[313].objectives[1].numFulfilled=4
        check("progress preserves reviewed objective identity",p.StepBindings.Match(real,313).ids[1]=="q313.wendigo-manes")
        local bind=p.StepBindings.Match(real,313);bind.ids[1]="changed"
        check("binding result cannot mutate pack",p.StepBindings.Match(real,313).ids[1]=="q313.wendigo-manes")
        for _,field in ipairs({"type","numRequired","text"}) do
            local wrong=copy(real);wrong.quests[313].objectives[1][field]=field=="numRequired" and 9 or "wrong"
            check("binding rejects mismatched "..field,not p.StepBindings.Match(wrong,313))
        end
        local wrong=copy(real);wrong.quests[313].title="Different quest"
        check("binding rejects changed title",not p.StepBindings.Match(wrong,313))
        wrong=copy(real);wrong.identity.build="1.60.2"
        check("binding rejects changed client build",not p.StepBindings.Match(wrong,313))
        wrong=copy(real);wrong.quests[313].objectives[1].text="3/8 Wendigo Mane"
        check("binding rejects contradictory observed counter",not p.StepBindings.Match(wrong,313))
        real.quests[287]={title="Frostmane Hold",objectives={
            {text="Fully explore Frostmane Hold",type="event",numFulfilled=0,numRequired=1,finished=false},
            {text="2/5 Frostmane Headhunter slain",type="monster",numFulfilled=2,numRequired=5,finished=false}}}
        bind=p.StepBindings.Match(real,287)
        check("reviewed identities survive objective reorder",bind.ids[1]=="q287.explore-hold" and bind.ids[2]=="q287.headhunter-kills")
        real.quests[287].objectives[2]=copy(real.quests[287].objectives[1])
        check("duplicate objective cannot bind another identity",not p.StepBindings.Match(real,287))

        snapshot.quests[313]=nil
        check("quest disappearance never manufactures completion",p.Steps.ObservedQuest(snapshot,313,ctx)==nil)
    end)
    RikUI=previous
    check("step evidence scenarios complete",ok,reason)
end
