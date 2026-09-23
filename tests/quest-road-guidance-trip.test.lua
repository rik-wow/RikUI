-- Road guidance trips: walk to a stop, show the link there, replan after the ride.
return function(check)
 local saved,savedTime=RikUI,GetTime
 local ok,why=pcall(function()
  RikUI={};RikUI['Secret']={IsSecret=function()return false end}
  dofile('src/modules/questplanner/quest-schema.lua')
  local p=RikUI.QuestPlanner
  GetTime=function()return 0 end
  local position={mapID=1426,x=.5,y=.5}
  p.Roads={
   Locate=function(mapID,x,y)return mapID==1439 and 1 or 0,{x=x*1000,z=y*1000},{} end,
   HasWorld=function()return true end,
   Prepare=function(_,world)return {revision='r'..world} end,
  }
  local goals,plans={},0
  p.RoadNavigate={Begin=function(_,_,_,goal)
   goals[#goals+1]=goal
   return {Step=function()return {status='no-known-path'} end,Cancel=function()end}
  end}
  local dock={id='dock:1:0',kind='dock',name='Menethil Harbor dock',world=0,point={600,0,500}}
  local lift={id='lift:1:0:bottom',kind='elevator',name='Undercity lift (bottom)',world=0,point={600,0,500}}
  local byID={[dock.id]=dock,[lift.id]=lift}
  local useLift,starts=false,{}
  p.RoadTravel={
   Count=function()return 3,1 end,
   Worlds=function()return {0,1} end,
   Stop=function(id)return byID[id] end,
   Begin=function(_,start)
    plans=plans+1;starts[#starts+1]=start
    if useLift then
     return {Step=function()return {status='planned',seconds=100,legs={
      {mode='walk',to=lift.id,stop=lift,text='Walk to the Undercity lift'},
      {mode='transport',from=lift.id,to='lift:1:0:top',link={vehicle='lift',direction='up'},text='Take the Undercity lift up'},
      {mode='walk',to='goal',text='Walk to the destination'}}} end}
    end
    return {Step=function()return {status='planned',seconds=300,legs={
     {mode='walk',to='dock:1:0',stop=dock,text='Walk to Menethil Harbor dock'},
     {mode='transport',from='dock:1:0',to='dock:1:1',text='Take the boat to Auberdine dock'},
     {mode='walk',to='goal',text='Walk to the destination'}}} end}
   end,
  }
  p.Context={Position=function()return position end}
  p.PeekSnapshot=function()return {identity={}} end
  local row={questID=1,destination={mapID=1439,x=.4,y=.4,scope='npc'}}
  p.Controller={Peek=function()return {status='current',selected=row} end}
  dofile('src/modules/questplanner/quest-road-guidance.lua')
  local g=p.RoadGuidance
  for _=1,3 do g.Step() end
  check('trip guidance routes the first walk to the stop',goals[1] and goals[1].x==600 and goals[1].z==500,goals[1] and goals[1].x)
  check('trip guidance plans the trip once while walking',plans==1,plans)
  position={mapID=1426,x=.605,y=.5}   -- at the dock (5 yd away)
  g.Step()
  local state=g.Status()
  check('trip guidance shows the link at the stop',state.status=='travel' and state.detail=='Take the boat to Auberdine dock',state.detail)
  position={mapID=1439,x=.2,y=.2}     -- after the ride: another world, far away
  g.Step()
  check('trip guidance replans after the ride',plans==2,plans)
  check('trip guidance starts the new plan at the landing stop of the ride',starts[2] and starts[2].stop=='dock:1:1',starts[2] and starts[2].stop)
  -- A lift: arriving shows the lift; walking off it replans from the top landing.
  useLift=true;g.Reset();position={mapID=1426,x=.5,y=.5};row.destination={mapID=1426,x=.9,y=.9,scope='npc'}
  for _=1,2 do g.Step() end
  position={mapID=1426,x=.603,y=.5};g.Step()
  check('trip guidance shows the lift at its stop',g.Status().detail=='Take the Undercity lift up',g.Status().detail)
  local before=plans
  position={mapID=1426,x=.64,y=.5};g.Step()
  check('walking off the lift replans from the top landing',plans==before+1 and starts[#starts].stop=='lift:1:0:top',
   starts[#starts] and starts[#starts].stop)
 end)
 RikUI,GetTime=saved,savedTime
 check('quest road guidance trip suite runs',ok,why)
end
