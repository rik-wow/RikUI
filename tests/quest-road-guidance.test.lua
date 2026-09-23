-- Road guidance: a failed plan is not restarted every frame, but is retried
-- after the player moves or a transient wait passes, and never claims that no
-- walking path exists.
return function(check)
 local saved,savedTime=RikUI,GetTime
 local ok,why=pcall(function()
  RikUI={};RikUI['Secret']={IsSecret=function()return false end}
  dofile('src/modules/questplanner/quest-schema.lua')
  local p=RikUI.QuestPlanner
  local clock,position,begins,status=0,{mapID=1426,x=.5,y=.5},0,'no-known-path'
  GetTime=function()return clock end
  p.Roads={
   Locate=function(mapID,x,y)return 0,{x=x*1000,z=y*1000},{} end,
   HasWorld=function()return true end,
   Prepare=function()return {revision='r'} end,
  }
  p.RoadNavigate={Begin=function()
   begins=begins+1
   return {Step=function()return {status=status,detail='raw'} end,Cancel=function()end}
  end}
  p.Context={Position=function()return position end}
  p.PeekSnapshot=function()return {identity={}} end
  local row={questID=1,destination={mapID=1429,x=.4,y=.8,scope='npc'}}
  p.Controller={Peek=function()return {status='current',selected=row} end}
  dofile('src/modules/questplanner/quest-road-guidance.lua')
  local g=p.RoadGuidance
  for _=1,20 do g.Step() end
  check('road guidance plans a failed destination once while the player stands still',begins==1,begins)
  local detail=g.Status().detail
  check('road guidance reports a model gap, not a missing walking path',detail:find('terrain model has a gap')~=nil and not detail:find('flight'),detail)
  position={mapID=1426,x=.55,y=.5}
  for _=1,3 do g.Step() end
  check('road guidance retries after the player moves 40 yards',begins==2,begins)
  g.Reset();for _=1,3 do g.Step() end
  check('road guidance retries after an explicit reset',begins==3,begins)
  status='loading';g.Reset();for _=1,5 do g.Step() end
  local first=begins;clock=clock+3;for _=1,3 do g.Step() end
  check('road guidance retries a transient failure after its wait',begins==first+1,begins-first)
 end)
 RikUI,GetTime=saved,savedTime
 check('quest road guidance suite runs',ok,why)
end
