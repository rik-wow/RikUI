-- Run with Lua 5.1: lua tests/quest-plan-calibration.lua REPO_ROOT
-- Offline production-module fixtures. No native gameplay, live timing, or drop-rate evidence.
local repo=arg[1] or '.'
RikUI={};RikUI['Secret']={IsSecret=function()return false end,Read=pcall}
GetTime=function()return 1 end
local function module(name)dofile(repo..'/src/modules/questplanner/quest-'..name..'.lua')end
module('schema')
local p=assert(RikUI.QuestPlanner)
p.Context={Frame=function(ctx)return{position=ctx and ctx.position,width=1000,height=1000}end,
 Call=function(fn,...)if type(fn)=='function'then return pcall(fn,...)end return false end}
for _,name in ipairs({'preferences','plan-state','plan-transitions','plan-learning','plan-costs','plan-rewards'})do module(name)end
local T,L,C=p.PlanTransitions,p.PlanLearning,p.PlanCosts
local cases,checks=0,0
local function check(value,message)checks=checks+1;assert(value,message or 'check failed')end
local function near(actual,expected,message)
 check(type(actual)=='number' and math.abs(actual-expected)<=1e-8*math.max(1,math.abs(expected)),
  (message or 'numeric mismatch')..': got '..tostring(actual)..', expected '..tostring(expected))
end
local function clone(value)return p.Schema.Clone(value)end
local identity={product='forever',build='1.60.1.69913',locale='enUS'}
local function state()
 return{fresh=true,identity=clone(identity),class=1,race=1,classMask=1,raceMask=1,
  level=10,xp=0,xpMax=1000,xpThresholds={[10]=1000,[11]=1100},
  partySize=1,equipmentKey='calibration-equipment-A',xpRested=false,
  position={mapID=1426,x=.5,y=.5},active={[900]=true},completed={[900]=false,[901]=false},
  failed={},progress={[900]={['live:1']=3}},live={[900]={objectivesComplete=false}},
  simulatedWork={},conditionalObjectives={},inventory={},inventoryExact=true,bank={},equipped={},
  logComplete=true,logCount=1,logCapacity=20,bagFree=20,stackRoom={},itemMaxStack={},money=1000,
  capabilities={combat={maxHealth=300,level=10,group=1}},branchLocks={},applied={},
  elapsed=0,upperElapsed=0,xpGained=0,unknownXP=0,visited={},assumptions={}}
end
local function action()
 return{id='900:objective:live:1',questID=900,kind='objective',objectiveKey='live:1',count=3,
  method='kill',objectiveType='kill',target={kind='npc',id=1127},zoneID=1426,requiredParty=1,risk=.05,
  destination={mapID=1426,x=.5,y=.5},encounter={minLevel=12,rank=0},
  preconditions={},consumes={},gains={}}
end
local pref=p.Preferences.Normalize({flavor='Challenge',readingSeconds=0,strictSession=false})
pref.maxRisk=1;pref.maxSeconds=3600
local environment={travel=function()return{seconds=0,lower=0,upper=0,status='authored'}end}
local function estimate(a,s)
 local cost,why=C.Estimate(a,s,pref,environment)
 check(type(cost)=='table','Cost estimate missing: '..tostring(why));return cost
end
local function reset()
 L.Bind(identity,'calibration-fixture');L.Reset('estimates')
end
local function observe(kind,key,values)
 for _,value in ipairs(values)do L.Observe(kind,key,value,1)end
end
local function case(name,body)
 reset();body();cases=cases+1;print('PASS '..name)
end

case('R13 zero, two, and three successful combat samples',function()
 local s,a=state(),action();local key=C.Context(a,s)
 local zero=estimate(a,s)
 check(zero.profileKnown==true,'Observed health/level profile must remain available')
 check(zero.capabilityKnown~=true,'An observed profile is not learned success evidence')
 observe('combat',key,{12,15})
 local model=L.Estimate('combat',key)
 check(model and model.samples==2,'Expected two independent combat observations')
 check(estimate(a,s).capabilityKnown~=true,'Two samples must not unlock learned difficulty fit')
 L.Observe('combat',key,18,1)
 model=L.Estimate('combat',key)
 check(model and model.samples==3,'Expected third combat observation')
 near(model.mean,15);near(model.minimum,12);near(model.maximum,18)
 check(estimate(a,s).capabilityKnown==true,'Three matching successful combat samples should unlock fit')
end)

case('R13 collection, rejected observations, and absent profile do not establish combat fit',function()
 local s,a=state(),action();local key=C.Context(a,s)
 observe('collection',key,{12,15,18})
 check(estimate(a,s).capabilityKnown~=true,'Collection timing is not combat success evidence')
 observe('combat',key,{12,15})
 for _,flag in ipairs({'paused','afk','unrelated'})do
  L.Observe('combat',key,18,1,{[flag]=true})
 end
 L.Observe('combat',key,0,1);L.Observe('combat',key,18,0)
 check(L.Estimate('combat',key).samples==2,'Rejected episodes must not increase samples')
 check(estimate(a,s).capabilityKnown~=true,'Rejected third episode must not unlock fit')
 L.Observe('combat',key,18,1);s.capabilities.combat=nil
 check(estimate(a,s).capabilityKnown~=true,'Learned durations do not replace absent live combat profile')
end)

case('R13 actor context changes invalidate learned fit without deleting old evidence',function()
 local s,a=state(),action();local original=C.Context(a,s)
 observe('combat',original,{12,15,18})
 check(estimate(a,s).capabilityKnown==true)
 local changes={class=2,level=11,partySize=2,equipmentKey='calibration-equipment-B',xpRested=true}
 for field,value in pairs(changes)do
  local changed=clone(s);changed[field]=value
  check(C.Context(a,changed)~=original,'Context missing actor field '..field)
  check(estimate(a,changed).capabilityKnown~=true,'Evidence leaked across actor field '..field)
 end
 local changedAction=clone(a);changedAction.target.id=1128
 check(C.Context(changedAction,s)~=original,'NPC context must distinguish target')
 check(estimate(changedAction,s).capabilityKnown~=true,'Evidence leaked to a different NPC')
 check(estimate(a,s).capabilityKnown==true,'Original matching evidence must remain usable')
end)

case('R13 learned fit cannot override observed group availability',function()
 local s,a=state(),action();a.requiredParty=3
 observe('combat',C.Context(a,s),{12,15,18})
 local solo=p.Preferences.Normalize({flavor='Challenge',group='solo'})
 local available=p.Preferences.Normalize({flavor='Challenge',group='available'})
 check(T.Check(a,s,solo)~=true,'Learned success cannot override solo constraint')
 check(T.Check(a,s,available)~=true,'Observed party of one cannot satisfy required party of three')
end)

case('R06 absent combat XP stays unknown and explicit zero stays known',function()
 local s,a=state(),action()
 local xp,authority=C.Reward(a,s)
 near(xp,0);check(authority=='combat-xp-unknown','Missing XP model must carry unknown authority')
 check(estimate(a,s).combatXPUnknown==true,'Cost must preserve missing combat XP evidence')
 a.confirmedCombatXP=0
 local zero,why=C.Reward(a,s)
 near(zero,0);check(why~='combat-xp-unknown','Observed zero XP is not missing evidence')
 check(estimate(a,s).combatXPUnknown~=true,'Explicit zero XP must not be relabeled unknown')
end)

case('R06 combat XP uses remaining work and matching actor context',function()
 local s,a=state(),action();local key=C.Context(a,s)
 observe('combatXP',key,{100,120,140})
 near(T.Remaining(a,s),3)
 local xp,authority=C.Reward(a,s)
 near(xp,360);check(authority=='observed-local-estimate','Learned XP must retain estimated authority')
 near(estimate(a,s).xp,360)
 local partial=clone(s);partial.progress[900]['live:1']=1
 near(T.Remaining(a,partial),1);near(C.Reward(a,partial),120,'Do not reuse original three-unit count')
 near(estimate(a,partial).xp,120)
 local done=clone(s);done.progress[900]['live:1']=0
 near(C.Reward(a,done),0,'Completed progress must not award another modeled kill')
 for field,value in pairs({level=11,partySize=2,equipmentKey='calibration-equipment-B',xpRested=true})do
  local changed=clone(s);changed[field]=value
  local valueXP,why=C.Reward(a,changed)
  near(valueXP,0);check(why=='combat-xp-unknown','Combat XP leaked across '..field)
 end
 a.confirmedCombatXP=73
 near(C.Reward(a,s),73,'Confirmed episode XP overrides an extrapolated total')
 near(C.Reward(a,partial),73,'Confirmed episode total must not be multiplied by remaining count')
end)

case('R06 drop objectives require known positive effort probability',function()
 local s,a=state(),action();a.method='drop';a.dropEstimate={probability=.5}
 s.progress[900]['live:1']=2;a.count=2
 observe('combatXP',C.Context(a,s),{100,120,140})
 near(C.Reward(a,s),480,'Two remaining drops at p=.5 imply four expected kills, not two')
 local partial=clone(s);partial.progress[900]['live:1']=1
 near(C.Reward(a,partial),240,'Partial drops must recompute remaining expected kills')
 for _,probability in ipairs({0,-.5,1.5})do
  a.dropEstimate.probability=probability
  local xp,why=C.Reward(a,s)
  check(xp==nil and why=='combat-effort-unknown','Invalid probability must not invent kills')
 end
 a.dropEstimate=nil
 local xp,why=C.Reward(a,s)
 check(xp==nil and why=='combat-effort-unknown','Missing probability must remain unknown effort')
end)

case('R06 one shared kill gives one XP reward across explicitly shared objectives',function()
 local s,a=state(),action()
 s.active[901]=true;s.logCount=2;s.progress[900]['live:1']=1;s.progress[901]={['live:1']=1}
 s.live[901]={objectivesComplete=false}
 a.count=1;a.sharedCredit='npc:1127';a.credits={{questID=901,key='live:1',count=1}}
 observe('combatXP',C.Context(a,s),{100,120,140})
 local cost=estimate(a,s);near(cost.xp,120)
 check(T.Check(a,s,pref)==true,'Shared kill fixture must be feasible')
 local nextState,why=T.Apply(a,s,pref,cost)
 check(nextState~=nil,'Shared kill transition failed: '..tostring(why))
 near(nextState.progress[900]['live:1'],0);near(nextState.progress[901]['live:1'],0)
 near(nextState.xpGained-s.xpGained,120,'Shared objective credit must not multiply XP')
 near(s.progress[900]['live:1'],1,'Transition must not mutate the live input state')
 near(s.xpGained,0)
 check(T.Check(a,nextState,pref)~=true,'Consumed objective action cannot reward twice')
end)

case('R06 simulation rollover uses known thresholds without mutating observed XP',function()
 local s,a=state(),action();s.xp=90;s.xpMax=100;s.xpThresholds={[10]=100,[11]=200,[12]=300}
 s.progress[900]['live:1']=1;a.count=1;a.confirmedCombatXP=120
 local cost=estimate(a,s);near(cost.xp,120)
 local nextState,why=T.Apply(a,s,pref,cost)
 check(nextState~=nil,'XP rollover transition failed: '..tostring(why))
 near(nextState.level,11);near(nextState.xp,110);near(nextState.xpMax,200)
 near(s.level,10);near(s.xp,90,'A predicted gain must not rewrite the observed actor')
end)

print(string.format('quest-plan-calibration: %d cases, %d assertions passed; offline production-model fixtures',cases,checks))
