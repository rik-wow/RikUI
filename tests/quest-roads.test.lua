-- Road network: codec-backed loading, A* against a brute-force oracle,
-- attachment legs and the polyline follower's display contract.
return function(check)
 local saved,savedAddOns=RikUI,C_AddOns
 local ok,why=pcall(function()
  for _,clientBuild in ipairs({'1.60.1.69913','1.60.1.70009'}) do
  RikUI={};RikUI['Secret']={IsSecret=function()return false end}
  for _,name in ipairs({'schema','builds','path-codec','roads','road-route','road-follow'})do dofile('src/modules/questplanner/quest-'..name..'.lua')end
  local p=RikUI.QuestPlanner;local identity={product='forever',build='1.60.1.69913',locale='enUS'}
  p.Builds.Observe(clientBuild)
  local requestIdentity=p.Schema.Clone(identity)
  identity.build=clientBuild
  local ALPHABET='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_`{|}~'
  local function b85(bytes)
   while #bytes%4~=0 do bytes=bytes..'\0' end
   local out={}
   for i=1,#bytes,4 do
    local a,b,c,d=bytes:byte(i,i+3);local word=((a*256+b)*256+c)*256+d;local chars={}
    for k=5,1,-1 do local digit=word%85;chars[k]=ALPHABET:sub(digit+1,digit+1);word=math.floor(word/85)end
    out[#out+1]=table.concat(chars)
   end
   return table.concat(out)
  end
  local function le(value,width)
   if value<0 then value=value+2^(8*width)end
   local s={};for k=1,width do s[k]=string.char(value%256);value=math.floor(value/256)end;return table.concat(s)
  end
  -- 3x3 grid of nodes 100 yd apart; the middle column is road (cost .6 x length).
  local nodes,edges,cells={}, {}, {}
  local function id(i,j)return (j-1)*3+i end
  for j=1,3 do for i=1,3 do nodes[id(i,j)]={x=(i-1)*100+50,z=(j-1)*100+50,road=i==2 and 1 or 0}end end
  local function link(a,b,corners)
   local na,nb=nodes[a],nodes[b];local len=math.sqrt((na.x-nb.x)^2+(na.z-nb.z)^2)
   local road=(na.road+nb.road)/2;edges[a]=edges[a]or{}
   table.insert(edges[a],{to=b,cost=len*(1-.4*road),len=len,corners=corners or{}})
  end
  for j=1,3 do for i=1,3 do
   if i<3 then link(id(i,j),id(i+1,j));link(id(i+1,j),id(i,j))end
   if j<3 then link(id(i,j),id(i,j+1),{{nodes[id(i,j)].x+10,nodes[id(i,j)].z+50}});link(id(i,j+1),id(i,j))end
  end end
  local nodeBytes,offsetBytes,edgeBytes,pointBytes,cellRows={}, {}, {}, {}, {}
  local count,points=0,0
  for n=1,9 do
   local v=nodes[n]
   nodeBytes[n]=le(v.x*4,4)..le(v.z*4,4)..le(0,4)..le(v.road*255,1)
   offsetBytes[n]=le(count,4)
   table.sort(edges[n],function(a,b)return a.to<b.to end)
   for _,e in ipairs(edges[n])do
    edgeBytes[#edgeBytes+1]=le(e.to,3)..le(math.floor(e.cost*4+.5),2)..le(math.floor(e.len*4+.5),2)..le(#e.corners,1)
    for _,c in ipairs(e.corners)do pointBytes[#pointBytes+1]=le((c[1]-v.x)*4,2)..le((c[2]-v.z)*4,2);points=points+1 end
    count=count+1
   end
   cellRows[#cellRows+1]={key=(math.floor(v.x/128)+2048)*4096+(math.floor(v.z/128)+2048),n=n}
  end
  offsetBytes[10]=le(count,4)
  table.sort(cellRows,function(a,b)return a.key<b.key or a.key==b.key and a.n<b.n end)
  local cellBytes={};for i,r in ipairs(cellRows)do cellBytes[i]=le(r.key,4)..le(r.n,4)end
  local repBytes={};for n=1,9 do repBytes[n]=le(1000+n,4)end
  local raw={nodes={table.concat(nodeBytes),13,9},offsets={table.concat(offsetBytes),4,10},edges={table.concat(edgeBytes),8,count},
   points={table.concat(pointBytes),4,points},cells={table.concat(cellBytes),8,9},reps={table.concat(repBytes),4,9}}
  local revision=string.rep('a',64);local streams={patches={bytes=0,stride=10,count=0,parts=0}}
  for name,s in pairs(raw)do streams[name]={bytes=#s[1],stride=s[2],count=s[3],parts=1};p.Roads.Page(revision,name,1,b85(s[1]))end
  local catalog={format='rikui-road-network-v1',identity=identity,worldMapID=0,revision=revision,cellYards=128,unitsPerYard=4,roadBonus=.4,
   counts={nodes=9,edges=count,points=points},streams=streams}
  local view={uiMapID=1426,projection={originX=1000,originY=1000,width=1000,height=1000},validUIRectangle={0,0,1,1}}
  check('road index installs',p.Roads.InstallIndex({format='rikui-road-index-v1',identity=identity,worlds={{worldMapID=0,revision=revision,addon='RikUIQuestRoads_W0',views={view}}}}))
  check('road index rejects bad format',not p.Roads.InstallIndex({format='x',identity=identity,worlds={}}))
  if clientBuild=='1.60.1.70009' then
   p.Roads.InstallIndex({format='rikui-road-index-v1',identity=requestIdentity,
       worlds={{worldMapID=0,revision=revision,addon='RikUIQuestRoads_W0',views={view}}}})
   local rejected,reason=p.Roads.Prepare(requestIdentity,0)
   check('70009 refuses old terrain even with compatible quest data',not rejected and reason=='road-network-identity')
   p.Roads.InstallIndex({format='rikui-road-index-v1',identity=identity,
       worlds={{worldMapID=0,revision=revision,addon='RikUIQuestRoads_W0',views={view}}}})
  end
  local loads=0
  C_AddOns={LoadAddOn=function(name)loads=loads+1;return p.Roads.Install(catalog)end}
  local graph,state
  for _=1,50 do graph,state=p.Roads.Prepare(requestIdentity,0);if graph then break end end
  check('road graph loads through its addon',graph~=nil and loads==1,state)
  check('road graph rejects other identities',not p.Roads.Prepare({product='x',build='1',locale='enUS'},0))
  local x,z,_,road=graph:Node(id(2,2));check('road node decodes position and road',x==150 and z==150 and road==1)
  check('road node maps to its patch polygon and back',graph:NodePolygon(4)==1004 and graph:PolygonNode(1004)==4 and graph:PolygonNode(5)==nil)
  check('road graph without quest patches reports none',graph:PatchAddon(graph:CellKey(0,0))==nil)
  local first,last=graph:EdgeRange(id(1,1));local target,_,len,corners,offset=graph:Edge(first)
  check('road edges decode in target order',target==id(2,1)and len==100 and corners==0)
  target,_,len,corners,offset=graph:Edge(last)
  local dx,dz=graph:Point(offset);check('road polyline point decodes relative offset',target==id(1,2)and corners==1 and dx==10 and dz==50)
  local world,point=p.Roads.Locate(1426,.95,.95);check('map position locates the world',world==0 and math.abs(point.x-50)<1e-9 and math.abs(point.z-50)<1e-9)
  local function run(start,goal)
   local job=assert(p.RoadRoute.Begin(graph,start,goal));for _=1,1000 do local r=job:Step(8);if r then return r end end
  end
  -- Oracle: brute-force Dijkstra over the fixture plus straight attachment legs.
  local function oracle(start,goal)
   local best=math.huge
   for s=1,9 do for t=1,9 do
    local dist,done={[s]=0},{}
    for _=1,9 do local u,bu=nil,math.huge;for n,d in pairs(dist)do if not done[n]and d<bu then u,bu=n,d end end
     if not u then break end;done[u]=true;for _,e in ipairs(edges[u])do if bu+e.cost<(dist[e.to]or math.huge)then dist[e.to]=bu+e.cost end end end
    if dist[t]then
     local a=math.sqrt((start.x-nodes[s].x)^2+(start.z-nodes[s].z)^2);local b=math.sqrt((goal.x-nodes[t].x)^2+(goal.z-nodes[t].z)^2)
     best=math.min(best,a+dist[t]+b)
    end
   end end
   return best
  end
  local cases={{{x=50,z=50},{x=250,z=250}},{{x=60,z=250},{x=250,z=60}},{{x=40,z=150},{x=260,z=150}},{{x=150,z=40},{x=150,z=260}}}
  for i,c in ipairs(cases)do
   local r=run(c[1],c[2]);local cost=0
   check('road A* finds route case '..i,r and r.status=='modeled',r and r.status)
   check('road route starts and ends at endpoints '..i,r.points[1][1]==c[1].x and r.points[#r.points][3]==c[2].z)
   check('road route keeps the open-ground legs labeled '..i,r.startLeg>=0 and r.goalLeg>=0 and r.nativeVerified==false)
  end
  local r=run({x=50,z=50},{x=250,z=50})
  check('road A* prefers the road column when cheaper',r.nodes>=3)
  local near=run({x=50,z=50},{x=52,z=52});check('road A* handles same-node trips',near and near.status=='modeled')
  check('road A* refuses points without nearby nodes',not p.RoadRoute.Begin(graph,{x=5000,z=5000},{x=50,z=50}))
  -- Brute force: the A* cost matches the oracle for every node-to-node trip.
  local mismatches=0
  for s=1,9 do for t=1,9 do
   local a,b={x=nodes[s].x,z=nodes[s].z},{x=nodes[t].x,z=nodes[t].z}
   local job=p.RoadRoute.Begin(graph,a,b);local res;for _=1,1000 do res=job:Step(8);if res then break end end
   local expected=oracle(a,b)
   -- Stored costs are quantized to a quarter yard per edge.
   if res.status~='modeled' or math.abs(res.cost-expected)>1 then mismatches=mismatches+1 end
  end end
  check('road A* cost matches the brute-force oracle for every fixture pair',mismatches==0,tostring(mismatches))
  local spur={{0,0,0},{10,0,0},{15,0,0},{14,0,0.1},{14,0,10}}
  p.RoadRoute.TrimSpurs(spur)
  check('road routes drop reversing spurs',#spur==4 and spur[3][1]==14 and spur[3][3]==0.1)
  local bend={{0,0,0},{10,0,0},{10,0,10}};p.RoadRoute.TrimSpurs(bend)
  check('road routes keep ordinary turns',#bend==3)
  -- Follower contract.
  local unproject=function(pt)return p.Roads.Unproject(view,pt)end
  local handle=assert(p.RoadFollow.Begin(run({x=50,z=50},{x=250,z=250}),unproject))
  local d=handle.follow({x=50,z=50},{speed=7})
  check('road follower publishes the display contract',d.status=='modeled'and d.path.first>=2 and #d.path.tail>=3 and d.next and d.meters>0 and d.seconds==d.meters/7)
  local later=handle.follow({x=150,z=52},{speed=7});check('road follower advances along the line',later.meters<d.meters)
  local off=handle.follow({x=150,z=400});check('road follower flags leaving the route',off.status=='off-route')
  check('road follower rejects empty routes',not p.RoadFollow.Begin({points={}},unproject))
  end
 end)
 RikUI,C_AddOns=saved,savedAddOns;check('road network suite completes',ok,why)
end
