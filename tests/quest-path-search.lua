-- Run: luajit tests/quest-path-search.lua src/modules/questplanner/quest-path-search.lua
RikUI={QuestPlanner={}}
assert(loadfile(assert(arg[1],'PathSearch module path required')))()
local S=assert(RikUI.QuestPlanner.PathSearch)
local checks,cases=0,0
local function check(value,message)checks=checks+1;assert(value,message or 'check failed')end
local function near(a,b)check(type(a)=='number' and math.abs(a-b)<1e-9,'Expected '..tostring(b)..', got '..tostring(a))end
local function same(path,text)check(table.concat(path,',')==text,'Expected gateway path '..text..', got '..table.concat(path,','))end
local function graph(n,rows,centers)
 local out={reads=0,opens=0}
 function out:Stats()local count=0;for _,list in pairs(rows)do count=count+#list end return{gateways=n,edges=count}end
 function out:Edges(node)
  self.opens=self.opens+1;local index=0
  return function()self.reads=self.reads+1;index=index+1;local row=(rows[node] or {})[index]
   if row then return row[1],row[2],nil,index end
  end
 end
 function out:Center(node)local xyz=(centers or {})[node] or{node,0,0};return{xyz[1],xyz[2],xyz[3]}end
 function out:Original(node)return node*100+7 end
 return out
end
local function run(job,budget)
 for _=1,100000 do local result=job:Step(budget or 64);if result then return result end end error('Job failed to terminate')
end
local function case(name,body)body();cases=cases+1;print('PASS '..name)end

case('one-way reachability is preserved',function()
 local g=graph(2,{[1]={{2,3}}})
 local forward=run(S.Begin(g,{[1]=2},{[2]=4}))
 check(forward.status=='modeled');near(forward.cost,9);same(forward.gatewayPath,'1,2')
 check(#forward.links==1 and forward.links[1].from==1 and forward.links[1].to==2)
 local reverse=run(S.Begin(g,{[2]=0},{[1]=0}))
 check(reverse.status=='no-model-path');check(reverse.cost==nil)
end)
case('all starts and all goals compete against direct cost',function()
 local g=graph(4,{[1]={{3,100}},[2]={{3,1},{4,2}}})
 local best=run(S.Begin(g,{[1]=0,[2]=2},{[3]=10,[4]=0},5))
 check(best.status=='modeled' and best.direct==false);near(best.cost,4);same(best.gatewayPath,'2,4')
 local direct=run(S.Begin(g,{[1]=0,[2]=2},{[3]=10,[4]=0},3))
 check(direct.status=='modeled' and direct.direct==true);near(direct.cost,3)
 check(#direct.gatewayPath==0 and #direct.links==0)
 local tie=run(S.Begin(g,{[2]=2},{[4]=0},4))
 check(tie.direct==true,'Virtual goal wins exact-cost direct tie')
end)
case('same gateway and no attachment direct cases work',function()
 local g=graph(1,{})
 local sameNode=run(S.Begin(g,{[1]=2},{[1]=3}))
 check(sameNode.status=='modeled');near(sameNode.cost,5);same(sameNode.gatewayPath,'1');check(#sameNode.links==0)
 local direct=run(S.Begin(g,nil,nil,0))
 check(direct.status=='modeled' and direct.direct);near(direct.cost,0)
 check(run(S.Begin(g,nil,nil)).status=='no-model-path')
end)
case('cliff or floor XY coincidence never creates an edge',function()
 local g=graph(2,{},{{1,1,0},{1,1,20}})
 check(g:Original(1)~=1 and g:Original(2)~=2,'Fixture distinguishes gateway from polygon IDs')
 local result=run(S.Begin(g,{[1]=0},{[2]=0}))
 check(result.status=='no-model-path','Same XY must not imply reachability')
end)
case('zero-cost cycles and adjacency order preserve deterministic ties',function()
 local a=graph(4,{[1]={{3,1},{2,1}},[2]={{1,0},{4,1}},[3]={{4,1}}})
 local b=graph(4,{[1]={{2,1},{3,1}},[2]={{4,1},{1,0}},[3]={{4,1}}})
 local ra=run(S.Begin(a,{[1]=0},{[4]=0}),1);local rb=run(S.Begin(b,{[1]=0},{[4]=0}),64)
 near(ra.cost,2);near(rb.cost,2);same(ra.gatewayPath,'1,2,4');same(rb.gatewayPath,'1,2,4')
 local cycle=graph(3,{[1]={{2,0}},[2]={{1,0},{3,1}}})
 local rc=run(S.Begin(cycle,{[1]=0},{[3]=0}),1)
 near(rc.cost,1);same(rc.gatewayPath,'1,2,3')
end)
case('caller mutation and stale cancellation cannot change an active query',function()
 local g=graph(2,{[1]={{2,1}}});local starts,goals={[1]=2},{[2]=3}
 local job=S.Begin(g,starts,goals);starts[1]=999;goals[2]=999
 near(run(job).cost,6)
 local current=true;local stale=S.Begin(g,{[1]=0},{[2]=0},nil,{isCurrent=function()return current end})
 check(stale:Step(1)==nil);current=false;local reads=g.reads
 local result=stale:Step(64);check(result.status=='cancelled' and result.reason=='stale');check(g.reads==reads)
 check(stale:Step(64)==result,'Terminal result must remain stable')
 local cancelled=S.Begin(g,{[1]=0},{[2]=0});check(cancelled:Cancel('superseded').status=='cancelled')
 check(cancelled:Step(64).reason=='superseded')
end)
case('work, relaxation, settlement, and heap limits are strict',function()
 local g=graph(3,{[1]={{2,1},{3,5}},[2]={{3,1}}})
 for option,expected in pairs({maxWork='work-limit',maxRelaxations='relaxation-limit',maxSettled='settled-limit',maxHeap='heap-limit'})do
  local limits={[option]=1};local result=run(S.Begin(g,{[1]=0},{[3]=0},nil,limits),64)
  check(result.status=='limited' and result.reason==expected,'Wrong limit result for '..option)
  check(result.cost==nil,'An incomplete query must not publish a modeled route')
  if option=='maxWork'then check(result.metrics.work<=1)end
  if option=='maxRelaxations'then check(result.metrics.relaxations<=1)end
  if option=='maxSettled'then check(result.metrics.settled<=1)end
  if option=='maxHeap'then check(result.metrics.peakHeap<=1)end
 end
end)
case('endpoint and weight validation fail closed',function()
 local g=graph(130,{})
 local starts={}for i=1,129 do starts[i]=0 end
 check(run(S.Begin(g,starts,{[1]=0})).status=='invalid')
 for _,bad in ipairs({{[0]=1},{[131]=1},{[1]=-1},{[1]=math.huge},{['1']=0}})do
  check(run(S.Begin(g,bad,{[1]=0})).status=='invalid')
 end
 check(run(S.Begin(g,{[1]=0},{[1]=0},-1)).status=='invalid')
 check(run(S.Begin(g,{[1]=0},{[1]=0},nil,{maxWork=0})).status=='invalid')
 check(run(S.Begin(graph(2,{[1]={{2,-1}}}),{[1]=0},{[2]=0})).status=='invalid')
 check(run(S.Begin(graph(2,{[1]={{3,1}}}),{[1]=0},{[2]=0})).status=='invalid')
end)
case('goal settlement stops before irrelevant distant branch',function()
 local g=graph(5,{[1]={{2,1},{3,100}},[3]={{4,1}},[4]={{5,1}}})
 local result=run(S.Begin(g,{[1]=0},{[2]=0}))
 check(result.status=='modeled');near(result.cost,1);check(result.metrics.settled==2)
end)
case('long reconstruction is sliced and deterministic across budgets',function()
 local rows={}for i=1,399 do rows[i]={{i+1,1}}end
 local g=graph(400,rows);local job=S.Begin(g,{[1]=2},{[400]=3});local result,calls
 for i=1,10000 do
  local before=g.reads;result=job:Step(1);check(g.reads-before<=1,'One unit must not traverse multiple edges')
  if result then calls=i;break end
 end
 check(result and result.status=='modeled');near(result.cost,404);check(#result.gatewayPath==400 and #result.links==399)
 check(calls==result.metrics.work,'Step(1) must consume exactly one recorded operation per call')
 local bulk=run(S.Begin(graph(400,rows),{[1]=2},{[400]=3}),64)
 near(bulk.cost,result.cost);check(bulk.metrics.work==result.metrics.work)
 check(table.concat(bulk.gatewayPath,',')==table.concat(result.gatewayPath,','))
end)
case('generated small directed graphs match an independent all-pairs oracle',function()
 local seed=1739
 local function random(limit)seed=(seed*48271)%2147483647;return seed%limit end
 for fixture=1,500 do
  local n=2+random(7);local rows,distance={},{}
  for from=1,n do
   rows[from]={};distance[from]={}
   for to=1,n do
    distance[from][to]=from==to and 0 or math.huge
    if from~=to and random(4)==0 then
     local cost=random(11);rows[from][#rows[from]+1]={to,cost};distance[from][to]=cost
    end
   end
  end
  -- Floyd-Warshall is independent of the production heap, predecessors, and slicing.
  for via=1,n do for from=1,n do for to=1,n do
   distance[from][to]=math.min(distance[from][to],distance[from][via]+distance[via][to])
  end end end
  local starts,goals={},{}
  for _=1,1+random(3)do starts[1+random(n)]=random(8)end
  for _=1,1+random(3)do goals[1+random(n)]=random(8)end
  local direct=random(4)==0 and random(20) or nil;local best=direct or math.huge
  for from,startCost in pairs(starts)do for to,goalCost in pairs(goals)do
   best=math.min(best,startCost+distance[from][to]+goalCost)
  end end
  local result=run(S.Begin(graph(n,rows),starts,goals,direct),1+random(64))
  if best==math.huge then check(result.status=='no-model-path','Oracle disconnected fixture '..fixture)
  else
   check(result.status=='modeled','Oracle feasible fixture '..fixture);near(result.cost,best)
   if result.direct then near(result.cost,direct)
   else
    local path=result.gatewayPath;check(#path>=1 and #result.links==#path-1)
    local total=assert(starts[path[1]])+assert(goals[path[#path]])
    for index=1,#path-1 do
     local weight=math.huge
     for _,row in ipairs(rows[path[index]])do if row[1]==path[index+1]then weight=math.min(weight,row[2])end end
     check(weight<math.huge,'Returned an edge outside the compiled model')
     check(result.links[index].from==path[index] and result.links[index].to==path[index+1])
     total=total+weight
    end
    near(total,result.cost)
   end
  end
 end
end)
print(string.format('quest-path-search: %d cases / %d checks passed',cases,checks))
