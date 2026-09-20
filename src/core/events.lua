-- One native frame; ordered subscriptions with deferred compaction during dispatch.
local core, runtime = RikUI, RikUI.Runtime
local frame = CreateFrame("Frame")
local events, rejected = {}, {}

local function compact(event, bucket)
    if bucket.depth > 0 or not bucket.dirty then return end
    bucket.dirty = false
    local handlers, write = bucket.handlers, 1
    for read = 1, #handlers do
        if handlers[read].callback then handlers[write] = handlers[read]; write = write + 1 end
    end
    for index = #handlers, write, -1 do handlers[index] = nil end
    if bucket.count == 0 then events[event] = nil end
end

local function remove(event, bucket, callback, owner)
    local removed = false
    for _, entry in ipairs(bucket.handlers) do
        if entry.callback and ((callback and entry.callback == callback) or (owner and entry.owner == owner)) then
            entry.callback, entry.owner = nil, nil
            bucket.count, removed, bucket.dirty = bucket.count - 1, true, true
        end
    end
    if bucket.count == 0 then runtime.Invoke("Unregister event " .. event, frame.UnregisterEvent, frame, event) end
    compact(event, bucket)
    return removed
end

function core:RegisterEvent(event, callback, owner)
    assert(type(event) == "string" and event ~= "" and type(callback) == "function",
        "RegisterEvent needs an event and callback")
    if owner == nil then owner = runtime.owner end
    if rejected[event] then return false end
    local bucket = events[event]
    if not bucket or bucket.count == 0 then
        local ok, registered = pcall(frame.RegisterEvent, frame, event)
        if not ok or registered == false then
            rejected[event] = true
            runtime.Report("Could not register event", event)
            return false
        end
        bucket = bucket or { handlers = {}, count = 0, depth = 0, label = "Event " .. event }
        events[event] = bucket
    end
    for _, entry in ipairs(bucket.handlers) do
        if entry.callback == callback and entry.owner == owner then return true end
    end
    bucket.handlers[#bucket.handlers + 1] = { callback = callback, owner = owner }
    bucket.count = bucket.count + 1
    return true
end

function core:UnregisterEvent(event, callback)
    assert(type(event) == "string" and type(callback) == "function", "UnregisterEvent needs an event and callback")
    local bucket = events[event]
    return bucket and remove(event, bucket, callback) or false
end

function core:UnregisterOwner(owner)
    assert(owner ~= nil and owner ~= false, "UnregisterOwner needs an owner")
    local removed = false
    for event, bucket in pairs(events) do
        if remove(event, bucket, nil, owner) then removed = true end
    end
    return removed
end

frame:SetScript("OnEvent", function(_, event, ...)
    local bucket = events[event]
    if not bucket then return end
    bucket.depth = bucket.depth + 1
    -- Additions wait for the next dispatch; removals take effect immediately.
    local handlers, count = bucket.handlers, #bucket.handlers
    for index = 1, count do
        local entry = handlers[index]
        if entry.callback then
            local previous = runtime.owner
            runtime.owner = entry.owner
            runtime.Invoke(bucket.label, entry.callback, event, ...)
            runtime.owner = previous
        end
    end
    bucket.depth = bucket.depth - 1
    compact(event, bucket)
end)
