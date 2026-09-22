return function(check)
    local old,oldCatalog,oldAddons=RikUI,RikUIQuestCorpusCatalog,C_AddOns
    RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
    local ok,err=pcall(function()
        for _,name in ipairs({"schema","objectives","optimizer","area-optimizer","steps","step-bindings","observed-steps","semantic-data","semantic-guidance","guidance"}) do
            dofile("src/modules/questplanner/quest-"..name..".lua")
        end
        local p=RikUI.QuestPlanner
        local identity={product="forever",build="1.60.1.69913",locale="enUS"}
        local area={id="npc:7:1426:1",mapID=1426,x=.2,y=.3,radius=0,floorKnown=false}
        local far={id="npc:7:1426:2",mapID=1426,x=.8,y=.3,radius=0,floorKnown=false}
        local quest={id=900,title="Field collection",objectives={{id="item:9",type="item",targetID=9,name="Field Token",
            methods={{kind="drop",targetKind="npc",targetID=7,name="Field Beast",areas={far,area}},
                     {kind="vendor",targetKind="npc",targetID=8,name="Trader",areas={{id="npc:8",mapID=1426,x=.1,y=.3}}}}}},
            ends={{kind="interact",targetKind="npc",targetID=10,name="Keeper",areas={{id="end",mapID=1426,x=.4,y=.3}}}}}
        RikUIQuestCorpusCatalog={version=1,identity=identity,revision="fixture",partitionSize=128,partitions={[7]="RikUIQuestCorpus_P00007"},counts={quests=1}}
        local sharedQuest=p.Schema.Clone(quest);sharedQuest.id=901;sharedQuest.title="Shared collection"
        sharedQuest.objectives[1].methods={{kind="drop",targetKind="npc",targetID=7,name="Field Beast",areas={far}}}
        local loads=0
        C_AddOns={LoadAddOn=function(name)
            loads=loads+1
            if name=="RikUIQuestCorpus_P00007" then assert(p.SemanticData.Register(7,"fixture",{[900]={base=quest,variants={}},[901]={base=sharedQuest,variants={}}})) end
            return true
        end}
        local snapshot={identity=identity,order={900},quests={[900]={id=900,title=quest.title,objectivesComplete=false,
            objectives={{text="2/8 Field Token",type="item",numFulfilled=2,numRequired=8,finished=false}}}}}
        local ctx={identity=identity,origin="live",position={mapID=1426,x=.19,y=.3},attributes={class=1,faction="Alliance"},
            destinations={},rewards={},history={},observedAt=1}
        p.Context={Frame=function() return {width=1000,height=1000,position=ctx.position} end,
            Call=function(fn,...) if type(fn)=="function" then return pcall(fn,...) end return false end}
        local policy={pins={},skips={},avoids={}}
        p.SemanticData.Ensure(snapshot,ctx)
        for _=1,3 do p.SemanticData.Step() end
        check("only required quest partition loads",loads==1)
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        local binding=p.StepBindings.Match(snapshot,900)
        check("unlisted quest binds semantic item by observed identity",binding and binding.ids[1]=="item:9")
        local function row() return p.Guidance.Observed(snapshot,ctx,policy)[1] end
        local value=row()
        check("nearest evidenced method area replaces missing quest POI",value.destination and value.destination.x==.2)
        check("missing vendor cost cannot displace a known hunt method",value.semantic and value.semantic.method=="drop")
        check("single spawn does not invent broad hunt radius",not value.hunt or value.hunt.radius==0)
        area.phase=1;p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("unknown phase cannot become an assumed usable area",row().destination.x==.8)
        area.phase=nil;area.floor=2;p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("known incompatible floor cannot become an assumed target",row().destination.x==.8)
        ctx.floor=2;p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("matching observed floor permits the sourced area",row().destination.x==.2)
        area.floor=nil;ctx.floor=nil
        ctx.position.x=.3;far.x=.48
        snapshot.order={900,901};snapshot.quests[901]=p.Schema.Clone(snapshot.quests[900])
        snapshot.quests[901].id=901;snapshot.quests[901].title=sharedQuest.title
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("shared target area reduces redundant travel across active quests",row().destination.x==.48 and row().semantic.sharedQuests==2)
        snapshot.order={900};snapshot.quests[901]=nil;ctx.position.x=.19;far.x=.8
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("semantic target stays reference confidence",value.semantic and value.semantic.authority=="reference")
        check("published step omits the world target graph",value.step and value.step.objectiveBinding and value.step.objectiveBinding.semantic==nil)
        check("proximity cannot complete collection",value.step and value.step.state=="active",value.step and value.step.reason)
        ctx.destinations[900]={mapID=1426,x=.6,y=.3,scope="current-waypoint"}
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("explicit runtime access waypoint wins",row().destination.x==.6)
        ctx.destinations[900]=nil
        snapshot.quests[900].objectives[1].text="2/8 Different Token"
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("changed live objective retracts incompatible semantic target",not row().destination)
        check("contradiction has a bounded receipt",p.SemanticGuidance.Status().conflicts>0)
        snapshot.quests[900].objectives[1].text="8/8 Field Token"
        snapshot.quests[900].objectives[1].numFulfilled=8
        snapshot.quests[900].objectives[1].finished=true
        snapshot.quests[900].objectivesComplete=true
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("live completion selects sourced turn-in",row().destination and row().destination.x==.4 and not row().hunt)
        snapshot.identity={product="forever",build="1.60.1.other",locale="enUS"}
        p.SemanticData.Ensure(snapshot,ctx);p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("build mismatch never inherits reference positions",not row().destination)

        snapshot.identity=identity;snapshot.quests[900].objectivesComplete=false
        snapshot.quests[900].objectives[1]={text="2/8 Field Token",type="item",numFulfilled=2,numRequired=8,finished=false}
        p.SemanticData.Ensure(snapshot,ctx);snapshot.generation=10
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        local copied=p.Schema.Clone(snapshot)
        check("detached view of current snapshot retains semantic guidance",p.SemanticGuidance.Apply(copied,900,nil).x==.2)
        policy.avoids[1426]=true;p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("avoid applies to sourced locations",not row().destination)
        policy.avoids[1426]=nil
        ctx.position.mapID=999
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("cross-map source target retains honest travel-unknown guidance",row().destination and row().destination.mapID==1426
            and row().semantic.costBasis=="travel distance unknown")
        ctx.position.mapID=1426
        local calls=0
        p.Terrain={BeginAreaEstimate=function(_,_,candidate)
            calls=calls+1
            return {Step=function()
                return {status="modeled",meters=candidate.x==.2 and 300 or 50}
            end}
        end}
        local q=p.Optimizer.BeginAreas({{area=area,distance=10},{area=far,distance=600}},{},identity,ctx.position)
        local best,done
        for _=1,10 do best,done=q:Step();if done then break end end
        check("bounded optimizer compares usable modeled costs rather than straight distance",done and best.area==far and calls==2)
        check("modeled area selection reports actual comparison work",best.comparison.attempted==2 and best.costBasis=="modeled walking distance")
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        policy.avoids[1426]=true;p.SemanticGuidance.Observe(snapshot,ctx,policy)
        for _=1,20 do p.SemanticGuidance.Step() end
        check("cancelled comparison cannot resurrect an avoided target",not row().destination)
        policy.avoids[1426]=nil
        p.Terrain={AreaRevision=function() return "disconnected" end,BeginAreaEstimate=function()
            return {Step=function() return {status="no-known-path"} end}
        end}
        ctx.destinations[900]={mapID=1426,x=.6,y=.3,scope="current-map-quest-poi"}
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        for _=1,20 do p.SemanticGuidance.Step() end
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("unmodeled source areas retain usable live marker",row().destination.x==.6
            and row().semantic.locationSource=="runtime-quest-marker")
        p.Terrain=nil;ctx.destinations[900]=nil
        local carried=0
        p.Context.ItemCount=function() return carried end
        quest.requiredItems={{itemID=11,methods={{kind="loot",targetKind="object",targetID=12,name="Supply crate",
            areas={{id="supplies",mapID=1426,x=.5,y=.3}}}}}}
        ctx.inventory=nil;p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("missing required source item selects its acquisition method",row().semantic and row().semantic.prerequisiteItemID==11)
        carried=1;ctx.inventory=nil;p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("carrying source item resumes live objective without completing it",not row().semantic.prerequisiteItemID and row().step.state=="active")
        quest.requiredItems=nil
        quest.objectives[1].sourceItemID=11;ctx.inventory=nil
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("carried use-item is not acquired again",not row().destination
            and row().referenceAdvice.lines[1]:find("Use carried item",1,true)~=nil)
        quest.objectives[1].sourceItemID=nil
        quest.objectives[1].runtimeObjectiveIndex=1
        quest.extraObjectives={{objectiveIndex=1,text="Ask the scout about the token",methods={{kind="talk",targetKind="npc",targetID=20,name="Scout",
            dispositionKnown=true,friendlyToFaction="A",areas={{id="scout",mapID=1426,x=.191,y=.3}}}}}}
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("indexed source hint requires matching semantic and live slot",row().semantic and row().semantic.method=="talk")
        quest.objectives[1].runtimeObjectiveIndex=2
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("changed source ordering withholds incorrectly indexed hint",row().semantic.method=="drop")
        quest.extraObjectives=nil
        local originalType=quest.objectives[1].type
        quest.objectives[1].type="kill-credit";quest.objectives[1].name="Field Beast"
        snapshot.quests[900].objectives[1].type="monster";snapshot.quests[900].objectives[1].text="2/8 Field Beast slain"
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("kill credit matches uniquely identified live monster objective",p.SemanticGuidance.Status().matched==1)
        quest.objectives[1].type=originalType;quest.objectives[1].name="Field Token"
        snapshot.quests[900].objectives[1].type="item";snapshot.quests[900].objectives[1].text="2/8 Field Token"
        RikUIQuestCorpusCatalog.revision="changed"
        p.SemanticData.Ensure(snapshot,ctx)
        check("hot corpus replacement cannot retain stale semantic rows",not p.SemanticData.Quest(identity,900)
            and p.SemanticData.Status().reason=="corpus revision changed; restart required")
        dofile("src/modules/questplanner/quest-semantic-data.lua")
        RikUIQuestCorpusCatalog.revision="shards"
        RikUIQuestCorpusCatalog.partitions[7]={addons={"RikUIQuestCorpus_P00007_S001","RikUIQuestCorpus_P00007_S002"}}
        local shardLoads={}
        C_AddOns.LoadAddOn=function(name)
            shardLoads[#shardLoads+1]=name
            if name:match("_S002$") then assert(p.SemanticData.Register(7,"shards",{[900]={base=quest,variants={}},[901]={base=sharedQuest,variants={}}})) end
            return true
        end
        snapshot.origin="imported-untrusted";p.SemanticData.Ensure(snapshot,ctx);p.SemanticData.Step()
        check("untrusted import cannot trigger companion loading",#shardLoads==0)
        snapshot.origin=nil;p.SemanticData.Ensure(snapshot,ctx);p.SemanticData.Step()
        check("first shard stays unpublished and bounded to one load",#shardLoads==1 and not p.SemanticData.Quest(identity,900))
        p.SemanticData.Step()
        check("final sequential shard publishes full partition",#shardLoads==2 and p.SemanticData.Quest(identity,900)==quest)
        ctx.attributes.faction="Unknown";p.SemanticData.Ensure(snapshot,ctx)
        check("unknown faction cannot fall back to base persona",not p.SemanticData.Quest(identity,900))


    end)
    RikUI,RikUIQuestCorpusCatalog,C_AddOns=old,oldCatalog,oldAddons
    check("semantic guidance suite completes",ok,err)
end

