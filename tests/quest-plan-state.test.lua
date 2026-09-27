-- Synthetic mechanics and source claims; never asserted as world facts.
return function(check)
    local old=RikUI
    RikUI={Secret={IsSecret=function() return false end}}
    local ok,err=pcall(function()
        for _,name in ipairs({"schema","preferences","plan-state"}) do dofile("src/modules/questplanner/quest-"..name..".lua") end
        local p=RikUI.QuestPlanner
        local preferences=assert(p.Preferences.Normalize({}))
        check("balanced is default",preferences.flavor=="Balanced")
        check("flavor names bounded",not p.Preferences.Normalize({flavor="Invented"}))
        for _,flavor in ipairs(p.Preferences.Flavors()) do
            check("all six presets validate "..flavor,p.Preferences.Normalize({flavor=flavor})~=nil)
        end
        check("invalid session rejected",not p.Preferences.Normalize({sessionMinutes=-1}))
        local snapshot={identity={product="forever",build="test",locale="enUS"},order={10},generation=1,
            quests={[10]={id=10,title="Collect",failed=false,objectivesComplete=false,
                objectives={{text="2/5 Tokens",type="item",numFulfilled=2,numRequired=5,finished=false}}}},
            reportedCount=1,coverage="log-complete"}
        local ctx={origin="live",attributes={level=5,class=1,race=3,faction="Alliance",logCapacity=20,xp=10,xpMax=100},
            history={[11]=false},inventory={[7]=2},position={mapID=1,x=.2,y=.3},partySize=1,characterKey="test-character"}
        local state=assert(p.PlanState.Build(snapshot,{state="current"},ctx,{},preferences))
        check("state detaches live input",state.active[10] and state.progress[10]["live:1"]==3)
        check("source absence cannot erase live quest",state.live[10] and state.logCount==1)
        check("absent history remains unknown",state.completed[12]==nil and state.completed[11]==false)
        check("inventory owned separately",state.inventory[7]==2 and state.bank[7]==nil)
        state.progress[10]["live:1"]=0
        check("simulated completion never changes live progress",snapshot.quests[10].objectives[1].numFulfilled==2)
        check("stale snapshot cannot plan",not p.PlanState.Build(snapshot,{state="stale"},ctx,{},preferences))
        snapshot.origin="imported-untrusted"
        check("untrusted import cannot plan",not p.PlanState.Build(snapshot,{state="current"},ctx,{},preferences))
        dofile("src/modules/questplanner/quest-waypoints.lua")
        dofile("src/modules/questplanner/quest-plan-graph.lua")
        snapshot.origin=nil
        local method={kind="kill",targetKind="npc",targetID=99,name="Beast",areas={{id="field",mapID=1,x=.3,y=.3}}}
        local record={id=11,title="Future work",objectives={{id="kill:99",type="monster",targetID=99,name="Beast",methods={method}}},
            starts={{kind="start",targetKind="npc",targetID=8,name="Scout",areas={{id="hub",mapID=1,x=.2,y=.3}}}},
            ends={{kind="finish",targetKind="npc",targetID=8,name="Scout",areas={{id="hub",mapID=1,x=.2,y=.3}}}},
            planning={version=1,requirements={op="completed",questID=10},blockedBy={12}},
            provenance={revision="fixture"},reward={baseXP=500,level=5}}
        local graphJob=assert(p.PlanGraph.Begin(state,{[11]=record},{{questID=10,detail="Collect Tokens"}},preferences))
        local graph
        for _=1,20 do graph=graphJob:Step(1);if graph then break end end
        check("normal corpus record constructs all future transitions",graph and #graph.byQuest[11]==4)
        check("unsupported future counts remain unknown",graph.byID["11:objective:kill:99:1:field"].countUnknown)
        check("pickup keeps typed prerequisite and exclusion",graph.byID["11:pickup:1:hub"].prerequisite.questID==10
            and graph.byID["11:pickup:1:hub"].excludes[1]==12)
        check("unknown live quest retains useful instructions",graph.byID["10:live:objective"].instruction=="Collect Tokens")
        method.areas[1].phase=2
        graphJob=assert(p.PlanGraph.Begin(state,{[11]=record},{},preferences))
        for _=1,20 do graph=graphJob:Step(1);if graph then break end end
        check("unknown phase never admitted as usable method",not graph.byID["11:objective:kill:99:1:field"])
        graphJob=assert(p.PlanGraph.Begin(state,{[11]=record},{},preferences));graphJob:Cancel()
        check("graph construction is cancellable",graphJob:Step().status=="cancelled")

        -- Moving past the nearest-area shortlist must not remove a still-valid commitment.
        method.areas={{id="near-a",mapID=1,x=.21,y=.3},{id="near-b",mapID=1,x=.22,y=.3},
            {id="committed",mapID=1,x=.9,y=.3}}
        local function build(records,prior)
            local job=assert(p.PlanGraph.Begin(state,records,{},preferences,prior))
            for _=1,100 do local result=job:Step(4);if result then return result end end
            error("graph failed to finish")
        end
        local committed="11:objective:kill:99:1:committed"
        graph=build({[11]=record},committed)
        check("valid current area survives nearest two pruning",graph.byID[committed] and #graph.byQuest[11]==6)
        method.name="Updated live source name"
        graph=build({[11]=record},committed)
        check("retained candidate is regenerated from current source",graph.byID[committed].target.name==method.name)
        method.areas[3].access=false
        graph=build({[11]=record},committed)
        check("commitment never bypasses source accessibility",not graph.byID[committed])
        method.areas[3].access=nil
        record.ends[1].areas=method.areas
        graph=build({[11]=record},"11:turnin:1:committed")
        check("valid current giver survives nearest two pruning",graph.byID["11:turnin:1:committed"]~=nil)
        method.areas={}
        for index=1,20 do method.areas[index]={id="distant-"..index,mapID=1,x=.8+index/1000,y=.3} end
        method.areas[21]={id="precise",mapID=1,x=.4,y=.3,spawns={{.21,.3},{.29,.3}}}
        graph=build({[11]=record})
        check("planner considers locations beyond the old first twelve source areas",
            graph.byID["11:objective:kill:99:1:precise:spawn:1"]~=nil)
        check("planner routes to an actual spawn within its source cluster",
            graph.byID["11:objective:kill:99:1:precise:spawn:1"].destination.x==.21)
        graph=build({[11]=record},"11:objective:kill:99:1:precise:spawn:2")
        check("planner retains a chosen exact spawn when a nearer sibling exists",
            graph.byID["11:objective:kill:99:1:precise:spawn:2"]~=nil)
        method.areas={{id="near-a",mapID=1,x=.21,y=.3},{id="near-b",mapID=1,x=.22,y=.3},
            {id="committed",mapID=1,x=.9,y=.3}}
        record.ends[1].areas=method.areas
        local crowded={}
        for id=1,96 do
            local row=p.Schema.Clone(record);row.id=id;row.objectives={}
            for n=1,8 do row.objectives[n]={id="kill:"..n,type="monster",targetID=99,methods={method}} end
            crowded[id]=row
        end
        graph=build(crowded,"96:objective:kill:8:1:committed")
        check("bounded graph reserves room for current valid candidate",#graph.actions==768 and graph.limited
            and graph.byID["96:objective:kill:8:1:committed"]~=nil)


    end)
    RikUI=old
    check("adaptive state fixture completes",ok,err)
end
