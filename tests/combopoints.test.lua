-- Combo points may be secret in combat, so the suite checks that the raw value reaches every pip's
-- StatusBar sink uncompared, and that the row never reads which pip changed.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local API = { "UnitClass", "UnitExists", "UnitCanAttack", "GetComboPoints" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local restore = widgets.install()
    local stub = {}
    local function installClient(class)
        stub.points, stub.target, stub.attackable, stub.error = 0, false, true, nil
        UnitClass = function() return class, class:upper(), 4 end
        UnitExists = function(unit) return unit == "player" or (unit == "target" and stub.target) end
        UnitCanAttack = function() return stub.attackable end
        GetComboPoints = function(unit, target)
            stub.args = { unit, target }
            if stub.error then error(stub.error) end
            return stub.points
        end
    end
    local function load(class, profile, combat, prepare)
        widgets.loadAddon(env, { "src/modules/combopoints/combopoints.lua" }, profile, combat, function()
            installClient(class or "Rogue")
            if prepare then prepare() end
        end)
        return RikUI.ComboPoints
    end
    local function target(exists, attackable)
        stub.target, stub.attackable = exists, attackable ~= false
        env.fire("PLAYER_TARGET_CHANGED")
    end
    local EASE, IMMEDIATE = Enum.StatusBarInterpolation.ExponentialEaseOut, Enum.StatusBarInterpolation.Immediate
    local ok, reason = pcall(function()
        local module = load()
        local holder, group, pips = module.Holder, RikUI.Layout.Groups.combopoints, module.Pips
        check("a rogue gets a row under layout key combopoints between the player and target frames", holder and group
            and group.frames[1] == holder and group.defaults.point == "BOTTOM" and group.defaults.x == 0
            and holder.width == 58 and holder.height == 10)
        check("five flat pips sit in a row with ranges 0-1 to 4-5", #pips == 5 and pips[1].bar.low == 0
            and pips[1].bar.high == 1 and pips[5].bar.low == 4 and pips[5].bar.high == 5
            and pips[2].points[1][4] == 12 and #pips[1].rikBorder == 4
            and pips[1].bar.texture == RikUI.Media.statusbar)
        check("the finishing pip has its own colour", pips[5].bar.color[2] < pips[1].bar.color[2])
        check("the row is hidden without a target", holder.shown == false)

        stub.points = 2
        target(true)
        check("an attackable target shows the row with a fade and an immediate first fill", holder.shown == true
            and module.Fade.plays == 1 and pips[1].bar.value == 2 and pips[5].bar.value == 2
            and pips[3].bar.easing == IMMEDIATE and stub.args[1] == "player" and stub.args[2] == "target")
        stub.points = 3
        env.fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
        check("a combo point event eases every pip to the raw value and flashes the row", pips[1].bar.value == 3
            and pips[4].bar.value == 3 and pips[4].bar.easing == EASE and module.Flash.plays == 1)
        stub.points = 4
        env.fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
        check("another power type refreshes nothing and does not flash", pips[1].bar.value == 3
            and module.Flash.plays == 1)
        env.fire("UNIT_POWER_FREQUENT", "target", "COMBO_POINTS")
        env.fire("UNIT_POWER_FREQUENT", env.SECRET, "COMBO_POINTS")
        check("another unit's or a secret unit's power event is ignored", pips[1].bar.value == 3
            and module.Flash.plays == 1 and #env.printed == 0)

        stub.points = env.SECRET
        env.fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
        check("a secret count reaches every sink without a comparison or a print", pips[1].bar.value == env.SECRET
            and pips[5].bar.value == env.SECRET and #env.printed == 0)
        stub.error = "combo points unavailable"
        env.fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
        env.fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
        check("a failing read is reported once and contained", widgets.printedContains(env, "Combo points read")
            and #env.printed == 1)
        stub.error, stub.points, env.printed = nil, 1, {}

        target(true)
        check("a target swap refills without easing or a second fade", pips[1].bar.value == 1
            and pips[1].bar.easing == IMMEDIATE and module.Fade.plays == 1)
        target(true, false)
        check("a target that cannot be attacked hides the row", holder.shown == false)
        target(true)
        check("the row fades in again with the next attackable target", holder.shown == true
            and module.Fade.plays == 2)
        target(false)
        check("losing the target hides the row", holder.shown == false)
        env.inCombat = true
        target(true)
        env.inCombat = false
        check("the row shows in combat without a protected write", holder.shown == true)
        UnitCanAttack = function() error("attack check unavailable") end
        target(true)
        check("a failing attack check leaves the row showing", holder.shown == true)

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports the row state", widgets.printedContains(env, "Combo points holder=true shown=true"))

        module = load("Druid")
        check("a druid gets the row too", module.Holder ~= nil)
        module = load("Warrior")
        stub.target = true
        env.fire("PLAYER_TARGET_CHANGED")
        check("another class builds nothing and says nothing", module.Holder == nil
            and RikUI.Layout.Groups.combopoints == nil and #env.printed == 0)

        module = load("Rogue", nil, true)
        env.fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
        check("a combat login builds nothing and survives a power event", module.Holder == nil and #env.printed == 0)
        stub.target, stub.points = true, 5
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat builds the row and fills it for the current target", module.Holder ~= nil
            and module.Holder.shown == true and module.Pips[5].bar.value == 5)

        module = load("Rogue", nil, false, function() GetComboPoints = nil end)
        check("a client without GetComboPoints builds nothing and says nothing", module.Holder == nil
            and #env.printed == 0)
        module = load("Rogue", { modules = { combopoints = false } })
        check("a disabled module builds nothing", module.Holder == nil and RikUI.Layout.Groups.combopoints == nil)
    end)
    restore()
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat = false
    check("combo point suite completes", ok, reason)
end
