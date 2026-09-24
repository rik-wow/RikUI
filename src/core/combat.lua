-- FIFO work queue. Explicit indices avoid shifting the array on every callback.
local core, runtime = RikUI, RikUI.Runtime
local queue, keyed = {}, {}
local head, tail, pending, draining = 1, 0, 0, false
local BATCH_LIMIT = 100
local continuation, scheduled

local function reset()
    queue, keyed = {}, {}
    head, tail, scheduled = 1, 0, false
    if continuation then continuation:SetScript("OnUpdate", nil) end
end

local function continueNextFrame()
    if scheduled then return end
    if not continuation then continuation = CreateFrame("Frame") end
    scheduled = true
    continuation:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        scheduled = false
        runtime.DrainCombat()
    end)
end

local function finishPass()
    if pending == 0 then reset()
    elseif not InCombatLockdown() then continueNextFrame() end
end

local function cancel(entry)
    if not entry or not entry.callback then return false end
    if entry.key then keyed[entry.key] = nil end
    entry.callback, entry.owner = nil, nil
    pending = pending - 1
    if pending == 0 and not draining then reset() end
    return true
end

function core.Combat.Pending() return pending end

function core.Combat.Cancel(key)
    return cancel(keyed[key])
end

local function drain(processed)
    if draining or scheduled or InCombatLockdown() then return end
    draining = true
    while head <= tail and processed < BATCH_LIMIT and not InCombatLockdown() do
        processed = processed + 1
        local entry = queue[head]
        queue[head], head = nil, head + 1
        if entry.callback then
            if entry.key then keyed[entry.key] = nil end
            pending = pending - 1
            runtime.InvokeOwned(entry.owner, "Combat queue", entry.callback)
        end
    end
    draining = false
    finishPass()
end

-- Event handlers may receive event names; they are never a batch counter.
function runtime.DrainCombat() drain(0) end

function core.Combat.Queue(callback, key)
    assert(type(callback) == "function", "Combat.Queue needs a function")
    assert(key == nil or (type(key) == "string" and key ~= ""), "Combat queue key must be a nonempty string")
    if not InCombatLockdown() and not draining and not scheduled and pending == 0 then
        -- Nested Queue calls join the tail instead of recursing on this stack.
        draining = true
        local ok, result = runtime.InvokeOwned(runtime.owner, "Combat queue", callback)
        draining = false
        drain(1)
        return ok, result
    end
    local entry = key and keyed[key]
    if entry then entry.callback, entry.owner = callback, runtime.owner
    else
        entry = { callback = callback, key = key, owner = runtime.owner }
        tail, pending = tail + 1, pending + 1
        queue[tail] = entry
        if key then keyed[key] = entry end
    end
    if not InCombatLockdown() and not draining then runtime.DrainCombat() end
    return true
end
