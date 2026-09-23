-- Road travel planning: walking against flights, boats between worlds,
-- discovered flight points and faction.
return function(check)
 local saved={RikUI,C_TaxiMap,UnitFactionGroup,GetTime}
 local ok,why=pcall(function()
  RikUI={};RikUI['Secret']={IsSecret=function()return false end}
  dofile('src/modules/questplanner/quest-schema.lua')
  dofile('src/modules/questplanner/quest-road-travel.lua')
  local p=RikUI.QuestPlanner;local travel=p.RoadTravel
  GetTime=function()return 0 end
  local faction,discovered='Alliance',{}
  UnitFactionGroup=function()return faction end
  C_TaxiMap={GetTaxiNodesForMap=function()
   local rows={};for id in pairs(discovered)do rows[#rows+1]={nodeID=id,isUndiscovered=false}end;return rows
  end}
  -- A world is a line of nodes 100 yd apart along x, each edge costing its length.
  local function line(count,stopRows,walks)
   local g={cellYards=128,catalog={travel={stops=stopRows,walks=walks}}}
   function g:Node(i)return (i-1)*100,0,0 end
   function g:EdgeRange(i)return i*2-1,i*2 end
   function g:Edge(e)
    local i=math.floor((e+1)/2);local to=e%2==1 and i-1 or i+1
    if to<1 or to>count then return i,0 end
    return to,100
   end
   function g:CellNodes(cx,cz)
    if cz~=0 then return {} end
    local out={};for i=1,count do if math.floor((i-1)*100/128)==cx then out[#out+1]=i end end;return out
   end
   return g
  end
  assert(travel.Install({stops={
    {id='flight:1',kind='flight',name='West Field',world=0,point={0,0,0},factions={'alliance'},taxiNode=1},
    {id='flight:2',kind='flight',name='East Field',world=0,point={1900,0,0},factions={'alliance'},taxiNode=2},
    {id='dock:9:0',kind='dock',name='East dock',world=0,point={1900,0,0}},
    {id='dock:9:1',kind='dock',name='Far dock',world=1,point={0,0,0}},
   },links={
    {id='flight:5',mode='flight',from='flight:1',to='flight:2',seconds=40,wait=0,factions={'alliance'}},
    {id='ride:9:0',mode='transport',from='dock:9:0',to='dock:9:1',seconds=60,wait=30,vehicle='boat'},
   }}))
  local west=line(20,{{id='flight:1',node=1,yards=0},{id='flight:2',node=20,yards=0},{id='dock:9:0',node=20,yards=0}},
   {{1,2,1900},{2,1,1900},{1,3,1900},{3,1,1900},{2,3,0},{3,2,0}})
  local far=line(3,{{id='dock:9:1',node=1,yards=0}},{})
  local function plan(graphs,start,goal)
   local job=assert(travel.Begin(graphs,start,goal))
   for _=1,1000 do local r=job:Step();if r then return r end end
  end
  local r=plan({[0]=west},{world=0,x=0,z=0},{world=0,x=1900,z=0})
  check('road travel walks when no flight point is discovered',r.status=='planned' and r.walkOnly,r.status)
  discovered={[1]=true,[2]=true}
  travel.OnEvent('TAXIMAP_CLOSED')
  r=plan({[0]=west},{world=0,x=0,z=0},{world=0,x=1900,z=0})
  -- The first walk is zero yards long; guidance moves past it on arrival.
  check('road travel flies between discovered flight points when faster',
   r.legs and #r.legs==3 and r.legs[1].to=='flight:1' and r.legs[2].mode=='flight' and r.legs[3].to=='goal',r.legs and #r.legs)
  check('road travel describes the flight',r.legs and r.legs[2].text=='Fly to East Field',r.legs and r.legs[2].text)
  faction='Horde';travel.OnEvent('TAXIMAP_CLOSED')
  r=plan({[0]=west},{world=0,x=0,z=0},{world=0,x=1900,z=0})
  check('road travel skips flights of the other faction',r.walkOnly,r.legs and r.legs[1].mode)
  r=plan({[0]=west,[1]=far},{world=0,x=0,z=0},{world=1,x=200,z=0})
  local modes={};for i,leg in ipairs(r.legs or {})do modes[i]=leg.mode end
  check('road travel crosses to another world by boat',table.concat(modes,',')=='walk,transport,walk',table.concat(modes,','))
  check('road travel names the boat leg',r.legs and r.legs[2].text=='Take the boat to Far dock',r.legs and r.legs[2].text)
  check('road travel counts the boat wait',r.seconds and math.abs(r.seconds-(1900/7+90+200/7))<.01,r.seconds)
  local island=line(3,{},{})
  r=plan({[0]=west,[2]=island},{world=0,x=0,z=0},{world=2,x=0,z=0})
  check('road travel reports no path when nothing links the worlds',r.status=='no-known-path',r.status)
  check('road travel lists linked worlds',table.concat(travel.Worlds(0,0),',')=='0,1',table.concat(travel.Worlds(0,0),','))
 end)
 RikUI,C_TaxiMap,UnitFactionGroup,GetTime=saved[1],saved[2],saved[3],saved[4]
 check('quest road travel suite runs',ok,why)
end
