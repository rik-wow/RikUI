-- Benchmark-only adapters. Production algorithms are loaded unchanged by the runner.
-- Fixture authority describes a synthetic model, never verified game/source availability.
return function(p,h,authoredPath)
 local B={}
 local clone=p.Schema.Clone
 local authored=authoredPath and assert(loadfile(authoredPath))() or nil
 if authored then
  assert(authored.version==1 and authored.commit=='72b6a16b6ba3c455614911dd9acdd06badcf5404')
  assert(authored.sha256=='835c635043fa4317fdca3626d8377866d79dcd82c2a802c8464232b18a44a342')
 end
 local function unavailable(why)return{status='unsupported',reason=why}end
 local function summary(node,baseline,pref,extra)
  local out=extra or {};out.status='ready';out.selected=node.key;out.score=node.score
  out.seconds=node.state.elapsed;out.upperSeconds=node.state.upperElapsed
  out.xp=node.state.xpGained;out.withinTrueEnvelope=not not h.within(node,baseline,pref)
  return out
 end
 local function output(prefixes,baseline,pref,extra)
  if #prefixes==0 then return unavailable('No common feasible prefix')end
  local node,fallback=h.pick(prefixes,baseline,pref);extra=extra or {};extra.envelopeFallback=fallback
  return summary(node,baseline,pref,extra)
 end
 local function available(g,node,pref,env)
  local rows={}
  for _,a in ipairs(g.actions)do
   if a.kind~='complete' then local nextNode=h.extend(node,a,pref,env)
    if nextNode then rows[#rows+1]={action=a,node=nextNode}end
   end
  end
  table.sort(rows,function(a,b)return a.action.id<b.action.id end);return rows
 end
 function B.Heuristic(g,initial,pref,env,baseline,maxDepth)
  local node=h.rootNode(initial);local prefixes={};local previous,prior
  for _=1,maxDepth do
   local grouped={}
   for _,choice in ipairs(available(g,node,pref,env))do local a=choice.action
    -- This live heuristic does not propose future pickups or services.
    if node.state.active[a.questID] and(a.kind=='objective' or a.kind=='turnin')then
     local old=grouped[a.questID];local cost=choice.node.costs[#choice.node.costs].seconds
     if not old or cost<old.cost or cost==old.cost and a.id<old.action.id then choice.cost=cost;grouped[a.questID]=choice end
    end
   end
   local rows,byID,quests={},{},{}
   local order={};for id in pairs(grouped)do order[#order+1]=id end;table.sort(order)
   for _,id in ipairs(order)do local choice=grouped[id];local a=choice.action
    local row={questID=id,kind=a.kind,stepID=a.id,destination=clone(a.destination),pinned=pref.pins[id]==true,
     semantic=a.destination and{areaID=a.destination.areaID}or nil}
    rows[#rows+1]=row;byID[id]=choice;local objectives={}
    for key,left in pairs(node.state.progress[id] or {})do
     local info=(node.state.objectiveInfo[id] or {})[key];local total=info and info.required
     if type(total)=='number' and total>0 and left>=0 then objectives[#objectives+1]={numRequired=total,numFulfilled=math.max(0,total-left)}end
    end
    quests[id]={objectives=objectives}
   end
   if #rows==0 then break end
   local ctx={position=node.state.position};h.setContext(ctx)
   p.Recommendations.Sort(rows,{quests=quests},ctx,previous,prior)
   local selected=rows[1];node=h.scored(byID[selected.questID].node,initial,pref)
   prefixes[#prefixes+1]=node;previous=selected.questID;prior={kind=selected.kind,stepID=selected.stepID}
  end
  return output(prefixes,baseline,pref,{projection='Unmodified Recommendations.Sort; nearest feasible method per live quest; best feasible prefix uses the common stopping evaluator'})
 end
 local function preparedState(initial)
  return {identity=clone(initial.identity),fresh=true,origin='live',node='origin',
   active=clone(initial.active),failed=clone(initial.failed),objectivesComplete=clone(initial.objectivesComplete),
   turnedIn={},logComplete=initial.logComplete,logCount=initial.logCount,logCapacity=initial.logCapacity,
   class=initial.class,race=initial.race,faction=initial.faction,level=initial.level,xp=initial.xp,xpMax=initial.xpMax,
   xpThresholds=clone(initial.xpThresholds),objectives={},inventory=clone(initial.inventory),
   travel={identity=clone(initial.identity),departure=0,flights={},transport={}}}
 end
 function B.Legacy(g,initial,pref,env,baseline,maxDepth)
  if maxDepth>8 or #g.actions>40 then return unavailable('Prepared optimizer supports at most 8 stages and 40 actions')end
  local source=clone(initial.identity);source.id='heldout-synthetic-model';source.authority='verified'
  local book=assert(p.Evidence.New(initial.identity));local oldState=preparedState(initial)
  local nodes={{id='origin',zoneID=initial.position.mapID}};local positions={origin=initial.position}
  local rows,lookup,objectiveKeys={},{},{}
  for _,a in ipairs(g.actions)do oldState.turnedIn[a.questID]=initial.completed[a.questID]end
  for index,a in ipairs(g.actions)do
   if a.kind=='pickup' then return unavailable('Future pickup and conditional prerequisites are outside this common prepared-action adapter')end
   if a.kind~='complete' then
    if a.kind~='objective' and a.kind~='turnin' then return unavailable('Action kind unsupported by common prepared-action adapter')end
    if a.countUnknown or a.liveFallback or #(a.gains or {})>0 or #(a.unknownConsumeItems or {})>0 then
     return unavailable('Unknown work, fallback or resource gains are not silently flattened for the prepared optimizer')
    end
    local alias='action'..index;local node='node'..index;local cost=assert(p.PlanCosts.Estimate(a,initial,pref,env))
    local duration=cost.seconds-(cost.travel or 0)
    if duration<0 or duration>3600 then return unavailable('Work duration exceeds prepared schema')end
    positions[node]=a.destination or initial.position;nodes[#nodes+1]={id=node,zoneID=positions[node].mapID}
    local row={id=alias,questID=a.questID,kind=a.kind,node=node,zoneID=positions[node].mapID,
     source=source,title=a.title,duration={combat=0,looting=0,interaction=duration,downtime=0},risk=0,uncertainty=0,
     consumes=clone(a.consumes),category=a.category}
    if a.kind=='turnin' then row.xp,row.xpLevel=cost.xp,initial.level
    else
     local count=p.PlanTransitions.Remaining(a,initial)
     if type(count)~='number' or count<=0 then return unavailable('Objective needs a known positive synthetic counter')end
     if cost.xp and cost.xp~=0 then return unavailable('Prepared objectives do not model combat XP')end
     local key='q'..a.questID..'o'..tostring(a.objectiveKey):gsub('[^%w]','_')
     if objectiveKeys[a.questID] and objectiveKeys[a.questID]~=key then return unavailable('Adapter restricted to one objective per quest')end
     objectiveKeys[a.questID]=key;row.sharedKey,row.progress=key,count
     oldState.objectives[a.questID]={[key]=count}
     if a.sharedCredit and #(a.credits or {})>1 then
      for _,credit in ipairs(a.credits)do if credit.questID~=a.questID then return unavailable('Shared-credit group requires a separate prepared graph adapter')end end
     end
    end
    rows[#rows+1]=row;lookup[alias]=a
   end
  end
  local edges={}
  for i,a in ipairs(nodes)do for j,b in ipairs(nodes)do if i~=j then
   local leg=assert(env.travel(positions[a.id],positions[b.id]));edges[#edges+1]={id='edge'..i..'_'..j,
    from=a.id,to=b.id,mode='walk',seconds=leg.seconds,risk=0,uncertainty=0,zones={a.zoneID},source=source}
  end end end
  local oldGraph=assert(p.Travel.New(initial.identity,'heldout-synthetic-planar',nodes,edges))
  local actionSet=assert(p.Actions.New(initial.identity,rows))
  local oldPolicy={depth=maxDepth,width=24,maxSeconds=pref.maxSeconds,maxRisk=pref.maxRisk,maxUncertainty=0,
   pins=clone(pref.pins),skips=clone(pref.skips),avoids=clone(pref.avoids),dungeons=pref.dungeons,classValue=0,unlockValue=0}
  for id in pairs(pref.defers or {})do if pref.defers[id]then oldPolicy.skips[id]=true end end
  local started=os.clock();local result=p.Optimizer.Plan(actionSet,oldState,book,oldGraph,oldPolicy)
  local elapsed=os.clock()-started;local node=h.rootNode(initial)
  for _,selected in ipairs(result.actions or {})do
   local action=assert(lookup[selected.id]);local nextNode=h.extend(node,action,pref,env)
   if not nextNode then return{status='infeasible-under-current-model',reason='Prepared route violates a current transition or strict upper-time constraint',nativeSelected=h.ids(result.actions)}end
   node=nextNode
  end
  if #node.actions==0 then return unavailable('Prepared optimizer returned no common feasible action')end
  h.scored(node,initial,pref)
  local secondsMatch=math.abs((result.seconds or 0)-node.state.elapsed)<=1e-7*math.max(1,node.state.elapsed)
  local xpMatch=math.abs((result.gainedXP or 0)-(node.state.xpGained or 0))<=1e-7
  return summary(node,baseline,pref,{nativeScore=result.score,nativeXP=result.gainedXP,nativeSeconds=result.seconds,
   nativeStatus=result.status,limited=result.limited,metrics=result.metrics,cpu=elapsed,
   comparable=secondsMatch and xpMatch,secondsMatch=secondsMatch,xpMatch=xpMatch,
   objective='Unmodified prepared Optimizer native XP/second objective; returned route evaluated by current flavor utility',
   authority='Synthetic benchmark model only; source corpus references were not promoted in production',
   difference=not(secondsMatch and xpMatch)and'Legacy fixed reward or transition model differs; exclude from equal-information aggregate'or nil})
 end
 function B.Authored(g,initial,pref,env,baseline,persona)
  if not authored then return unavailable('No pinned external authored facts supplied')end
  if initial.position.mapID~=authored.mapID or not authored.personas[persona.class..':'..persona.race]then
   return unavailable('No applicable pinned authored subset for this map and persona')
  end
  local candidate,covered={},{}
  for _,a in ipairs(g.actions)do candidate[a.questID]=true end
  for _,step in ipairs(authored.steps)do if candidate[step.questID]then covered[step.questID]=true end end
  for id in pairs(candidate)do if not covered[id]then return unavailable('Authored subset lacks quest '..id)end end
  local node=h.rootNode(initial);local prefixes,lines={},{}
  for _,step in ipairs(authored.steps)do if candidate[step.questID]then
   -- Already observed stages are omitted from this declared projection.
   local done=(step.kind=='pickup' and(initial.active[step.questID] or initial.completed[step.questID]))
    or(step.kind=='objective' and initial.objectivesComplete[step.questID])
   if not done then
    local choices={}
    for _,a in ipairs(g.byQuest[step.questID] or {})do if a.kind==step.kind then choices[#choices+1]=a end end
    table.sort(choices,function(a,b)return a.id<b.id end)
    local accepted=false
    for _=1,#choices do
     local nextNode
     for _,a in ipairs(choices)do local n=h.extend(node,a,pref,env)
      if n and(not nextNode or n.state.elapsed<nextNode.state.elapsed or n.state.elapsed==nextNode.state.elapsed and n.key<nextNode.key)then nextNode=n end
     end
     if not nextNode then break end
     accepted=true;node=h.scored(nextNode,initial,pref);prefixes[#prefixes+1]=node;lines[#lines+1]=step.line
     if step.kind~='objective'then break end
    end
    if not accepted then return{status='infeasible-projection',reason='Authored quest stage unavailable in common model',line=step.line,questID=step.questID,kind=step.kind}end
   end
  end end
  return output(prefixes,baseline,pref,{repository=authored.repository,commit=authored.commit,license=authored.license,
   sourceFile=authored.file,sourceSHA256=authored.sha256,lines=lines,scope=authored.scope,
   methodChoice='Fastest feasible common-model method at each source-ordered quest stage; source travel not reproduced'})
 end
 function B.Source()return authored and{repository=authored.repository,commit=authored.commit,license=authored.license,
  file=authored.file,sha256=authored.sha256,scope=authored.scope}or nil end
 return B
end
