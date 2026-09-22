return function(check)
    local saved={}
    for _,name in ipairs({"RikUI","RikUIQuestPathsCatalog","RikUIQuestPathsPayloads","C_AddOns","InCombatLockdown","debugprofilestop"}) do saved[name]={rawget(_G,name)} end
    local ok,why=pcall(function()
        RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
        dofile("src/modules/questplanner/quest-schema.lua")
        local p=RikUI.QuestPlanner
        local identity={product="forever",build="1.60.1.69913",locale="enUS"}
        local hash=string.rep("a",64)
        local binding={identity=identity,mapID=1426,graphSHA256=hash}
        local calls,steps,cancelled,combat=0,0,0,false
        local result={identity="fixture graph"}
        p.PathGraph={Begin=function(catalog,payload)
            if not payload or payload.format~=catalog.format then return nil,"wrong payload" end
            return {Cancel=function() cancelled=cancelled+1 end,Step=function()
                steps=steps+1
                if steps%6==0 then return result,nil,true end
            end}
        end}
        dofile("src/modules/questplanner/quest-paths.lua")
        local paths=p.Paths
        debugprofilestop=nil
        InCombatLockdown=function() return combat end
        RikUIQuestPathsCatalog=nil;RikUIQuestPathsPayloads={}
        check("paths absent pack does not load addons",select(2,paths.Prepare(identity,1426,binding))=="unavailable")
        RikUIQuestPathsCatalog={format="rikui-path-backbone-v2",identity=identity,uiMapID=1426,
            graphSHA256=hash,payloadID=hash,addonName="RikUIQuestPaths_M1426"}
        C_AddOns={LoadAddOn=function(name)
            calls=calls+1
            assert(calls<=2,"recursive or repeated addon loading")
            local _,state=paths.Prepare(identity,1426,binding)
            assert(state=="loading","reentrant load must defer")
            RikUIQuestPathsPayloads[hash]={format="rikui-path-backbone-v2"};return true
        end}
        check("paths unmatched map does not load",select(2,paths.Prepare(identity,1,binding))=="unavailable" and calls==0)
        local mismatch={identity=identity,mapID=1426,graphSHA256=string.rep("b",64)}
        check("paths source graph mismatch cannot attach",select(2,paths.Prepare(identity,1426,mismatch))=="incompatible-path-source" and calls==0)
        combat=true
        check("paths cold loading waits until outside combat",select(2,paths.Prepare(identity,1426,binding))=="combat-loading-deferred" and calls==0)
        combat=false
        local value,state=paths.Prepare(identity,1426,binding)
        check("paths load returns before graph admission",not value and state=="loading" and calls==1 and steps==0)
        value,state=paths.Prepare(identity,1426,binding)
        check("paths admission has bounded fallback slices",not value and state=="loading" and steps==4)
        value,state=paths.Prepare(identity,1426,binding)
        check("paths publishes only finished graph",value==result and state=="ready" and steps==6)
        local after=steps
        check("paths ready graph is reused",paths.Prepare(identity,1426,binding)==result and steps==after and calls==1)
        paths.Reset();paths.Prepare(identity,1426,binding);paths.Reset()
        check("paths reset cancels an unfinished admission",cancelled==1)
        local invalid=p.Schema.Clone(RikUIQuestPathsCatalog);invalid.format="rikui-path-backbone-v1";RikUIQuestPathsCatalog=invalid
        check("paths shared payload ID does not admit an older format",select(2,paths.Prepare(identity,1426,binding))=="invalid-path-catalog")
        local before=calls;paths.Prepare(identity,1426,binding)
        check("paths invalid catalog does not reload each frame",calls==before)
        invalid=p.Schema.Clone(invalid);invalid.format="rikui-path-backbone-v2";RikUIQuestPathsCatalog=invalid
        RikUIQuestPathsPayloads[hash]={format="corrupt"}
        check("paths invalid payload fails before publication",select(2,paths.Prepare(identity,1426,binding))=="wrong payload")
        -- Multipart delivery loads exactly one bounded addon per call and
        -- never admits a graph until all completion markers are present.
        local multipart=p.Schema.Clone(invalid)
        multipart.loadParts={{addon="RikUIQuestPaths_M1426_P001",bytes=120000},{addon="RikUIQuestPaths_M1426_P002",bytes=100}}
        RikUIQuestPathsCatalog=multipart;RikUIQuestPathsPayloads={}
        local loadedNames={}
        C_AddOns.LoadAddOn=function(name)
            loadedNames[#loadedNames+1]=name
            if name==multipart.addonName then RikUIQuestPathsPayloads[hash]={format=multipart.format,loadedParts={}}
            else
                local index=tonumber(name:match("_P(%d+)$"));RikUIQuestPathsPayloads[hash].loadedParts[index]=true
            end
            check("multipart recursive prepare defers",select(2,paths.Prepare(identity,1426,binding))=="loading")
            return true
        end
        local startSteps=steps
        paths.Prepare(identity,1426,binding)
        check("multipart base load defers all parts",#loadedNames==1 and steps==startSteps)
        paths.Prepare(identity,1426,binding)
        check("multipart first load is bounded to one part",#loadedNames==2 and steps==startSteps)
        combat=true
        check("multipart combat defers the next part",select(2,paths.Prepare(identity,1426,binding))=="combat-loading-deferred" and #loadedNames==2)
        combat=false;paths.Prepare(identity,1426,binding)
        check("multipart final load still defers admission",#loadedNames==3 and steps==startSteps)
        paths.Prepare(identity,1426,binding)
        check("multipart starts admission after all markers",steps==startSteps and #loadedNames==3)
        paths.Prepare(identity,1426,binding);value=paths.Prepare(identity,1426,binding)
        check("multipart publishes the completed graph",value==result and #loadedNames==3)
        local malformed=p.Schema.Clone(multipart);malformed.loadParts[1].bytes=131073;RikUIQuestPathsCatalog=malformed
        check("multipart oversized declaration rejected",select(2,paths.Prepare(identity,1426,binding))=="invalid-path-parts")
        malformed=p.Schema.Clone(multipart);malformed.loadParts[1].addon="UnrelatedAddon";RikUIQuestPathsCatalog=malformed
        check("multipart unrelated addon name rejected",select(2,paths.Prepare(identity,1426,binding))=="invalid-path-parts")
        RikUIQuestPathsCatalog=p.Schema.Clone(multipart);RikUIQuestPathsPayloads[hash].loadedParts={}
        C_AddOns.LoadAddOn=function() return true end
        check("multipart missing completion marker rejected",select(2,paths.Prepare(identity,1426,binding))=="incomplete-path-part")
        RikUIQuestPathsCatalog=p.Schema.Clone(multipart);RikUIQuestPathsPayloads={}
        C_AddOns.LoadAddOn=function()
            paths.Reset();return true
        end
        check("multipart reset during loading cannot publish stale payload",select(2,paths.Prepare(identity,1426,binding))=="loading")
    end)
    for name,row in pairs(saved) do rawset(_G,name,row[1]) end
    check("compact paths lifecycle fixture completes",ok,why)
end
