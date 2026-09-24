-- The scrolling text's font object and the engine's damage font global. The global has to respect
-- the module flag, which only exists once the saved variables have arrived.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local API = { "CombatTextFont", "DAMAGE_TEXT_FONT", "C_CVar", "CombatText_LoadUI", "UpdateFloatingCombatTextSafe" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local STOCK = "Fonts\\FRIZQT__.TTF"
    local function fontObject(size)
        local object = { font = { STOCK, size, "" } }
        function object:GetFont() return unpack(self.font) end
        function object:SetFont(path, height, flags)
            if self.refuse then return false end
            self.font = { path, height, flags }
            return true
        end
        return object
    end
    local function load(profile, prepare)
        widgets.loadAddon(env, { "src/modules/combattext/combattext.lua" }, profile, false, function()
            CombatTextFont, DAMAGE_TEXT_FONT = fontObject(25), STOCK
            if prepare then prepare() end
        end)
        return RikUI.CombatText
    end
    local ok, reason = pcall(function()
        load()
        check("the scrolling text font object takes the RikUI font at Blizzard's size with an outline",
            CombatTextFont.font[1] == RikUI.Media.font and CombatTextFont.font[2] == 25
            and CombatTextFont.font[3] == "OUTLINE")
        check("the engine's damage font points at the RikUI font", DAMAGE_TEXT_FONT == RikUI.Media.font)
        check("a clean run prints nothing", #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports both writes", widgets.printedContains(env, "Combat text font=true damage=true"))

        load(nil, function() CombatTextFont = nil end)
        check("a client without the font object still sets the damage font and says nothing",
            DAMAGE_TEXT_FONT == RikUI.Media.font and #env.printed == 0)

        load(nil, function() CombatTextFont.font[2] = 0 end)
        check("a font object that reports no size gets the fallback size", CombatTextFont.font[2] == 25)

        load(nil, function() CombatTextFont.refuse = true end)
        check("a refused font is reported once", widgets.printedContains(env, "Combat text font") and #env.printed == 1)

        load({ font = "game" })
        check("profile font binds before early native damage consumers", DAMAGE_TEXT_FONT == (STANDARD_TEXT_FONT or STOCK)
            and CombatTextFont.font[1] == DAMAGE_TEXT_FONT)

        local values = { enableFloatingCombatText = "0", floatingCombatTextFloatMode_v2 = "1", classicStyleWorldText = "0" }
        local writes, loads, refreshes = 0, 0, 0
        C_CVar = {
            GetCVar = function(name) return values[name] end,
            SetCVar = function(name, value) writes = writes + 1; values[name] = value; return true end,
        }
        CombatText_LoadUI = function() loads = loads + 1 end
        UpdateFloatingCombatTextSafe = function() refreshes = refreshes + 1 end
        local module = load()
        check("combat text startup leaves client preferences alone", writes == 0)
        local settings = module.Options and module.Options.settings
        check("native combat text controls exist", settings and #settings == 2)
        if settings then
            local enabled, flow = settings[1], settings[2]
            enabled.set(true)
            check("native text enable loads the renderer", values.enableFloatingCombatText == "1" and loads == 1)
            flow.set(3)
            check("native arc flow updates displayed text", values.floatingCombatTextFloatMode_v2 == "3" and refreshes == 2)
            env.inCombat = true
            flow.set(1); flow.set(2)
            check("combat flow writes wait", writes == 2)
            env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
            check("combat flow requests coalesce", writes == 3 and values.floatingCombatTextFloatMode_v2 == "2")
            values.classicStyleWorldText = "1"
            check("classic world text disables unsupported flow", flow.disabled())
            flow.set(3)
            check("unsupported flow cannot write", writes == 3)
            values.classicStyleWorldText = "0"
            flow.set(99)
            check("invalid flow cannot write", writes == 3)
            values.floatingCombatTextFloatMode_v2 = nil
            check("missing flow CVar disables control", flow.disabled())
            C_CVar.SetCVar = function() error("rejected native write") end
            local safe = pcall(enabled.set, false)
            check("native write failure is contained", safe and values.enableFloatingCombatText == "1")
        end

        load({ modules = { combattext = false } })
        check("a disabled module leaves the font object and the damage font stock",
            CombatTextFont.font[1] == STOCK and DAMAGE_TEXT_FONT == STOCK)
    end)
    for _, name in ipairs(API) do _G[name] = saved[name] end
    check("combat text suite completes", ok, reason)
end
