-- Bounded local calibration. Preferences never change in response to incidental movement.
local planner=RikUI.QuestPlanner
local schema,learning=planner.Schema,{}
planner.PlanLearning=learning
local models,order,recent,visits,failures={}, {}, {}, {}, {}
local completed,completionOrder={},{}
local places={}
local identityKey
local function summarize(model)
    model.mean,model.minimum,model.maximum=0,math.huge,0
    for _,value in ipairs(model.values) do
        model.mean=model.mean+value;model.minimum=math.min(model.minimum,value);model.maximum=math.max(model.maximum,value)
    end
    model.mean=model.mean/#model.values
    model.samples=math.max(#model.values,model.samples or 0)
    return model
end
local function key(identity,character)
    return identity and table.concat({identity.product,identity.build,identity.locale,character or "session"},":")
end
function learning.Bind(identity,character)
    local value=key(identity,character)
    if value~=identityKey then models,order,recent,visits,failures={},{},{},{},{};completed,completionOrder={},{};identityKey=value;places={} end
end
function learning.Observe(kind,context,seconds,units,options)
    options=options or {}
    if options.paused or options.afk or options.unrelated or not schema.Text(context) or #context>160
        or not schema.Number(seconds,.05,kind=="combatXP" and 1200000 or 1200) or not schema.Number(units,.001,10000) then return false end
    if kind~="combat" and kind~="collection" and kind~="travel" and kind~="waiting" and kind~="interaction" and kind~="recovery" and kind~="death" and kind~="combatXP" then return false end
    local id=kind..":"..context
    local model=models[id]
    if not model then
        if #order>=128 then models[table.remove(order,1)]=nil end
        model={samples=0,values={},kind=kind,context=context};models[id]=model;order[#order+1]=id
    end
    model.values[#model.values+1]=seconds/units
    if #model.values>32 then table.remove(model.values,1) end
    model.samples=model.samples+1;model.mean=0;model.minimum=math.huge;model.maximum=0
    for _,value in ipairs(model.values) do
        model.mean=model.mean+value;model.minimum=math.min(model.minimum,value);model.maximum=math.max(model.maximum,value)
    end
    model.mean=model.mean/#model.values
    return true
end
function learning.Estimate(kind,context)
    local model=models[kind..":"..tostring(context)]
    if not model then return end
    return {mean=model.mean,minimum=model.minimum,maximum=model.maximum,samples=#model.values,totalSamples=model.samples,
        authority="observed-local",context=context}
end
function learning.Activity(activity)
    if not schema.Text(activity) then return end
    recent[#recent+1]=activity;if #recent>12 then table.remove(recent,1) end
end
function learning.Visit(mapID)
    if not schema.ID(mapID) then return end
    if not visits[mapID] then
        local n=0;for _ in pairs(visits) do n=n+1 end
        if n>=128 then return end
        visits[mapID]=true
    end
end
function learning.Failure(actionID,unavailable)
    if not schema.Text(actionID) then return end
    if unavailable then
        local n=0;for _ in pairs(failures) do n=n+1 end
        if n>=128 and not failures[actionID] then return end
        failures[actionID]=math.min(2,(failures[actionID] or 0)+1)
    else failures[actionID]=nil end
end
function learning.Completion(id,done)
    if not schema.ID(id) then return end
    if done==true then
        if not completed[id] then
            if #completionOrder>=256 then completed[table.remove(completionOrder,1)]=nil end
            completionOrder[#completionOrder+1]=id
        end
        completed[id]=true
    elseif done==false then
        completed[id]=nil
        for index=#completionOrder,1,-1 do if completionOrder[index]==id then table.remove(completionOrder,index) end end
    end
end
function learning.VisitPlace(key)
    if not schema.Text(key) or #key>160 then return end
    if not places[key] then
        local ids={};for id in pairs(places) do ids[#ids+1]=id end
        if #ids>=128 then table.sort(ids);places[ids[1]]=nil end
        places[key]=true
    end
end
function learning.State() return {recent=schema.Clone(recent),visited=schema.Clone(visits),failures=schema.Clone(failures),
    completed=schema.Clone(completed),places=schema.Clone(places)} end
function learning.Reset(kind)
    if kind=="estimates" then models,order={},{}
    elseif kind=="history" then recent,visits,completed,completionOrder={},{},{},{};places={}
    elseif kind=="retries" then failures={}
    elseif kind==nil then models,order,recent,visits,failures={},{},{},{},{};completed,completionOrder={},{};places={} end
end
function learning.Export(compact)
    if compact then
        local savedModels,savedOrder={},{}
        for index=math.max(1,#order-7),#order do
            local id=order[index]
            savedOrder[#savedOrder+1]=id
            local model=schema.Clone(models[id])
            while #model.values>8 do table.remove(model.values,1) end
            for index,value in ipairs(model.values) do model.values[index]=math.max(.000001,math.floor(value*1000+.5)/1000) end
            savedModels[id]=summarize(model)
        end
        local savedFailures,ids={},{}
        for id in pairs(failures) do ids[#ids+1]=id end;table.sort(ids)
        for index=1,math.min(16,#ids) do savedFailures[ids[index]]=failures[ids[index]] end
        local saved={version=1,identity=identityKey,models=savedModels,order=savedOrder,
            recent=schema.Clone(recent),visits=schema.Clone(visits),failures=savedFailures,completed=schema.Clone(completionOrder),places=schema.Clone(places)}
        if RikUI.Codec then
            for _=1,12 do
                local wire=RikUI.Codec.Encode(saved)
                if wire and #wire<=6000 then break end
                if #saved.order>0 then saved.models[table.remove(saved.order,1)]=nil
                elseif next(saved.failures) then saved.failures={}
                elseif #saved.completed>64 then for _=1,64 do table.remove(saved.completed,1) end
                elseif next(saved.places) then saved.places={}
                else saved.visits={};break end
            end
        end
        return saved
    end
    return {version=1,identity=identityKey,models=schema.Clone(models),order=schema.Clone(order),
        recent=schema.Clone(recent),visits=schema.Clone(visits),failures=schema.Clone(failures),completed=schema.Clone(completionOrder),places=schema.Clone(places)}
end
function learning.Restore(raw)
    local copy=schema.CopyLimited(raw,24000,180000,8)
    if not copy or copy.version~=1 or copy.identity~=identityKey or not schema.List(copy.order,128)
        or not schema.List(copy.recent,12) then return false end
    local restored={}
    for _,id in ipairs(copy.order) do
        local model=copy.models and copy.models[id]
        if not schema.Text(id) or not model or not schema.List(model.values,32) or #model.values==0
            or not schema.Number(model.mean,.000001,1200000) then return false end
        for _,value in ipairs(model.values) do if not schema.Number(value,.000001,1200000) then return false end end
        if restored[id] or not schema.Integer(model.samples or #model.values,1,2147483647) then return false end
        restored[id]=summarize(model)
    end
    local restoredVisits={}
    local n=0
    for id,value in pairs(copy.visits or {}) do
        n=n+1;if n>128 or not schema.ID(id) or value~=true then return false end
        restoredVisits[id]=true
    end
    local restoredCompleted,restoredOrder,restoredFailures={},{},{}
    if not schema.List(copy.completed or {},256) then return false end
    for _,id in ipairs(copy.completed or {}) do
        if not schema.ID(id) or restoredCompleted[id] then return false end
        restoredCompleted[id]=true;restoredOrder[#restoredOrder+1]=id
    end
    local failureCount=0
    for id,value in pairs(copy.failures or {}) do
        failureCount=failureCount+1
        if failureCount>128 or not schema.Text(id) or #id>160 or not schema.Integer(value,1,2) then return false end
        restoredFailures[id]=value
    end
    local restoredPlaces={};local placeCount=0
    for id,value in pairs(copy.places or {}) do
        placeCount=placeCount+1
        if placeCount>128 or not schema.Text(id) or #id>160 or value~=true then return false end
        restoredPlaces[id]=true
    end
    places=restoredPlaces
    models,order,recent,visits,failures=restored,copy.order,copy.recent,restoredVisits,restoredFailures
    completed,completionOrder=restoredCompleted,restoredOrder
    return true
end
local replayActive=false
function learning.WithSnapshot(raw,fn)
    if replayActive or type(fn)~="function" or not schema.PlainTable(raw) or not schema.Text(raw.identity) then return false,"Invalid replay learning" end
    local saved={identityKey,models,order,recent,visits,failures,completed,completionOrder,places}
    replayActive=true;identityKey=raw.identity
    local restored,accepted=pcall(learning.Restore,raw)
    local ok,result
    if not restored or accepted~=true then ok=false;result="Invalid replay learning"
    else ok,result=pcall(fn) end
    identityKey,models,order,recent,visits,failures,completed,completionOrder,places=unpack(saved,1,9)
    replayActive=false
    return ok,result
end
