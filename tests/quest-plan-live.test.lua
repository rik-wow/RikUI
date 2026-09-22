-- Ordinary corpus/controller/widgets under guarded live API stubs. Native acceptance is separate.
return function(check)
    local env=require("wow_stub")
    local restoreWidgets=require("widget_stub").install()
    local names={"RikUI","RikUIQuestCorpusCatalog","C_AddOns","C_Map","C_Item","C_Container","C_QuestLog","C_Reputation","C_SpellBook",
        "GetTime","debugprofilestop","UnitGUID","UnitClass","UnitRace","UnitFactionGroup","UnitLevel","UnitXP","UnitXPMax",
        "GetMoney","GetNumGroupMembers","UnitHealthMax","UnitIsAFK","UnitIsDeadOrGhost","UnitAffectingCombat","GetQuestLogRewardXP",
        "IsPlayerSpell","GetProfessions","GetProfessionInfo","GetFactionInfoByID","NUM_BAG_SLOTS","GetInventoryItemID","CanMerchantRepair","GetRepairAllCost","GetNumTrainerServices","GetTrainerServiceInfo","GetTrainerServiceCost"}
    local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
    local ok,err=pcall(function()
        env.frames,env.inCombat={},false
        RikUI={CharDB={},Media={Font=function() end},Combat={Queue=function(fn) fn() end},
            Changed=function() end,Print=function() end}
        RikUI["Secret"]={IsSecret=function() return false end,Read=function(fn,...) return pcall(fn,...) end}
        local now,x,counts=1,.1,{[9]=2,[55]=1}
        GetTime=function() return now end;debugprofilestop=function() return os.clock()*1000 end
        UnitGUID=function() return "Player-test" end
        UnitClass=function() return "Warrior","WARRIOR",1 end
        UnitRace=function() return "Dwarf","Dwarf",3 end
        UnitFactionGroup=function() return "Alliance" end
        UnitLevel=function() return 10 end;UnitXP=function() return 0 end;UnitXPMax=function() return 1000 end
        GetMoney=function() return 100 end;GetNumGroupMembers=function() return 0 end
        UnitHealthMax=function() return 300 end;UnitIsAFK=function() return false end
        UnitIsDeadOrGhost=function() return false end;UnitAffectingCombat=function() return false end
        NUM_BAG_SLOTS=4
        GetInventoryItemID=function() return nil end
        C_Container={GetContainerNumSlots=function(bag) return bag==0 and 6 or 4 end,
            GetContainerNumFreeSlots=function(bag) return bag==0 and 6-((counts[9] or 0)>0 and 1 or 0)-((counts[55] or 0)>0 and 1 or 0) or 4,0 end,
            GetContainerItemInfo=function(bag,slot)
                local id=bag==0 and ({9,55})[slot]
                if id and (counts[id] or 0)>0 then return {itemID=id,stackCount=counts[id],quality=0,isLocked=false,hasNoValue=false} end
            end,
            GetContainerItemQuestInfo=function() return {isQuestItem=false} end}
        C_Item={GetItemCount=function(id) return (counts[id] or 0)+100 end, -- Aggregate deliberately disagrees with bag contents.
            GetItemInfo=function(id) return "Item",nil,0,nil,nil,nil,nil,20,nil,nil,1 end}
        C_Map={GetBestMapForUnit=function() return 1426 end,
            GetPlayerMapPosition=function() return {GetXY=function() return x,.3 end} end,
            GetMapWorldSize=function() return 1000,1000 end}
        C_QuestLog={IsQuestFlaggedCompleted=function() return false end,
            GetMaxNumQuestsCanAccept=function() return 20 end,GetQuestsOnMap=function() return {} end}
        GetQuestLogRewardXP=nil;IsPlayerSpell=function() return false end
        C_Reputation={GetFactionDataByID=function() end}
        C_SpellBook={IsSpellKnown=function() return false end}
        GetProfessions=function() return nil,2,nil,nil,5 end
        GetProfessionInfo=function(index) return "Profession","icon",75,150,nil,nil,index==2 and 164 or 185 end
        GetFactionInfoByID=function() return "Faction","description",3,-3000,0,-1000 end
        for _,name in ipairs({"schema","objectives","optimizer","area-optimizer","context","steps","step-bindings",
            "observed-steps","semantic-data","semantic-guidance","recommendations","guidance","preferences","plan-state","plan-graph",
            "plan-transitions","plan-learning","plan-rewards","plan-costs","plan-search","transfer","bag-scan","plan-services","plan-context","plan-observer","plan-runtime","controller","plan-controls","view","commands"}) do
            dofile("src/modules/questplanner/quest-"..name..".lua")
        end
        local p=RikUI.QuestPlanner
        p.enabled=true;p.Request=function() end
        p.Navigation={Open=function() end}
        p.Journal={Dialog=function() end,TurnedIn=function() return false end}
        local invalidations=0
        p.Terrain={Guidance=function() end,Invalidate=function() invalidations=invalidations+1 end,Status=function() return {status="unavailable"} end}
        local identity={product="forever",build="1.60.1.69913",locale="enUS"}
        local method={kind="drop",targetKind="npc",targetID=7,name="Field Beast",areas={{id="field",mapID=1426,x=.2,y=.3}}}
        local record={id=900,title="Field collection",objectives={{id="item:9",type="item",targetID=9,name="Field Token",required=4,
            sourceItemID=55,methods={method}}},planning={version=1,requirements={op="all",args={}}},
            starts={{kind="start",targetKind="npc",targetID=10,name="Keeper",areas={{id="hub",mapID=1426,x=.1,y=.3}}}},
            ends={{kind="finish",targetKind="npc",targetID=10,name="Keeper",areas={{id="hub",mapID=1426,x=.1,y=.3}}}},
            reward={level=10,baseXP=1000},eligibility={questLevel=10},provenance={revision="test"}}
        local future=p.Schema.Clone(record);future.id=901;future.title="Follow-up"
        future.planning.requirements={op="completed",questID=900};future.reward.baseXP=2000
        RikUIQuestCorpusCatalog={version=1,identity=identity,revision="fixture",partitionSize=128,
            partitions={[7]="RikUIQuestCorpus_P00007"},planning={version=1,maps={[1426]={900,901}},links={[900]={901}},quests={
                [900]={semantic=true,minLevel=1},[901]={semantic=true,minLevel=1}}}}
        C_AddOns={LoadAddOn=function()
            assert(p.SemanticData.Register(7,"fixture",{[900]={base=record,variants={}},[901]={base=future,variants={}}}))
            return true
        end}
        local snapshot={identity=identity,order={900},generation=1,reportedCount=1,observedCount=1,coverage="log-complete",
            quests={[900]={id=900,title=record.title,level=10,failed=false,objectivesComplete=false,
                objectives={{text="2/4 Field Token",type="item",numFulfilled=2,numRequired=4,finished=false}}}}}
        p.GetSnapshot=function() return p.Schema.Clone(snapshot),{state="current"} end
        p.PeekSnapshot=p.GetSnapshot
        p.Controller.Start()
        local function update(reason)
            p.BagScan.Invalidate();for _=1,24 do p.BagScan.Step(32) end
            snapshot.generation=snapshot.generation+1
            p.Controller.Update(snapshot,{state="current"},reason or "fixture")
        end
        update()
        check("cold normal path has immediate live fallback",p.Controller.Get().selected~=nil)
        p.Controller.Step();update("source loaded")
        for _=1,2000 do p.Controller.Step() end
        local model=p.Controller.Get()
        check("normal source path invokes adaptive search",model.adaptive and model.metrics and model.metrics.transitions>0,model.planStatus)
        check("source action retains live objective and source item",model.selected and model.selected.questID==900
            and model.selected.planAction and model.selected.planAction.objectiveKey=="item:9",model.selected and model.selected.detail)
        check("future source record enters normal plan",#(model.upNext or {})>0)
        check("guarded capabilities reach normal context",p.Controller.Context().bagFree==20 and p.Controller.Context().partySize==1)
        local before=invalidations
        now=now+10;counts[9]=3;snapshot.quests[900].objectives[1].text="3/4 Field Token"
        snapshot.quests[900].objectives[1].numFulfilled=3
        update("partial progress")
        check("partial counts keep terrain",invalidations==before and p.Controller.Get().selected.questID==900)
        counts[55]=0;update("source item lost")
        for _=1,100 do p.Controller.Step() end
        model=p.Controller.Get()
        check("missing source item does not retain invalid simulated action",not model.selected.planAction,
            tostring(model.selected.planAction and model.selected.planAction.id)..":"..tostring(p.Controller.Context().inventory[55])..":"..tostring(p.Controller.Context().inventoryExact))
        counts[55]=1
        p.Command("preferences")
        check("real preferences window opens",p.PlanControls.Window and p.PlanControls.Window:IsShown())
        local function clickLabel(text)
            for _,frame in pairs(env.frames) do
                if frame.label and frame.label.GetText and frame.label:GetText()==text then
                    local handler=frame:GetScript("OnClick")
                    if handler then handler(frame);return true end
                end
            end
            return false
        end
        for _,flavor in ipairs(p.Preferences.Flavors()) do
            local current=p.Controller.Policy().flavor
            check("style widget click "..flavor,clickLabel((current==flavor and "Selected: " or "")..flavor))
            update("flavor")
            for _=1,300 do p.Controller.Step() end
            check("style reaches production planner "..flavor,p.Controller.Policy().flavor==flavor and p.Controller.Get().flavor==flavor)
        end
        p.Command("defer 900");update("defer")
        check("defer is distinct from permanent skip",p.Controller.Policy().defers[900] and not p.Controller.Policy().skips[900])
        p.View.Open()
        local found
        for _,row in ipairs(p.View.Window.rows) do if row.questID==900 then found=row end end
        check("deferred quest has real restore control",found and found.defer.label:GetText()=="Resume")
        found.defer:GetScript("OnClick")(found.defer);update("restore")
        check("defer restore widget resumes quest",not p.Controller.Policy().defers[900])
        p.Command("decline-exploration");update("decline")
        check("exploration decline persists without flavor changes",p.Controller.Policy().explorationMinutes==0
            and RikUI.CharDB.questPolicy.explorationMinutes==0 and p.Controller.Policy().flavor=="Challenge")
        local policy=p.Controller.Policy();p.Controller.Restore()
        check("settings restore without route jobs",p.Controller.Policy().flavor==policy.flavor
            and p.Controller.Policy().explorationMinutes==0 and not RikUI.CharDB.questPolicy.search)
        local ctx=p.Context.Read(snapshot)
        p.PlanContext.Enrich(ctx,snapshot,{[1]={planning={requirements={op="all",args={
            {op="skill",id=164,value=75},{op="reputationMin",id=10,value=-1500},{op="spell",id=9,value=false}}}}}})
        check("sparse profession index and legacy negative reputation",ctx.skills[164]==75 and ctx.reputation[10]==-1000)
        check("forbidden spell observes literal false",ctx.spells[9]==false)
        C_Container.GetContainerNumFreeSlots=function() return 10,nil end
        p.BagScan.Invalidate();for _=1,24 do p.BagScan.Step(32) end
        p.PlanContext.Enrich(ctx,snapshot,{})
        check("nil bag family remains unknown",ctx.bagFree==nil)
        -- Restore complete bag APIs after the deliberate unavailable-family case.
        C_Container.GetContainerNumFreeSlots=function(bag) return bag==0 and 4 or 4,0 end
        counts[9],counts[55]=4,1;snapshot.quests[900].objectives[1].numFulfilled=4
        snapshot.quests[900].objectives[1].finished=true;snapshot.quests[900].objectivesComplete=true
        update("objective completed")
        for _=1,2000 do p.Controller.Step() end
        check("completion promptly advances to turn-in",p.Controller.Get().selected.kind=="turnin")
        local trace=p.PlanRuntime.Replay()
        local packet,why=p.Transfer.EncodePlan(trace)
        check("normal decision exports complete replay evidence",packet~=nil,why)
        local replay=p.Transfer.DecodePlan(packet)
        check("plan replay keeps inputs and candidates",replay and replay.stateKey==trace.stateKey
            and #replay.candidateIDs==#trace.candidateIDs and replay.constraints.flavor=="Challenge")
        check("imported rollout cannot be used as live truth",replay and not replay.state.fresh
            and p.PlanTransitions.Check(p.Controller.Get().selected.planAction,replay.state,p.Controller.Policy())==false)
        check("plan export is deterministic",p.Transfer.EncodePlan(trace)==packet)
        check("damaged plan rejected",not p.Transfer.DecodePlan(packet:sub(1,-2).."z"))

        local source={searchRevision=p.PlanSearch.REVISION,corpusRevision="fixture",identity=identity}
        local function same(a,b)
            if type(a)~=type(b) then return false end
            if type(a)~="table" then return a==b end
            for k,v in pairs(a) do if not same(v,b[k]) then return false end end
            for k in pairs(b) do if a[k]==nil then return false end end
            return true
        end
        local liveLearning=p.PlanLearning.Export()
        local rerun=p.PlanRuntime.RerunReplay(replay,source)
        check("R20 imported production trace exactly reexecutes",rerun.status=="match",rerun.reason or rerun.phase)
        check("R20 repeat deterministic and live learning unchanged",same(rerun,p.PlanRuntime.RerunReplay(replay,source))
            and same(liveLearning,p.PlanLearning.Export()) and replay.state.fresh==false)
        local wrong=p.Schema.Clone(replay);wrong.source.corpusRevision="stale"
        check("R20 stale source rejected",p.PlanRuntime.RerunReplay(wrong,source).reason=="source_mismatch")
        wrong=p.Schema.Clone(replay);wrong.searchActions={}
        local mismatch=p.PlanRuntime.RerunReplay(wrong,source)
        check("R20 expectations cannot influence solver",mismatch.status=="mismatch" and mismatch.phase=="search")
        wrong=p.Schema.Clone(replay);wrong.graph.actions[2]=p.Schema.Clone(wrong.graph.actions[1]);wrong.candidateIDs[2]=wrong.candidateIDs[1]
        check("R20 duplicate graph rejected",p.PlanRuntime.RerunReplay(wrong,source).reason=="invalid_graph")
        local oldBegin=p.PlanSearch.Begin;p.PlanSearch.Begin=function() error("deliberate offline failure") end
        local failedReplay=p.PlanRuntime.RerunReplay(replay,source);p.PlanSearch.Begin=oldBegin
        check("R20 failed replay restores live learning",failedReplay.reason=="replay_error" and same(liveLearning,p.PlanLearning.Export()))

        local beforeTeleport=invalidations
        now=now+1;x=.9
        p.Controller.Step()
        check("teleport invalidates pending guidance",invalidations>beforeTeleport)
        update("teleport")
        for _=1,2000 do p.Controller.Step() end
        check("new result uses teleported origin",p.PlanRuntime.Replay().state.position.x==.9)

        -- Only observed, optional service offers are admitted.
        CanMerchantRepair=function() return true end;GetRepairAllCost=function() return 25,true end
        GetNumTrainerServices=function() return 1 end
        GetTrainerServiceInfo=function() return "New rank",nil,"available" end
        GetTrainerServiceCost=function() return 10,false end
        local serviceCtx=p.Controller.Context()
        serviceCtx.inventory[77]=1
        serviceCtx.bagItems={{bag=0,slot=3,itemID=77,count=1,generic=true,quality=0,isLocked=false,hasNoValue=false}}
        check("closed interactions do not invent services",#p.PlanServices.Read(serviceCtx,{})==0)
        p.PlanServices.OnEvent("MERCHANT_SHOW");p.PlanServices.OnEvent("TRAINER_SHOW")
        local offers=p.PlanServices.Read(serviceCtx,{})
        check("observed vendor repair and training offers",#offers==3)
        local vendor;for _,offer in ipairs(offers) do if offer.id=="observed-vendor" then vendor=offer end end
        check("vendor frees observed generic stack only",vendor and vendor.freesSlots==1 and vendor.conditionalService)
        check("quest-required item excluded from sale plan",#p.PlanServices.Read(serviceCtx,{[1]={requiredItems={{itemID=77}}}})==2)
        serviceCtx.money=0
        check("unaffordable repair/training excluded",#p.PlanServices.Read(serviceCtx,{})==1)
        p.PlanServices.OnEvent("MERCHANT_CLOSED");p.PlanServices.OnEvent("TRAINER_CLOSED")
        check("closed services immediately disappear",#p.PlanServices.Read(serviceCtx,{})==0)


        -- Frequent refreshes must not shorten witnessed work episodes.
        p.PlanObserver.Reset();p.PlanLearning.Reset("estimates")
        local timedAction={id="timed:kill",questID=900,kind="objective",method="kill",liveIndex=1,target={id=7},zoneID=1426}
        local timedSnapshot={identity=identity,quests={[900]={objectives={{numFulfilled=0}}}}}
        local timedCtx={observedAt=100,characterKey="Player-test",attributes={class=1,level=10},partySize=1,
            position={mapID=1426,x=.2,y=.3},targetNPC=7,inCombat=true,equipmentKey="1"}
        local timedPolicy={paused=false}
        now=100;p.PlanObserver.Observe(timedSnapshot,timedCtx,timedPolicy,timedAction)
        for tick=1,100 do
            now=100+tick/10;timedCtx=p.Schema.Clone(timedCtx);timedCtx.observedAt=now
            if tick==100 then timedSnapshot.quests[900].objectives[1].numFulfilled=1 end
            p.PlanObserver.Observe(timedSnapshot,timedCtx,timedPolicy,timedAction)
        end
        local timingKey=p.PlanCosts.Context(timedAction,{identity=identity,class=1,level=10,partySize=1,equipmentKey="1"})
        check("R18 refresh frequency does not shrink combat time",math.abs(p.PlanLearning.Estimate("combat",timingKey).mean-10)<.0001)
        timedCtx.inCombat=false;p.PlanObserver.OnEvent("PLAYER_REGEN_ENABLED")
        p.PlanObserver.Feedback("waiting")
        for tick=1,20 do now=110+tick;timedCtx.observedAt=now;p.PlanObserver.Observe(timedSnapshot,timedCtx,timedPolicy,timedAction) end
        p.PlanObserver.Feedback("waiting");p.PlanObserver.Feedback("recovery")
        now=135;timedCtx.observedAt=now;p.PlanObserver.Observe(timedSnapshot,timedCtx,timedPolicy,timedAction)
        p.PlanObserver.Feedback("recovery")
        timedCtx.inCombat=true;p.PlanObserver.OnEvent("PLAYER_REGEN_DISABLED")
        now=145;timedCtx.observedAt=now;timedSnapshot.quests[900].objectives[1].numFulfilled=2
        p.PlanObserver.Observe(timedSnapshot,timedCtx,timedPolicy,timedAction)
        check("R18 explicit waiting and recovery require confirmed progress",p.PlanLearning.Estimate("waiting",timingKey).mean==20
            and p.PlanLearning.Estimate("recovery",timingKey).mean==5)
        local sampleCount=p.PlanLearning.Estimate("combat",timingKey).samples
        timedCtx.afk=true;now=150;timedCtx.observedAt=now;p.PlanObserver.Observe(timedSnapshot,timedCtx,timedPolicy,timedAction)
        timedCtx.afk=false;timedCtx.inCombat=false;now=155;timedCtx.observedAt=now;p.PlanObserver.Observe(timedSnapshot,timedCtx,timedPolicy,timedAction)
        now=175;timedCtx.observedAt=now;timedSnapshot.quests[900].objectives[1].numFulfilled=3
        p.PlanObserver.Observe(timedSnapshot,timedCtx,timedPolicy,timedAction)
        check("R18 stationary and AFK time not invented combat/waiting",p.PlanLearning.Estimate("combat",timingKey).samples==sampleCount
            and p.PlanLearning.Estimate("waiting",timingKey).samples==1)
        p.PlanObserver.OnEvent("PLAYER_ENTERING_WORLD")
        check("R18 reload/world boundary discards pending attribution",not p.PlanObserver.Status().active)

        -- Real persistence codec, adversarial maximum histories and bounded samples.
        dofile("src/persistence/codec.lua")
        p.PlanLearning.Bind(identity,"Player-test")
        for id=1,300 do p.PlanLearning.Completion(id,true);p.PlanLearning.Visit(id) end
        for id=1,140 do
            local key=string.rep("x",120)..id
            for sample=1,40 do p.PlanLearning.Observe("collection",key,10+sample/7,1) end
            p.PlanLearning.Failure(key,true)
        end
        local memory=p.PlanLearning.Export(true)
        local encoded=RikUI.Codec.Encode(memory)
        check("durable memory leaves room for other settings",encoded and #encoded<=6000,encoded and #encoded)
        local full=p.PlanLearning.Export()
        check("session calibration independently bounded",#full.order<=128 and #full.completed<=256 and #full.recent<=12)
        p.PlanLearning.Reset()
        check("bounded memory survives settings codec reload",p.PlanLearning.Restore(RikUI.Codec.Decode(encoded)))
        check("completion memory retained with identity",p.PlanLearning.State().completed[300]==true)
        local before=p.PlanLearning.Export();p.PlanLearning.Bind(identity,"different-character")
        check("cross-character memory rejected",not p.PlanLearning.Restore(before))
        print("Adaptive normal controller, six style widgets, resource loss, completion, teleport, services, replay and persistence verified")
    end)
    for _,name in ipairs(names) do _G[name]=saved[name] end
    restoreWidgets()
    check("adaptive live suite completes",ok,err)
end
