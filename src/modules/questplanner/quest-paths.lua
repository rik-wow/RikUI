-- Lazy compact network admission, matched to the installed local terrain corpus.
local planner=RikUI.QuestPlanner
local schema,paths=planner.Schema,{}
planner.Paths=paths
local rawSeen,catalog,loader,graph,failure,busy,partAt
local stats={loads=0,maxLoadMS=0,admissionSlices=0}
local function same(a,b) return a and b and a.product==b.product and a.build==b.build and a.locale==b.locale end
local function reject(reason) failure=reason;loader=nil;return nil,reason end
function paths.Stats() return schema.Clone(stats) end
function paths.Reset()
    if loader then loader:Cancel() end
    rawSeen,catalog,loader,graph,failure,partAt=nil,nil,nil,nil,nil,1
end
local function loadPart(name,raw)
    if type(InCombatLockdown)=="function" and InCombatLockdown() then return nil,"combat-loading-deferred" end
    local load=type(C_AddOns)=="table" and C_AddOns.LoadAddOn
    if type(load)~="function" then return reject("path-loader-unavailable") end
    local clock=type(debugprofilestop)=="function" and debugprofilestop
    local before=clock and clock()
    busy=true
    local ok,loaded=pcall(load,name)
    busy=nil
    if rawSeen~=raw then return nil,"loading" end
    if before then
        local duration=clock()-before
        stats.loadMS=(stats.loadMS or 0)+duration
        if duration>stats.maxLoadMS then stats.maxLoadMS=duration;stats.maxLoadAddon=name end
    end
    stats.loads=stats.loads+1
    if not ok or not loaded then return reject("path-addon-unavailable") end
    return true
end
function paths.Prepare(identity,mapID,binding)
    if busy then return nil,"loading" end
    local raw=RikUIQuestPathsCatalog
    if raw==nil then return nil,"unavailable" end
    if raw~=rawSeen then
        paths.Reset();rawSeen=raw
        local copy=schema.CopyLimited(raw,4096,65536,12)
        if not copy or copy.format~="rikui-path-backbone-v2" or not schema.Identity(copy.identity)
            or not schema.ID(copy.uiMapID) or type(copy.addonName)~="string"
            or copy.addonName~="RikUIQuestPaths_M"..copy.uiMapID then return reject("invalid-path-catalog") end
        if copy.loadParts~=nil then
            if not schema.PlainTable(copy.loadParts) or #copy.loadParts<1 or #copy.loadParts>512 then return reject("invalid-path-parts") end
            for key,part in pairs(copy.loadParts) do
                if not schema.Number(key,1,#copy.loadParts) or key%1~=0 or not schema.PlainTable(part)
                    or part.addon~=copy.addonName..string.format("_P%03d",key)
                    or not schema.Number(part.bytes,1,131072) or part.bytes%1~=0 then return reject("invalid-path-parts") end
            end
            for at=1,#copy.loadParts do if not copy.loadParts[at] then return reject("invalid-path-parts") end end
        end
        catalog=copy
    end
    if failure then return nil,failure end
    if not catalog or not same(identity,catalog.identity) or mapID~=catalog.uiMapID then return nil,"unavailable" end
    if not binding or binding.graphSHA256~=catalog.graphSHA256 or not same(binding.identity,catalog.identity)
        or binding.mapID~=mapID then return nil,"incompatible-path-source" end
    if graph then return graph,"ready" end
    if not loader then
        local payload=RikUIQuestPathsPayloads and RikUIQuestPathsPayloads[catalog.payloadID]
        if not payload then
            local loaded,why=loadPart(catalog.addonName,raw)
            if not loaded then return nil,why end
            payload=RikUIQuestPathsPayloads and RikUIQuestPathsPayloads[catalog.payloadID]
            if not payload then return reject("missing-path-payload") end
            if catalog.loadParts then return nil,"loading" end
        end
        if catalog.loadParts then
            if not schema.PlainTable(payload) or payload.format~=catalog.format or not schema.PlainTable(payload.loadedParts) then return reject("invalid-path-payload") end
            while partAt<=#catalog.loadParts and payload.loadedParts[partAt]==true do partAt=partAt+1 end
            if partAt<=#catalog.loadParts then
                local loaded,why=loadPart(catalog.loadParts[partAt].addon,raw)
                if not loaded then return nil,why end
                if payload.loadedParts[partAt]~=true then return reject("incomplete-path-part") end
                partAt=partAt+1
                return nil,"loading"
            end
        end
        local problem
        loader,problem=planner.PathGraph.Begin(catalog,payload)
        if not loader then return reject(problem or "invalid-path-payload") end
        return nil,"loading"
    end
    local clock=type(debugprofilestop)=="function" and debugprofilestop
    local before=clock and clock()
    for _=1,clock and 16 or 4 do
        local value,problem,done=loader:Step(8)
        stats.admissionSlices=stats.admissionSlices+1
        if done then
            loader=nil
            if not value then return reject(problem or "invalid-path-payload") end
            graph=value;return graph,"ready"
        end
        if clock and clock()-before>=2 then break end
    end
    return nil,"loading"
end
