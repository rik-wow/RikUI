-- Exercise the real native-container integration with hostile aura APIs.
return function(check)
    local loader = dofile("tests/load_addon.lua").Loadfile
    local env = require("wow_stub")
    local savedClass, savedAuras, savedCore = UnitClass, C_UnitAuras, RikUI
    local savedCreate = CreateFrame
    CreateFrame = function(...)
        local frame = savedCreate(...)
        function frame:GetFrameLevel() return 1 end
        return frame
    end
    local reads = 0
    C_UnitAuras = setmetatable({}, { __index = function()
        return function() reads = reads + 1; error("secret aura access") end
    end })
    local function load(profile, combat, missing, invalid, class)
        env.frames, env.printed, env.timers, env.inCombat = {}, {}, {}, false
        env.auraContainerMissing = missing == true
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile or { modules = { auras = false } } } }, nil
        UnitClass = function() return class or "Warrior", class or "WARRIOR" end
        for _, path in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/platform/hide.lua",
            "src/ui/media.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua",
            "src/layout/layout.lua", "src/modules/auras/auras.lua", "src/modules/auras/auras-button.lua" }) do
            assert(loader(path))("RikUI", {})
        end
        RikUI.Spells = { Entry = function(name, class)
            if class == "WARRIOR" and name == "Battle Shout" then return { ranks = { 6673, 5242 } } end
            if class == "WARRIOR" and name == "Rend" then return { ranks = { 772, 6546 } } end
        end }
        RikUI.ClassAuraProfiles = { WARRIOR = { player = { invalid and "Unknown" or "Battle Shout" },
            harmful = { "Rend" }, helpful = { "Battle Shout" }, enchants = true } }
        assert(loader("src/modules/auras/auras-class.lua"))("RikUI", {})
        if class then
            for _, path in ipairs(dofile("tests/load_addon.lua").Manifest()) do
                if path == "data/spells.lua" or path:match("^data/spells%-")
                    or path:match("^data/class%-auras%-") then assert(loader(path))("RikUI", {}) end
            end
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.ClassAuras
    end
    local cases = {
        { class = "ROGUE", player = { 5171, 6774, 5277 }, harmful = { 1943, 11275, 8647 }, helpful = {  }, excluded = { 1752 }, enchants = true },
        { class = "WARRIOR", player = { 6673, 25289, 2565 }, harmful = { 772, 7386 }, helpful = {  }, excluded = { 78 }, enchants = false },
        { class = "HUNTER", player = { 3045 }, harmful = { 1130, 1978, 5116 }, helpful = {  }, excluded = { 75 }, enchants = false },
        { class = "PALADIN", player = { 25780, 642 }, harmful = { 853 }, helpful = { 1044, 19740 }, excluded = { 20271 }, enchants = false },
        { class = "SHAMAN", player = { 324, 2645 }, harmful = { 8050, 8056 }, helpful = { 546, 131 }, excluded = { 403 }, enchants = true },
        -- Additional verified class fixtures.
    }
    local function verifyProfile(sample)
        local module = load(nil, false, false, false, sample.class)
        check(sample.class .. " creates class buff and effect rows", module.Rows.player and module.Rows.target)
        local profile = RikUI.ClassAuraProfiles[sample.class]
        check(sample.class .. " profile loads from the manifest", profile ~= nil)
        for _, key in ipairs({ "player", "harmful", "helpful" }) do
            local row = module.Rows[key == "player" and "player" or "target"]
            local group = row and row.container.groups[key]
            for _, id in ipairs(sample[key]) do
                check(sample.class .. " tracks direct " .. key .. " effect " .. id,
                    group and group.options.candidateFilters.includeSpellIDs[id] == true)
            end
            for _, name in ipairs(profile and profile[key] or {}) do
                local entry = RikUI.Spells.Entry(name, sample.class)
                check(sample.class .. " family resolves " .. name, entry ~= nil)
                for _, id in ipairs(entry and entry.ranks or {}) do
                    check(sample.class .. " preserves rank " .. id, group and group.options.candidateFilters.includeSpellIDs[id] == true)
                end
            end
            for _, id in ipairs(sample.excluded) do
                check(sample.class .. " excludes direct damage " .. id .. " from " .. key,
                    not group or not group.options.candidateFilters.includeSpellIDs[id])
            end
        end
        local native = module.Rows.player and module.Rows.player.container.enchants
        check(sample.class .. " weapon-enchant ownership is explicit", native
            and (native[0] ~= nil) == sample.enchants and (native[1] ~= nil) == sample.enchants)
    end
    local ok, reason = pcall(function()
        for _, sample in ipairs(cases) do verifyProfile(sample) end
        local module = load()
        local player, target = module.Rows.player, module.Rows.target
        check("class tracker creates independent movable native rows", player and target
            and player.container.unit == "player" and target.container.unit == "target"
            and RikUI.Layout.Groups.classbuffs and RikUI.Layout.Groups.classeffects)
        local buffs = player and player.container.groups.player
        local harms = target and target.container.groups.harmful
        local helps = target and target.container.groups.helpful
        check("class filters include every rank and isolate harmful own target effects", buffs
            and buffs.options.candidateFilters.includeSpellIDs[6673]
            and buffs.options.candidateFilters.includeSpellIDs[5242]
            and not buffs.options.candidateFilters.includeSpellIDs[772]
            and harms.filter == "HARMFUL|PLAYER" and helps.filter == "HELPFUL|PLAYER"
            and harms.options.maxFrameCount == 6 and helps.options.maxFrameCount == 6)
        check("class tracker delegates enchant timing to native slots", player
            and player.container.enchants[0] and player.container.enchants[1]
            and not player.container.enchants[2])
        local button = buffs and buffs.frames[1]
        check("class aura buttons preserve native countdown and stack bindings without cancel", button
            and button.registered.cooldown and button.registered.count and not rawget(button, "cancelButtons"), table.concat(env.printed, " | "))
        local before = target.container.updates
        env.fire("PLAYER_TARGET_CHANGED")
        check("target swap refreshes class effects", target.container.updates == before + 1)
        before = target.container.updates
        env.fire("PLAYER_ENTERING_WORLD")
        check("world changes refresh class effects", target.container.updates == before + 1)
        check("class tracker never reads secret aura data", reads == 0)
        local rowCount = 0
        for _ in pairs(module.Rows) do rowCount = rowCount + 1 end
        env.fire("PLAYER_LOGIN")
        check("duplicate enable does not build duplicate rows", rowCount == 2 and module.Rows.player == player)
        module = load(nil, true)
        check("combat login defers class containers", next(module.Rows) == nil)
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat creates class rows", module.Rows.player and module.Rows.target)
        module = load({ modules = { classauras = false, auras = false } })
        check("disabled class tracker creates no rows", next(module.Rows) == nil)
        module = load(nil, false, true)
        check("missing native templates create no visible substitute", next(module.Rows) == nil)
        module = load(nil, false, false, true)
        check("unknown family fails closed without showing all player auras", module.Rows.player == nil
            and module.Rows.target ~= nil)
        module = load()
        local container = module.Rows.target.container
        container.UpdateAllAuras = function() error("restricted") end
        env.fire("PLAYER_TARGET_CHANGED"); env.fire("PLAYER_TARGET_CHANGED")
        local reports = 0
        for _, line in ipairs(env.printed) do if line:find("Class auras refresh", 1, true) then reports = reports + 1 end end
        check("refused class refresh is diagnosed once", reports == 1)
    end)
    UnitClass, C_UnitAuras, RikUI, CreateFrame = savedClass, savedAuras, savedCore, savedCreate
    env.auraContainerMissing, env.inCombat = false, false
    check("class aura integration suite completes", ok, reason)
end

