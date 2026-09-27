return function(check)
    local old,oldCatalog,oldAddons=RikUI,RikUIQuestCorpusCatalog,C_AddOns
    RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
    local ok,err=pcall(function()
        for _,name in ipairs({"schema","objectives","optimizer","area-optimizer","steps","step-bindings","observed-steps","semantic-data","waypoints","objective-guide","semantic-guidance","guidance"}) do
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
        RikUIQuestCorpusCatalog={version=1,identity=identity,revision="fixture",partitionSize=128,partitions={[7]={pages={"P00007_S001"}},[8]={pages={"P00008_S001"}}},counts={quests=1}}
        local sharedQuest=p.Schema.Clone(quest);sharedQuest.id=901;sharedQuest.title="Shared collection"
        sharedQuest.objectives[1].methods={{kind="drop",targetKind="npc",targetID=7,name="Field Beast",areas={far}}}
        local loads=0
        C_AddOns={LoadAddOn=function() error("embedded corpus never loads addons") end}
        assert(p.SemanticData.Page("P00007_S001",function()
            loads=loads+1
            assert(p.SemanticData.Register(7,"fixture",{[900]={base=quest,variants={}},[901]={base=sharedQuest,variants={}}}))
        end))
        assert(p.SemanticData.Page("P00008_S001",function() loads=loads+1 end))
        check("page registry rejects malformed keys and duplicates",not p.SemanticData.Page("bad",function() end) and not p.SemanticData.Page("P00008_S001",function() end))
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
        check("generic hunt binding names the objective rather than an arbitrary dropper",binding.navigation["item:9"].text=="Collect Field Token")
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
        local unknown=p.Optimizer.BeginAreas({{area={id="a"},distance=math.huge},
            {area={id="z"},distance=math.huge,questZone=true}},{},identity,ctx.position)
        local preferred
        for _=1,4 do preferred=unknown:Step() end
        check("unknown cross-zone travel prefers the quest region before lexical IDs",preferred and preferred.area.id=="z")
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
        check("objective location survives a same-map general quest marker",row().destination.x==.2
            and row().destination.scope=="semantic-objective-area")
        check("reference target keeps its own coordinates and objective identity",row().semantic.targetID==7
            and row().semantic.objectiveKey=="item:9" and row().semantic.authority=="reference")
        p.Terrain=nil
        local originalMap,areaID,farID=area.mapID,area.id,far.id
        area.mapID=1437;far.mapID=1437;area.id="wetlands-near";far.id="wetlands-far"
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        local unrelated=row()
        check("other-zone source keeps its own map instead of local marker coordinates", unrelated.destination.mapID==1437
            and unrelated.semantic.targetID==7 and unrelated.semantic.locationSource~="runtime-quest-marker"
            and unrelated.semantic.costBasis=="travel distance unknown")
        area.mapID=originalMap;far.mapID=originalMap;area.id=areaID;far.id=farID
        ctx.destinations[900]=nil
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
        -- Every live objective gets its own guide row and exact source locations.
        area.spawns={{.21,.3},{.23,.3}};area.spawnCount=2
        quest.objectives[2]={id="monster:21",type="monster",targetID=21,name="Scout",
            methods={{kind="kill",targetKind="npc",targetID=21,name="Scout",
                areas={{id="scouts",mapID=1426,x=.4,y=.3}}}}}
        snapshot.quests[900].objectives[2]={text="0/2 Scout slain",type="monster",numFulfilled=0,numRequired=2,finished=false}
        snapshot.quests[900].objectives[3]={text="Investigate the hidden cache",type="log",numFulfilled=0,numRequired=1,finished=false}
        p.SemanticGuidance.Observe(snapshot,ctx,policy)
        local entries=p.ObjectiveGuide.Rows(snapshot,900)
        check("guide retains every live objective including source gaps",#entries==3
            and entries[1].destination.x==.21 and entries[2].destination.x==.4 and not entries[3].destination)
        check("guide counts every exact source spawn without mutating the cluster",entries[1].locations==3 and area.x==.2)
        check("collection guide names both source and requested item",entries[1].instruction:find("Field Beast",1,true)
            and entries[1].instruction:find("Field Token",1,true))
        assert(p.ObjectiveGuide.Select(snapshot,900,1,true))
        p.SemanticGuidance.Observe(snapshot,ctx,policy,900)
        check("alternate exact spawn selection reaches live guidance",row().destination.x==.23)
        p.SemanticGuidance.Observe(snapshot,ctx,policy,900)
        check("chosen spawn survives observation refresh",row().destination.x==.23)
        assert(p.ObjectiveGuide.Select(snapshot,900,2))
        p.SemanticGuidance.Observe(snapshot,ctx,policy,900)
        check("explicit second objective drives step and waypoint together",row().destination.x==.4
            and row().step.active.objectiveID=="monster:21")
        check("unknown objective cannot borrow another objective waypoint",not p.ObjectiveGuide.Select(snapshot,900,3))
        snapshot.quests[900].objectives[2].finished=true
        p.SemanticGuidance.Observe(snapshot,ctx,policy,900)
        check("completion advances to remaining objective without arrival credit",row().destination.x==.21
            and row().step.active.objectiveID=="item:9")
        local stale=p.Schema.Clone(snapshot);stale.generation=9
        check("stale guide cannot select a current target",#p.ObjectiveGuide.Rows(stale,900)==0
            and not p.ObjectiveGuide.Select(stale,900,1))
        local imported=p.Schema.Clone(snapshot);imported.origin="imported-untrusted"
        check("untrusted guide never exposes actionable waypoints",#p.ObjectiveGuide.Rows(imported,900)==0)
        policy.avoids[1426]=true;p.SemanticGuidance.Observe(snapshot,ctx,policy)
        check("avoid removes objective controls and destinations",not p.ObjectiveGuide.Rows(snapshot,900)[1].destination)
        policy.avoids[1426]=nil
        area.spawns=nil;area.spawnCount=nil;quest.objectives[2]=nil
        snapshot.quests[900].objectives[2]=nil;snapshot.quests[900].objectives[3]=nil
        p.ObjectiveGuide.Clear();p.SemanticGuidance.Observe(snapshot,ctx,policy)
        RikUIQuestCorpusCatalog.revision="changed"
        p.SemanticData.Ensure(snapshot,ctx)
        check("hot corpus replacement cannot retain stale semantic rows",not p.SemanticData.Quest(identity,900)
            and p.SemanticData.Status().reason=="corpus revision changed; restart required")
        dofile("src/modules/questplanner/quest-semantic-data.lua")
        RikUIQuestCorpusCatalog.revision="shards"
        RikUIQuestCorpusCatalog.partitions[7]={pages={"P00007_S001","P00007_S002"}}
        local shardLoads={}
        for _,key in ipairs({"P00007_S001","P00007_S002"}) do
            assert(p.SemanticData.Page(key,function()
                shardLoads[#shardLoads+1]=key
                if key:match("_S002$") then assert(p.SemanticData.Register(7,"shards",{[900]={base=quest,variants={}},[901]={base=sharedQuest,variants={}}})) end
            end))
        end
        snapshot.origin="imported-untrusted";p.SemanticData.Ensure(snapshot,ctx);p.SemanticData.Step()
        check("untrusted import cannot trigger page loading",#shardLoads==0)
        snapshot.origin=nil;p.SemanticData.Ensure(snapshot,ctx);p.SemanticData.Step()
        check("first page stays unpublished and bounded to one run",#shardLoads==1 and not p.SemanticData.Quest(identity,900))
        p.SemanticData.Step()
        check("final sequential page publishes full partition",#shardLoads==2 and p.SemanticData.Quest(identity,900)==quest)
        ctx.attributes.faction="Unknown";p.SemanticData.Ensure(snapshot,ctx)
        check("unknown faction cannot fall back to base persona",not p.SemanticData.Quest(identity,900))
        ctx.attributes.faction="Alliance"
        RikUIQuestCorpusCatalog.partitions[9]={pages={"P00009_S001"}}
        snapshot.order={900,9*128+1};p.SemanticData.Ensure(snapshot,ctx);p.SemanticData.Step()
        check("missing page reports an install problem without stalling the queue",p.SemanticData.Status().reason:find("corpus page missing",1,true)
            and p.SemanticData.Status().queuedPartitions==0)
        dofile("src/modules/questplanner/quest-semantic-data.lua")
        RikUIQuestCorpusCatalog=nil
        snapshot.order={900};p.SemanticData.Ensure(snapshot,ctx);p.SemanticData.Step()
        check("absent catalog reports uninstalled data",p.SemanticData.Status().reason=="corpus data not installed")


    end)
    RikUI,RikUIQuestCorpusCatalog,C_AddOns=old,oldCatalog,oldAddons
    check("semantic guidance suite completes",ok,err)
end

