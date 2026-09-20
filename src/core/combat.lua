-- FIFO work queue. Explicit indices avoid shifting the array on every callback.
local core, runtime = RikUI, RikUI.Runtime
local queue, keyed = {}, {}
local head, tail, pending, draining = 1, 0, 0, false

local function reset()
    queue, keyed = {}, {}
    head, tail = 1, 0
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

function runtime.DrainCombat()
    if draining or InCombatLockdown() then return end
    draining = true
    while head <= tail and not InCombatLockdown() do
        local entry = queue[head]
        queue[head], head = nil, head + 1
        if entry.callback then
            if entry.key then keyed[entry.key] = nil end
            pending = pending - 1
            local previous = runtime.owner
            runtime.owner = entry.owner
            runtime.Invoke("Combat queue", entry.callback)
            runtime.owner = previous
        end
    end
    draining = false
    if head > tail then reset() end
end

function core.Combat.Queue(callback, key)
    assert(type(callback) == "function", "Combat.Queue needs a function")
    assert(key == nil or (type(key) == "string" and key ~= ""), "Combat queue key must be a nonempty string")
    if not InCombatLockdown() and not draining and pending == 0 then
        return runtime.Invoke("Combat queue", callback)
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
