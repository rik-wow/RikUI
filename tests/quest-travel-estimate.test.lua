-- Strategic estimates use only index projections and stop links, never network loads.
return function(check)
    local saved,savedTaxi=RikUI,C_TaxiMap
    local ok,why=pcall(function()
        RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
        for _,name in ipairs({"schema","roads","road-travel","plan-learning","travel-estimate"}) do
            dofile("src/modules/questplanner/quest-"..name..".lua")
        end
        local p=RikUI.QuestPlanner
        local identity={product="forever",build="test",locale="enUS"}
        local function view(id)
            return {uiMapID=id,projection={originX=0,originY=0,width=10000,height=10000},validUIRectangle={0,0,1,1}}
        end
        local index={format="rikui-road-index-v1",identity=identity,worlds={
            {worldMapID=0,revision=string.rep("a",64),addon="World0",views={view(1),view(2)}},
            {worldMapID=1,revision=string.rep("b",64),addon="World1",views={view(3)}}},
            travel={stops={
                {id="tramA",kind="tram",name="A",world=0,point={0,0,0},taxiNode=10},
                {id="tramB",kind="tram",name="B",world=0,point={-10000,0,0}},
                {id="dock",kind="dock",name="C",world=1,point={0,0,0},taxiNode=20}},
                links={{id="tram",mode="transport",from="tramA",to="tramB",seconds=30,wait=20},
                    {id="boat",mode="transport",from="tramA",to="dock",seconds=600,wait=120},
                    {id="flight",mode="flight",from="tramA",to="dock",seconds=60,wait=0,factions={"alliance"}}}}}
        assert(p.Roads.InstallIndex(index))
        C_TaxiMap={GetTaxiNodesForMap=function() return {} end}
        local state={identity=identity,faction="Alliance"}
        local model=p.TravelEstimate.Capture(state,{[4]={1000,1000}})
        local query,_,stats=p.TravelEstimate.Open(model);assert(query)
        local start={mapID=1,x=0,y=0}
        local near={mapID=1,x=.01,y=0}
        local far={mapID=1,x=1,y=0}
        local sea={mapID=3,x=0,y=0}
        check("strategic cross-continent travel costs more than local walk",query(start,sea).seconds>query(start,near).seconds)
        check("strategic tram includes ride and wait and beats direct walk",query(start,far).seconds>=50 and query(start,far).seconds<55)
        check("strategic cross-map same-world distance uses projection",math.abs(query(start,near).seconds-query(start,{mapID=2,x=.01,y=0}).seconds)<1e-9)
        check("strategic unknown flights use known transport",query(start,sea).seconds>=720)
        local cached=stats().dijkstra
        local again=assert(p.TravelEstimate.Open(p.Schema.Copy(model)))
        check("serialized model rebuild preserves time and shared graph cache",again(start,sea).seconds==query(start,sea).seconds and stats().dijkstra==cached)
        local cells=stats().memo
        query({mapID=1,x=.0001,y=.0001},{mapID=1,x=.0101,y=.0001})
        local same=stats().memo
        query({mapID=1,x=.0002,y=.0002},{mapID=1,x=.0102,y=.0002})
        check("strategic estimates memoize 8-yard cells",stats().memo==same and same>=cells)
        query(start,near).seconds=-1
        check("callers cannot mutate memoized estimates",query(start,near).seconds>0)
        local uncovered=query({mapID=9,x=.1,y=.2},{mapID=8,x=.5,y=.5})
        check("uncovered travel is a positive unverified estimate",uncovered.seconds>0 and uncovered.status=="unverified")
        check("missing points never reject travel",query(nil,nil).seconds>0)
        check("same point is free",query(start,start).seconds==0)
        check("same-map fallback uses captured dimensions",math.abs(query({mapID=4,x=0,y=0},{mapID=4,x=1,y=0}).seconds-1000*1.3/7)<1e-9)
        p.PlanLearning.Bind(identity,"test")
        p.PlanLearning.Observe("travel","test:1:foot",30,100)
        local learned=p.TravelEstimate.Capture(state,{})
        local learnedQuery=assert(p.TravelEstimate.Open(learned))
        check("travel captures learned seconds per straight-line yard",learned.rates[1]==.3 and learnedQuery(start,near).seconds>query(start,near).seconds)
        C_TaxiMap={GetTaxiNodesForMap=function() return {{nodeID=10,isUndiscovered=false},{nodeID=20,isUndiscovered=false}} end}
        p.RoadTravel.OnEvent("TAXIMAP_OPENED")
        local flights=p.TravelEstimate.Capture(state,{})
        local flying=assert(p.TravelEstimate.Open(flights))
        check("discovered faction flight wins when cheaper",flying(start,sea).seconds<70 and flights.flightDigest~=model.flightDigest)
        state.faction="Horde"
        local horde=assert(p.TravelEstimate.Open(p.TravelEstimate.Capture(state,{})))
        check("wrong faction cannot use flight",horde(start,sea).seconds>=720)
        local wrong=p.Schema.Clone(model);wrong.flightDigest="wrong"
        check("forged flight digest rejected",not p.TravelEstimate.Open(wrong))
        local before=query(start,far).seconds
        index.travel.links[1].seconds=80
        assert(p.Roads.InstallIndex(index))
        local stale,reason=p.TravelEstimate.Open(model)
        check("changed transport source rejects replay model",not stale and reason=="source_mismatch")
        check("running search retains immutable old source",query(start,far).seconds==before)
        local revised=p.TravelEstimate.Capture(state,{})
        index.worlds[1].views[1].projection.width=9000
        assert(p.Roads.InstallIndex(index))
        local _,changed=p.TravelEstimate.Open(revised)
        check("changed projection rejects replay model",changed=="source_mismatch")
        local current=p.TravelEstimate.Capture(state,{})
        index.worlds[1].views[1].projection.width=-1
        check("invalid index is rejected atomically",not p.Roads.InstallIndex(index) and p.TravelEstimate.Open(current)~=nil)
    end)
    RikUI,C_TaxiMap=saved,savedTaxi
    check("travel estimate suite completes",ok,why)
end
