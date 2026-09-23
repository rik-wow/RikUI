-- Composition and file-load global ownership; runtime behavior has separate suites.
return function(check)
    local files = dofile("tests/load_addon.lua").Manifest()
    local index, chunks = {}, {}
    for position, path in ipairs(files) do
        check("TOC entry is unique: " .. path, index[path:lower()] == nil)
        index[path:lower()] = position
        local chunk, reason = loadfile(path)
        check("TOC entry exists and compiles: " .. path, chunk ~= nil, reason)
        chunks[path] = chunk
    end
    local function before(first, second)
        local a, b = index[first:lower()], index[second:lower()]
        check("TOC prerequisite: " .. first .. " before " .. second, a ~= nil and b ~= nil and a < b)
    end
    local bootstrap, lifecycle = "src/core/core.lua", "src/core/lifecycle.lua"
    check("TOC starts with bootstrap", files[1] == bootstrap)
    for _, name in ipairs({ "events", "profiles", "modules", "commands", "combat" }) do
        local path = "src/core/" .. name .. ".lua"
        before(bootstrap, path)
        before(path, lifecycle)
    end
    for _, path in ipairs(files) do
        if not path:match("^src/core/") then before(lifecycle, path) end
    end
    for _, edge in ipairs({
        { "src/setup/setup.lua", "src/modules/bars/bars-ghosts.lua" },
        { "src/modules/bars/bars.lua", "src/modules/bars/bars-ghosts.lua" },
        { "src/modules/questplanner/quest-schema.lua", "src/modules/questplanner/quest-evidence.lua" },
        { "src/modules/questplanner/quest-schema.lua", "src/modules/questplanner/quest-reader.lua" },
        { "src/modules/questplanner/quest-reader.lua", "src/modules/questplanner/questplanner.lua" },
        { "src/modules/questplanner/quest-evidence.lua", "src/modules/questplanner/quest-corpus.lua" },
        { "src/modules/questplanner/quest-schema.lua", "src/modules/questplanner/quest-transfer.lua" },
        { "src/modules/questplanner/quest-schema.lua", "src/modules/questplanner/quest-eligibility.lua" },
        { "src/modules/questplanner/quest-schema.lua", "src/modules/questplanner/quest-elevators.lua" },
        { "src/modules/questplanner/quest-elevators.lua", "src/modules/questplanner/quest-travel.lua" },
        { "src/modules/questplanner/quest-eligibility.lua", "src/modules/questplanner/quest-actions.lua" },
        { "src/modules/questplanner/quest-actions.lua", "src/modules/questplanner/quest-simulation.lua" },
        { "src/modules/questplanner/quest-simulation.lua", "src/modules/questplanner/quest-optimizer.lua" },
        { "src/modules/questplanner/quest-travel.lua", "src/modules/questplanner/quest-optimizer.lua" },
        { "src/modules/questplanner/quest-optimizer.lua", "src/modules/questplanner/quest-context.lua" },
        { "src/modules/questplanner/quest-context.lua", "src/modules/questplanner/quest-journal.lua" },
        { "src/modules/questplanner/quest-journal.lua", "src/modules/questplanner/quest-dataset.lua" },
        { "src/modules/questplanner/quest-dataset.lua", "src/modules/questplanner/quest-guidance.lua" },
        { "src/modules/questplanner/quest-guidance.lua", "src/modules/questplanner/quest-controller.lua" },
        { "src/modules/questplanner/quest-controller.lua", "src/modules/questplanner/quest-view.lua" },
        { "src/modules/questplanner/quest-view.lua", "src/modules/questplanner/quest-window-layout.lua" },
        { "src/modules/questplanner/quest-window-layout.lua", "src/modules/questplanner/quest-window.lua" },
        { "src/modules/questplanner/quest-window.lua", "src/modules/questplanner/quest-navigation.lua" },
        { "src/modules/questplanner/quest-navigation.lua", "src/modules/questplanner/quest-transfer-view.lua" },
        { "src/modules/questplanner/quest-transfer-view.lua", "src/modules/questplanner/quest-commands.lua" },
        { "src/modules/questplanner/quest-commands.lua", "src/modules/questplanner/questplanner.lua" },
        { "src/modules/questplanner/quest-schema.lua", "src/modules/questplanner/quest-nav-geometry.lua" },
        { "src/modules/questplanner/quest-nav-geometry.lua", "src/modules/questplanner/quest-nav-search.lua" },
        { "src/modules/questplanner/quest-nav-search.lua", "src/modules/questplanner/quest-navmesh.lua" },
        { "src/modules/questplanner/quest-navmesh.lua", "src/modules/questplanner/quest-terrain.lua" },
        { "src/modules/questplanner/quest-context.lua", "src/modules/questplanner/quest-terrain.lua" },
        { "src/modules/questplanner/quest-controller.lua", "src/modules/questplanner/quest-terrain.lua" },
        { "src/modules/questplanner/quest-terrain.lua", "src/modules/questplanner/quest-navigation.lua" },
        { "src/ui/media.lua", "src/ui/primitives.lua" },
        { "src/ui/primitives.lua", "src/modules/unitframes/unitframes.lua" },
        { "src/ui/unit-colors.lua", "src/modules/unitframes/unitframes-status.lua" },
        { "src/ui/motion.lua", "src/modules/unitframes/unitframes-motion.lua" },
        { "src/ui/motion.lua", "src/modules/nameplates/nameplates-skin.lua" },
        { "src/modules/unitframes/unitframes-status.lua", "src/modules/unitframes/unitframes-motion.lua" },
        { "src/ui/media.lua", "src/ui/skin.lua" },
        { "src/ui/skin.lua", "src/modules/cooldownviewer/cooldownviewer.lua" },
        { "src/platform/hooks.lua", "src/modules/personalresource/personalresource.lua" },
        { "src/ui/skin.lua", "src/modules/personalresource/personalresource.lua" },
        { "src/platform/hooks.lua", "src/modules/cooldownviewer/cooldownviewer.lua" },
        { "src/modules/cooldownviewer/cooldownviewer.lua", "src/modules/cooldownviewer/cooldownviewer-style.lua" },
        { "src/modules/cooldownviewer/cooldownviewer-style.lua", "src/modules/cooldownviewer/cooldownviewer-layout.lua" },
        { "src/modules/cooldownviewer/cooldownviewer-layout.lua", "src/modules/cooldownviewer/cooldownviewer-controls.lua" },
        { "src/platform/editmode.lua", "src/modules/cooldownviewer/cooldownviewer-layout.lua" },
        { "src/layout/layout-drag.lua", "src/modules/cooldownviewer/cooldownviewer-controls.lua" },
        { "src/layout/layout-geometry.lua", "data/layouts.lua" },
        { "data/layouts.lua", "src/layout/layout-audit.lua" },
        { "src/setup/setup.lua", "src/layout/layout.lua" },
        { "src/persistence/codec.lua", "src/persistence/store.lua" },
        { "src/persistence/store.lua", "src/persistence/store-macros.lua" },
        { "src/modules/unitframes/unitframes.lua", "src/modules/auras/auras-units.lua" },
        { "src/modules/auras/auras.lua", "src/modules/nameplates/nameplates.lua" },
        { "src/configuration/wizard/wizard-controls.lua", "src/configuration/wizard/wizard.lua" },
        { "src/configuration/wizard/wizard.lua", "src/configuration/wizard/wizard-preview.lua" },
        { "src/configuration/wizard/wizard-preview.lua", "src/configuration/wizard/wizard-pages.lua" },
        { "src/configuration/options/options-widgets.lua", "src/configuration/options/options-controls.lua" },
        { "src/configuration/options/options-controls.lua", "src/configuration/options/options.lua" },
        { "src/configuration/options/options.lua", "src/configuration/options/options-view.lua" },
        { "src/ui/skin.lua", "src/ui/scroll.lua" },
        { "src/ui/scroll.lua", "src/ui/shell.lua" },
        { "src/ui/shell.lua", "src/modules/cooldownviewer/cooldownviewer-controls.lua" },
    }) do before(edge[1], edge[2]) end

    local owners = {
        RikUI = bootstrap,
        SLASH_RIKUI1 = "src/core/commands.lua",
        BINDING_HEADER_RIKUI = "src/layout/layout-unlock.lua",
        BINDING_NAME_RIKUI_UNLOCK = "src/layout/layout-unlock.lua",
    }
    local values, activeFile = {}, nil
    for _, name in ipairs({
        "assert", "error", "ipairs", "next", "pairs", "pcall", "select", "tonumber", "tostring", "type",
        "unpack", "xpcall", "getmetatable", "setmetatable", "rawget", "rawset", "math", "string", "table", "coroutine", "os",
    }) do values[name] = _G[name] end
    local isolated = setmetatable({}, {
        __index = values,
        __newindex = function(_, name, value)
            if activeFile and owners[name] ~= activeFile then
                error("Unexpected global write in " .. activeFile .. ": " .. tostring(name), 2)
            end
            values[name] = value
        end,
    })
    values._G = isolated
    local support, allowed = {}, { wow_stub = true, aura_stub = true, tooltip_stub = true }
    values.require = function(name)
        assert(allowed[name], "Unexpected stub dependency: " .. tostring(name))
        if support[name] ~= nil then return support[name] end
        local chunk = assert(loadfile("tests/" .. name .. ".lua"))
        support[name] = setfenv(chunk, isolated)()
        return support[name]
    end
    local hostCore, hostSlash = RikUI, SlashCmdList
    local ok, reason = pcall(values.require, "wow_stub")
    check("architecture stub loads in isolation", ok, reason)
    if not ok then return end
    local namespace = {}
    for _, path in ipairs(files) do
        if not chunks[path] then return end
        activeFile = path
        local loaded, failure = pcall(setfenv(chunks[path], isolated), "RikUI", namespace)
        check("TOC load respects namespaces: " .. path, loaded, failure)
        if not loaded then return end
    end
    activeFile = nil
    check("TOC exports one shared addon namespace", type(values.RikUI) == "table" and namespace.Core == values.RikUI)
    check("TOC load preserves host test globals", RikUI == hostCore and SlashCmdList == hostSlash)
end
