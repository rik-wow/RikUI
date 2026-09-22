return function(check)
    local old=RikUI
    RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
    local ok,err=pcall(function()
        for _,name in ipairs({"schema","objectives","recommendations","guidance"}) do dofile("src/modules/questplanner/quest-"..name..".lua") end
        local p=RikUI.QuestPlanner
        local id={product="forever",build="1.60.1.69913",locale="enUS"}
        local snapshot={identity=id,order={100,900},quests={}}
        local ctx={position={mapID=1426,x=0,y=.5},destinations={},rewards={},history={}}
        p.Context={Frame=function() return {position=ctx.position,width=1000,height=1000} end}
        local policy={pins={},skips={},avoids={}}
        local function quest(q,x,done,count,total)
            snapshot.quests[q]={id=q,title="Quest "..q,objectivesComplete=done,
                objectives={{text="Collect tokens",type="item",numFulfilled=count or 0,numRequired=total or 10,finished=done}}}
            ctx.destinations[q]={mapID=1426,x=x,y=.5,scope="current-map-quest-poi"}
        end
        local function rows(previous,prior) return p.Guidance.Observed(snapshot,ctx,policy,previous,false,prior) end
        quest(100,.9,true);quest(900,.1,false)
        check("nearby work beats a remote turn-in",rows()[1].questID==900)
        quest(100,.12,true)
        check("nearby turn-in gets a modest priority",rows()[1].questID==100)
        quest(100,.12,false);quest(900,.1,false)
        check("small distance advantage does not churn current quest",rows(100)[1].questID==100)
        quest(100,.4,false)
        check("clear travel improvement can change the next quest",rows(100)[1].questID==900)
        policy.pins[100]=true
        check("explicit pin beats automatic proximity",rows()[1].questID==100)
        policy.skips[100]=true
        check("skipped pin cannot become an automatic target",rows()[1].questID==900)
        policy.skips[100]=nil;policy.pins[100]=nil
        quest(100,.14,false,9,10);quest(900,.13,false)
        check("known near-completion breaks a small travel tie",rows()[1].questID==100)
        quest(100,.8,false,9,10)
        check("progress cannot outweigh a large travel detour",rows()[1].questID==900)
        quest(100,.12,true);quest(900,.09,false)
        check("completion drops old continuity advantage",rows(900,{questID=900,kind="turnin"})[1].questID==100)
        ctx.destinations[100].mapID=999
        check("unknown cross-map travel does not displace a known local target",rows(100)[1].questID==900)
        ctx.destinations[900].mapID=998
        check("unknown travel retains a stable usable previous choice",rows(100)[1].questID==100)
        ctx.destinations[100]=nil
        check("missing destination cannot beat an available marker",rows(100)[1].questID==900)
        quest(100,.1,false);quest(900,.1,false)
        snapshot.order={900,100}
        check("equal choices use log order instead of numeric quest ID",rows()[1].questID==900)
        policy.avoids[1426]=true
        check("all excluded quests leave no automatic recommendation",#rows()==0)
        policy.avoids[1426]=nil
        p.SemanticGuidance={Advice=function() end,Apply=function(_,q,point)
            if q==100 then return {mapID=999,x=.1,y=.5},nil,{areaID="other-map",action="Collect from a crate"} end
            return point
        end}
        policy.avoids[999]=true
        check("avoid applies after a semantic target changes the map",#rows()==1 and rows()[1].questID==900)
        p.SemanticGuidance=nil;policy.avoids[999]=nil
        local frame=p.Context.Frame()
        check("boundary jitter does not trigger movement scans",not p.Recommendations.Moved(
            {mapID=1426,x=.0249,y=.5},{mapID=1426,x=.0251,y=.5},frame))
        check("meaningful movement triggers refreshed recommendations",p.Recommendations.Moved(
            {mapID=1426,x=.01,y=.5},{mapID=1426,x=.08,y=.5},frame))
        check("map transitions invalidate distance context",p.Recommendations.Moved(
            {mapID=999,x=.01,y=.5},ctx.position,frame))
        local shared={
            {questID=100,kind="objective",destination={mapID=1426,x=.11,y=.5},semantic={areaID="npc:1:1426:surface1"},pinned=false},
            {questID=900,kind="objective",destination={mapID=1426,x=.1,y=.5},pinned=false},
            {questID=901,kind="objective",destination={mapID=1426,x=.11,y=.5},semantic={areaID="npc:1:1426:surface1"},pinned=false},
        }
        p.Recommendations.Sort(shared,snapshot,ctx)
        check("shared active area can save a small separate trip",shared[1].questID==100)
        check("shared benefit counts distinct active quest IDs",shared[1].recommendation.shared==1)
        local marked=p.Recommendations and rows()[1].recommendation
        check("recommendation explains estimated travel without claiming a walking route",marked and marked.distance==100 and marked.basis=="map-distance estimate")
    end)
    RikUI=old
    check("dynamic recommendations suite completes",ok,err)
end

