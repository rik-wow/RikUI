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
  builds.Observe('1.60.1.69913')
  check('no client build is reported when it equals the data build',builds.Client()==nil)
 end)
 RikUI=saved
 check('quest builds suite runs',ok,why)
end
