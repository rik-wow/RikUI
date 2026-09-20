-- Bootstrap and protected calls. Other services extend this one addon namespace.
local addonName, namespace = ...
local core = { Modules = {}, Data = {}, Presets = {}, Secret = {}, Combat = {}, UI = {} }
RikUI = core
if type(namespace) == "table" then namespace.Core = core end

-- Private service coordination; features use the public APIs documented in docs/architecture.md.
local runtime = { addonName = addonName, initialized = false, loggedIn = false, moduleOrder = {} }
core.Runtime = runtime

function core:Print(message)
    if issecretvalue(message) then message = "<secret>" end
    print("|cff80c0ffRikUI:|r " .. tostring(message))
end

function runtime.Report(context, reason)
    local detail = "unknown error"
    if not issecretvalue(reason) and type(reason) == "string" then detail = reason end
    -- Reporting must never abort event dispatch or leave a queue locked.
    pcall(core.Print, core, context .. ": " .. detail)
end

function runtime.Invoke(context, callback, ...)
    local ok, result = pcall(callback, ...)
    if not ok then runtime.Report(context, result) end
    return ok, result
end

-- Keep the pcall flag separate from every opaque return value, including nil slots.
function core.Secret.Read(reader, ...)
    return pcall(reader, ...)
end

function core.Secret.IsSecret(value)
    return issecretvalue(value)
end

local function deliver(sink, ok, ...)
    if not ok then return false, ... end
    return pcall(sink, ...)
end

function core.Secret.Apply(sink, reader, ...)
    return deliver(sink, core.Secret.Read(reader, ...))
end
