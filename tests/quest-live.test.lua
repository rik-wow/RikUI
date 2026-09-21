-- Real controller and widgets under guarded API replays; native rendering remains separate.
return function(check)
    local env=require("wow_stub")
    local restore=require("widget_stub").install()
    local names={"RikUI","RikUIDB","RikUICharDB","C_QuestLog","C_Map","C_Item","GetBuildInfo","GetLocale",
        "C_GossipInfo","UnitRace","UnitFactionGroup","UnitLevel","UnitXP","UnitXPMax","GetQuestID","GetTitleText","GetRewardXP",
        "GetQuestLogRewardXP","UnitGUID","debugprofilestop","QuestMapFrame_OpenToQuestDetails","WorldMapFrame","GetPlayerFacing","UnitPosition"}
    local saved={}
    for _,name in ipairs(names) do saved[name]=_G[name] end
    local added={}
    for _,name in ipairs({"QUEST_ACCEPTED","QUEST_REMOVED","QUEST_TURNED_IN","QUEST_DETAIL","QUEST_PROGRESS","QUEST_COMPLETE","QUEST_FINISHED","GOSSIP_SHOW","GOSSIP_CLOSED","WAYPOINT_UPDATE"}) do
        added[name]=env.KNOWN_EVENTS[name] or false; env.KNOWN_EVENTS[name]=true
    end
    local selected,complete,dialogID,opened=10,true,10,nil
    local ok,reason=pcall(function()
        env.frames,env.timers,env.printed,env.inCombat={},{},{},false
        RikUI,RikUIDB,RikUICharDB=nil,nil,nil
        GetBuildInfo=function() return "1.60.1","69913","date",16001 end
        GetLocale=function() return "enUS" end
        UnitRace=function() return "Dwarf","Dwarf",3 end
        UnitFactionGroup=function() return "Alliance","Alliance" end
        UnitLevel=function() return 7 end; UnitXP=function() return 100 end; UnitXPMax=function() return 1000 end
        UnitGUID=function() return "Creature-0-1-0-1-123-00000" end
        GetQuestID=function() return dialogID end; GetTitleText=function() return "A real fixture" end
        GetRewardXP=function() return 120 end; GetQuestLogRewardXP=function() return 120 end
        C_Map={GetBestMapForUnit=function() return 1426 end,GetPlayerMapPosition=function()
            return {GetXY=function() return .45,.5 end} end}
        C_QuestLog={
            GetNumQuestLogEntries=function() return 2,2 end,
            GetInfo=function(index) return {questID=index==1 and 10 or 11,title=index==1 and "A quest" or "Another quest",level=7} end,
            GetQuestObjectives=function() return {{text="Wolves: 1/2",type="monster",numFulfilled=1,numRequired=2,finished=false}} end,
            IsComplete=function(id) return id==10 and complete end,IsFailed=function() return false end,
            GetSelectedQuest=function() return selected end,IsQuestFlaggedCompleted=function() return false end,
            GetMaxNumQuestsCanAccept=function() return 40 end,
            GetNextWaypoint=function(id) return 1426,id==10 and .5 or .6,.5 end,
            GetNextWaypointText=function() return "Quest waypoint" end,
        }
        QuestMapFrame_OpenToQuestDetails=function(id) opened=id end
        dofile("tests/load_addon.lua").Core()
        assert(loadfile("src/ui/media.lua"))("RikUI",{})
        for _,name in ipairs({"schema","objectives","evidence","corpus","reader","transfer","eligibility","elevators","travel","actions","simulation","optimizer",
            "context","gossip","journal","dataset","targets","guidance","controller","nav-geometry","view","navigation","transfer-view","commands"}) do
            dofile("src/modules/questplanner/quest-"..name..".lua")
        end
        dofile("src/modules/questplanner/questplanner.lua")
        env.fire("ADDON_LOADED","RikUI"); env.fire("PLAYER_LOGIN"); env.flushTimers()
        local p=RikUI.QuestPlanner
        local model=p.Controller.Get()
        check("reader records initial snapshot independently",p.Journal.Export().entries[1].event=="initial-observation")
        check("live unknown geometry presents observations without ETA",model.status=="observed" and not model.calculated and model.seconds==nil)
        check("ready turn-in is the useful observed choice",model.selected.questID==10 and model.selected.destination.mapID==1426)
        check("context reads real capacity and selected contextual reward",p.Controller.Context().attributes.logCapacity==40
            and p.Controller.Context().rewards[10].xp==120 and p.Controller.Context().rewards[11]==nil)
        local savedModel=p.Controller.Get()
        local requested,invalidations=0,0
        local savedRequest=p.Request
        p.Request=function() requested=requested+1 end
        p.Terrain={Invalidate=function() invalidations=invalidations+1 end,
            Guidance=function() end,Status=function() return {status="unavailable"} end}
        assert(p.Controller.Set("arrow",true))
        check("arrow preference preserves selected guidance",p.Controller.Get().selected
            and p.Controller.Get().selected.questID==savedModel.selected.questID)
        check("arrow preference avoids terrain invalidation and replan",requested==0 and invalidations==0)
        assert(p.Controller.Set("arrow",true))
        assert(p.Controller.Set("paused",false))
        check("unchanged preferences do no work",requested==0 and invalidations==0)
        p.Request=savedRequest;p.Terrain=nil
        p.Controller.Set("arrow",false);env.flushTimers()
        local replans=p.Controller.Stats().replans
        env.fire("QUEST_LOG_UPDATE"); env.flushTimers()
        check("identical event does not replan",p.Controller.Stats().replans==replans)
        -- Regional fixture has explicit provenance; it is never installed as game data.
        local identity=p.Schema.Clone(p.GetSnapshot().identity)
        local source=p.Schema.Clone(identity); source.id="region-fixture"; source.authority="verified"
        local manifest=p.Schema.Clone(source)
        manifest.dataset,manifest.status,manifest.mode,manifest.assertions="fixture","active","snapshot",0
        manifest.revision,manifest.parser,manifest.sha256="v1","fixture",string.rep("b",64)
        manifest.uri,manifest.terms="fixture://original","Original test fixture"
        local raw={identity=identity,revision="fixture-v1",sources={manifest},facts={},edges={},
            nodes={{id="npc",zoneID=1426,mapID=1426,x=.45,y=.5}},
            actions={{id="turnin",questID=10,kind="turnin",node="npc",zoneID=1426,source=source,
                duration={combat=0,looting=0,interaction=3,downtime=0},risk=0,uncertainty=0}},
            anchors={{node="npc",npcID=123,mapID=1426,source=source}},
            bindings={{questID=11,source=source,objectives={{key="wolves",text="Wolves: #/#",type="monster",required=2}}}}}
        local region=assert(p.Dataset.New(raw))
        local ctx=p.Context.Read(p.GetSnapshot())
        local input=assert(region:Prepare(p.GetSnapshot(),(select(2,p.GetSnapshot())),ctx,{npcID=123}))
        check("compiled adapter binds complete matching objective signature",input.state.objectives[11].wolves==1)
        check("compiled adapter overrides only selected contextual XP",input.actions:Get("turnin").xp==120)
        check("coordinate proximity cannot establish graph anchor",not region:Prepare(p.GetSnapshot(),(select(2,p.GetSnapshot())),ctx,nil))
        local changed=p.GetSnapshot(); changed.quests[11].objectives[1].text="Bears: 1/2"
        local changedInput=assert(region:Prepare(changed,(select(2,p.GetSnapshot())),ctx,{npcID=123}))
        check("changed Forever objective text cannot inherit old mapping",changedInput.state.objectives[11]==nil)
        local numbered=p.Schema.Clone(raw)
        numbered.bindings[1].objectives[1].text="Section 2: #/#"
        local numberedRegion=assert(p.Dataset.New(numbered))
        local numericSnapshot=p.GetSnapshot();numericSnapshot.quests[11].objectives[1].text="Section 2: 1/2"
        local numberedInput=assert(numberedRegion:Prepare(numericSnapshot,(select(2,p.GetSnapshot())),ctx,{npcID=123}))
        check("objective binding retains authored numbers",numberedInput.state.objectives[11].wolves==1)
        numericSnapshot.quests[11].objectives[1].text="Section 3: 1/2"
        local otherNumber=assert(numberedRegion:Prepare(numericSnapshot,(select(2,p.GetSnapshot())),ctx,{npcID=123}))
        check("changed numbered goal cannot inherit binding",otherNumber.state.objectives[11]==nil)
        local longGoal=p.GetSnapshot()
        longGoal.quests[11].objectives[1].text=string.rep("x",250).."Section 2"
        local firstSignature=p.Guidance.Signature(longGoal,{state="current"},ctx)
        longGoal.quests[11].objectives[1].text=string.rep("x",250).."Section 3"
        check("material changes beyond display truncation invalidate planning",
            firstSignature~=p.Guidance.Signature(longGoal,{state="current"},ctx))
        local typeSignature=p.Guidance.Signature(longGoal,{state="current"},ctx)
        longGoal.quests[11].objectives[1].type="event"
        check("objective type is material",typeSignature~=p.Guidance.Signature(longGoal,{state="current"},ctx))
        local oversized=p.GetSnapshot();oversized.quests[11].objectives={}
        for index=1,32 do oversized.quests[11].objectives[index]={text=string.rep("z",2048),
            type="item",numFulfilled=0,numRequired=1,finished=false} end
        oversized.quests[10].objectives=p.Schema.Clone(oversized.quests[11].objectives)
        check("oversized signature refuses calculation explicitly",not p.Guidance.Signature(oversized,{state="current"},ctx))
        p.Controller.Update(oversized,{state="current"},"size fixture")
        check("signature size limit clears actionable state",p.Controller.Get().status=="unavailable"
            and p.Controller.Get().selected==nil and p.Controller.Get().detail:find("size limit",1,true))
        p.Controller.Update(p.GetSnapshot(),(select(2,p.GetSnapshot())),"fixture restored")
        raw.anchors[1].npcID=999
        check("compiled region detached from caller mutations",region:Prepare(p.GetSnapshot(),(select(2,p.GetSnapshot())),ctx,{npcID=123})~=nil)
        local wrong=p.Schema.Clone(raw); wrong.actions[1].source.id="missing"
        check("compiled actions require active source manifests",not p.Dataset.New(wrong))
        local untrusted=p.Schema.Clone(ctx); untrusted.origin="imported-untrusted"
        check("regional adapter rejects imported observations",not region:Prepare(p.GetSnapshot(),(select(2,p.GetSnapshot())),untrusted,{npcID=123}))
        local conflict=p.Guidance.Result({actions={},deferredPins={10}}, {},ctx,nil,nil,
            {pins={[10]=true},skips={[10]=true},avoids={}})
        check("fallback preserves pin conflict without duplicate deferred pins",conflict.status=="constraint-conflict"
            and conflict.selected==nil and #conflict.deferredPins==1)
        -- Map projection owns only its widgets and never creates a walking segment.
        local canvas=CreateFrame("Frame",nil,UIParent); canvas:SetSize(1000,600)
        WorldMapFrame=CreateFrame("Frame",nil,UIParent)
        WorldMapFrame.GetCanvas=function() return canvas end
        WorldMapFrame.GetMapID=function() return 1426 end
        WorldMapFrame:Show()
        local facing=0
        GetPlayerFacing=function() return facing end
        C_Map.GetMapWorldSize=function() return 2000,1000 end
        p.Command("arrow on"); env.flushTimers()
        for _,frame in ipairs(env.frames) do
            if frame.scripts.OnUpdate then env.runScript(frame,"OnUpdate",.2) end
        end
        local pin,arrow
        for _,frame in ipairs(env.frames) do
            if frame.parent==canvas and frame.questID==10 then pin=frame end
            if frame.label and frame.icon and frame:GetParent()==UIParent and frame:GetWidth()==240 then arrow=frame end
        end
        check("map marker projects observed destination on current canvas",pin and pin.point[4]==500 and pin.point[5]==-300)
        check("optional bearing is visible for readable same-map location",arrow and arrow:IsShown())
        local angle
        arrow.icon.SetRotation=function(_,value) angle=value end
        p.Navigation.Refresh()
        check("east target while facing north points right",math.abs(angle+math.pi/2)<.000001)
        facing=3*math.pi/2
        local oldPointCalls,pointCalls=canvas.GetWidth,0
        canvas.GetWidth=function(...) pointCalls=pointCalls+1;return oldPointCalls(...) end
        for _,driver in ipairs(env.frames) do
            if driver.scripts.OnUpdate then env.runScript(driver,"OnUpdate",.016) end
        end
        check("arrow observes facing on the next frame",math.abs(math.sin(angle))<.000001 and math.cos(angle)>.9999)
        check("fast arrow refresh does not redraw map geometry",pointCalls==0)
        canvas.GetWidth=oldPointCalls
        p.Navigation.Refresh()
        check("east target while facing east points forward",math.abs(math.sin(angle))<.000001 and math.cos(angle)>.9999)
        GetPlayerFacing=function() return nil end; p.Navigation.Refresh()
        check("unavailable orientation hides arrow",not arrow:IsShown())
        local originalFrame,recordedLines=CreateFrame,{}
        CreateFrame=function(...)
            local frame=originalFrame(...)
            frame.CreateLine=function()
                local line={}
                function line:Hide() self.shown=false end
                function line:Show() self.shown=true end
                function line:SetThickness(value) self.thickness=value end
                function line:SetColorTexture(...) self.color={...} end
                function line:SetStartPoint(...) self.first={...} end
                function line:SetEndPoint(...) self.last={...} end
                recordedLines[#recordedLines+1]=line
                return line
            end
            return frame
        end
        dofile("tests/quest-route-display-fixture.lua")(check,p,env,canvas,arrow)
        p.Terrain={Guidance=function() return {points={
            {mapID=1426,x=.45,y=.5},{mapID=1426,x=.45,y=.4},{mapID=1426,x=.5,y=.4}}} end}
        p.Navigation.Refresh()
        check("map draws supplied corridor segments without destination shortcut",#recordedLines==2 and recordedLines[1].first[3]==450
            and recordedLines[1].last[3]==450 and recordedLines[2].last[3]==500)
        local longRoute={points={}}
        for index=1,267 do longRoute.points[index]={mapID=1426,x=.2+index/1000,y=.4} end
        p.Terrain={Guidance=function() return longRoute end}
        p.Navigation.Refresh()
        check("long corridor allocates at most thirty-two lines per refresh",#recordedLines==34)
        for _=1,8 do p.Navigation.Refresh() end
        check("map includes full long corridor beyond old cap",#recordedLines==266
            and recordedLines[266].shown and math.abs(recordedLines[266].last[3]-467)<.00001)
        p.Terrain={Guidance=function() return {points={longRoute.points[1],longRoute.points[2]}} end}
        p.Navigation.Refresh()
        check("shorter route hides stale tail",recordedLines[1].shown and not recordedLines[266].shown)
        p.Terrain=nil; CreateFrame=originalFrame
        WorldMapFrame.GetMapID=function() return 999 end; p.Navigation.Refresh()
        check("map switch hides old terrain corridor",not recordedLines[1].shown and not recordedLines[2].shown)
        check("other map hides stale marker",not pin:IsShown())
        p.Command("arrow off"); env.flushTimers()
        p.Command("show")
        check("explicit window has quest rows and actual summary",p.View.Window:IsShown() and p.View.Window.rows[1].questID==10)
        dofile("tests/quest-status-fixture.lua")(check,p,env)
        env.click(p.View.Window.summary.pin)
        env.flushTimers()
        check("pin control persists bounded preference only",p.Controller.Policy().pins[10] and RikUI.CharDB.questPolicy.pins[10]
            and RikUI.CharDB.questplanner==nil)
        p.Command("map")
        check("map command delegates explicit quest opening",opened==10)
        p.Command("pause"); env.flushTimers()
        check("pause clears actionable guidance",p.Controller.Get().status=="paused" and p.Controller.Get().selected==nil)
        p.Command("resume"); env.flushTimers()
        env.fire("QUEST_COMPLETE"); env.flushTimers()
        for _=1,100 do p.Controller.Step() end
        model=p.Controller.Get()
        check("current turn-in dialog feeds real optimizer at interaction node",model.calculated and model.selected.questID==10 and model.xp==120)
        check("bounded controller exposes actual slice counters",p.Controller.Stats().frameCalls<=64)
        local originalResult,originalTime=p.Guidance.Result,GetTime
        local observedNow=GetTime()
        p.Guidance.Result=function(route,...)
            if route.actions[1] then route.actions[1].travel.path={{elevator={
                expiresAt=observedNow+20,departAt=observedNow+7,board=2}}} end
            return originalResult(route,...)
        end
        env.fire("QUEST_COMPLETE"); env.flushTimers()
        for _=1,100 do p.Controller.Step() end
        check("guidance retains earliest lift boarding deadline",p.Controller.Get().validUntil==observedNow+5)
        GetTime=function() return observedNow+6 end
        p.Controller.Step()
        check("missed lift boarding deadline cancels published plan",p.Controller.Get().status=="updating"
            and p.Controller.Get().selected==nil)
        p.Guidance.Result,GetTime=originalResult,originalTime
        env.flushTimers()
        env.fire("QUEST_COMPLETE"); env.flushTimers()
        env.fire("QUEST_FINISHED")
        p.Controller.Step()
        check("dialog close cancels before queued refresh and publication",p.Controller.Get().status=="updating")
        env.flushTimers()
        check("closed dialog loses zero-travel interaction feasibility",not p.Controller.Get().calculated)
        C_GossipInfo={GetAvailableQuests=function() return {{questID=98319,title="Offered fixture",questLevel=8}} end,
            GetActiveQuests=function() return {{questID=10,title="Active fixture",questLevel=7,isComplete=true}} end}
        p.Journal.Record("QUEST_COMPLETE",p.GetSnapshot())
        env.fire("GOSSIP_SHOW");env.flushTimers()
        local events=p.Journal.Export().entries
        local offered=events[#events]
        check("registered gossip event captures offers with snapshot identity",offered.event=="GOSSIP_SHOW"
            and offered.identity.build=="1.60.1.69913" and offered.offered[1].questID==98319)
        check("new gossip dialog clears previous quest interaction",p.Journal.Dialog()==nil)
        p.Journal.Record("QUEST_TURNED_IN",p.GetSnapshot(),10,0,5)
        events=p.Journal.Export().entries
        local turnin=events[#events]
        check("turnin keeps zero XP and event context without base XP",turnin.receivedXP==0 and turnin.receivedMoney==5
            and turnin.identity.build=="1.60.1.69913" and turnin.levelAtEvent==7
            and turnin.contextStatus.time.state=="observed" and turnin.baseXP==nil)
        local originalContext,originalInfo=p.Context.Read,C_QuestLog.GetInfo
        p.Context.Read=function() return nil end
        C_QuestLog.GetInfo=function(index) local row=originalInfo(index);row.level=8;return row end
        p.Refresh()
        check("log journal survives unavailable planning context",p.Journal.Status().lastChange=="quest details changed"
            and p.Journal.Status().changedQuests==2)
        p.Context.Read,C_QuestLog.GetInfo=originalContext,originalInfo;p.Refresh()
        p.Command("export")
        local wire=p.TransferView.Window.edit:GetText()
        local imported=assert(p.Transfer.Decode(wire))
        check("copy window exports session journal separately from settings",imported.origin=="imported-untrusted"
            and imported.journal.scope=="session-only" and #imported.journal.entries>0)
        p.Command("inspect")
        p.TransferView.Window.edit:SetText(wire)
        env.runScript(p.TransferView.Window.edit,"OnTextChanged")
        check("inspection cannot become active observations",p.GetSnapshot().origin~="imported-untrusted" and not p.Controller.Get().calculated)
        local holder=CreateFrame("Frame",nil,UIParent)
        check("inline respects collapsed tracker",p.View.RenderInline(holder,22,200,true)==0)
        check("inline respects available room",p.View.RenderInline(holder,22,60,false)==0)
        check("inline reserves bounded tracker height",p.View.RenderInline(holder,22,200,false)==116)
        local inline
        for _,candidate in ipairs(env.frames) do
            if candidate.parent==holder and candidate.arrowToggle then inline=candidate end
        end
        check("tracker exposes arrow state directly",inline and inline.arrowToggle.label:GetText()=="Arrow: off")
        assert(inline,"tracker arrow control missing")
        env.click(inline.arrowToggle);env.flushTimers()
        check("tracker arrow toggle persists on and refreshes both views",p.Controller.Policy().arrow
            and RikUI.CharDB.questPolicy.arrow and inline.arrowToggle.label:GetText()=="Arrow: on"
            and p.View.Window.arrow.label:GetText()=="Arrow: on")
        env.click(inline.arrowToggle);env.flushTimers()
        check("tracker arrow toggle can turn guidance off",not p.Controller.Policy().arrow
            and inline.arrowToggle.label:GetText()=="Arrow: off")
        local selectedFloor,clickedKey,automaticFloor=0,nil,nil
        p.Terrain={Guidance=function() end,Status=function() return {status="ready"} end,
            Floors=function() return {key="floor-fixture",selected=selectedFloor,automatic=automaticFloor,
            choices={{height=0,label="Lower floor"},{height=10,label="Upper floor"}}} end,
            SelectFloor=function(index,key) selectedFloor,clickedKey=index,key;return true end}
        p.View.Refresh()
        check("ambiguous destination exposes floor action in both views",inline.floor:IsShown()
            and p.View.Window.summary.floor:IsShown() and not inline.arrowHint:IsShown())
        env.click(inline.floor)
        check("tracker floor action selects lower floor with displayed destination key",
            selectedFloor==1 and clickedKey=="floor-fixture" and inline.floor.label:GetText()=="Lower floor")
        env.click(p.View.Window.summary.floor)
        check("details floor action synchronizes upper floor to tracker",
            selectedFloor==2 and inline.floor.label:GetText()=="Upper floor")
        env.click(inline.floor)
        check("floor action restores Auto after last option",selectedFloor==0 and inline.floor.label:GetText()=="Floor: Auto")
        p.Command("floor 2");check("floor command selects explicit alternative",selectedFloor==2)
        p.Command("floor auto");check("floor command restores automatic approach",selectedFloor==0)
        automaticFloor={label="Basement",basis="Quest text and reviewed model; inferred."};p.View.Refresh()
        check("automatic annotation is named in both floor controls",inline.floor.label:GetText()=="Auto: Basement"
            and p.View.Window.summary.floor.label:GetText()=="Auto: Basement")
        env.runScript(inline.floor,"OnEnter")
        local explainsInference=false
        for _,line in ipairs(GameTooltip.lines) do if line.text==automaticFloor.basis then explainsInference=true end end
        check("automatic floor tooltip explains inference",explainsInference)
        p.Terrain=nil;p.View.Refresh()
        check("unavailable floor alternatives restore ordinary guidance",not inline.floor:IsShown() and inline.arrowHint:IsShown())
        env.inCombat=true
        check("existing inline refresh avoids combat reparenting",pcall(p.View.RenderInline,holder,22,200,false))
        env.inCombat=false
        UnitPosition=function() return -5500,-700,400,0 end
        local world=p.Context.WorldPosition()
        check("readable position keeps unestablished vertical datum separate",world.x==-700 and world.z==-5500
            and world.rawReportedZ==400 and world.height==nil and world.verticalStatus=="unestablished" and world.mapID==0)
        UnitPosition=function() return -5500,env.SECRET,400,0 end
        check("secret world coordinate remains unavailable",p.Context.WorldPosition()==nil)
        UnitPosition=nil
        local captured=p.Controller.Context()
        C_QuestLog.GetNextWaypoint=function() return 1426,env.SECRET,.5 end
        local unknown=p.Context.Read(p.GetSnapshot())
        check("secret map coordinate is not normalized into a location",unknown.destinations[10]==nil)
        C_QuestLog.GetSelectedQuest=function() selected=selected==10 and 11 or 10; return selected end
        check("changing selected quest discards contextual XP",next(p.Context.Read(p.GetSnapshot()).rewards)==nil)
        C_QuestLog.GetNextWaypoint=nil
        p.Command("avoid 1426"); env.flushTimers()
        check("avoid retains uncertainty when location unavailable",p.Controller.Get().seconds==nil)
        for id=1,35 do p.Controller.Toggle("pins",id) end
        local count=0; for _ in pairs(p.Controller.Policy().pins) do count=count+1 end
        check("preference transport bound enforced",count<=32)
        for _=1,60 do p.Journal.Record("QUEST_COMPLETE") end
        check("session journal bounded with explicit dropped count",#p.Journal.Export().entries==48 and p.Journal.Export().dropped>0)
        check("raw observations never installed as compiled data",not p.Controller.Install(imported))
        local copy=p.Controller.Get(); copy.detail="modified"
        check("published view detached",p.Controller.Get().detail~="modified")
        p.enabled=false
        env.fire("QUEST_LOG_UPDATE"); env.flushTimers(); p.Controller.Step()
        check("disabled planner cannot publish from pending job",p.Controller.Get().detail~="modified")
        C_Map.GetPlayerMapPosition=function() return env.SECRET end
        check("secret map vector rejected",p.Context.Position()==nil)
        check("prior captured context remains detached",captured.destinations[10].x==.5)
    end)
    for name,value in pairs(added) do env.KNOWN_EVENTS[name]=value or nil end
    for _,name in ipairs(names) do _G[name]=saved[name] end
    restore()
    check("live guidance fixture completes",ok,reason)
end
