-- Deterministic activation with explicit dependencies and isolated failure states.
local core, runtime = RikUI, RikUI.Runtime
local records, visiting, owners = {}, {}, {}
local order = runtime.moduleOrder
local starting = false

local function configure(name)
    local flags = core.Profile.modules
    if type(flags[name]) ~= "boolean" then flags[name] = true end
    core.Modules[name].enabled = flags[name]
    if records[name].state == "registered" or records[name].state == "disabled" then
        records[name].state = flags[name] and "registered" or "disabled"
    end
end

function runtime.ConfigureModules()
    for _, name in ipairs(order) do configure(name) end
end

local function block(name, reason)
    local record = records[name]
    if record.reason ~= reason then runtime.Report("Module " .. name, reason) end
    record.state, record.reason = "blocked", reason
    return false
end

local function activate(name)
    local module, record = core.Modules[name], records[name]
    record.state, record.reason = "enabling", nil
    local ok, reason = true, nil
    if module.OnEnable then
        ok, reason = runtime.InvokeOwned(module, "Module " .. name, module.OnEnable, module)
    end
    record.state = ok and "enabled" or "failed"
    if not ok then
        record.reason = type(reason) == "string" and not core.Secret.IsSecret(reason) and reason or "activation failed"
        core:UnregisterOwner(module)
        -- Queued service work is not rolled back: shared jobs own pending flags.
    end
    return ok
end

local enable
enable = function(name)
    local record = records[name]
    if not record then return false end
    if visiting[name] then return block(name, "cyclic module dependency") end
    if record.state ~= "registered" then return record.state == "enabled" end
    visiting[name] = true
    for _, dependency in ipairs(record.dependencies) do
        if not enable(dependency) then
            visiting[name] = nil
            return block(name, "dependency unavailable: " .. dependency)
        end
    end
    visiting[name] = nil
    return activate(name)
end

function runtime.StartModules()
    if starting then return end
    starting = true
    local count
    repeat
        count = #order
        -- Only new registrations justify another pass over blocked consumers.
        -- Failed hooks never retry: they may have installed irreversible hooks.
        for _, name in ipairs(order) do
            if records[name].state == "blocked" then records[name].state = "registered" end
        end
        local index = 1
        while index <= #order do enable(order[index]); index = index + 1 end
    until #order == count
    starting = false
end

local function dependencies(options)
    if options == nil then return {} end
    assert(type(options) == "table", "Module options must be a table")
    local source, copy, count = options.dependencies, {}, 0
    if source == nil then source = {} end
    assert(type(source) == "table", "Module dependencies must be a list")
    for key, value in pairs(source) do
        assert(type(key) == "number" and key >= 1 and key % 1 == 0 and key <= #source,
            "Module dependencies must be a dense list")
        assert(type(value) == "string" and value ~= "", "Module dependency must be a name")
        copy[key], count = value, count + 1
    end
    assert(count == #source, "Module dependencies must be a dense list")
    return copy
end

function core:RegisterModule(name, module, options)
    assert(type(name) == "string" and name ~= "" and type(module) == "table", "RegisterModule needs a name and table")
    assert(not self.Modules[name], "Module already registered: " .. name)
    assert(not owners[module], "Module table already registered: " .. tostring(owners[module]))
    assert(module.OnEnable == nil or type(module.OnEnable) == "function", "OnEnable must be a function")
    local record = { state = "registered", dependencies = dependencies(options) }
    self.Modules[name], records[name], owners[module] = module, record, name
    order[#order + 1] = name
    if runtime.initialized then configure(name) end
    if runtime.loggedIn then runtime.StartModules() end
    return module
end

function core:GetModuleState(name)
    local record = records[name]
    if record then return record.state, record.reason end
end
