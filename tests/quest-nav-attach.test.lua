-- Loaded from repository root by the standard Lua harness.
-- Directed local polygon fixtures; this is model verification, not native terrain evidence.
return function(check)
 local originalCore=RikUI
 RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
 dofile('src/modules/questplanner/quest-schema.lua')
 local planner=assert(RikUI.QuestPlanner)
 local oldGeometry,oldAttach=planner.NavGeometry,planner.NavAttach
 local function near(a,b)return type(a)=='number' and math.abs(a-b)<=1e-8*math.max(1,math.abs(b))end
 local function length(a,b)return math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2+(a[3]-b[3])^2)end
 local function point(center,dx,dy)return{center[1]+(dx or 0),center[2],center[3]+(dy or 0)}end
 local function count(map)local n=0;for _ in pairs(map or {})do n=n+1 end return n end
 local function mesh(cells,links)
  local data={polygons={},order={}}
  for _,cell in ipairs(cells)do
   local id,x,z,y=cell[1],cell[2],cell[3],cell[4] or 0
   data.order[#data.order+1]=id
   data.polygons[id]={id=id,center={x,y,z},points={{x-.5,y,z-.5},{x+.5,y,z-.5},{x+.5,y,z+.5},{x-.5,y,z+.5}},portals={}}
  end
  table.sort(data.order)
  for _,link in ipairs(links or {})do
   local from,to=data.polygons[link[1]],data.polygons[link[2]]
   local a,b=from.center,to.center;local dx,dy=b[1]-a[1],b[3]-a[3]
   assert(math.abs(dx)+math.abs(dy)==1 and a[2]==b[2],'Fixture portals must join shared square edges')
   local mid={(a[1]+b[1])/2,a[2],(a[3]+b[3])/2}
   from.portals[#from.portals+1]={to=to.id,meters=length(a,b),
    left={mid[1]-dy*.5,mid[2],mid[3]+dx*.5},right={mid[1]+dy*.5,mid[2],mid[3]-dx*.5},midpoint=mid}
  end
  return data
 end
 local function graph(mapping)
  return{Gateway=function(_,originalID)return mapping[originalID]end}
 end
 local function finish(job,budget)
  assert(type(job)=='table','Expected a sliced job')
  for _=1,100000 do
   local output,problem,done=job:Step(budget or 64)
   if done then return output,problem end
   assert(output==nil,'Intermediate step must not expose a finished result')
  end
  error('Sliced job did not terminate')
 end
 local function solve(data,start,goal,network,budget)
  local job,problem=planner.NavAttach.Begin(data,start,goal,network)
  assert(job,'NavAttach.Begin failed: '..tostring(problem))
  local result,why=finish(job,budget);assert(result,'NavAttach failed: '..tostring(why))
  return result,job
 end
 local function floyd(data)
  local d={}
  for _,from in ipairs(data.order)do
   d[from]={};for _,to in ipairs(data.order)do d[from][to]=from==to and 0 or math.huge end
   for _,portal in ipairs(data.polygons[from].portals)do d[from][portal.to]=math.min(d[from][portal.to],portal.meters)end
  end
  for _,via in ipairs(data.order)do for _,from in ipairs(data.order)do for _,to in ipairs(data.order)do
   d[from][to]=math.min(d[from][to],d[from][via]+d[via][to])
  end end end
  return d
 end
 local function pathCost(data,path,first,last)
  if type(path)~='table' or #path==0 or path[1]~=first or path[#path]~=last then return nil end
  local total,seen=0,{}
  for i,id in ipairs(path)do
   if seen[id] or not data.polygons[id]then return nil end;seen[id]=true
   if i<#path then
    local cost=math.huge
    for _,portal in ipairs(data.polygons[id].portals)do if portal.to==path[i+1]then cost=math.min(cost,portal.meters)end end
    if cost==math.huge then return nil end;total=total+cost
   end
  end
  return total
 end
 local function leg(result,name,gateway)
  local job,problem=result[name](result,gateway)
  if not job then return nil,problem end
  return finish(job,1)
 end
 local function location(data,id,dx,dy)return{id=id,point=point(data.polygons[id].center,dx,dy)}end
 local function line(n)
  local cells,links,mapping={},{},{}
  for i=1,n do cells[i]={10000+i,i-1,0,0};mapping[10000+i]=i
   if i>1 then links[#links+1]={10000+i-1,10000+i}end
  end
  return mesh(cells,links),mapping
 end
 local function failed(job,problem)
  if not job then return type(problem)=='string' and problem~='' end
  local output,why=finish(job,64);return output==nil and type(why)=='string' and why~=''
 end
 local function run()
  dofile('src/modules/questplanner/quest-nav-geometry.lua')
  dofile('src/modules/questplanner/quest-nav-attach.lua')
  assert(planner.NavAttach,'NavAttach export missing')
  local data=mesh({{101,0,0},{203,1,0},{307,2,0},{409,0,1},{503,1,1},{607,2,1},{709,0,0,20}},
   {{101,203},{203,307},{101,409},{409,503},{503,203},{203,503},{503,607},{307,607}})
  local mapping={[101]=9,[203]=16,[307]=23,[409]=30,[503]=37,[607]=44,[709]=51}
  local network=graph(mapping);local distances=floyd(data)
  for _,startID in ipairs(data.order)do for _,goalID in ipairs(data.order)do
   local start=location(data,startID,.1,.2);local goal=location(data,goalID,-.2,.1)
   local result=solve(data,start,goal,network,1)
   local startOffset=length(start.point,data.polygons[startID].center)
   local goalOffset=length(goal.point,data.polygons[goalID].center)
   local expectedStarts,expectedGoals=0,0
   for _,id in ipairs(data.order)do
    local gateway=mapping[id];local forward,reverse=distances[startID][id],distances[id][goalID]
    if forward<math.huge then
     expectedStarts=expectedStarts+1
     check('NavAttach prefix distance '..startID..' to '..id,near(result.starts[gateway],startOffset+forward))
     local path=leg(result,'BeginPrefix',gateway);local cost=pathCost(data,path,startID,id)
     check('NavAttach prefix uses forward original polygon links '..startID..' to '..id,cost~=nil and near(cost+startOffset,result.starts[gateway]))
    else check('NavAttach prefix does not cross a missing directed link '..startID..' to '..id,result.starts[gateway]==nil)end
    if reverse<math.huge then
     expectedGoals=expectedGoals+1
     check('NavAttach suffix reverse-search distance '..id..' to '..goalID,near(result.goals[gateway],reverse+goalOffset))
     local path=leg(result,'BeginSuffix',gateway);local cost=pathCost(data,path,id,goalID)
     check('NavAttach suffix reconstruction follows forward portals '..id..' to '..goalID,cost~=nil and near(cost+goalOffset,result.goals[gateway]))
    else check('NavAttach suffix does not reverse a one-way portal '..id..' to '..goalID,result.goals[gateway]==nil)end
   end
   check('NavAttach includes all and only reachable dense starts '..startID..'/'..goalID,count(result.starts)==expectedStarts)
   check('NavAttach includes all and only reachable dense goals '..startID..'/'..goalID,count(result.goals)==expectedGoals)
   local direct=distances[startID][goalID]
   if startID==goalID then direct=length(start.point,goal.point)
   elseif direct<math.huge then direct=direct+startOffset+goalOffset end
   if direct<math.huge then
    check('NavAttach direct modeled cost '..startID..'/'..goalID,near(result.directCost,direct))
    local path=leg(result,'BeginDirect');local cost=pathCost(data,path,startID,goalID)
    check('NavAttach direct witness continuity '..startID..'/'..goalID,cost~=nil and(startID==goalID or near(cost+startOffset+goalOffset,direct)))
   else
    check('NavAttach disconnected direct path stays unavailable '..startID..'/'..goalID,result.directCost==nil)
    local path,problem=leg(result,'BeginDirect')
    check('NavAttach unavailable direct witness cannot invent a path '..startID..'/'..goalID,path==nil and type(problem)=='string')
   end
  end end

  local farther=mesh({{1001,0,0},{1002,1,0},{1003,2,0},{1004,4,0}},{{1001,1002},{1002,1003}})
  local all=solve(farther,location(farther,1001),location(farther,1004),graph({[1001]=7,[1003]=8,[1004]=9}),1)
  check('NavAttach retains nearer and farther gateway candidates',near(all.starts[7],0) and near(all.starts[8],2) and count(all.starts)==2)
  check('NavAttach retains goal component without inventing local connection',near(all.goals[9],0) and all.directCost==nil)
  -- A global graph can connect dense8->dense9 while dense7 is a dead end; no nearest-only pruning is allowed.
  check('NavAttach preserves farther candidate needed by global continuation',all.starts[8]~=nil)

  local emptyNetwork=graph({});local localOnly=solve(data,location(data,101),location(data,607),emptyNetwork)
  check('NavAttach no-network case retains local direct route',count(localOnly.starts)==0 and count(localOnly.goals)==0 and near(localOnly.directCost,3))
  local localPath=leg(localOnly,'BeginDirect')
  check('NavAttach local-only witness is usable',near(pathCost(data,localPath,101,607),3))
  local disconnected=solve(data,location(data,101),location(data,709),emptyNetwork)
  check('NavAttach empty attachments and absent direct path are valid model coverage',count(disconnected.starts)==0 and count(disconnected.goals)==0 and disconnected.directCost==nil)

  local job=assert(planner.NavAttach.Begin(data,location(data,101),location(data,607),network))
  local previous=job:Progress();check('NavAttach Progress is numeric',type(previous)=='number')
  local result
  for _=1,10000 do
   local output,problem,done=job:Step(1);local current=job:Progress()
   check('NavAttach one-unit step bounds counted work',type(current)=='number' and current>=previous and current-previous<=1)
   previous=current
   if done then assert(output,problem);result=output;break end
  end
  check('NavAttach sliced solve terminates',result~=nil)
  check('NavAttach result work agrees with Progress',result and result.work==job:Progress())
  local after=job:Progress();job:Step(64)
  check('NavAttach completed job does not perform more work',job:Progress()==after)
  local cancelled=assert(planner.NavAttach.Begin(data,location(data,101),location(data,607),network))
  cancelled:Step(1);local before=cancelled:Progress();cancelled:Cancel()
  local cancelledOutput,cancelledWhy,cancelledDone=cancelled:Step(64)
  check('NavAttach cancellation terminates without an attachment result',cancelledDone and cancelledOutput==nil and type(cancelledWhy)=='string')
  check('NavAttach cancellation performs no further work',cancelled:Progress()==before)
  cancelled:Step(64);check('NavAttach repeated cancelled steps are inert',cancelled:Progress()==before)
  local prefix=assert(result:BeginPrefix(mapping[607]));prefix:Step(1);prefix:Cancel()
  local cancelledPath,legWhy,legDone=prefix:Step(64)
  check('NavAttach leg reconstruction honors cancellation',legDone and cancelledPath==nil and type(legWhy)=='string')

  local boundary,boundaryMap=line(128)
  local admitted=solve(boundary,location(boundary,10001),location(boundary,10128),graph(boundaryMap),64)
  check('NavAttach admits exactly128 gateways per direction',count(admitted.starts)==128 and count(admitted.goals)==128)
  local large,largeMap=line(256)
  local capJob,capWhy=planner.NavAttach.Begin(large,location(large,10001),location(large,10256),graph(largeMap))
  check('NavAttach256 reachable gateways fails explicitly instead of dropping candidates',failed(capJob,capWhy))
  -- Forward sees only the final node here; reverse search reaches all256 and must enforce its own cap.
  local reverseJob,reverseWhy=planner.NavAttach.Begin(large,location(large,10256),location(large,10256),graph(largeMap))
  check('NavAttach reverse gateway cap is independently enforced',failed(reverseJob,reverseWhy))
  local missingJob,missingWhy=planner.NavAttach.Begin(data,{id=999999,point={0,0,0}},location(data,101),network)
  check('NavAttach missing endpoint fails explicitly',failed(missingJob,missingWhy))

  local long=select(1,line(4097));local longResult=solve(long,location(long,10001),location(long,14097),graph({[14097]=1}),64)
  local tooLong,tooLongWhy=longResult:BeginPrefix(1)
  check('NavAttach reconstruction cap rejects more than4096 polygons',failed(tooLong,tooLongWhy))
 end
 local ok,problem=xpcall(run,function(err)return debug and debug.traceback and debug.traceback(err,2) or tostring(err)end)
 planner.NavGeometry=oldGeometry;planner.NavAttach=oldAttach
 RikUI=originalCore
 if not ok then error(problem,0)end
end
