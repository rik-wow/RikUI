-- Run: lua tests/quest-plan-heldout.lua ADDON_ROOT [REPO_ROOT] [REPORT_JSON] [EXTERNAL_AUTHORED_FACTS_LUA]
-- Source-held-out model benchmark: real corpus, synthetic character/log/history/resources/travel.
-- Exact enumeration shares production transitions/costs/scoring: not an independent mechanics oracle.
-- Restricted 3-quest turn-in graph, <=2 source finisher methods per quest. No native reachability claim.
-- Optional arg[3] writes a structured JSON report; stdout always reports coverage and comparisons.
local addonRoot=assert(arg[1],'ADDON_ROOT required');local repo=arg[2] or '.'
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function copy(t)local o={} for k,v in pairs(t or {})do o[k]=v end return o end
local function append(t,v)local o={}for i,x in ipairs(t)do o[i]=x end o[#o+1]=v return o end
local function ids(rows)local o={}for i,a in ipairs(rows or {})do o[i]='|'..a.id end return table.concat(o)end
GetTime=function()return 1 end
RikUI={};RikUI['Secret']={IsSecret=function() return false end,Read=pcall}
local activeContext
C_AddOns={LoadAddOn=function() error('embedded corpus never loads addons') end}
local function module(name)dofile(repo..'/src/modules/questplanner/quest-'..name..'.lua')end
module('schema');local p=assert(RikUI.QuestPlanner);local history={}
p.Context={History=function(requested)
 local out={}for _,id in ipairs(requested or {})do if history[id]~=nil then out[id]=history[id]end end return out
end,Call=function(fn,...)if type(fn)~='function'then return false end return pcall(fn,...)end,
 Frame=function()return{position=activeContext and activeContext.position,width=1000,height=1000}end}
for _,name in ipairs({'objectives','transfer','optimizer','area-optimizer','steps','step-bindings',
 'guide-data','observed-steps','semantic-data','waypoints','objective-guide','semantic-guidance','hunts','targets','guidance',
 'preferences','plan-state','plan-graph','plan-transitions','plan-learning','plan-costs','plan-rewards','plan-search','evidence','eligibility','elevators','travel','actions','simulation','recommendations'})do module(name)end
local generated=dofile(repo..'/tests/generated_stub.lua')
generated.Load(generated.Base(addonRoot),{'corpus'})
local catalog=assert(RikUIQuestCorpusCatalog);local identity=assert(catalog.identity)
local partitionSize=assert(tonumber(catalog.partitionSize));assert(partitionSize>0 and partitionSize%1==0)
local flavors={'Balanced','Efficient','Story','Explorer','Relaxed','Challenge'}
local maps={1426,1429,1411,1412,1438}
-- Valid original-Classic combinations, not a claim about additional Forever combinations.
local archetypes={
 {name='Human warrior',class=1,race=1,faction='Alliance'},
 {name='Dwarf paladin',class=2,race=3,faction='Alliance'},
 {name='Orc hunter',class=3,race=2,faction='Horde'},
 {name='Gnome rogue',class=4,race=7,faction='Alliance'},
 {name='Troll priest',class=5,race=8,faction='Horde'},
 {name='Tauren shaman',class=7,race=6,faction='Horde'},
 {name='Undead mage',class=8,race=5,faction='Horde'},
 {name='Human warlock',class=9,race=1,faction='Alliance'},
 {name='Night elf druid',class=11,race=4,faction='Alliance'},
}
local personas={}
for _,a in ipairs(archetypes)do for _,level in ipairs({10,20})do
 local persona=copy(a);persona.level=level;persona.id=a.faction..':'..a.class..':'..a.race..':'..level
 personas[#personas+1]=persona
end end
local buckets={}
for k in pairs(assert(catalog.partitions))do local n=assert(tonumber(k),'Non-numeric bucket');assert(n>=0 and n%1==0);buckets[#buckets+1]=n end
table.sort(buckets)
local function policy(flavor)
 local pref=p.Preferences.Normalize({flavor=flavor,readingSeconds=0,strictSession=true})
 pref.maxSeconds=3600;return pref
end
local function context(persona,map)
 return{origin='live',identity=identity,observedAt=1,characterKey='heldout:'..persona.id,history=history,
 attributes={level=persona.level,xp=0,xpMax=1000,class=persona.class,race=persona.race,faction=persona.faction,logCapacity=20},
 position={mapID=map,x=.5,y=.5},inventory={},inventoryExact=true,bagFree=20,partySize=1,money=10000,skills={},spells={},reputation={}}
end
local function loadPartitions(ctx)
 local records={};local count=0
 for _,bucket in ipairs(buckets)do
  p.SemanticData.Ensure({identity=identity,order={bucket*partitionSize+1},quests={}},ctx)
  local n=0
  while(p.SemanticData.Status().queuedPartitions or 0)>0 do
   p.SemanticData.Step(64);n=n+1;assert(n<50000,'Corpus queue did not settle')
  end
  -- Capture before any bounded semantic cache can evict a partition.
  for id=math.max(1,bucket*partitionSize),(bucket+1)*partitionSize-1 do
   local record=p.SemanticData.Quest(identity,id)
   if record then records[id]=record;history[id]=false;count=count+1 end
  end
 end
 return records,count
end
local function state(order,records,ctx,pref)
 local quests={}for _,id in ipairs(order)do local r=assert(records[id]);local lv=tonumber(r.eligibility and r.eligibility.questLevel)
  if not lv or lv<1 then lv=ctx.attributes.level end
  quests[id]={id=id,title=r.title or r.name or('Quest '..id),level=lv,objectivesComplete=true,failed=false,objectives={}}
 end
 local snap={origin='live',identity=identity,generation=1,reportedCount=#order,observedCount=#order,coverage='log-complete',order=order,quests=quests}
 local out,why=p.PlanState.Build(snap,{state='current'},ctx,records,pref);assert(out and out.fresh,'State not fresh: '..tostring(why));return out
end
local function graph(initial,records,pref)
 local job=p.PlanGraph.Begin(initial,records,{},pref)
 for _=1,50000 do local out=job:Step(64);if out then assert(out.status=='ready');return out end end error('Graph cap exceeded')
end
local function positive(v)return tonumber(v) and tonumber(v)>0 end
local function noItems(r)
 if positive(r.providedItemID) or type(r.requiredItems)=='table' and next(r.requiredItems)then return false end
 for _,o in pairs(r.objectives or {})do if type(o)=='table' and(o.kind=='item' or o.type=='item' or positive(o.itemID) or positive(o.sourceItemID))then return false end end return true
end
local function fixture(map,ctx,corpus)
 local candidates={}for _,id in ipairs(catalog.planning.maps[map] or catalog.planning.maps[tostring(map)] or {})do candidates[#candidates+1]=assert(tonumber(id))end table.sort(candidates)
 local chosen,records={},{};local pref=policy('Balanced')
 for _,id in ipairs(candidates)do local r=corpus[id]
  if r and noItems(r)then local one={[id]=r};local empty=state({},one,ctx,pref);local available=false
   for _,a in ipairs(graph(empty,one,pref).actions or {})do if a.questID==id and a.kind=='pickup' and p.PlanTransitions.Check(a,empty,pref)==true then available=true;break end end
   if available then local active=state({id},one,ctx,pref);local finish=false
    for _,a in ipairs(graph(active,one,pref).actions or {})do if a.questID==id and a.kind=='turnin' and a.destination and a.destination.mapID==map and finite(a.destination.x) and finite(a.destination.y) and p.PlanTransitions.Check(a,active,pref)==true then finish=true;break end end
    if finish then chosen[#chosen+1]=id;records[id]=r end
   end
   if #chosen==3 then return chosen,records end
  end
 end return nil,'Fewer than three eligible item-free same-map finishers ('..#chosen..')'
end
local function environment()return{travel=function(a,b)
 if not a or not b or a.mapID~=b.mapID or not finite(a.x) or not finite(a.y) or not finite(b.x) or not finite(b.y) then return nil end
 local s=math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)*1000/7;return{seconds=s,lower=s,upper=s,status='authored'}
end}end
local function restrictedGraph(initial,records,pref)
 local full=graph(initial,records,pref);local grouped={}
 for _,a in ipairs(full.actions or {})do if a.kind=='turnin' and records[a.questID] and a.destination and a.destination.mapID==initial.position.mapID and p.PlanTransitions.Check(a,initial,pref)==true then
  grouped[a.questID]=grouped[a.questID] or {};table.insert(grouped[a.questID],a)
 end end
 local keep={}for _,rows in pairs(grouped)do table.sort(rows,function(a,b)
  local da=(a.destination.x-.5)^2+(a.destination.y-.5)^2;local db=(b.destination.x-.5)^2+(b.destination.y-.5)^2
  if da~=db then return da<db end return a.id<b.id end)
  for i=1,math.min(2,#rows)do keep[rows[i].id]=true end
 end
 local out=copy(full);out.actions={};out.byID={};out.byQuest={}
 for _,a in ipairs(full.actions or {})do if keep[a.id]then out.actions[#out.actions+1]=a;out.byID[a.id]=a end end
 for q,rows in pairs(full.byQuest or {})do assert(type(rows)=='table','Unexpected byQuest shape')
  for k in pairs(rows)do assert(type(k)=='number' and k%1==0 and k>=1 and k<=#rows,'Unexpected byQuest key')end
  local selected={}for _,entry in ipairs(rows)do assert(type(entry)=='table','byQuest must contain action objects');local id=entry.id;assert(type(id)=='string','Unexpected byQuest action ID')
   if keep[id]then selected[#selected+1]=entry end
  end if #selected>0 then out.byQuest[q]=selected end
 end assert(#out.actions>=3 and #out.actions<=6,'Expected 3-6 source finisher methods');return out
end
local function rootNode(initial)return{state=p.PlanTransitions.Fork(initial),actions={},costs={},key=''}end
local function extend(node,a,pref,env)
 if p.PlanTransitions.Check(a,node.state,pref)~=true then return nil end
 local cost=p.PlanCosts.Estimate(a,node.state,pref,env);if not cost then return nil end
 assert(finite(cost.seconds) and cost.seconds>=0 and finite(cost.lower) and finite(cost.upper) and cost.lower>=0 and cost.lower<=cost.seconds and cost.seconds<=cost.upper,'Invalid cost interval')
 if pref.strictSession and(node.state.upperElapsed or 0)+cost.upper>pref.maxSeconds then return nil end
 local nextState=p.PlanTransitions.Apply(a,node.state,pref,cost);if not nextState then return nil end
 assert(finite(nextState.elapsed) and finite(nextState.upperElapsed),'Missing cumulative time')
 assert(not pref.strictSession or nextState.upperElapsed<=pref.maxSeconds,'Strict prefix exceeded session')
 local actions=append(node.actions,a);return{state=nextState,actions=actions,costs=append(node.costs,cost),key=ids(actions)}
end
local function scored(node,initial,pref)node.score,node.features=p.PlanSearch.Score(node,initial,pref);assert(finite(node.score));return node end
local function better(a,b)
 if not b then return true end if a.score~=b.score then return a.score>b.score end
 if a.features.progress~=b.features.progress then return a.features.progress>b.features.progress end
 if a.state.elapsed~=b.state.elapsed then return a.state.elapsed<b.state.elapsed end return a.key<b.key
end
local function within(node,baseline,pref)local f=node.features
 return f.pinned or f.efficiency>=baseline/(1+pref.detour) or baseline==0 or f.progress==0 and f.unknownXP>0
end
local function pick(nodes,baseline,pref)
 local best,fallback
 for _,n in ipairs(nodes)do if better(n,fallback)then fallback=n end
  if n.state.elapsed<=pref.maxSeconds and within(n,baseline,pref) and better(n,best)then best=n end
 end return best or fallback,best==nil
end
local function oracle(g,initial,pref,env,maxDepth)
 maxDepth=maxDepth or 3
 local nodes={};local baseline=0;local upper;local visits=0
 local function walk(node)
  visits=visits+1;assert(visits<=100000,'Oracle cap exceeded')
  if #node.actions>0 then scored(node,initial,pref);nodes[#nodes+1]=node;if better(node,upper)then upper=node end
   if node.features.finished>0 and node.state.elapsed<=pref.maxSeconds then baseline=math.max(baseline,node.features.efficiency)end
  end
  if #node.actions==maxDepth then return end
  for _,a in ipairs(g.actions)do local nextNode=extend(node,a,pref,env);if nextNode then walk(nextNode)end end
 end
 walk(rootNode(initial));assert(upper,'No feasible oracle trajectory');local ideal,fallback=pick(nodes,baseline,pref);return upper,ideal,baseline,visits,fallback
end
local function greedy(g,initial,pref,env,baseline,maxDepth)
 local node=rootNode(initial);local prefixes={}
 for _=1,maxDepth or 3 do local best,bestCost
  for _,a in ipairs(g.actions)do local n=extend(node,a,pref,env)
   if n then local c=n.costs[#n.costs].seconds;if not best or c<bestCost or c==bestCost and n.key<best.key then best=n;bestCost=c end end
  end
  if not best then break end node=scored(best,initial,pref);prefixes[#prefixes+1]=node
 end return assert(pick(prefixes,baseline,pref))
end
-- Predeclared fixed order is ascending quest ID; it is not an authored guide route.
local function fixedOrder(g,initial,pref,env,baseline,chosen)
 local node=rootNode(initial);local prefixes={}
 for _,questID in ipairs(chosen)do
  local methods={};for _,a in ipairs(g.byQuest[questID] or {})do methods[#methods+1]=a end
  table.sort(methods,function(a,b)return a.id<b.id end)
  local nextNode
  for _,a in ipairs(methods)do nextNode=extend(node,a,pref,env);if nextNode then break end end
  if not nextNode then break end
  node=scored(nextNode,initial,pref);prefixes[#prefixes+1]=node
 end
 return assert(pick(prefixes,baseline,pref))
end
local function solve(g,initial,pref,env)
 local job=p.PlanSearch.Begin(g,initial,pref,env)
 for _=1,1000 do local out=job:Step(64);if out then assert(out.status=='ready');return out end end error('Search did not settle')
end
local function verify(result,g,initial,pref,env,maxDepth)
 local node=rootNode(initial);local seen={};assert(#result.actions>=1 and #result.actions<=(maxDepth or 3))
 for _,a in ipairs(result.actions)do assert(g.byID[a.id] and not seen[a.id]);seen[a.id]=true;node=assert(extend(node,g.byID[a.id],pref,env),'Infeasible returned action')end
 scored(node,initial,pref);assert(math.abs(node.score-result.score)<=1e-7*math.max(1,math.abs(node.score)),'Score replay mismatch');return node
end

local compare=dofile(repo..'/tests/quest-plan-heldout-baselines.lua')(p,{
 rootNode=rootNode,extend=extend,scored=scored,pick=pick,within=within,ids=ids,
 setContext=function(ctx)activeContext=ctx end},arg[4])
local broader,broaderSkips,broaderCohorts={},{},{}
local function workState(chosen,records,ctx,pref)
 local initial=state(chosen,records,ctx,pref)
 -- Explicit synthetic bound live counters. This exercises planning, not live/source text matching.
 for _,id in ipairs(chosen)do
  initial.objectivesComplete[id]=false;initial.live[id].objectivesComplete=false
  initial.progress[id],initial.objectiveInfo[id]={},{}
  for index,o in ipairs(records[id].objectives or {})do
   initial.progress[id][o.id]=2
   initial.objectiveInfo[id][o.id]={index=index,type=o.type,text='Synthetic bound objective '..o.id,
    required=3,fulfilled=1,bound=true,finished=false}
  end
 end
 return initial
end
local function objectiveFixture(map,ctx,corpus)
 local candidates={}
 for _,rawID in ipairs(catalog.planning.maps[map] or catalog.planning.maps[tostring(map)] or {})do
  local id=assert(tonumber(rawID));local r=corpus[id]
  if r and noItems(r) and #(r.objectives or {})>=1 and #r.objectives<=2 then
   local supported=true;for _,o in ipairs(r.objectives)do if o.type~='monster'then supported=false end end
   if supported then candidates[#candidates+1]=id end
  end
 end
 table.sort(candidates,function(a,b)
  local aa=math.abs((tonumber(corpus[a].eligibility and corpus[a].eligibility.questLevel) or 0)-ctx.attributes.level)
  local bb=math.abs((tonumber(corpus[b].eligibility and corpus[b].eligibility.questLevel) or 0)-ctx.attributes.level)
  return aa==bb and a<b or aa<bb
 end)
 local sampling='level-ranked source candidates'
 -- Predeclared independent-author overlap, not selected based on planner performance.
 if compare.Source() and map==1426 and(ctx.attributes.class==2 and ctx.attributes.race==3 or ctx.attributes.class==4 and ctx.attributes.race==7)then
  local reordered={};for _,id in ipairs({182,183})do for _,candidate in ipairs(candidates)do if candidate==id then reordered[#reordered+1]=id end end end
  for _,id in ipairs(candidates)do if id~=182 and id~=183 then reordered[#reordered+1]=id end end
  candidates=reordered;sampling='predeclared pinned-author overlap first, then level-ranked source candidates'
 end
 local chosen,records={},{};local pref=policy('Balanced');local examined=0
 for _,id in ipairs(candidates)do
  examined=examined+1;if examined>128 then break end
  local one={[id]=corpus[id]};local initial=state({},one,ctx,pref);local pickup=false
  for _,a in ipairs(graph(initial,one,pref).actions)do
   if a.kind=='pickup' and a.destination and a.destination.mapID==map and p.PlanTransitions.Check(a,initial,pref)==true then pickup=true;break end
  end
  if pickup then
   local active=workState({id},one,ctx,pref);local objectives,turnin={},false
   for _,a in ipairs(graph(active,one,pref).actions)do
    if a.destination and a.destination.mapID==map then
     if a.kind=='objective' and a.method=='kill' and not a.liveFallback and p.PlanTransitions.Check(a,active,pref)==true then objectives[a.objectiveKey]=true end
     if a.kind=='turnin' then turnin=true end
    end
   end
   local complete=true;for _,o in ipairs(corpus[id].objectives)do if not objectives[o.id]then complete=false end end
   if complete and turnin then chosen[#chosen+1]=id;records[id]=corpus[id]end
   if #chosen==2 then return chosen,records,examined,sampling end
  end
 end
 return nil,'Fewer than two eligible one/two kill-objective quests after '..examined..' level-ranked candidates',examined
end
local function objectiveGraph(initial,records,pref)
 local full=graph(initial,records,pref);local grouped={}
 for _,a in ipairs(full.actions)do
  local sameMap=a.destination and a.destination.mapID==initial.position.mapID
  if not a.liveFallback and(a.kind=='complete' or sameMap and(a.kind=='turnin' or a.kind=='pickup' and not initial.active[a.questID]
   or a.kind=='objective' and a.method=='kill'))then
   local key=a.questID..':'..a.kind..':'..tostring(a.objectiveKey or '');local old=grouped[key]
   local function distance(x)return x.destination and((x.destination.x-.5)^2+(x.destination.y-.5)^2)or 0 end
   if not old or distance(a)<distance(old)or distance(a)==distance(old)and a.id<old.id then grouped[key]=a end
  end
 end
 local keep={};for _,a in pairs(grouped)do keep[a.id]=true end
 local out=copy(full);out.actions={};out.byID={};out.byQuest={}
 for _,raw in ipairs(full.actions)do if keep[raw.id]then
  local a=p.Schema.Clone(raw)
  -- Declared synthetic work models, identical for all solvers. Unknown count stays unknown.
  local duration=a.kind=='objective' and(a.countUnknown and 180 or a.count*20)or a.kind=='complete' and 0 or 5
  a.cost={seconds=duration,lower=a.countUnknown and 30 or duration,upper=a.countUnknown and 900 or duration,authority='authored'}
  out.actions[#out.actions+1]=a;out.byID[a.id]=a;out.byQuest[a.questID]=out.byQuest[a.questID]or{}
  table.insert(out.byQuest[a.questID],a)
 end end
 for id in pairs(records)do
  local stages={};for _,a in ipairs(out.byQuest[id]or{})do stages[a.kind]=true end
  assert(stages.objective and stages.complete and stages.turnin,'Incomplete broader quest projection')
  assert(initial.active[id]or stages.pickup,'Missing broader pickup')
 end
 assert(#out.actions<=10,'Broader scenario exceeds exhaustive stage bound');return out
end
local function runBroader(persona,map,ctx,corpus)
 local chosen,records,examined,sampling=objectiveFixture(map,ctx,corpus)
 if not chosen then broaderSkips[#broaderSkips+1]={persona=persona.id,mapID=map,reason=records,scenarios=2};return end
 broaderCohorts[#broaderCohorts+1]={persona=persona.id,mapID=map,candidateIDs=chosen,examined=examined,sampling=sampling}
 for _,scenario in ipairs({'active-partial-kill','future-pickup-continuation'})do
  for _,flavor in ipairs(flavors)do
   local pref=policy(flavor);pref.maxSeconds=1800
   local initial=scenario=='active-partial-kill'and workState(chosen,records,ctx,pref)or state({},records,ctx,pref)
   local g=objectiveGraph(initial,records,pref);local env=environment();local depth=#g.actions
   local upper,ideal,baseline,visits,fallback=oracle(g,initial,pref,env,depth)
   local started=os.clock();local result=solve(g,initial,pref,env);local cpu=os.clock()-started
   local actual=verify(result,g,initial,pref,env,depth);local again=solve(g,initial,pref,env)
   verify(again,g,initial,pref,env,depth)
   assert(ids(result.actions)==ids(again.actions)and result.score==again.score,'Broader scenario nondeterministic')
   local nearest=greedy(g,initial,pref,env,baseline,depth)
   local legacy=compare.Legacy(g,initial,pref,env,baseline,depth)
   local heuristic=compare.Heuristic(g,initial,pref,env,baseline,depth)
   local authored=compare.Authored(g,initial,pref,env,baseline,persona)
   local tolerance=1e-7*math.max(1,math.abs(upper.score))
   assert(result.score<=upper.score+tolerance and nearest.score<=upper.score+tolerance,'Broader upper bound violated')
   for _,comparison in ipairs({legacy,heuristic,authored})do
    if comparison.score then assert(comparison.score<=upper.score+tolerance,'Baseline exceeded broader exhaustive upper bound')end
   end
   local conditional=0;for _,done in pairs(actual.state.conditionalCompleted or{})do if done then conditional=conditional+1 end end
   broader[#broader+1]={scenario=scenario,persona=persona.id,mapID=map,flavor=flavor,candidateIDs=chosen,
    selected=ids(result.actions),score=result.score,utilityUpper=upper.score,utilityLoss=math.max(0,upper.score-result.score),
    constrainedIdeal=ideal.score,constrainedDelta=ideal.score-result.score,constrainedLoss=math.max(0,ideal.score-result.score),
    withinTrueEnvelope=not not within(actual,baseline,pref),solverBaseline=result.baselineEfficiency,baseline=baseline,
    oracleFallback=fallback,oracleVisits=visits,depth=depth,seconds=actual.state.elapsed,upperSeconds=actual.state.upperElapsed,
    xp=actual.state.xpGained,unknownXP=actual.state.unknownXP,conditionalCompleted=conditional,
    legacy=legacy,heuristic=heuristic,authored=authored,greedyScore=nearest.score,greedySelected=nearest.key,
    work=result.metrics and result.metrics.work,limited=result.limited,solveCPU=cpu}
  end
 end
end

local results,skips,cohorts={},{},{}
for _,persona in ipairs(personas)do
 history={}
 -- This is a declared synthetic fresh-history actor. IDs outside the catalog stay unknown.
 for key in pairs(assert(catalog.planning.quests))do history[assert(tonumber(key))]=false end
 local ctx=context(persona,maps[1]);activeContext=ctx;p.PlanLearning.Reset();p.PlanLearning.Bind(identity,ctx.characterKey)
 local corpus,recordCount=loadPartitions(ctx)
 for _,map in ipairs(maps)do
  ctx.position={mapID=map,x=.5,y=.5};activeContext=ctx
  runBroader(persona,map,ctx,corpus);activeContext=ctx
  local chosen,records=fixture(map,ctx,corpus)
  if not chosen then
   skips[#skips+1]={persona=persona.id,faction=persona.faction,class=persona.class,race=persona.race,level=persona.level,mapID=map,reason=records}
  else
   cohorts[#cohorts+1]={persona=persona.id,faction=persona.faction,class=persona.class,race=persona.race,level=persona.level,mapID=map,ids=chosen,loadedRecords=recordCount}
   for _,flavor in ipairs(flavors)do
    local pref=policy(flavor);local initial=state(chosen,records,ctx,pref);local g=restrictedGraph(initial,records,pref);local env=environment()
    local t=os.clock();local upper,ideal,baseline,visits,fallback=oracle(g,initial,pref,env);local oracleCPU=os.clock()-t
    local nearest=greedy(g,initial,pref,env,baseline);local fixed=fixedOrder(g,initial,pref,env,baseline,chosen)
    local legacy=compare.Legacy(g,initial,pref,env,baseline,3)
    local heuristic=compare.Heuristic(g,initial,pref,env,baseline,3)
    local authored=compare.Authored(g,initial,pref,env,baseline,persona)
    t=os.clock();local result=solve(g,initial,pref,env);local solveCPU=os.clock()-t
    local actual=verify(result,g,initial,pref,env);local again=solve(g,initial,pref,env)
    verify(again,g,initial,pref,env)
    assert(ids(result.actions)==ids(again.actions) and result.score==again.score,'Nondeterministic result')
    local tol=1e-7*math.max(1,math.abs(upper.score))
    assert(result.score<=upper.score+tol and nearest.score<=upper.score+tol and fixed.score<=upper.score+tol,'Exceeded exact utility upper bound')
    for _,comparison in ipairs({legacy,heuristic,authored})do if comparison.score then assert(comparison.score<=upper.score+tol,'Comparison exceeds exact utility upper bound')end end
    results[#results+1]={persona=persona.id,faction=persona.faction,class=persona.class,race=persona.race,level=persona.level,
     mapID=map,flavor=flavor,candidateIDs=chosen,selected=ids(result.actions),score=result.score,
     utilityUpper=upper.score,utilityLoss=math.max(0,upper.score-result.score),
     constrainedIdeal=ideal.score,constrainedDelta=ideal.score-result.score,
     constrainedLoss=math.max(0,ideal.score-result.score),
     greedyScore=nearest.score,greedySelected=nearest.key,fixedOrderScore=fixed.score,fixedOrderSelected=fixed.key,
     baseline=baseline,solverBaseline=result.baselineEfficiency,withinTrueEnvelope=not not within(actual,baseline,pref),
     oracleFallback=fallback,upperElapsed=actual.state.upperElapsed,limited=result.limited,work=result.metrics and result.metrics.work,
     visits=visits,oracleCPU=oracleCPU,solveCPU=solveCPU,legacy=legacy,heuristic=heuristic,authored=authored}
   end
  end
 end
end
assert(#personas==18,'Expected 18 valid synthetic personas')
assert(#cohorts+#skips==#personas*#maps,'Cohort accounting mismatch')
assert(#results==#cohorts*#flavors and #results>0,'Missing cases or no qualified source cohorts')
local report={identity=identity,corpusRevision=catalog.revision,providerRevision=catalog.providerRevision,
 sourceSHA256=catalog.sourceSHA256,searchRevision=p.PlanSearch.REVISION,partitionSize=partitionSize,partitionCount=#buckets,
 synthetic=true,scope='Three source quests, up to two source finisher methods; synthetic completed logs, fresh history, resources and planar exact travel; production-model exhaustive prefix enumeration; no native gameplay or path evidence',
 personas=personas,maps=maps,flavors=flavors,potentialCases=#personas*#maps*#flavors,
 testedCases=#results,omittedCases=#skips*#flavors,
 preparedOptimizerComparison='Unmodified Optimizer on synthetic prepared common-domain actions; route replay and XP/time comparability reported; future conditional pickup domain explicitly unsupported',
 authoredGuideComparison='Pinned external source-ordered subset if arg[4] is provided; omissions and projection limits explicit; fixed quest-ID order remains separate',
 authoredSource=compare.Source(),
 broaderScope='Two source quests with one or two kill objectives, level-ranked except explicitly predeclared pinned-guide overlap actors; one method per stage; synthetic observed bound remaining counters or source-unknown conditional future counts; exact planar travel and declared work priors; no native gameplay claim',
 broaderPotentialCases=#personas*#maps*#flavors*2,broaderTestedCases=#broader,broaderOmittedCases=#broaderSkips*#flavors*2,
 broader=broader,broaderSkips=broaderSkips,broaderCohorts=broaderCohorts,
 results=results,skips=skips,cohorts=cohorts}
print(string.format('heldout corpus=%s build=%s locale=%s revision=%s provider=%s search=%s partitions=%d personas=%d cohorts=%d cases=%d potential=%d omitted=%d',
 tostring(identity.product),tostring(identity.build),tostring(identity.locale),tostring(catalog.revision),tostring(catalog.providerRevision),
 tostring(p.PlanSearch.REVISION),#buckets,#personas,#cohorts,#results,report.potentialCases,report.omittedCases))
print('scope='..report.scope)
print('preparedOptimizer='..report.preparedOptimizerComparison)
print('authoredGuide='..report.authoredGuideComparison)
print(string.format('broader cohorts=%d cases=%d potential=%d omitted=%d',#broaderCohorts,#broader,report.broaderPotentialCases,report.broaderOmittedCases))
assert(#broaderCohorts+#broaderSkips==#personas*#maps,'Broader cohort accounting')
assert(#broader==#broaderCohorts*2*#flavors,'Broader case accounting')
assert(#broader>0,'No broader source scenarios qualified')
local function aggregate(rows)
 local out={}
 for _,flavor in ipairs(flavors)do
  local total={cases=0,utilityLoss=0,maxUtilityLoss=0,constrainedLoss=0,maxConstrainedLoss=0,envelopeMisses=0,limited=0,
   legacy={tested=0,comparable=0,unsupported=0,scoreDelta=0},heuristic={tested=0,unsupported=0,scoreDelta=0},authored={tested=0,unsupported=0,scoreDelta=0}}
  for _,row in ipairs(rows)do if row.flavor==flavor then
   total.cases=total.cases+1;total.utilityLoss=total.utilityLoss+row.utilityLoss
   total.maxUtilityLoss=math.max(total.maxUtilityLoss,row.utilityLoss)
   total.constrainedLoss=total.constrainedLoss+row.constrainedLoss;total.maxConstrainedLoss=math.max(total.maxConstrainedLoss,row.constrainedLoss)
   total.envelopeMisses=total.envelopeMisses+(row.withinTrueEnvelope and 0 or 1);total.limited=total.limited+(row.limited and 1 or 0)
   for _,kind in ipairs({'legacy','heuristic','authored'})do local comparison=row[kind];local acc=total[kind]
    if comparison and comparison.status=='ready' then
     acc.tested=acc.tested+1
     if kind~='legacy' or comparison.comparable then
      acc.scoreDelta=acc.scoreDelta+row.score-comparison.score
      if kind=='legacy'then acc.comparable=acc.comparable+1 end
     end
    else acc.unsupported=acc.unsupported+1 end
   end
  end end
  if total.cases>0 then total.meanUtilityLoss=total.utilityLoss/total.cases;total.meanConstrainedLoss=total.constrainedLoss/total.cases end
  for _,kind in ipairs({'legacy','heuristic','authored'})do local acc=total[kind];local count=kind=='legacy'and acc.comparable or acc.tested
   if count>0 then acc.meanScoreDelta=acc.scoreDelta/count end
  end
  out[flavor]=total
 end
 return out
end
report.summary=aggregate(results);report.broaderSummary=aggregate(broader)
for _,flavor in ipairs(flavors)do local row=report.broaderSummary[flavor]
 print(string.format('broader flavor=%s cases=%d meanUtilityLoss=%.6f maxUtilityLoss=%.6f meanConstrainedLoss=%.6f legacyComparable=%d heuristic=%d authored=%d limited=%d',
  flavor,row.cases,row.meanUtilityLoss or 0,row.maxUtilityLoss,row.meanConstrainedLoss or 0,row.legacy.comparable,row.heuristic.tested,row.authored.tested,row.limited))
end

for _,c in ipairs(cohorts)do print(string.format('cohort persona=%s map=%d quests=%s records=%d',c.persona,c.mapID,table.concat(c.ids,','),c.loadedRecords))end
for _,flavor in ipairs(flavors)do
 local n,gap,maxGap,loss,maxLoss,delta,greedyDelta,fixedDelta,miss,limited,work,cpu=0,0,0,0,0,0,0,0,0,0,0,0
 for _,r in ipairs(results)do if r.flavor==flavor then
  n=n+1;gap=gap+r.utilityLoss;maxGap=math.max(maxGap,r.utilityLoss)
  loss=loss+r.constrainedLoss;maxLoss=math.max(maxLoss,r.constrainedLoss);delta=delta+r.constrainedDelta
  greedyDelta=greedyDelta+r.score-r.greedyScore;fixedDelta=fixedDelta+r.score-r.fixedOrderScore
  miss=miss+(r.withinTrueEnvelope and 0 or 1);limited=limited+(r.limited and 1 or 0);work=work+(r.work or 0);cpu=cpu+r.solveCPU
 end end
 assert(n>0,'Missing flavor '..flavor)
 print(string.format('flavor=%s cases=%d meanUtilityLoss=%.6f maxUtilityLoss=%.6f meanConstrainedLoss=%.6f maxConstrainedLoss=%.6f meanConstrainedDelta=%.6f meanVsGreedy=%.6f meanVsFixedOrder=%.6f trueEnvelopeMisses=%d limited=%d work=%d cpu=%.6f',
 flavor,n,gap/n,maxGap,loss/n,maxLoss,delta/n,greedyDelta/n,fixedDelta/n,miss,limited,work,cpu))
end
for _,map in ipairs(maps)do local n=0;for _,c in ipairs(cohorts)do if c.mapID==map then n=n+1 end end print(string.format('map=%d qualifiedCohorts=%d potential=%d',map,n,#personas))end
for _,s in ipairs(skips)do print(string.format('skip persona=%s map=%d reason=%s',s.persona,s.mapID,s.reason))end
local function jsonString(s)
 return '"'..s:gsub('[%z\1-\31\\"]',function(c)
  local escapes={['"']='\\"',['\\']='\\\\',['\b']='\\b',['\f']='\\f',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
  return escapes[c] or string.format('\\u%04x',c:byte())
 end)..'"'
end
local function json(value)
 local kind=type(value)
 if kind=='nil'then return'null'end
 if kind=='boolean'then return tostring(value)end
 if kind=='number'then assert(finite(value),'Nonfinite report value');return string.format('%.17g',value)end
 if kind=='string'then return jsonString(value)end
 assert(kind=='table','Unsupported JSON type '..kind)
 local array=true;local count=0
 for k in pairs(value)do count=count+1;if type(k)~='number' or k%1~=0 or k<1 then array=false end end
 array=array and count==#value
 local parts={}
 if array then for i=1,#value do parts[i]=json(value[i])end return'['..table.concat(parts,',')..']'end
 local keys={}for k in pairs(value)do assert(type(k)=='string','Expected string object key');keys[#keys+1]=k end table.sort(keys)
 for i,k in ipairs(keys)do parts[i]=jsonString(k)..':'..json(value[k])end
 return'{'..table.concat(parts,',')..'}'
end
if arg[3]then local output=assert(io.open(arg[3],'wb'));output:write(json(report),'\n');output:close()end
return report
