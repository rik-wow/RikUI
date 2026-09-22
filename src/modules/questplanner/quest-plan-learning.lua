-- Bounded local calibration. Preferences never change in response to incidental movement.
local planner=RikUI.QuestPlanner
local schema,learning=planner.Schema,{}
planner.PlanLearning=learning
local models,order,recent,visits,failures={}, {}, {}, {}, {}
local identityKey
local function key(identity,character)
    return identity and table.concat({identity.product,identity.build,identity.locale,character or "session"},":")
end
function learning.Bind(identity,character)
    local value=key(identity,character)
    if value~=identityKey then models,order,recent,visits,failures={},{},{},{},{};identityKey=value end
end
function learning.Observe(kind,context,seconds,units,options)
    options=options or {}
    if options.paused or options.afk or options.unrelated or not schema.Text(context) or #context>160
        or not schema.Number(seconds,.05,1200) or not schema.Number(units,.001,10000) then return false end
    if kind~="combat" and kind~="collection" and kind~="travel" and kind~="waiting" and kind~="interaction" and kind~="recovery" then return false end
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
function learning.State() return {recent=schema.Clone(recent),visited=schema.Clone(visits),failures=schema.Clone(failures)} end
function learning.Reset(kind)
    if kind=="estimates" then models,order={},{}
    elseif kind=="history" then recent,visits={},{}
    elseif kind=="retries" then failures={}
    elseif kind==nil then models,order,recent,visits,failures={},{},{},{},{} end
end
function learning.Export()
    return {version=1,identity=identityKey,models=schema.Clone(models),order=schema.Clone(order),
        recent=schema.Clone(recent),visits=schema.Clone(visits)}
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
        restored[id]=model
    end
    local restoredVisits={}
    local n=0
    for id,value in pairs(copy.visits or {}) do
        n=n+1;if n>128 or not schema.ID(id) or value~=true then return false end
        restoredVisits[id]=true
    end
    models,order,recent,visits=restored,copy.order,copy.recent,restoredVisits
    return true
end
