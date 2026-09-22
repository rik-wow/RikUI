-- Lazy compact network admission, matched to the installed local terrain corpus.
local planner=RikUI.QuestPlanner
local schema,paths=planner.Schema,{}
planner.Paths=paths
local rawSeen,catalog,loader,graph,failure,busy,partAt,requestKey
local stats={loads=0,maxLoadMS=0,admissionSlices=0,retainedSourceBudgetBytes=0}
local catalogs,loadedNames={},{}
local catalogCount=0
local composition
local MAX_RETAINED_SOURCE=134217728
local function hash(v)return type(v)=="string"and#v==64 and v:match("^[a-f0-9]+$")end
function paths.Install(raw)
    local value=schema.CopyLimited(raw,4096,65536,12)
    if not value or not planner.TerrainPacks or not planner.TerrainPacks.Namespace(value.namespace,value.worldMapID)
        or not schema.Identity(value.identity)or not hash(value.sourceSHA256)or not hash(value.graphSHA256)
        or value.addonName~="RikUIQuestPaths_"..value.namespace then return nil,"invalid physical path catalog"end
    local prior=catalogs[value.namespace]
    if prior then
        if prior.payloadID==value.payloadID and prior.graphSHA256==value.graphSHA256 and prior.sourceSHA256==value.sourceSHA256 then return true end
        return nil,"path namespace already loaded"
    end
    if catalogCount>=64 then return nil,"path catalog cache limit"end
    catalogs[value.namespace]=value;catalogCount=catalogCount+1;return true
end
local function same(a,b) return a and b and a.product==b.product and a.build==b.build and a.locale==b.locale end
local function reject(reason) failure=reason;loader=nil;return nil,reason end
function paths.Stats() return schema.Clone(stats) end
local function resetSingle()
    if loader then loader:Cancel() end
    rawSeen,catalog,loader,graph,failure,partAt,requestKey=nil,nil,nil,nil,nil,1,nil
end
local function loadPart(name,raw,declaredBytes)
    if planner.TerrainPacks and planner.TerrainPacks.IsLoading()then return nil,"loading"end
    if type(InCombatLockdown)=="function" and InCombatLockdown() then return nil,"combat-loading-deferred" end
    local load=type(C_AddOns)=="table" and C_AddOns.LoadAddOn
    if type(load)~="function" then return reject("path-loader-unavailable") end
    local bytes=declaredBytes or 131072
    if not schema.Integer(bytes,1,131072)then return reject("invalid-path-load-budget")end
    if not loadedNames[name]then
        if stats.retainedSourceBudgetBytes+bytes>MAX_RETAINED_SOURCE then return reject("path source cache limit")end
        loadedNames[name]=bytes;stats.retainedSourceBudgetBytes=stats.retainedSourceBudgetBytes+bytes
    end
    local clock=type(debugprofilestop)=="function" and debugprofilestop
    local before=clock and clock()
    if planner.TerrainPacks and not planner.TerrainPacks.BeginLoad()then return nil,"loading"end
    busy=true
    local ok,loaded=pcall(load,name)
    busy=nil
    if planner.TerrainPacks then planner.TerrainPacks.EndLoad()end
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
local function prepareSingle(identity,mapID,binding)
    if busy then return nil,"loading"end
    local key=table.concat({tostring(identity and identity.product),tostring(identity and identity.build),
        tostring(identity and identity.locale),tostring(mapID),tostring(binding and binding.packKey),
        tostring(binding and binding.namespace),tostring(binding and binding.graphSHA256)},":")
    if requestKey~=key then resetSingle();requestKey=key end
    local raw=binding and binding.namespace and catalogs[binding.namespace]or(not(binding and binding.namespace)and RikUIQuestPathsCatalog)
    if raw==nil then return nil,"unavailable" end
    if raw~=rawSeen then
        resetSingle();requestKey=key;rawSeen=raw
        local copy=schema.CopyLimited(raw,4096,65536,12)
        if not copy or copy.format~="rikui-path-backbone-v2" or not schema.Identity(copy.identity)
            or not schema.ID(copy.uiMapID) or type(copy.addonName)~="string"
            or copy.addonName~=(copy.namespace and("RikUIQuestPaths_"..copy.namespace)or("RikUIQuestPaths_M"..copy.uiMapID))then return reject("invalid-path-catalog")end
        if copy.namespace and(not planner.TerrainPacks or not planner.TerrainPacks.Namespace(copy.namespace,copy.worldMapID)
            or not hash(copy.sourceSHA256))then return reject("invalid-path-catalog")end
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
    if not catalog or not same(identity,catalog.identity)or(not catalog.namespace and mapID~=catalog.uiMapID)then return nil,"unavailable"end
    if not binding or binding.graphSHA256~=catalog.graphSHA256 or not same(binding.identity,catalog.identity)
        or binding.mapID~=mapID or binding.namespace~=catalog.namespace
        or catalog.namespace and(binding.worldMapID~=catalog.worldMapID or binding.sourceSHA256~=catalog.sourceSHA256
            or not hash(binding.projectionSHA256))then return nil,"incompatible-path-source"end
    if graph then return graph,"ready" end
    if not loader then
        local payload=RikUIQuestPathsPayloads and RikUIQuestPathsPayloads[catalog.payloadID]
        if not payload then
            local loaded,why=loadPart(catalog.addonName,raw,catalog.baseBytes)
            if not loaded then return nil,why end
            payload=RikUIQuestPathsPayloads and RikUIQuestPathsPayloads[catalog.payloadID]
            if not payload then return reject("missing-path-payload") end
            if catalog.loadParts then return nil,"loading" end
        end
        if catalog.loadParts then
            if not schema.PlainTable(payload) or payload.format~=catalog.format or not schema.PlainTable(payload.loadedParts) then return reject("invalid-path-payload") end
            while partAt<=#catalog.loadParts and payload.loadedParts[partAt]==true do partAt=partAt+1 end
            if partAt<=#catalog.loadParts then
                local loaded,why=loadPart(catalog.loadParts[partAt].addon,raw,catalog.loadParts[partAt].bytes)
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


function paths.Reset()
    if composition and composition.job then composition.job:Cancel()end
    composition=nil;resetSingle()
end
function paths.Prepare(identity,mapID,binding)
    if not binding or not binding.packs then
        if composition then paths.Reset()end
        return prepareSingle(identity,mapID,binding)
    end
    if not planner.PathCompose or not planner.TerrainPacks then return nil,"composition-unavailable"end
    if not same(identity,binding.identity)or binding.mapID~=mapID or not schema.List(binding.packs,8)
        or#binding.packs<2 or type(binding.packKey)~="string"then return nil,"invalid-composition-binding"end
    if not composition or composition.key~=binding.packKey then
        paths.Reset();composition={key=binding.packKey,at=1,inputs={},binding=binding}
    end
    local current=composition
    if current.failure then return nil,current.failure end
    if current.graph then return current.graph,"ready"end
    local part=current.binding.packs[current.at]
    if part then
        local value,why=prepareSingle(identity,mapID,part)
        if composition~=current then return nil,"loading"end
        if not value then
            if why~="loading"and why~="combat-loading-deferred"then current.failure=why end
            return nil,why
        end
        current.inputs[#current.inputs+1]={namespace=part.namespace,graph=value,meta=part.meta}
        current.at=current.at+1;return nil,"loading"
    end
    if not current.job then
        local seams,why=planner.TerrainPacks.PrepareSeams(current.binding.connections)
        if not seams then
            if why~="loading"and why~="combat-loading-deferred"then current.failure=why end
            return nil,why
        end
        current.job,why=planner.PathCompose.Begin(current.inputs,seams,{maxStep=current.binding.maxStep,
            isCurrent=function()return composition==current end})
        if not current.job then current.failure=why;return nil,why end
        return nil,"loading"
    end
    local clock=type(debugprofilestop)=="function"and debugprofilestop;local before=clock and clock()
    for _=1,clock and 16 or 4 do
        local value,why,done=current.job:Step(8)
        if composition~=current then return nil,"loading"end
        if done then current.job=nil;current.graph=value;current.failure=not value and why or nil;return value,value and"ready"or why end
        if clock and clock()-before>=2 then break end
    end
    return nil,"loading"
end
