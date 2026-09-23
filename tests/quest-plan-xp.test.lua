return function(check)
    local savedRik,savedAPI,savedLegacy,savedTemplate,savedEvents=RikUI,C_CombatLog,CombatLogGetCurrentEventInfo,COMBATLOG_XPGAIN_FIRSTPERSON,C_EventUtils
    local ok,err=pcall(function()
        RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
        dofile("src/modules/questplanner/quest-schema.lua")
        dofile("src/modules/questplanner/quest-plan-learning.lua")
        local p=RikUI.QuestPlanner;p.Context={Call=function(fn,...) if type(fn)~="function" then return false end;return pcall(fn,...) end}
        dofile("src/modules/questplanner/quest-plan-xp.lua")
        local x=p.PlanXP
        local formats={
            COMBATLOG_XPGAIN_FIRSTPERSON="%s dies, you gain %d experience.",
            COMBATLOG_XPGAIN_FIRSTPERSON_GROUP="%s dies, you gain %d experience. (+%d group bonus)",
            COMBATLOG_XPGAIN_EXHAUSTION1="%s dies, you gain %d experience. (%d rest bonus)",
            COMBATLOG_XPGAIN_EXHAUSTION2="%s dies, you gain %d experience. (%d rest bonus)",
            COMBATLOG_XPGAIN_FIRSTPERSON_RAID="%2$d XP après %1$s. 100%%",
            COMBATLOG_XPGAIN_EXHAUSTION4="%1$s [%2$d] (%1$s)",
        }
        local patterns=x.Compile(formats)
        check("XP template basic amount",x.Parse(patterns,"Wolf dies, you gain 100 experience.").xp==100)
        check("XP bonus not counted twice",x.Parse(patterns,"Wolf dies, you gain 100 experience. (+25 group bonus)").xp==100
            and x.Parse(patterns,"Wolf dies, you gain 100 experience. (50 rest bonus)").xp==100)
        local reordered=x.Parse(patterns,"100 XP après Loup. 100%")
        check("XP positional UTF8 and literal percent",reordered.name=="Loup" and reordered.xp==100)
        check("XP repeated argument literal punctuation",x.Parse(patterns,"Wolf [12] (Wolf)").xp==12 and not x.Parse(patterns,"Wolf [12] (Bear)"))
        check("XP partial unknown and zero rejected",not x.Parse(patterns,"Wolf dies, you gain 100 experience. trailing")
            and not x.Parse(patterns,"Wolf dies, you gain 0 experience.") and not x.Parse(patterns,"You gain 100 experience."))
        local unsupported=x.Compile({COMBATLOG_XPGAIN_FIRSTPERSON="%s |4dies:die;, %d.",COMBATLOG_XPGAIN_QUEST="Quest gives %d."})
        check("XP unsupported grammar and unnamed rewards not guessed",#unsupported==0)
        COMBATLOG_XPGAIN_FIRSTPERSON=formats.COMBATLOG_XPGAIN_FIRSTPERSON
        local event
        C_CombatLog={GetCurrentEventInfo=function() return unpack(event,1,16) end,IsCombatLogRestricted=function() return false end}
        C_EventUtils=nil
        check("legacy combat reader supports native event subscription",x.CanObserveCombat())
        C_CombatLog.IsCombatLogRestricted=function() return true end
        check("restricted combat log is rejected before registration",not x.CanObserveCombat())
        C_CombatLog.IsCombatLogRestricted=function() error("restricted API unavailable") end
        check("unknown combat restrictions fail closed",not x.CanObserveCombat())
        C_CombatLog.IsCombatLogRestricted=function() return false end
        C_EventUtils={IsEventValid=function() return true end,IsCallbackEvent=function() return true end}
        check("callback-only combat event is not registered as a frame event",not x.CanObserveCombat())
        C_EventUtils.IsCallbackEvent=function() return false end
        check("ordinary permitted combat event remains enabled",x.CanObserveCombat())
        C_EventUtils.IsEventValid=function() return false end
        check("removed combat event is not probed through RegisterEvent",not x.CanObserveCombat())
        C_EventUtils=nil
        local identity={product="forever",build="test",locale="enUS"}
        local context={key="test:kill:123",npcID=123,playerGUID="Player-1",petGUID="Pet-1"}
        local A,B="Creature-0-1-1-1-123-AAAA","Creature-0-1-1-1-123-BBBB"
        local function reset()
            p.PlanLearning.Bind(identity,"test");p.PlanLearning.Reset();x.Reset();x.SetContext(context,0)
        end
        local function combat(at,kind,guid,name,mine)
            event={0,kind,false,mine or "Player-1","Player",0,0,guid,name or "Wolf",0,0,20,0,0,20}
            x.OnEvent("COMBAT_LOG_EVENT_UNFILTERED",at)
        end
        local function message(at,line,otherGUID)
            local args={"Wolf dies, you gain 100 experience.","","","","","",0,0,"",0,line,otherGUID}
            x.OnEvent("CHAT_MSG_COMBAT_XP_GAIN",at,unpack(args,1,12))
        end
        reset();combat(0,"SWING_DAMAGE",A);combat(1,"UNIT_DIED",A);message(1.1,1,B);x.Tick(3.2)
        check("confirmed XP uses combat dest not chat GUID",x.Status().samples==1 and x.Status().confirmedXP==100)
        x.Tick(5);message(5.1,1);x.Tick(8)
        check("XP row and death consumed once",x.Status().samples==1)
        reset();combat(0,"SWING_DAMAGE",A,nil,"Pet-1");message(1,1);combat(2,"UNIT_DIED",A);x.Tick(4.1)
        check("XP before death and pet participation correlate",x.Status().samples==1)
        reset();combat(0,"SWING_DAMAGE",A);combat(1,"PARTY_KILL",A);combat(1.1,"UNIT_DIED",A);message(1.2,1);x.Tick(3.3)
        check("PARTY_KILL plus UNIT_DIED is one victim",x.Status().samples==1)
        reset();combat(0,"SWING_DAMAGE",A);combat(1,"UNIT_DIED",A);message(1.1,1);combat(1.5,"UNIT_DIED",B,nil,"Other");x.Tick(4)
        check("unparticipated same-name death makes attribution ambiguous",x.Status().samples==0)
        reset();combat(0,"SWING_DAMAGE",A);combat(1,"UNIT_DIED",A);message(1.1,1);x.Tick(2);message(2.5,2);x.Tick(5)
        check("settlement waits for complete ambiguity window",x.Status().samples==0)
        reset();combat(1,"UNIT_DIED",A,nil,"Other");message(1.1,1);x.Tick(4)
        check("unparticipated XP never trains target",x.Status().samples==0)
        reset();combat(0,"SWING_DAMAGE",A);combat(1,"UNIT_DIED",A);message(1.1,1)
        x.SetContext({key="different",npcID=123,playerGUID="Player-1"},2);x.Tick(4)
        check("changed action context discards unfinished XP",x.Status().samples==0)
        reset();C_CombatLog.IsCombatLogRestricted=function() return true end
        combat(0,"SWING_DAMAGE",A);combat(1,"UNIT_DIED",A);message(1.1,1);x.Tick(4)
        check("restricted combat log remains unknown",x.Status().samples==0 and x.Status().lastUnknown~=nil)
        C_CombatLog.IsCombatLogRestricted=function() return false end
        reset()
        for id=1,33 do combat(id/100,"SWING_DAMAGE","Creature-0-1-1-1-123-"..id) end
        check("XP participant queue is bounded and quarantined",x.Status().participants<=32 and x.Status().lastUnknown=="participant overflow")
        x.OnEvent("PLAYER_ENTERING_WORLD",1)
        check("XP world change clears pending evidence",x.Status().deaths==0 and x.Status().messages==0)
    end)
    RikUI,C_CombatLog,CombatLogGetCurrentEventInfo,COMBATLOG_XPGAIN_FIRSTPERSON,C_EventUtils=savedRik,savedAPI,savedLegacy,savedTemplate,savedEvents
    check("confirmed combat XP suite completes",ok,err)
end
