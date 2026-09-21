-- Validated compiled region inputs. No Lua evaluation or promotion of imported observations.
local planner, schema = RikUI.QuestPlanner, RikUI.QuestPlanner.Schema
local dataset = {}
planner.Dataset = dataset
local function same(a,b) return a.product==b.product and a.build==b.build and a.locale==b.locale end
local function sourced(source, identity, manifests)
    local manifest=source and manifests[source.id]
    return schema.Source(source) and same(source,identity) and manifest and manifest.status=="active"
        and manifest.authority==source.authority
end
local function book(raw)
    if not schema.List(raw.facts or {},32768) then return nil,"fact limit" end
    local builder,reason=planner.Corpus.New(raw.identity,raw.sources,raw.revision)
    if not builder then return nil,reason end
    for first=1,#(raw.facts or {}),64 do
        local batch={}
        for index=first,math.min(first+63,#raw.facts) do batch[#batch+1]=raw.facts[index] end
        local ok,problem=builder:Append(batch)
        if not ok then return nil,problem end
    end
    return builder:Finish()
end
local function references(rule, set)
    if not rule then return end
    if rule.questID then set[rule.questID]=true end
    if rule.arg then references(rule.arg,set) end
    for _,child in ipairs(rule.args or {}) do references(child,set) end
end
local function metadata(raw, corpus, nodes)
    local manifests, history, bindings, anchors={},{},{},{}
    for _,source in ipairs(corpus:Sources()) do manifests[source.id]=source end
    for _,edge in ipairs(raw.edges or {}) do
        if not sourced(edge.source,raw.identity,manifests) then return nil,"travel manifest missing" end
    end
    for _,row in ipairs(raw.actions or {}) do
        if not sourced(row.source,raw.identity,manifests) then return nil,"action manifest missing" end
        history[row.questID]=true
        references(row.requirement,history)
    end
    for _,fact in ipairs(raw.facts or {}) do
        if fact.field=="prerequisites" or fact.field=="requirements" then references(fact.value,history) end
    end
    if not schema.List(raw.bindings or {},40) or not schema.List(raw.anchors or {},64) then return nil,"binding limit" end
    for _,rawBinding in ipairs(raw.bindings or {}) do
        local binding=schema.Copy(rawBinding)
        if not binding then return nil,"invalid binding data" end
        if not schema.ID(binding.questID) or bindings[binding.questID] or not schema.List(binding.objectives,32)
            or not sourced(binding.source,raw.identity,manifests) then return nil,"invalid objective binding" end
        local keys={}
        for _,row in ipairs(binding.objectives) do
            if not schema.Text(row.key) or keys[row.key] or not schema.Text(row.text) or not schema.Text(row.type)
                or not schema.Integer(row.required,0,2147483647) then return nil,"invalid objective binding shape" end
            keys[row.key]=true
        end
        bindings[binding.questID]=schema.Clone(binding)
    end
    for _,rawAnchor in ipairs(raw.anchors or {}) do
        local anchor=schema.Copy(rawAnchor)
        if not anchor then return nil,"invalid anchor data" end
        if not nodes[anchor.node] or not schema.ID(anchor.npcID) or not schema.ID(anchor.mapID)
            or not sourced(anchor.source,raw.identity,manifests) then return nil,"invalid interaction anchor" end
        anchors[#anchors+1]=schema.Clone(anchor)
    end
    local ids={}
    for id in pairs(history) do ids[#ids+1]=id; if #ids>256 then return nil,"history query limit" end end
    table.sort(ids)
    return {history=ids,bindings=bindings,anchors=anchors}
end
local function counters(snapshot, bindings)
    local result={}
    for id,binding in pairs(bindings) do
        local row=snapshot.quests[id]
        local values=row and row.objectives
        if binding.source.authority=="verified" and values and #values==#binding.objectives then
            local mapped,valid={},true
            for index,expected in ipairs(binding.objectives) do
                local observed=values[index]
                if observed.type~=expected.type or observed.numRequired~=expected.required
                    or planner.Objectives.Text(observed)~=expected.text then valid=false; break end
                mapped[expected.key]=math.max(0,observed.numRequired-observed.numFulfilled)
            end
            if valid then result[id]=mapped end
        end
    end
    return result
end
local function locate(meta,ctx,dialog)
    if not dialog or not dialog.npcID or not ctx.position then return nil end
    local found
    for _,anchor in ipairs(meta.anchors) do
        if anchor.source.authority=="verified" and anchor.npcID==dialog.npcID and anchor.mapID==ctx.position.mapID then
            if found and found~=anchor.node then return nil end
            found=anchor.node
        end
    end
    return found
end
local function prepare(data,snapshot,status,ctx,dialog)
    if not same(data.identity,snapshot.identity) or ctx.origin~="live" then return nil,"dataset build/locale mismatch" end
    local state=planner.Eligibility.FromSnapshot(snapshot,status,ctx.attributes,planner.Context.History(data.meta.history))
    if not state then return nil,"current state unavailable" end
    state.node=locate(data.meta,ctx,dialog)
    if not state.node then return nil,"player is outside a verified graph anchor" end
    state.xp,state.xpMax=ctx.attributes.xp,ctx.attributes.xpMax
    state.travel={identity=schema.Clone(state.identity),departure=ctx.observedAt,flights={},transport={}}
    state.objectives,state.inventory=counters(snapshot,data.meta.bindings),{}
    local rows=data.actions:List()
    local queried,queries={},0
    for _,action in ipairs(rows) do
        local reward=ctx.rewards[action.questID]
        if reward and action.kind=="turnin" then action.xp,action.xpLevel=reward.xp,reward.level end
        for _,item in ipairs(action.consumes or {}) do
            if not queried[item.itemID] and queries<64 then
                queried[item.itemID],queries=true,queries+1
                local fn=type(C_Item)=="table" and C_Item.GetItemCount or GetItemCount
                local ok,count=planner.Context.Call(fn,item.itemID,false,false,false,false)
                if ok and schema.Integer(count,0,2147483647) then state.inventory[item.itemID]=count end
            end
        end
    end
    return {state=state,actions=planner.Actions.New(state.identity,rows),book=data.book,graph=data.graph}
end
local function construct(raw)
    if not schema.PlainTable(raw) or not schema.Identity(raw.identity) then return nil,"invalid dataset" end
    local corpus,reason=book(raw)
    if not corpus then return nil,reason end
    local actions,problem=planner.Actions.New(raw.identity,raw.actions or {})
    if not actions then return nil,problem end
    local graph,failure=planner.Travel.New(raw.identity,raw.revision,raw.nodes or {},raw.edges or {})
    if not graph then return nil,failure end
    local nodes={}
    for _,node in ipairs(raw.nodes or {}) do nodes[node.id]=schema.Clone(node) end
    local meta,issue=metadata(raw,corpus,nodes)
    if not meta then return nil,issue end
    local data={identity=corpus:Identity(),book=corpus,actions=actions,graph=graph,nodes=nodes,meta=meta}
    return {Identity=function() return corpus:Identity() end,Revision=function() return corpus:Revision() end,
        Coverage=function(_,zone) return corpus:Coverage(zone) end,
        Node=function(_,id) return schema.Clone(nodes[id]) end,
        Prepare=function(_,...) return prepare(data,...) end}
end
function dataset.New(raw)
    local ok,value,reason=pcall(construct,raw)
    if ok then return value,reason end
    return nil,"invalid compiled dataset"
end
