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

local errors, MAX_ERRORS, MAX_DETAIL = {}, 20, 512

local function errorText(value, fallback)
    if issecretvalue(value) or type(value) ~= "string" then return fallback end
    return value:sub(1, MAX_DETAIL)
end

function core:GetErrors()
    local copy = {}
    for index, entry in ipairs(errors) do
        copy[index] = { context = entry.context, detail = entry.detail, count = entry.count }
    end
    return copy
end

function core:ClearErrors() errors = {} end

function runtime.Report(context, reason)
    context = errorText(context, "Runtime")
    local detail = errorText(reason, "unknown error")
    for _, entry in ipairs(errors) do
        if entry.context == context and entry.detail == detail then
            entry.count = entry.count + 1
            return
        end
    end
    if #errors == MAX_ERRORS then table.remove(errors, 1) end
    errors[#errors + 1] = { context = context, detail = detail, count = 1 }
    -- Reporting must never abort event dispatch or leave a queue locked.
    pcall(core.Print, core, context .. ": " .. detail .. " (see /rik errors)")
end

function runtime.Invoke(context, callback, ...)
    local ok, result = pcall(callback, ...)
    if not ok then runtime.Report(context, result) end
    return ok, result
end

-- Ownership is scoped to one callback, including nested calls and failures.
function runtime.InvokeOwned(owner, context, callback, ...)
    local previous = runtime.owner
    runtime.owner = owner
    local ok, result = runtime.Invoke(context, callback, ...)
    runtime.owner = previous
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
