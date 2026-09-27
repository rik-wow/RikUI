-- Ordinary corpus/controller/widgets under guarded live API stubs. Native acceptance is separate.
return function(check)
    local env=require("wow_stub")
    local restoreWidgets=require("widget_stub").install()
    local names={"RikUI","RikUIDB","RikUIQuestCorpusCatalog","C_AddOns","C_Map","C_Item","C_Container","C_QuestLog","C_Reputation","C_SpellBook",
        "GetTime","debugprofilestop","UnitGUID","UnitClass","UnitRace","UnitFactionGroup","UnitLevel","UnitXP","UnitXPMax",
        "GetMoney","GetNumGroupMembers","UnitHealthMax","UnitIsAFK","UnitIsDeadOrGhost","UnitAffectingCombat","GetQuestLogRewardXP",
        "IsPlayerSpell","GetProfessions","GetProfessionInfo","GetFactionInfoByID","NUM_BAG_SLOTS","GetInventoryItemID","CanMerchantRepair","GetRepairAllCost","GetNumTrainerServices","GetTrainerServiceInfo","GetTrainerServiceCost","Settings"}
    local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
    local ok,err=xpcall(function()
        env.frames,env.inCombat={},false
        RikUI={CharDB={},Media={Font=function() end},Combat={Queue=function(fn) fn() end},
            Changed=function() end,Print=function() end,GetModuleState=function() return "enabled" end,GetModuleRequirements=function() return {} end,ProfileNeedsReload=function() return false end,ProfileSelectionNeedsReload=function() return false end}
        assert(loadfile("src/ui/media.lua"))("RikUI",{})
        dofile("src/ui/motion.lua");dofile("src/ui/skin.lua");dofile("src/ui/scroll.lua")
        RikUI["Secret"]={IsSecret=function() return false end,Read=function(fn,...) return pcall(fn,...) end}
        local now,x,counts=1,.1,{[9]=2,[55]=1}
        local mapID=1426
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
        C_Map={GetBestMapForUnit=function() return mapID end,
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
            "observed-steps","semantic-data","waypoints","objective-guide","semantic-guidance","recommendations","guidance","preferences","plan-state","plan-graph",
            "plan-transitions","plan-learning","plan-rewards","plan-costs","plan-search","transfer","bag-scan","plan-services","plan-travel","plan-context","plan-xp","plan-observer","roads","road-travel","travel-estimate","plan-runtime","controller","plan-controls","view","window-layout","window","commands"}) do
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
            partitions={[7]={pages={"P00007_S001"}}},planning={version=1,maps={[1426]={900,901}},links={[900]={901}},quests={
                [900]={semantic=true,minLevel=1},[901]={semantic=true,minLevel=1}}}}
        C_AddOns={LoadAddOn=function() error("embedded corpus never loads addons") end}
        assert(p.SemanticData.Page("P00007_S001",function()
            assert(p.SemanticData.Register(7,"fixture",{[900]={base=record,variants={}},[901]={base=future,variants={}}}))
        end))
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
        local coldTrace=p.PlanRuntime.Replay()
        local coldReplay=coldTrace and p.PlanRuntime.RerunReplay(coldTrace,coldTrace.source)
        check("R20 cold displayed fallback has decision-only evidence",coldTrace and coldTrace.version==3
            and coldTrace.kind=="fallback" and coldTrace.displayed.selected.questID==p.Controller.Get().selected.questID
            and not coldTrace.searchWork and not p.PlanRuntime.ReplaySearch())
        check("R20 cold fallback replay does not claim solver execution",coldReplay and coldReplay.status=="match"
            and coldReplay.replayKind=="fallback" and not coldReplay.searchActions,coldReplay and coldReplay.reason)
        p.Controller.Step();update("source loaded")
        for _=1,2000 do p.Controller.Step() end
        local model=p.Controller.Get()
        check("normal source path invokes adaptive search",model.adaptive and model.metrics and model.metrics.transitions>0,model.planStatus)
        check("source action retains live objective and source item",model.selected and model.selected.questID==900
            and model.selected.planAction and model.selected.planAction.objectiveKey=="item:9",model.selected and model.selected.detail)
        check("future source record enters normal plan",#(model.upNext or {})>0)
        check("guarded capabilities reach normal context",p.Controller.Context().bagFree==20 and p.Controller.Context().partySize==1)
        local committedID=model.actionID
        local switchesBefore=#p.PlanRuntime.Switches()
        for _,nextMap in ipairs({1455,1426,1455,1426}) do
            mapID=nextMap;now=now+2
            p.Controller.Step() -- Observe the boundary before draining the queued refresh.
            p.Controller.Invalidate(true)
            check("invalidated display hides stale selection",p.Controller.Get().selected==nil and p.PlanRuntime.Replay()==nil)
            update("city boundary and quest-event refresh")
            check("refresh retains the committed action while searching",p.Controller.Get().actionID==committedID
                and p.PlanRuntime.Replay().kind=="continuity")
            for _=1,2000 do p.Controller.Step() end
            local trace=p.PlanRuntime.Replay()
            check("new search reprices the pre-invalidation incumbent",trace and trace.environment
                and trace.environment.previousID==committedID and #trace.environment.incumbent>0)
            check("refresh does not manufacture a new switch",p.Controller.Get().actionID==committedID
                and #p.PlanRuntime.Switches()==switchesBefore)
        end
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
        RikUI.Modules={questplanner=p};RikUI.Profile={modules={}}
        RikUI.DB={profiles={Default={}}};RikUI.CharDB.profile="Default"
        RikUI.GetProfileNames=function() return {"Default"} end
        RikUI.RegisterEvent=function() end;RikUI.RegisterCommand=function() end;RikUI.HasCommand=function() return false end
        Settings=nil
        for _,file in ipairs({"options-widgets","options-controls","options","options-view"}) do
            dofile("src/configuration/options/"..file..".lua")
        end
        p.Command("preferences")
        check("preferences open the shared RikUI config page",p.PlanControls.Window and p.PlanControls.Window:IsShown()
            and p.PlanControls.Window.pages[p.PlanControls.Window.current].id=="questplanner")
        local config=p.PlanControls.Window
        local questPage=config.pages[config.current]
        local function setting(key)
            for _,row in ipairs(questPage.list.rows) do if row.spec.key==key then return row end end
        end
        check("planner preferences stay inside a bounded scrolling page",questPage.scroll.range>0
            and questPage.scroll.view.clips==true and questPage.group=="Gameplay")
        for index,flavor in ipairs(p.Preferences.Flavors()) do
            env.click(setting("flavor").widget)
            local choice=setting("flavor").widget.list.buttons[index]
            check("style widget offers "..flavor,choice.entry.value==flavor)
            env.click(choice)
            update("flavor")
            for _=1,300 do p.Controller.Step() end
            check("style reaches production planner "..flavor,p.Controller.Policy().flavor==flavor and p.Controller.Get().flavor==flavor)
        end
        p.Controller.Preference("rewardTarget",77)
        RikUI.Options.Commit(setting("rewardTargetInput"),"invalid")
        env.click(setting("applyRewardTarget").widget)
        check("invalid reward target preserves saved preference",p.Controller.Policy().rewardTarget==77)
        RikUI.Options.Commit(setting("rewardTargetInput"),"")
        env.click(setting("applyRewardTarget").widget)
        check("empty reward target explicitly clears preference",p.Controller.Policy().rewardTarget==nil)
        p.Command("defer 900");update("defer")
        check("defer is distinct from permanent skip",p.Controller.Policy().defers[900] and not p.Controller.Policy().skips[900])
        p.View.Open()
        local found
        for _,row in ipairs(p.View.Window.rows) do if row.questID==900 then found=row end end
        env.click(found)
        check("deferred quest has real restore control",p.View.Window.selection.defer.label:GetText()=="Resume quest")
        env.click(p.View.Window.selection.defer);update("restore")
        check("defer restore widget resumes quest",not p.Controller.Policy().defers[900])
        -- Exercise objective controls through the actual quest window and controller.
        record.objectives[1].sourceItemID=nil
        method.areas[1].spawns={{.2,.3},{.24,.3}}
        record.objectives[2]={id="monster:88",type="monster",name="Camp Scout",targetID=88,
            methods={{kind="kill",targetKind="npc",targetID=88,name="Camp Scout",
                areas={{id="scout",mapID=1426,x=.6,y=.3}}}}}
        snapshot.quests[900].objectives[2]={text="0/1 Camp Scout slain",type="monster",numRequired=1,numFulfilled=0,finished=false}
        update("objective guide controls");p.View.Refresh()
        local panel=p.View.Window.selection
        check("quest window exposes objective selection and exact location count",
            panel.objective:IsShown() and panel.body:GetText():find("2 known locations",1,true)
            and panel.body:GetText():find("Camp Scout",1,true))
        env.click(panel.location);update("alternate source location")
        check("next location control routes to the alternate exact spawn",
            p.Controller.Get().manual and p.Controller.Get().selected.destination.x==.24)
        env.click(panel.objective);env.click(panel.route);update("choose second objective")
        check("objective control selects that objective in production guidance",
            p.Controller.Get().selected.step.active.objectiveID=="monster:88"
            and p.Controller.Get().selected.destination.x==.6)
        snapshot.quests[900].objectives[2].finished=true
        update("selected objective completes")
        check("manual quest guide automatically resumes another unfinished objective",
            p.Controller.Get().selected.step.active.objectiveID=="item:9")
        record.objectives[2]=nil;snapshot.quests[900].objectives[2]=nil
        record.objectives[1].sourceItemID=55;method.areas[1].spawns=nil
        p.Controller.Select(nil);update("restore automatic planning")
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
        local completedAction=p.Controller.Get().actionID
        p.Controller.Invalidate(true)
        update("objective completed")
        for _=1,2000 do p.Controller.Step() end
        check("completion promptly advances to turn-in",p.Controller.Get().selected.kind=="turnin")
        local switch=p.PlanRuntime.Switches()
        switch=switch[#switch]
        check("completed action switch keeps its real predecessor",switch and switch.from
            and switch.from.actionID==completedAction and switch.to.actionID==p.Controller.Get().actionID
            and switch.reason=="completed")
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
        check("R20 travel model is captured without function",replay.environment.travelModel and replay.environment.travel==nil)
        local wrong=p.Schema.Clone(replay);wrong.environment.travelModel.indexRevision="changed"
        check("R20 changed travel index rejects replay",p.PlanRuntime.RerunReplay(wrong,source).reason=="source_mismatch")
        wrong=p.Schema.Clone(replay);wrong.source.corpusRevision="stale"
        check("R20 stale source rejected",p.PlanRuntime.RerunReplay(wrong,source).reason=="source_mismatch")
        wrong=p.Schema.Clone(replay);wrong.searchActions={}
        local mismatch=p.PlanRuntime.RerunReplay(wrong,source)
        check("R20 expectations cannot influence solver",mismatch.status=="mismatch" and mismatch.phase=="search")
        wrong=p.Schema.Clone(replay);wrong.graph.actions[2]=p.Schema.Clone(wrong.graph.actions[1]);wrong.candidateIDs[2]=wrong.candidateIDs[1]
        check("R20 duplicate graph rejected",p.PlanRuntime.RerunReplay(wrong,source).reason=="invalid_graph")
        local oldBegin=p.PlanSearch.Begin;p.PlanSearch.Begin=function() error("deliberate offline failure") end
        local failedReplay=p.PlanRuntime.RerunReplay(replay,source);p.PlanSearch.Begin=oldBegin
        check("R20 failed replay restores live learning",failedReplay.reason=="replay_error" and same(liveLearning,p.PlanLearning.Export()))

        check("R20 ready trace captures actual displayed decision",replay.version==3 and replay.kind=="search"
            and same(replay.displayed,p.PlanRuntime.Displayed(p.Controller.Get()))
            and same(rerun.displayed,replay.displayed))
        local legacy=p.Schema.Clone(replay);legacy.version=2;legacy.displayInputs=nil;legacy.displayed=nil;legacy.kind=nil
        local legacyPacket=assert(p.Transfer.EncodePlan(legacy))
        local legacyDecoded=assert(p.Transfer.DecodePlan(legacyPacket))
        check("R20 v2 packet still imports without invented display evidence",legacyDecoded.version==2
            and legacyDecoded.state.fresh==false
            and p.PlanRuntime.RerunReplay(legacyDecoded,source).reason=="display_evidence_unavailable")
        local state=p.Schema.Clone(replay.state);state.fresh=true
        local graph=p.Schema.Clone(replay.graph);graph.byID={};graph.byQuest={}
        for _,action in ipairs(graph.actions) do
            graph.byID[action.id]=action;graph.byQuest[action.questID]=graph.byQuest[action.questID] or {}
            table.insert(graph.byQuest[action.questID],action)
        end
        local replayCtx=p.Controller.Context()
        local replayObserved=p.Guidance.Observed(snapshot,replayCtx,p.Controller.Policy(),900,false,p.Controller.Get().selected)
        local replayPolicy=p.Schema.Clone(replay.constraints)
        local function annotate(raw)
            raw.replayGraph=replay.graph;raw.replayState=state;raw.replayEnvironment=replay.environment
            raw.replayLearning=replay.learning;raw.candidateIDs=replay.candidateIDs;raw.stateKey=replay.stateKey
            return raw
        end
        local function replayDisplayed(raw,ctx,pref,initial)
            local model=p.PlanRuntime.Result(raw,replayObserved,ctx or replayCtx,pref or replayPolicy,nil,initial or state)
            local trace=assert(p.PlanRuntime.Replay())
            local packet,problem=p.Transfer.EncodePlan(trace);assert(packet,problem)
            local imported=assert(p.Transfer.DecodePlan(packet))
            local out=p.PlanRuntime.RerunReplay(imported,source)
            check("R20 displayed model agrees with captured identity",same(trace.displayed,p.PlanRuntime.Displayed(model)))
            check("R20 displayed decision reexecutes "..trace.kind,out.status=="match"
                and same(out.displayed,trace.displayed),out.reason or out.phase)
            check("R20 displayed replay preserves imported freshness",imported.state.fresh==false)
            return model,trace,imported,out
        end
        local readySearch=p.PlanRuntime.ReplaySearch()
        local beforeLearning=p.PlanLearning.Export()
        local boundaries={}
        local ran,boundaryError=p.PlanLearning.WithSnapshot(replay.learning,function()
            local search=assert(p.PlanSearch.Begin(graph,state,replayPolicy,replay.environment))
            boundaries[1]=search:Peek()
            assert(not search:Step(1));boundaries[2]=search:Peek()
            for _=1,1000 do
                assert(not search:Step(1),"fixture must expose a refining incumbent")
                local preview=search:Peek()
                if #preview.actions>0 then
                    boundaries[3]=preview
                    assert(not search:Step(1));boundaries[4]=search:Peek()
                    break
                end
            end
            search:Cancel()
        end)
        assert(ran,boundaryError)
        check("R20 fixture exposes zero one and incumbent work boundaries",#boundaries==4
            and boundaries[1].metrics.work==0 and boundaries[2].metrics.work==1
            and boundaries[3].metrics.work>1 and #boundaries[3].actions>0
            and boundaries[4].metrics.work==boundaries[3].metrics.work+1)
        for index,raw in ipairs(boundaries) do
            local model,trace,imported,out=replayDisplayed(annotate(raw))
            check("R20 refining exact work boundary "..index,trace.searchStatus=="refining"
                and out.metrics and out.metrics.work==raw.metrics.work)
            local shifted=p.Schema.Clone(imported);shifted.searchWork=shifted.searchWork+1
            check("R20 inconsistent work receipt rejected "..index,
                p.PlanRuntime.RerunReplay(shifted,source).reason=="invalid_search_boundary")
            local premature=p.Schema.Clone(imported);premature.searchStatus="ready"
            check("R20 refining trace cannot claim terminal work "..index,
                p.PlanRuntime.RerunReplay(premature,source).reason=="search_boundary_mismatch")
            if index<=2 then
                check("R20 empty solver preview replays actual live fallback "..index,#trace.searchActions==0
                    and model.selected and model.selected.questID==900 and not model.actionID)
            end
        end
        check("R20 partial replays leave live learning and completed evidence unchanged",
            same(beforeLearning,p.PlanLearning.Export()) and same(readySearch,p.PlanRuntime.ReplaySearch()))

        local action=assert(graph.byID[replay.displayed.actionID],"Displayed action must have source graph evidence")
        local retainedModel,retainedTrace=replayDisplayed({actions={action},status="refining",decisionKind="continuity",
            reason="Continue while future options are updated"})
        check("R20 continuity rechecks the current action without solver claims",retainedTrace.kind=="continuity"
            and retainedModel.actionID==action.id and not retainedTrace.searchWork and not retainedTrace.graph
            and same(readySearch,p.PlanRuntime.ReplaySearch()))
        local fallbackModel,fallbackTrace,fallbackImport=replayDisplayed({actions={},status="refining",decisionKind="fallback",
            reason="Refining future quest options"})
        check("R20 fallback identity is independent of last searched action",fallbackModel.selected.questID==900
            and fallbackModel.selected.kind=="turnin" and not fallbackModel.actionID and #fallbackTrace.actions==0)
        wrong=p.Schema.Clone(fallbackImport);wrong.displayed.selected.questID=901
        check("R20 changing displayed fallback expectation is detected",p.PlanRuntime.RerunReplay(wrong,source).phase=="display")
        local blockedCtx=p.Schema.Clone(replayCtx);blockedCtx.failures={[action.id]=2}
        local blockedModel,blockedTrace=replayDisplayed({actions={},status="refining",decisionKind="fallback",
            reason="Refining future quest options"},blockedCtx)
        check("R20 failure-suppressed fallback is an actual replayed decision",blockedModel.status=="unavailable"
            and not blockedModel.selected and blockedTrace.displayInputs.previous.id==action.id
            and blockedTrace.displayInputs.previousFailures==2)
        local conflictPolicy=p.Schema.Clone(replayPolicy);conflictPolicy.pins[900]=true;conflictPolicy.skips[900]=true
        local conflictModel=replayDisplayed({actions={},status="refining",decisionKind="fallback",
            reason="Refining future quest options"},replayCtx,conflictPolicy)
        check("R20 pin conflict uses the same live fallback projection",conflictModel.status=="constraint-conflict"
            and not conflictModel.selected)
        check("R20 decision-only replay leaves learning unchanged",same(beforeLearning,p.PlanLearning.Export()))
        p.Controller.Invalidate(false)
        check("R20 invalidated display does not expose old decision as current",p.PlanRuntime.Replay()==nil
            and same(readySearch,p.PlanRuntime.ReplaySearch()))
        update("R20 replay fixture restored");for _=1,2000 do p.Controller.Step() end
        check("R20 normal publication restores current decision evidence",p.PlanRuntime.Replay()
            and same(p.PlanRuntime.Replay().displayed,p.PlanRuntime.Displayed(p.Controller.Get())))


        local unavailableAction=p.Controller.Get().actionID
        p.Command("unavailable");p.Command("unavailable");update("S09 unavailable giver")
        for _=1,2000 do p.Controller.Step() end
        local unavailable=p.Controller.Get()
        check("S09 exhausted interaction does not return through fallback",unavailable.status=="unavailable"
            and not unavailable.selected and p.PlanLearning.State().failures[unavailableAction]==2,unavailable.status)
        p.Command("retry-action");update("S09 explicit retry")
        for _=1,2000 do p.Controller.Step() end
        check("S09 explicit retry restores feasible guidance",p.Controller.Get().selected and p.Controller.Get().selected.questID==900
            and not p.PlanLearning.State().failures[unavailableAction])
        snapshot.order={900,999};snapshot.reportedCount=2;snapshot.observedCount=2
        snapshot.quests[999]={id=999,title="New server expedition",level=10,failed=false,objectivesComplete=false,
            objectives={{text="Read the new server expedition instructions",type="event",numFulfilled=0,numRequired=1,finished=false}}}
        update("S13 new server quest")
        for _=1,2000 do p.Controller.Step() end
        local unknownRow
        for _,row in ipairs(p.Controller.Quests()) do if row.questID==999 then unknownRow=row end end
        check("S13 missing provider preserves live quest instructions",unknownRow and unknownRow.title=="New server expedition"
            and type(unknownRow.detail)=="string" and #unknownRow.detail>0)
        check("S13 production graph reports live-only coverage",p.Controller.Get().coverage and p.Controller.Get().coverage.liveOnly>=1)
        local originalX,originalPOIs=x,C_QuestLog.GetQuestsOnMap
        x=.5
        C_QuestLog.GetQuestsOnMap=function()
            return {{questID=999,mapID=1426,x=.51,y=.3,isQuestStart=false,isMapIndicatorQuest=false,inProgress=true}}
        end
        p.Controller.Step();update("live-only quest location")
        for _=1,2000 do p.Controller.Step() end
        local localModel=p.Controller.Get()
        check("coverage normal controller selects live-only nearby quest",localModel.localGuidance
            and localModel.selected.questID==999 and localModel.actionID=="999:live:objective")
        p.View.Open()
        check("coverage real widget displays limitation",p.View.Window.summary.arrowHint:GetText()=="Partial quest data")
        check("coverage details name missing quest and omit comparison",p.View.Window.instructions:GetText():find("New server expedition",1,true)
            and p.View.Window.instructions:GetText():find("XP and completion time are not compared",1,true))
        local trace=p.PlanRuntime.Replay()
        local rerun=p.PlanRuntime.RerunReplay(trace,trace.source)
        check("coverage normal controller export replays selection",rerun.status=="match",rerun.reason or rerun.phase)
        p.Controller.Invalidate(true);update("live-only refresh")
        for _=1,2000 do p.Controller.Step() end
        check("coverage controller retains live incumbent across invalidation",p.Controller.Get().actionID==localModel.actionID)
        snapshot.quests[999].objectivesComplete=true
        snapshot.quests[999].objectives[1].finished=true
        snapshot.quests[999].objectives[1].numFulfilled=1
        update("live-only objective completion")
        for _=1,2000 do p.Controller.Step() end
        check("coverage real progress advances live-only turnin",p.Controller.Get().actionID=="999:live:turnin"
            and p.Controller.Get().selected.kind=="turnin")
        check("coverage navigation never invents completion history",not p.PlanLearning.State().completed[999])
        x=originalX;p.Controller.Step();update("modeled nearest with partial coverage")
        for _=1,2000 do p.Controller.Step() end
        local modeledLocal=p.Controller.Get()
        check("coverage nearby modeled work competes with live-only work",modeledLocal.localGuidance and modeledLocal.selected.questID==900)
        for refresh=1,3 do
            p.Controller.Invalidate(true);update("modeled local refresh")
            check("coverage modeled incumbent stable before search "..refresh,p.Controller.Get().actionID==modeledLocal.actionID)
            for _=1,2000 do p.Controller.Step() end
            check("coverage modeled incumbent stable after search "..refresh,p.Controller.Get().actionID==modeledLocal.actionID)
        end
        local modeledSource
        for _,action in ipairs(p.PlanRuntime.ReplaySearch().graph.actions) do
            if action.questID==900 and action.kind=="turnin" and not action.liveFallback then modeledSource=action;break end
        end
        assert(modeledSource)
        p.PlanLearning.Failure(modeledSource.id,true);p.PlanLearning.Failure(modeledSource.id,true)
        update("modeled incumbent becomes unavailable")
        check("coverage cached source rechecks new failures immediately",p.Controller.Get().selected.questID==999)
        local pendingTrace=p.PlanRuntime.Replay()
        check("coverage cached-source decision exactly replays",p.PlanRuntime.RerunReplay(pendingTrace,pendingTrace.source).status=="match")
        p.PlanLearning.Failure(modeledSource.id,false)
        C_QuestLog.GetQuestsOnMap=originalPOIs
        snapshot.order={900};snapshot.reportedCount=1;snapshot.observedCount=1;snapshot.quests[999]=nil
        p.Controller.Step();update("S13 fixture restored");for _=1,2000 do p.Controller.Step() end

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

        -- S19 two virtual hours,24 map changes,6 actual module reloads and cancelled old jobs.
        RikUI.CharDB.questPolicy=p.Preferences.Normalize({flavor="Explorer",readingSeconds=0,
            skips={[98761]=true},defers={[98762]=true},avoids={[98763]=true}})
        p.Controller.Invalidate(false);p.Controller.Restore();p.PlanLearning.Bind(identity,"Player-test")
        local function keys(t) local n=0;for _ in pairs(t or {}) do n=n+1 end;return n end
        local requestPending=false
        p.Request=function() requestPending=true end
        for cycle=1,24 do
            mapID=cycle%2==0 and 1426 or 1427;now=now+300;x=.40+(cycle%7)*.002
            for n=1,40 do
                local id=cycle*40+n
                p.PlanLearning.Observe("combat","long-session:"..id,10+n/10,1)
                p.PlanLearning.Activity("kill");p.PlanLearning.Completion(id,true);p.PlanLearning.Visit(id);p.PlanLearning.VisitPlace("place:"..id)
            end
            update("S19 map transition");p.Controller.Step()
            if cycle%4==0 then
                local retired=p.Controller;retired.Invalidate(false)
                p.PlanRuntime.OnEvent("PLAYER_LOGOUT")
                local packet=assert(RikUI.Codec.Encode(RikUI.CharDB.questPlanMemory))
                check("S19 durable packet bound "..cycle,#packet<=6000)
                local memory=RikUI.Codec.Decode(packet)
                for _,name in ipairs({"plan-learning","plan-runtime","controller"}) do dofile("src/modules/questplanner/quest-"..name..".lua") end
                RikUI.CharDB.questPlanMemory=memory
                p.Controller.Start();update("S19 module reload");retired.Step()
            end
            for _=1,2000 do
                p.Controller.Step()
                if requestPending then
                    requestPending=false;p.Controller.Update(snapshot,{state="current"},"S19 queued live refresh")
                end
            end
            local ctx=p.Controller.Context();local view=p.Controller.Get();local trace=p.PlanRuntime.Replay()
            check("S19 latest map and generation "..cycle,ctx.position.mapID==mapID and view.status~="updating"
                and (not trace or trace.state.position.mapID==mapID and trace.state.generation==snapshot.generation),
                tostring(ctx.position.mapID)..":"..tostring(view.status)..":"..tostring(view.adaptive)..":"..tostring(trace and trace.state.position.mapID)..":"..tostring(trace and trace.state.generation)..":"..snapshot.generation)
            local restored=p.Controller.Policy()
            check("S19 durable explicit preferences "..cycle,restored.flavor=="Explorer" and restored.skips[98761]
                and restored.defers[98762] and restored.avoids[98763])
            local learned=p.PlanLearning.Export();local bounded=#learned.order<=128 and #learned.completed<=256
                and #learned.recent<=12 and keys(learned.visits)<=128 and keys(learned.places)<=128 and keys(learned.failures)<=128
            for _,model in pairs(learned.models) do bounded=bounded and #model.values<=32 end
            check("S19 bounded state after churn "..cycle,bounded and #learned.order>0)
        end

        RikUIDB={planSwitches={}}
        local logCtx={observedAt=123,position={mapID=1426,x=.5,y=.6}}
        local old={actionID="a",score=1,selected={title="Old quest"}}
        local new={actionID="b",score=2,incumbentScore=1.5,switchReason="better",selected={title="New quest"}}
        p.PlanRuntime.RecordSwitch(old,new,logCtx)
        local switches=p.PlanRuntime.Switches()
        check("published switch keeps cause, repriced scores and position",#switches==1 and switches[1].reason=="better"
            and switches[1].from.actionID=="a" and switches[1].to.title=="New quest"
            and switches[1].fromScore==1.5 and switches[1].toScore==2 and switches[1].position.mapID==1426)
        p.PlanRuntime.RecordSwitch(new,new,logCtx)
        check("repeated publication does not create a switch",#p.PlanRuntime.Switches()==1)
        for i=1,60 do new.actionID="b"..i;p.PlanRuntime.RecordSwitch(old,new,logCtx) end
        check("switch log retains only last 50 entries",#p.PlanRuntime.Switches()==50 and p.PlanRuntime.Switches()[1].to.actionID=="b11")
        switches=p.PlanRuntime.Switches();switches[1].reason="changed"
        check("switch log reader cannot mutate saved data",p.PlanRuntime.Switches()[1].reason=="better")
        local printed={};RikUI.Print=function(_,message) printed[#printed+1]=message end
        p.Command("switches")
        check("switch command prints last ten with reasons",#printed==10 and printed[1]:find("b51",1,true) and printed[10]:find("better",1,true))
        printed={};p.Command("help")
        check("quest help exposes switch log and replay export",table.concat(printed," "):find("plan-export",1,true)
            and table.concat(printed," "):find("switches",1,true))
        print("Adaptive normal controller, six style widgets, resource loss, completion, teleport, services, replay and persistence verified")
    end,debug.traceback)
    for _,name in ipairs(names) do _G[name]=saved[name] end
    restoreWidgets()
    check("adaptive live suite completes",ok,err)
end
