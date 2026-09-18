-- Preset resolution and diagnostics; ordered Apply lives in setup-apply.lua.
local core = RikUI
local setup = {}
core.Setup = setup

local ACTIONS = { "spell", "macro", "item" }
local SLOTS_PER_PAGE = 12

-- Native binding pages: MultiActionBar1=6, MultiActionBar2=5, right=3, left=4.
local PAGE_STARTS = { main = 1, battle = 73, defensive = 85, berserker = 97,
    bar2 = 61, bar3 = 49, bar4 = 25, bar5 = 37 }
setup.PageOrder = { "main", "battle", "defensive", "berserker", "bar2", "bar3", "bar4", "bar5" }

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
end

function setup.SlotToAction(page, index)
    local first = PAGE_STARTS[page]
    if not first or type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > SLOTS_PER_PAGE then
        return nil, "unknown page or slot outside 1..12"
    end
    return first + index - 1
end

local function overlay(target, layer)
    for index, slot in pairs(layer or {}) do target[index] = copy(slot) end
end

local function resolvePage(preset, overrides, page)
    local slots = {}
    if page == "battle" or page == "defensive" or page == "berserker" then
        overlay(slots, preset.bars.main)
        overlay(slots, overrides.main)
    end
    overlay(slots, preset.bars[page])
    overlay(slots, overrides[page])
    return slots
end

function setup.Resolve(class, role)
    local preset = core.Presets[class]
    if not preset then return nil, "No preset for " .. tostring(class) end
    role = role or "dps"
    if type(preset.roles) ~= "table" or not preset.roles[role] then return nil, "Unknown role: " .. tostring(role) end
    local issues = setup.ValidatePreset(preset)
    if #issues > 0 then return nil, issues[1] end
    local result, overrides = copy(preset), (preset.roleOverrides or {})[role] or {}
    result.bars, result.class, result.role = {}, class, role
    for _, page in ipairs(setup.PageOrder) do
        -- Do not populate stance pages for classes that did not declare them.
        if preset.bars[page] or overrides[page] then result.bars[page] = resolvePage(preset, overrides, page) end
    end
    return result
end

local function actionKind(slot)
    local kind, count = nil, 0
    for _, name in ipairs(ACTIONS) do
        if slot[name] ~= nil then kind, count = name, count + 1 end
    end
    if count == 1 then return kind end
end

local function spellIssue(slot)
    local entry = core.SpellData and core.SpellData[slot.spell]
    if not entry then return "unresolved spell: " .. slot.spell end
    if slot.level ~= entry.level then
        return slot.spell .. " level must be " .. entry.level
    end
end

local function slotIssue(slot, macros)
    if type(slot) ~= "table" then return "slot must be a table" end
    local kind = actionKind(slot)
    if not kind then return "slot must contain exactly one action" end
    local name = slot[kind]
    if type(name) ~= "string" or name == "" then return kind .. " must be a nonempty name" end
    if kind == "spell" then return spellIssue(slot) end
    if kind == "macro" and type(macros[name]) ~= "table" then
        return "unresolved macro: " .. name
    end
end

local function checkPage(slots, macros, path, issues)
    if type(slots) ~= "table" then
        issues[#issues + 1] = path .. ": page must be a table"
        return
    end
    for index, slot in pairs(slots) do
        local location = path .. "[" .. tostring(index) .. "]"
        if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > SLOTS_PER_PAGE then
            issues[#issues + 1] = location .. ": slot index must be 1.." .. SLOTS_PER_PAGE
        else
            local reason = slotIssue(slot, macros)
            if reason then issues[#issues + 1] = location .. ": " .. reason end
        end
    end
end

local function checkPages(pages, macros, path, issues)
    if type(pages) ~= "table" then
        issues[#issues + 1] = path .. ": pages must be a table"
        return
    end
    for page, slots in pairs(pages) do
        if not PAGE_STARTS[page] then issues[#issues + 1] = path .. ": unknown page " .. tostring(page) end
        checkPage(slots, macros, path .. "." .. tostring(page), issues)
    end
end

function setup.ValidatePreset(preset)
    if type(preset) ~= "table" then return { "preset must be a table" } end
    local issues, macros = {}, preset.macros
    if type(macros) ~= "table" then
        issues[#issues + 1] = "macros must be a table"
        macros = {}
    end
    checkPages(preset.bars, macros, "bars", issues)
    if preset.roleOverrides ~= nil then
        if type(preset.roleOverrides) ~= "table" then
            issues[#issues + 1] = "roleOverrides must be a table"
        else
            for role, pages in pairs(preset.roleOverrides) do
                checkPages(pages, macros, "roleOverrides." .. tostring(role), issues)
            end
        end
    end
    table.sort(issues)
    return issues
end

local function showPresets(args)
    if args ~= "validate" then core:Print("Usage: /rik preset validate") return end
    local names = {}
    for name in pairs(core.Presets) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then core:Print("No presets loaded.") return end
    for _, name in ipairs(names) do
        local issues = setup.ValidatePreset(core.Presets[name])
        if #issues == 0 then
            core:Print(name .. ": preset valid (catalogue references and spell levels).")
        else
            for _, issue in ipairs(issues) do core:Print(name .. ": " .. issue) end
        end
    end
end

core:RegisterCommand("preset", showPresets, "Validate loaded presets: /rik preset validate")
