-- The only place RikUI hooks code it does not own.
-- On 1.60.1.69977, hooksecurefunc(object, "Method", fn) on a Blizzard object left that method nil for
-- Blizzard's own callers (nameplate UpdateAnchors, name:Show, ChatFrame1:SetPoint inside Edit Mode,
-- edit box UpdateHeader, ZoneAbilityFrame updates). So RikUI never hooks a method on a Blizzard
-- object: it hooks the object's scripts, a global function by name, or listens to an event.
-- tests/hooks-policy.test.lua keeps hooksecurefunc out of every other file.
local core = RikUI
local hooks = {}
core.Hooks = hooks

local owned = setmetatable({}, { __mode = "k" })

local function isFrame(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.HookScript) == "function"
end

-- frame:HookScript(script, fn). Returns false when the frame has no such script.
function hooks.Script(frame, script, fn)
    assert(type(script) == "string" and type(fn) == "function", "Hooks.Script needs a script name and a function")
    if not isFrame(frame) then return false end
    if type(frame.HasScript) == "function" then
        local ok, has = pcall(frame.HasScript, frame, script)
        if ok and has == false then return false end
    end
    local ok = pcall(frame.HookScript, frame, script, fn)
    return ok
end

-- Post-hook of a global function, by name. Returns false when the global is not a function.
function hooks.Function(name, fn)
    assert(type(name) == "string" and type(fn) == "function", "Hooks.Function needs a global name and a function")
    if type(_G[name]) ~= "function" then return false end
    hooksecurefunc(name, fn)
    return true
end

-- Post-hook of a function in one of the client's C_ API namespaces (C_ActionBar). Those are plain
-- tables of engine functions, not widgets, so the 69977 method-hook failure does not apply.
function hooks.Namespace(namespace, name, fn)
    assert(type(namespace) == "string" and namespace:match("^C_") and type(name) == "string" and type(fn) == "function",
        "Hooks.Namespace needs a C_ namespace name, a function name and a function")
    local tbl = _G[namespace]
    if type(tbl) ~= "table" or type(tbl[name]) ~= "function" then return false end
    hooksecurefunc(tbl, name, fn)
    return true
end

-- Marks a table as RikUI's own, so its methods may be post-hooked with Hooks.Owned.
function hooks.Own(tbl)
    assert(type(tbl) == "table", "Hooks.Own needs a table")
    owned[tbl] = true
    return tbl
end

local function pack(...) return { n = select("#", ...), ... } end

-- Post-hook of a method on a RikUI-owned table. Blizzard never calls these, so a plain wrapper is used.
function hooks.Owned(tbl, method, fn)
    assert(owned[tbl], "Hooks.Owned: table is not registered with Hooks.Own")
    assert(type(method) == "string" and type(fn) == "function", "Hooks.Owned needs a method name and a function")
    local original = tbl[method]
    if type(original) ~= "function" then return false end
    tbl[method] = function(...)
        local results = pack(original(...))
        fn(...)
        return unpack(results, 1, results.n)
    end
    return true
end

hooks.Own(core)
