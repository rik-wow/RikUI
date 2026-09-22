-- Production event -> attribution/episode -> learning -> cost pipeline under guarded API fixtures.
-- Offline deterministic evidence; no claim about native event timing or gameplay.
return function(check)
    local names={"RikUI","C_CombatLog","CombatLogGetCurrentEventInfo","COMBATLOG_XPGAIN_FIRSTPERSON",
        "GetTime","GetQuestID","GetXPExhaustion","C_Timer"}
    local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
    local ok,err=pcall(function()
        RikUI={};RikUI["Secret"]={IsSecret=function() return false end,Read=pcall}
        local function module(name) dofile("src/modules/questplanner/quest-"..name..".lua") end
        module("schema")
        local p=RikUI.QuestPlanner
        local now,event,currentQuest,exhaustion=0,nil,900,nil
        GetTime=function() return now end;GetQuestID=function() return currentQuest end
        GetXPExhaustion=function() return exhaustion end
        p.Context={Call=function(fn,...) if type(fn)~="function" then return false end;return pcall(fn,...) end,
            Frame=function() end}
        for _,name in ipairs({"preferences","plan-transitions","plan-learning","plan-costs","plan-search","guidance","plan-xp","plan-observer","plan-runtime"}) do module(name) end
        COMBATLOG_XPGAIN_FIRSTPERSON="%s dies, you gain %d experience."
        C_CombatLog={GetCurrentEventInfo=function() return unpack(event,1,16) end,
            IsCombatLogRestricted=function() return false end}
        local S,T,L,C,X,O=p.Schema,p.PlanTransitions,p.PlanLearning,p.PlanCosts,p.PlanXP,p.PlanObserver
        local identity={product="forever",build="1.60.1.69913",locale="enUS"}
        local policy=p.Preferences.Normalize({flavor="Challenge",readingSeconds=0})
        policy.maxRisk=1;policy.maxSeconds=3600
        local action={id="900:objective:live:1",questID=900,kind="objective",objectiveKey="live:1",count=8,
            method="kill",activity="kill",objectiveType="kill",target={kind="npc",id=123},zoneID=1426,
            requiredParty=1,risk=.05,encounter={minLevel=12},preconditions={},consumes={},gains={},
            sharedCredit="npc:123",credits={{questID=901,key="live:1",count=8}}}
        local ctx,snapshot,state
        local function fresh()
            now=0;exhaustion=nil;policy.paused=false
            module("plan-runtime");L.Bind(identity,"Player-1");L.Reset();X.Reset();O.Reset()
            snapshot={identity=identity,generation=1,quests={}}
            for _,id in ipairs({900,901}) do snapshot.quests[id]={id=id,objectivesComplete=false,
                objectives={{type="monster",numFulfilled=0,numRequired=8,finished=false}}} end
            ctx={observedAt=0,characterKey="Player-1",petGUID="Pet-1",attributes={class=1,race=1,level=10,xp=0,xpMax=1000},
                partySize=1,equipmentKey="equipment-A",xpRested=false,targetNPC=123,inCombat=false,
                position={mapID=1426,x=.5,y=.5},destinations={},failures={},rewards={},inventory={}}
            state={fresh=true,identity=S.Clone(identity),sourceRevision="event-fixture",generation=1,class=1,race=1,
                classMask=1,raceMask=1,level=10,xp=0,xpMax=1000,partySize=1,equipmentKey=ctx.equipmentKey,xpRested=false,
                position=S.Clone(ctx.position),active={[900]=true,[901]=true},completed={[900]=false,[901]=false},
                failed={},progress={[900]={["live:1"]=8},[901]={["live:1"]=8}},
                objectiveInfo={[900]={["live:1"]={index=1}},[901]={["live:1"]={index=1}}},
                live={[900]={objectivesComplete=false},[901]={objectivesComplete=false}},simulatedWork={},conditionalObjectives={},
                inventory={},inventoryExact=true,bank={},equipped={},logComplete=true,logCount=2,logCapacity=20,
                bagFree=20,stackRoom={},itemMaxStack={},money=1000,capabilities={combat={maxHealth=300,level=10,group=1}},
                branchLocks={},applied={},elapsed=0,upperElapsed=0,xpGained=0,unknownXP=0,visited={},assumptions={}}
            p.PlanRuntime.Observe(snapshot,ctx,policy)
            local model=p.PlanRuntime.Result({actions={action},status="refining",decisionKind="continuity",stateKey="events",
                reason="Event fixture"},{{questID=900,kind="objective",title="Shared kill"}},ctx,policy,nil,state)
            assert(model.actionID==action.id,"event fixture needs a feasible published action")
            p.PlanRuntime.Observe(snapshot,ctx,policy)
        end
        local function observe(at,changes)
            now=at;ctx=S.Clone(ctx);ctx.observedAt=at
            for k,v in pairs(changes or {}) do ctx[k]=v end
            p.PlanRuntime.Observe(snapshot,ctx,policy)
        end
        local function dispatch(at,name,...)
            now=at;p.PlanRuntime.OnEvent(name,...)
        end
        local function combat(at,kind,guid,source,npcName)
            event={at,kind,false,source or "Player-1","Player",0,0,guid,npcName or "Wolf",0,0,20,0,0,20}
            dispatch(at,"COMBAT_LOG_EVENT_UNFILTERED")
        end
        local function message(at,line,xp,name)
            local args={string.format("%s dies, you gain %d experience.",name or "Wolf",xp or 100),"","","","","",0,0,"",0,line}
            dispatch(at,"CHAT_MSG_COMBAT_XP_GAIN",unpack(args,1,11))
        end
        local function progress()
            for _,id in ipairs({900,901}) do
                local row=snapshot.quests[id].objectives[1];row.numFulfilled=row.numFulfilled+1
                state.progress[id]["live:1"]=row.numRequired-row.numFulfilled
            end
        end
        local function kill(at,line,xp,source)
            local guid="Creature-0-1-1-1-123-"..line
            observe(at,{inCombat=true,targetNPC=123});dispatch(at,"PLAYER_REGEN_DISABLED")
            combat(at,"SWING_DAMAGE",guid,source)
            combat(at+5,"PARTY_KILL",guid,source);combat(at+5,"UNIT_DIED",guid,source)
            dispatch(at+5,"PLAYER_REGEN_ENABLED");message(at+5.1,line,xp)
            progress();observe(at+5.2,{inCombat=false});observe(at+7.2)
            return guid
        end
        local function near(a,b) return type(a)=="number" and math.abs(a-b)<.000001 end
        local function estimate()
            return assert(C.Estimate(action,state,policy,{travel=function() return {seconds=0,lower=0,upper=0,status="authored"} end}))
        end

        fresh();local key=C.Context(action,state)
        kill(10,1,100);kill(30,2,120,"Pet-1");kill(50,3,140)
        local xp=L.Estimate("combatXP",key);local timing=L.Estimate("combat",key)
        check("R06 runtime events produce one XP sample per unique shared kill",xp and xp.samples==3
            and near(xp.mean,120) and X.Status().confirmedXP==360)
        check("R13 runtime progress confirms three witnessed combat episodes",timing and timing.samples==3
            and near(timing.mean,5) and estimate().capabilityKnown==true)
        check("R06 runtime XP model prices remaining shared work once",near(C.Reward(action,state),600)
            and near(estimate().xp,600) and near(estimate().components.combat.seconds,25))
        local nextState,why=T.Apply(action,state,policy,estimate())
        check("R06 event-trained rollout does not duplicate shared objective XP",nextState
            and nextState.progress[900]["live:1"]==0 and nextState.progress[901]["live:1"]==0
            and near(nextState.xpGained,600),why)
        message(58,3,140);observe(61)
        check("R06 repeated XP line cannot train a consumed death again",L.Estimate("combatXP",key).samples==3
            and X.Status().confirmedXP==360)
        for field,value in pairs({partySize=2,equipmentKey="equipment-B",xpRested=true,level=11,class=2}) do
            local changed=S.Clone(state);changed[field]=value
            local valueXP,authority=C.Reward(action,changed)
            check("R06 event model cannot leak to actor cohort "..field,valueXP==0 and authority=="combat-xp-unknown")
        end

        fresh();key=C.Context(action,state)
        local guid="Creature-0-1-1-1-123-AMBIG"
        combat(1,"SWING_DAMAGE",guid);combat(2,"UNIT_DIED",guid);message(2.1,11);message(2.2,12)
        observe(5)
        check("R06 distinct duplicate XP lines remain ambiguous rather than doubling",not L.Estimate("combatXP",key))
        fresh();key=C.Context(action,state)
        combat(1,"SWING_DAMAGE","Creature-0-1-1-1-999-WRONG")
        combat(2,"UNIT_DIED","Creature-0-1-1-1-999-WRONG");message(2.1,13);observe(5)
        check("R06 same-name different NPC cannot train the selected target",not L.Estimate("combatXP",key))
        fresh();key=C.Context(action,state)
        combat(1,"SWING_DAMAGE",guid,"Other-player");combat(2,"PARTY_KILL",guid,"Other-player")
        combat(2,"UNIT_DIED",guid,"Other-player");message(2.1,14);observe(5)
        check("R06 another player's participation is not attributed to this player",not L.Estimate("combatXP",key))

        for _,field in ipairs({"partySize","equipmentKey","xpRested","level"}) do
            fresh();key=C.Context(action,state)
            combat(1,"SWING_DAMAGE",guid);combat(2,"UNIT_DIED",guid);message(2.1,20)
            local changes={}
            if field=="level" then changes.attributes=S.Clone(ctx.attributes);changes.attributes.level=11
            else changes[field]=field=="partySize" and 2 or field=="equipmentKey" and "equipment-B" or true end
            observe(2.2,changes);observe(5)
            check("R06 observed cohort change drops pending attribution "..field,not L.Estimate("combatXP",key)
                and X.Status().samples==0)
        end
        for _,boundary in ipairs({"GROUP_ROSTER_UPDATE","PLAYER_LEVEL_UP","PLAYER_EQUIPMENT_CHANGED","UNIT_PET"}) do
            fresh();key=C.Context(action,state)
            combat(1,"SWING_DAMAGE",guid);combat(2,"UNIT_DIED",guid);message(2.1,30)
            dispatch(2.2,boundary,boundary=="UNIT_PET" and "player" or 11)
            now=5;X.Tick(now) -- Controller may settle XP before its queued context refresh.
            check("R06 event boundary cannot settle against old cohort "..boundary,not L.Estimate("combatXP",key)
                and X.Status().samples==0)
        end
        fresh();key=C.Context(action,state)
        combat(1,"SWING_DAMAGE",guid);combat(2,"UNIT_DIED",guid);message(2.1,31)
        dispatch(2.2,"UNIT_PET","party1");observe(5)
        check("R06 another unit's pet event does not erase player attribution",L.Estimate("combatXP",key)
            and L.Estimate("combatXP",key).samples==1)
        fresh();key=C.Context(action,state)
        combat(1,"SWING_DAMAGE",guid);combat(2,"UNIT_DIED",guid);message(2.1,32)
        observe(5,{position={mapID=1427,x=.5,y=.5}})
        check("R06 changed live map cannot settle old-zone attribution",not L.Estimate("combatXP",key)
            and X.Status().samples==0)
        for _,flag in ipairs({"paused","afk","dead"}) do
            fresh();key=C.Context(action,state)
            combat(1,"SWING_DAMAGE",guid);combat(2,"UNIT_DIED",guid);message(2.1,40)
            if flag=="paused" then policy.paused=true;observe(5) else observe(5,{[flag]=true}) end
            check("R06 unusable actor evidence clears pending XP "..flag,not L.Estimate("combatXP",key))
        end

        fresh();exhaustion=500;state.xpRested=true;observe(0,{xpRested=true});key=C.Context(action,state)
        combat(10,"SWING_DAMAGE",guid);combat(12,"UNIT_DIED",guid);message(12.1,50)
        exhaustion=400;dispatch(12.2,"UPDATE_EXHAUSTION");observe(15)
        check("R06 ordinary rested-pool decrease keeps the same XP cohort",L.Estimate("combatXP",key)
            and L.Estimate("combatXP",key).samples==1)
        fresh();exhaustion=500;state.xpRested=true;observe(0,{xpRested=true});key=C.Context(action,state)
        combat(10,"SWING_DAMAGE",guid);combat(12,"UNIT_DIED",guid);message(12.1,51)
        exhaustion=0;dispatch(12.2,"UPDATE_EXHAUSTION");now=15;X.Tick(now)
        check("R06 changed rested bonus cannot settle into the prior XP cohort",not L.Estimate("combatXP",key))
        fresh();key=C.Context(action,state)
        combat(1,"SWING_DAMAGE",guid);combat(2,"UNIT_DIED",guid);message(2.1,52)
        dispatch(2.2,"UNIT_INVENTORY_CHANGED","player");observe(5)
        check("R06 ordinary inventory updates do not discard participated kill XP",L.Estimate("combatXP",key)
            and L.Estimate("combatXP",key).samples==1)
        fresh();key=C.Context(action,state)
        combat(1,"SWING_DAMAGE",guid);combat(2,"UNIT_DIED",guid);message(2.1,53)
        dispatch(2.2,"PLAYER_DEAD");now=5;X.Tick(now)
        check("R06 death event suspends XP before a delayed context refresh",not L.Estimate("combatXP",key)
            and O.Status().phase=="death")
        fresh();key=C.Context(action,state)
        combat(1,"SWING_DAMAGE",guid);combat(2,"UNIT_DIED",guid);message(2.1,54)
        dispatch(2.2,"GROUP_ROSTER_UPDATE");observe(5,{partySize=2});state.partySize=2
        kill(10,55,80)
        check("R06 stable post-boundary group observations train only the new cohort",not L.Estimate("combatXP",key)
            and L.Estimate("combatXP",C.Context(action,state)) and near(C.Reward(action,state),560))

        -- Classic QUEST_ACCEPTED is (questIndex, questId), not (questId).
        fresh();L.Completion(900,true);L.Completion(7,true)
        dispatch(1,"QUEST_ACCEPTED",7,900)
        check("R18 Classic acceptance clears the quest ID rather than log index",L.State().completed[900]~=true
            and L.State().completed[7]==true)
        O.Reset();local pickup=S.Clone(action);pickup.kind="pickup";pickup.id="pickup:900";pickup.method="start"
        ctx.observedAt=2;now=2;O.Observe(snapshot,ctx,policy,pickup)
        dispatch(2,"QUEST_DETAIL");dispatch(7,"QUEST_ACCEPTED",7,900)
        local interaction=L.Estimate("interaction",C.Context(pickup,state))
        check("R18 Classic acceptance closes the actual pickup episode",interaction and interaction.samples==1
            and near(interaction.mean,5))
        dispatch(10,"QUEST_ACCEPTED",7,900)
        local after=L.Estimate("interaction",C.Context(pickup,state))
        check("R18 duplicate acceptance cannot record another episode",after and after.samples==1)
        -- Exercise the real registration and dispatcher, not just direct Runtime calls.
        local handlers,refreshes,invalidations,attributions={},0,0,0
        RikUI.RegisterModule=function(_,name,value) assert(name=="questplanner" and value==p) end
        RikUI.RegisterCommand=function() end
        RikUI.RegisterEvent=function(_,name,fn) handlers[name]=fn end
        C_Timer={After=function() end}
        p.Controller={Start=function() end,Peek=function() return {} end,
            Refresh=function() refreshes=refreshes+1 end,Invalidate=function() invalidations=invalidations+1 end}
        local originalEvent=p.PlanRuntime.OnEvent
        p.PlanRuntime.OnEvent=function(...) attributions=attributions+1;return originalEvent(...) end
        dofile("src/modules/questplanner/questplanner.lua");p.enabled=true;p:OnEnable()
        check("R06 actor boundary events are registered in production",handlers.UNIT_PET and handlers.UPDATE_EXHAUSTION
            and handlers.PLAYER_LEVEL_UP and handlers.GROUP_ROSTER_UPDATE and handlers.PLAYER_EQUIPMENT_CHANGED)
        event={20,"SWING_DAMAGE",false,"Player-1","Player",0,0,guid,"Wolf",0,0,20,0,0,20};now=20
        for _=1,200 do handlers.COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED") end
        local args={"Wolf dies, you gain 100 experience.","","","","","",0,0,"",0,70}
        handlers.CHAT_MSG_COMBAT_XP_GAIN("CHAT_MSG_COMBAT_XP_GAIN",unpack(args,1,11))
        check("R16 high-volume attribution events do not cancel strategic work",attributions==201
            and refreshes==0 and invalidations==0)
        handlers.QUEST_LOG_UPDATE("QUEST_LOG_UPDATE")
        check("R15 real quest changes still refresh the strategic plan",refreshes==1 and attributions==202)
        print("Combat XP event-chain fixture completed; observed event ownership and modeled estimates only")
    end)
    for _,name in ipairs(names) do _G[name]=saved[name] end
    check("combat XP event-chain suite completes",ok,err)
end
