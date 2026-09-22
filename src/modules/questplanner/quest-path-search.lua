-- Bounded, incremental Dijkstra over a compiled directed gateway network.
-- Attachment and edge costs are DISTANCES in one consistent unit, never seconds.
local planner=RikUI.QuestPlanner
local search={REVISION='gateway-dijkstra-1'}
planner.PathSearch=search
local Job={};Job.__index=Job
local defaults={maxWork=250000,maxRelaxations=200000,maxSettled=8192,maxHeap=8192}
local maximums={maxWork=1000000,maxRelaxations=1000000,maxSettled=65536,maxHeap=65536}
local function finite(value)
 return type(value)=='number' and value==value and math.abs(value)<math.huge
end
local function integer(value,minimum,maximum)
 return finite(value) and value%1==0 and value>=minimum and value<=maximum
end
local function metrics(job)
 return{work=job.work or 0,settled=job.settledCount or 0,relaxations=job.relaxations or 0,
  peakHeap=job.peakHeap or 0}
end
local function finish(job,status,reason,result)
 if job.result then return job.result end
 result=result or {};result.status=status;result.reason=reason;result.metrics=metrics(job)
 job.result=result
 job.graph=nil;job.iterator=nil;job.heap=nil;job.positions=nil;job.distance=nil
 job.parents=nil;job.settled=nil;job.goals=nil;job.reverse=nil;job.path=nil;job.links=nil
 job.isCurrent=nil
 return result
end
local function less(a,b)
 return a.cost<b.cost or a.cost==b.cost and a.node<b.node
end
local function swap(job,a,b)
 local heap=job.heap;heap[a],heap[b]=heap[b],heap[a]
 job.positions[heap[a].node]=a;job.positions[heap[b].node]=b
end
local function up(job,index)
 while index>1 do
  local parent=math.floor(index/2)
  if not less(job.heap[index],job.heap[parent])then break end
  swap(job,index,parent);index=parent
 end
end
local function pop(job)
 local heap=job.heap;local first=heap[1]
 if not first then return nil end
 local last=table.remove(heap);job.positions[first.node]=nil
 if #heap>0 then
  heap[1]=last;job.positions[last.node]=1;local index=1
  while index*2<=#heap do
   local child=index*2
   if child<#heap and less(heap[child+1],heap[child])then child=child+1 end
   if not less(heap[child],heap[index])then break end
   swap(job,index,child);index=child
  end
 end
 return first
end
local function relax(job,node,cost,parent)
 if not finite(cost)then finish(job,'invalid','distance-overflow');return false end
 if job.settled[node] or job.distance[node] and cost>=job.distance[node]then return true end
 local index=job.positions[node]
 if not index and #job.heap>=job.limits.maxHeap then finish(job,'limited','heap-limit');return false end
 job.distance[node]=cost;job.parents[node]=parent
 if index then job.heap[index].cost=cost
 else index=#job.heap+1;job.heap[index]={node=node,cost=cost};job.positions[node]=index end
 up(job,index);job.peakHeap=math.max(job.peakHeap,#job.heap)
 return true
end
local function copyAttachments(input,gateways)
 if input==nil then return {},{} end
 if type(input)~='table'then return nil,nil,'attachment-map-required' end
 local values,keys={},{}
 for node,cost in pairs(input)do
  if #keys>=128 then return nil,nil,'attachment-count-limit' end
  if not integer(node,1,gateways) or not finite(cost) or cost<0 then return nil,nil,'invalid-attachment' end
  values[node]=cost;keys[#keys+1]=node
 end
 table.sort(keys);return values,keys
end
local function take(job)
 if job.work>=job.limits.maxWork then finish(job,'limited','work-limit');return false end
 job.work=job.work+1;return true
end
local function terminalGoal(job,row)
 job.pathCost=row.cost
 local parent=job.parents[0]
 if parent==nil then
  finish(job,'modeled',nil,{cost=row.cost,gatewayPath={},links={},direct=true})
 else job.trace=parent;job.reverse={};job.phase='trace' end
end
local function settle(job)
 local row=pop(job)
 if not row then
  finish(job,'no-model-path','no-connected-path-for-these-attachments');return
 end
 if row.node==0 then terminalGoal(job,row);return end
 if job.settledCount>=job.limits.maxSettled then finish(job,'limited','settled-limit');return end
 job.settled[row.node]=true;job.settledCount=job.settledCount+1
 job.current=row.node;job.currentCost=row.cost
 if job.goals[row.node]~=nil then job.phase='goal' else job.phase='open-edges' end
end
local function goalArc(job)
 if job.relaxations>=job.limits.maxRelaxations then finish(job,'limited','relaxation-limit');return end
 job.relaxations=job.relaxations+1
 if relax(job,0,job.currentCost+job.goals[job.current],job.current)then job.phase='open-edges' end
end
local function openEdges(job)
 local ok,iterator=pcall(job.graph.Edges,job.graph,job.current)
 if not ok or type(iterator)~='function'then finish(job,'invalid','edge-iterator-unavailable');return end
 job.iterator=iterator;job.phase='edges'
end
local function edge(job)
 local ok,target,cost=pcall(job.iterator)
 if not ok then finish(job,'invalid','edge-iterator-failed');return end
 if target==nil then job.iterator=nil;job.phase='pop';return end
 if not integer(target,1,job.gateways) or not finite(cost) or cost<0 then finish(job,'invalid','invalid-edge');return end
 if job.relaxations>=job.limits.maxRelaxations then finish(job,'limited','relaxation-limit');return end
 job.relaxations=job.relaxations+1
 relax(job,target,job.currentCost+cost,job.current)
end
local function trace(job)
 if #job.reverse>=job.settledCount then finish(job,'invalid','parent-chain-cycle');return end
 job.reverse[#job.reverse+1]=job.trace;job.trace=job.parents[job.trace]
 if job.trace==nil then
  job.path={};job.links={};job.buildIndex=#job.reverse;job.phase='build'
 end
end
local function build(job)
 local node=job.reverse[job.buildIndex];local previous=job.path[#job.path]
 job.path[#job.path+1]=node
 if previous then job.links[#job.links+1]={from=previous,to=node}end
 job.buildIndex=job.buildIndex-1
 if job.buildIndex==0 then
  finish(job,'modeled',nil,{cost=job.pathCost,gatewayPath=job.path,links=job.links,direct=false})
 end
end
function Job:Cancel(reason)
 return finish(self,'cancelled',type(reason)=='string' and reason:sub(1,96) or 'cancelled')
end
function Job:Step(budget)
 if self.result then return self.result end
 if self.isCurrent then
  local ok,current=pcall(self.isCurrent)
  if not ok or current~=true then return self:Cancel(ok and 'stale' or 'freshness-check-failed')end
 end
 budget=finite(budget) and math.floor(budget) or 32;budget=math.max(1,math.min(64,budget))
 for _=1,budget do
  if not take(self)then return self.result end
  if self.phase=='pop'then settle(self)
  elseif self.phase=='goal'then goalArc(self)
  elseif self.phase=='open-edges'then openEdges(self)
  elseif self.phase=='edges'then edge(self)
  elseif self.phase=='trace'then trace(self)
  elseif self.phase=='build'then build(self)
  else return finish(self,'invalid','invalid-search-phase')end
  if self.result then return self.result end
 end
 return nil
end
function search.Begin(graph,starts,goals,directCost,options)
 local job=setmetatable({work=0,settledCount=0,relaxations=0,peakHeap=0},Job)
 if options==nil then options={}end
 if type(options)~='table' or type(graph)~='table' or type(graph.Stats)~='function' or type(graph.Edges)~='function'then
  finish(job,'invalid','invalid-graph-or-options');return job
 end
 local ok,stats=pcall(graph.Stats,graph)
 if not ok or type(stats)~='table' or not integer(stats.gateways,0,1000000)then
  finish(job,'invalid','invalid-graph-stats');return job
 end
 job.limits={}
 for name,default in pairs(defaults)do
  local value=options[name];if value==nil then value=default end
  if not integer(value,1,maximums[name])then finish(job,'invalid','invalid-'..name);return job end
  job.limits[name]=value
 end
 if options.isCurrent~=nil and type(options.isCurrent)~='function'then
  finish(job,'invalid','invalid-freshness-callback');return job
 end
 if directCost~=nil and(not finite(directCost) or directCost<0)then finish(job,'invalid','invalid-direct-cost');return job end
 local startValues,startKeys,startProblem=copyAttachments(starts,stats.gateways)
 local goalValues,goalKeys,goalProblem=copyAttachments(goals,stats.gateways)
 if not startValues or not goalValues then finish(job,'invalid',startProblem or goalProblem);return job end
 job.graph=graph;job.gateways=stats.gateways;job.goals=goalValues;job.isCurrent=options.isCurrent
 job.heap={};job.positions={};job.distance={};job.parents={};job.settled={};job.phase='pop'
 if directCost~=nil then relax(job,0,directCost,nil)end
 -- When no goal can be attached, only the supplied direct path can be used.
 if #goalKeys>0 then
  for _,node in ipairs(startKeys)do if not relax(job,node,startValues[node],nil)then break end end
 end
 return job
end
