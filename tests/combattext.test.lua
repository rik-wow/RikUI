-- The scrolling text's font object and the engine's damage font global. The global has to respect
-- the module flag, which only exists once the saved variables have arrived.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local API = { "CombatTextFont", "DAMAGE_TEXT_FONT" }
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

        load({ modules = { combattext = false } })
        check("a disabled module leaves the font object and the damage font stock",
            CombatTextFont.font[1] == STOCK and DAMAGE_TEXT_FONT == STOCK)
    end)
    for _, name in ipairs(API) do _G[name] = saved[name] end
    check("combat text suite completes", ok, reason)
end
