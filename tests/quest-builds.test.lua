-- Verified client builds map to the build RikUI's data was compiled from.
return function(check)
 local saved=RikUI
 local ok,why=pcall(function()
  RikUI={QuestPlanner={}}
  dofile('src/modules/questplanner/quest-builds.lua')
  local builds=RikUI.QuestPlanner.Builds
  check('a verified patch build uses the compiled data build',builds.DataBuild('1.60.1.69977')=='1.60.1.69913')
  check('the compiled build maps to itself',builds.DataBuild('1.60.1.69913')=='1.60.1.69913')
  check('an unverified build keeps its own identity',builds.DataBuild('1.60.1.70000')=='1.60.1.70000')
  builds.Observe('1.60.1.69977')
  check('the real client build stays readable',builds.Client()=='1.60.1.69977')
  builds.Observe('1.60.1.70009')
  local quest={product='forever',build=builds.DataBuild('1.60.1.70009'),locale='enUS'}
  local navigation=builds.NavigationIdentity(quest)
  check('70009 retains the supported quest baseline',quest.build=='1.60.1.69913')
  check('70009 requires rebuilt navigation',navigation.build=='1.60.1.70009' and builds.Client()=='1.60.1.70009')
  check('navigation conversion does not mutate the quest snapshot',quest.build=='1.60.1.69913' and navigation~=quest)
  local locale={product='forever',build=quest.build,locale='deDE'}
  check('navigation conversion preserves locale',builds.NavigationIdentity(locale).locale=='deDE')
  for _,other in ipairs({{product='other',build=quest.build,locale='enUS'},
      {product='forever',build='1.60.1.70000',locale='enUS'}}) do
   check('unverified identity is never converted',builds.NavigationIdentity(other)==other)
  end
  builds.Observe('1.60.1.70124')
  local current={product='forever',build=builds.DataBuild('1.60.1.70124'),locale='enUS'}
  local currentNavigation=builds.NavigationIdentity(current)
  check('70124 retains the verified quest subset',current.build=='1.60.1.69913')
  check('70124 retains the actual client identity',builds.Client()=='1.60.1.70124')
  check('70124 admits byte-identical 70009 navigation',currentNavigation.build=='1.60.1.70009')
  check('70124 does not mutate quest provenance',current.build=='1.60.1.69913' and currentNavigation~=current)
  check('70124 preserves locale',builds.NavigationIdentity(locale).locale=='deDE')
  for _,other in ipairs({{product='other',build='1.60.1.69913',locale='enUS'},
      {product='forever',build='1.60.1.70000',locale='enUS'}}) do
   check('70124 never converts unrelated identities',builds.NavigationIdentity(other)==other)
  end
  builds.Observe('1.60.1.70125')
  check('an unverified future build clears prior admission',builds.Client()==nil and builds.NavigationIdentity(current)==current)
  builds.Observe('1.60.1.69977')
  check('byte-identical client still uses original navigation',builds.NavigationIdentity(quest)==quest)
  builds.Observe('1.60.1.69913')
  check('no client build is reported when it equals the data build',builds.Client()==nil)
 end)
 RikUI=saved
 check('quest builds suite runs',ok,why)
end
