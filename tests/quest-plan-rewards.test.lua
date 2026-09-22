-- Loaded by the project's Lua test harness from the repository root.
-- Uses production Schema/PlanRewards and a guarded Context.Call boundary.
-- API shape source: Classic generated ItemDocumentation.lua, GetItemInfo returns 8/9.
return function(check)
 local originalCore=RikUI
 RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
 dofile('src/modules/questplanner/quest-schema.lua')
 local planner=assert(RikUI.QuestPlanner)
 local oldContext,oldRewards=planner.Context,planner.PlanRewards
 local globals={'GetQuestLogSelectedID','C_QuestLog','GetNumQuestLogRewards','GetQuestLogRewardInfo',
  'GetNumQuestLogChoices','GetQuestLogChoiceInfo','GetQuestLogRewardMoney','C_QuestInfoSystem','C_Item','GetItemInfo'}
 local saved={}for _,name in ipairs(globals)do saved[name]={value=rawget(_G,name)}end
 local secret=setmetatable({},{__tostring=function()error('Secret value formatted')end,
  __lt=function()error('Secret value ordered')end,__le=function()error('Secret value ordered')end})
 local function pack(...)return{n=select('#',...),...}end
 local function guarded(fn,...)
  if type(fn)~='function'then return false end
  local values=pack(pcall(fn,...))
  if not values[1]then return false end
  for i=2,values.n do if values[i]==secret then return false end end
  return unpack(values,1,values.n)
 end
 planner.Context={Call=guarded}
 local spec,reads
 local function current()return spec.selected end
 local function itemRows(rows,index)
  reads.items=reads.items+1;local row=rows[index]
  if row then return row.name or 'Reward',17,row.count,row.quality or 3,row.usable,row.itemID end
 end
 local function metadata(id)
  reads.metadata=reads.metadata+1;local row=spec.metadata[id]
  if not row then return nil end
  -- Deliberately distinct positions to detect a tuple shift. Stack=8, equip=9 before pcall.
  return 'Item '..id,'item:'..id,3,27,10,'Armor','Plate',row.stack,row.equip,90123,54321,4,4
 end
 local function reset()
  spec={selected=900,show=true,rewards={},choices={},money=nil,spells=nil,spellInfo={},metadata={}}
  reads={items=0,metadata=0,money=0,spells=0}
  GetQuestLogSelectedID=current
  C_QuestLog={GetSelectedQuest=current,ShouldShowQuestRewards=function()return spec.show end}
  GetNumQuestLogRewards=function()if spec.noRewardCount then return nil end return spec.rewardCount or #spec.rewards end
  GetNumQuestLogChoices=function()if spec.noChoiceCount then return nil end return spec.choiceCount or #spec.choices end
  GetQuestLogRewardInfo=function(index)return itemRows(spec.rewards,index)end
  GetQuestLogChoiceInfo=function(index)return itemRows(spec.choices,index)end
  GetQuestLogRewardMoney=function()
   reads.money=reads.money+1;if spec.switchOnMoney then spec.selected=901 end;return spec.money
  end
  C_QuestInfoSystem={GetQuestRewardSpells=function()return spec.spells end,
   GetQuestRewardSpellInfo=function(_,id)reads.spells=reads.spells+1;return spec.spellInfo[id]end}
  C_Item={GetItemInfo=metadata};GetItemInfo=metadata
 end
 local snapshot={quests={[900]={id=900},[901]={id=901}}}
 local function row(ctx,id)return ctx.rewards and ctx.rewards[id or 900]end
 local function list(value)return type(value)=='table' and value or {}end
 local function attach(live,policy)
  local action={id='900:turnin',kind='turnin',questID=900}
  planner.PlanRewards.Attach(action,{}, {live={[900]={reward=live}}},policy or {})
  return action
 end
 local function run()
  dofile('src/modules/questplanner/quest-plan-rewards.lua')
  local rewards=assert(planner.PlanRewards)
  reset();spec.money=0
  spec.rewards={{itemID=500,count=7,usable=true}};spec.metadata[500]={stack=20,equip='INVTYPE_CHEST'}
  local ctx={};rewards.Read(ctx,snapshot);local live=row(ctx);local item=live and list(live.items)[1]
  check('reward API stack tuple includes pcall prefix',item and item.stackSize==20)
  check('reward API equip tuple includes pcall prefix',item and item.equipment==true)
  check('reward quantity is not stack size',item and item.count==7)
  check('known zero money is preserved',live and live.money==0)
  check('known stack metadata is indexed by actual item ID',ctx.stackSizes and ctx.stackSizes[500]==20)

  reset();spec.rewards={{itemID=501,count=1,usable=false}};local missing={}
  rewards.Read(missing,snapshot);live=row(missing);item=live and list(live.items)[1]
  check('missing item metadata keeps reward item identity',item and item.itemID==501)
  check('missing item metadata does not invent equipment',item and item.equipment~=true)
  check('missing item metadata does not invent stack size',item and item.stackSize==nil)
  check('observed false usability stays false',item and item.usable==false,
   'Boolean false must not collapse to nil through an and/or expression')

  reset();GetQuestLogSelectedID=nil;C_Item=nil
  spec.rewards={{itemID=502,count=2,usable=true}};spec.metadata[502]={stack=5,equip=''}
  local fallback={};rewards.Read(fallback,snapshot);item=row(fallback) and list(row(fallback).items)[1]
  check('guarded modern selection and legacy item API fallback',item and item.itemID==502 and item.stackSize==5)
  check('empty equip location does not become equipment',item and item.equipment~=true)

  reset();spec.money=123;spec.switchOnMoney=true
  local unchanged={rewards={[900]={money=44,authority='previous'},[901]={money=55,authority='previous'}}}
  rewards.Read(unchanged,snapshot)
  check('selection change discards complete pending reward row',row(unchanged,900).money==44 and row(unchanged,900).authority=='previous')
  check('selection change cannot contaminate other quest rewards',row(unchanged,901).money==55)
  reset();spec.selected=999;local absent={};rewards.Read(absent,snapshot)
  check('selection outside snapshot is not observed',absent.rewards==nil and reads.items==0 and reads.money==0)
  reset();spec.show=false;local hidden={};rewards.Read(hidden,snapshot)
  check('ShouldShowQuestRewards false prevents positive observation',hidden.rewards==nil and reads.items==0 and reads.money==0)
  reset();spec.show=nil;local unknownVisibility={};rewards.Read(unknownVisibility,snapshot)
  check('unknown reward visibility does not become true',unknownVisibility.rewards==nil)

  for _,count in ipairs({-1,.5,33,1000000000})do
   reset();spec.rewardCount=count;spec.choiceCount=count;local bounded={};rewards.Read(bounded,snapshot)
   local observed=row(bounded)
   check('invalid reward count does not drive item API loop '..count,reads.items==0 and reads.metadata==0)
   check('invalid reward count does not create guaranteed items '..count,not observed or #list(observed.items)==0)
  end
  reset();spec.rewardCount=0;spec.choiceCount=0
  local zero={rewards={[900]={items={{itemID=1,count=1}},choices={{itemID=2,count=1}},money=99}}}
  spec.money=0;rewards.Read(zero,snapshot);live=row(zero)
  check('known zero item counts replace old lists',live and type(live.items)=='table' and #live.items==0 and type(live.choices)=='table' and #live.choices==0)
  check('known zero money replaces previous nonzero amount',live and live.money==0)

  reset();spec.rewardCount=secret;local secretCount={};rewards.Read(secretCount,snapshot)
  check('secret reward count stops enumeration',reads.items==0 and(not row(secretCount) or #list(row(secretCount).items)==0))
  reset();spec.rewards={{itemID=510,count=secret,usable=true}};local secretQuantity={};rewards.Read(secretQuantity,snapshot)
  check('secret reward quantity cannot create a gain',not row(secretQuantity) or #list(row(secretQuantity).items)==0)
  reset();spec.selected=secret;local secretSelection={};rewards.Read(secretSelection,snapshot)
  check('secret quest identity is rejected before reads',secretSelection.rewards==nil and reads.items==0 and reads.money==0)

  reset();spec.spells={701,702};spec.spellInfo={[701]={isSpellLearned=true},[702]={isSpellLearned=false}}
  local spells={};rewards.Read(spells,snapshot);live=row(spells)
  check('only supported learned-spell reward entries are retained',live and #list(live.spells)==1 and live.spells[1]==701)
  reset();spec.spells={};spec.spellInfo={}
  for i=1,40 do spec.spells[i]=700+i;spec.spellInfo[700+i]={isSpellLearned=true}end
  local boundedSpells={};rewards.Read(boundedSpells,snapshot)
  check('spell reward metadata reads are bounded',reads.spells<=32)

  local chosenLive={authority='observed-offer',money=0,spells={701},
   items={{itemID=100,count=2,stackSize=20}},
   choices={{itemID=201,count=1,usable=false,equipment=true},{itemID=203,count=3,usable=true,equipment=false},{itemID=202,count=1,usable=true,equipment=true}}}
  local automatic=attach(chosenLive);local typed=automatic.typedRewards
  check('all guaranteed items plus exactly one choice',typed and #list(typed.items)==2 and typed.choiceItemID==202)
  check('preferred automatic choice is usable equipment',typed and typed.items[2].itemID==202)
  check('planned gains contain one selected choice',#list(automatic.gains)==2 and automatic.gains[1].itemID==100 and automatic.gains[2].itemID==202)
  local target=attach(chosenLive,{rewardTarget=201})
  check('explicit item goal selects one matching choice',target.typedRewards and target.typedRewards.choiceItemID==201 and #target.typedRewards.items==2)
  local first=attach({items={},choices={{itemID=204,count=1},{itemID=205,count=1}}})
  check('unknown choice metadata does not fabricate a preferred upgrade',first.typedRewards and first.typedRewards.choiceItemID==204 and #first.typedRewards.items==1)
  if typed and typed.items[1]then typed.items[1].count=99 end
  check('typed reward edits cannot mutate observed reward rows',chosenLive.items[1].count==2)
  local objective={kind='objective',questID=900};rewards.Attach(objective,{}, {live={[900]={reward=chosenLive}}},{})
  check('objective action cannot attach turn-in rewards',objective.typedRewards==nil)

  reset();spec.money=99;spec.rewards={{itemID=500,count=2,usable=true}}
  spec.choices={{itemID=501,count=1,usable=true}};spec.metadata[500]={stack=20,equip=''}
  spec.metadata[501]={stack=1,equip='INVTYPE_CHEST'};spec.spells={701};spec.spellInfo[701]={isSpellLearned=true}
  local stale={};rewards.Read(stale,snapshot)
  spec.money=nil;spec.noRewardCount=true;spec.noChoiceCount=true;spec.spells=nil
  rewards.Read(stale,snapshot);local current=attach(row(stale) or {});typed=current.typedRewards or {}
  check('unavailable money does not inherit current live authority',typed.money==nil,
   'Merging only present keys from a new row must not preserve an old live money amount')
  check('unavailable guaranteed and choice lists cannot be spent as current rewards',#list(typed.items)==0,
   'A prior reward list needs explicit stale authority or removal before Attach consumes it')
  check('unavailable learned spells cannot remain current reward evidence',#list(typed.spells)==0)
 end
 local ok,problem=xpcall(run,function(err)return debug and debug.traceback and debug.traceback(err,2) or tostring(err)end)
 planner.Context=oldContext;planner.PlanRewards=oldRewards
 for _,name in ipairs(globals)do rawset(_G,name,saved[name].value)end
 RikUI=originalCore
 if not ok then error(problem,0)end
end
