-- GetTotemInfo with readable, secret and failing answers. Whether 69913 hands out secrets here is
-- unverified, so the suite pins both routes: readable values decide presence, secret values go
-- straight to the widgets, and neither raises.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local API = { "GetTotemInfo", "MAX_TOTEMS" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local savedSetTotem = GameTooltip.SetTotem
    local restore = widgets.install()
    local stub = {}
    local FIRE, EARTH, WATER = 1, 2, 3
    local function installClient()
        stub.totems, stub.error, stub.tooltipSlot = {}, nil, nil
        MAX_TOTEMS = 4
        GetTotemInfo = function(slot)
            if stub.error then error(stub.error) end
            local totem = stub.totems[slot]
            if not totem then return false, "", 0, 0, nil end
            return totem.have, totem.name, totem.start, totem.duration, totem.icon
        end
        function GameTooltip:SetTotem(slot) stub.tooltipSlot = slot end
    end
    local function load(profile, combat, prepare)
        widgets.loadAddon(env, { "skin.lua", "totems.lua" }, profile, combat, function()
            installClient()
            if prepare then prepare() end
        end)
        return RikUI.Totems
    end
    local function place(slot, totem)
        stub.totems[slot] = totem
        env.fire("PLAYER_TOTEM_UPDATE", slot)
    end
    local function recordCooldowns(module)
        for _, button in ipairs(module.Slots) do
            function button.cooldown:SetCooldown(start, duration) self.start, self.duration = start, duration end
            function button.cooldown:Clear() self.start, self.duration = nil, nil end
        end
    end
    local ok, reason = pcall(function()
        local module = load()
        recordCooldowns(module)
        local holder, group = module.Holder, RikUI.Layout.Groups.totems
        check("the row registers with the layout under key totems", holder and group and group.frames[1] == holder
            and group.defaults.point == "BOTTOM")
        check("four flat slots exist and none shows without a totem", #module.Slots == 4
            and #module.Slots[1].rikBorder == 4 and module.Slots[1].shown == false and module.Slots[4].shown == false)

        place(FIRE, { have = true, name = "Searing Totem", start = 100, duration = 55, icon = 135825 })
        local fire = module.Slots[FIRE]
        check("a placed totem shows its cropped icon with a sweep from the client's start and duration",
            fire.shown == true and fire.icon.texture == 135825 and fire.icon.coords[1] > 0
            and fire.cooldown.start == 100 and fire.cooldown.duration == 55)
        check("the slot fades in and the others stay hidden", fire.fade.plays == 1 and module.Slots[EARTH].shown == false)
        env.fire("PLAYER_TOTEM_UPDATE", FIRE)
        check("an update for a totem that is already up does not fade in again", fire.fade.plays == 1)
        place(EARTH, { have = true, name = "Stoneskin Totem", start = 110, duration = 120, icon = 136098 })
        check("shown slots pack from the left in slot order", fire.points[1][4] == 0
            and module.Slots[EARTH].points[1][4] > 0)
        place(FIRE, nil)
        check("a removed totem hides, clears its sweep and the rest repack", fire.shown == false
            and fire.cooldown.duration == nil and module.Slots[EARTH].points[1][4] == 0)
        place(WATER, { have = true, name = "Expired", start = 0, duration = 0, icon = 1 })
        check("a totem with no duration counts as gone", module.Slots[WATER].shown == false)

        env.runScript(module.Slots[EARTH], "OnEnter")
        check("hovering a slot asks the tooltip for that totem", stub.tooltipSlot == EARTH)
        check("slots take no clicks", module.Slots[EARTH]:GetScript("OnClick") == nil)

        place(FIRE, { have = env.SECRET, name = env.SECRET, start = env.SECRET, duration = env.SECRET,
            icon = env.SECRET })
        check("secret values go straight to the widgets and the slot shows", fire.shown == true
            and fire.icon.texture == env.SECRET and fire.cooldown.duration == env.SECRET and #env.printed == 0)
        stub.error = "totem read refused"
        env.fire("PLAYER_TOTEM_UPDATE", FIRE)
        check("a failing read hides every slot and is reported once", fire.shown == false
            and module.Slots[EARTH].shown == false and widgets.printedContains(env, "Totems read") and #env.printed == 1)
        stub.error = nil
        env.inCombat = true
        env.fire("PLAYER_TOTEM_UPDATE", EARTH)
        env.inCombat = false
        check("totems appear in combat without a protected write", module.Slots[EARTH].shown == true
            and #env.printed == 1)
        SlashCmdList.RIKUI("debug")
        check("debug reports the row", widgets.printedContains(env, "Totems holder=true shown=2"))

        module = load(nil, true)
        check("a combat login builds nothing yet", module.Holder == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("the row is built when combat ends", module.Holder ~= nil and #module.Slots == 4)

        module = load(nil, false, function() GetTotemInfo = nil end)
        check("a client without totems builds nothing", module.Holder == nil and #env.printed == 0)

        module = load({ modules = { totems = false } })
        check("a disabled module builds nothing", module.Holder == nil and RikUI.Layout.Groups.totems == nil)
    end)
    restore()
    for _, name in ipairs(API) do _G[name] = saved[name] end
    GameTooltip.SetTotem = savedSetTotem
    env.inCombat = false
    check("totem suite completes", ok, reason)
end
