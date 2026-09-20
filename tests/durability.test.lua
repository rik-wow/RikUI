-- The alert status is inventory state and readable; the suite still checks a failing read is
-- contained, and that the item durability behind the tooltip percent may be missing.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local API = { "GetInventoryAlertStatus", "GetInventoryItemDurability", "DurabilityFrame", "C_GameRules" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local savedRule = Enum.GameRule
    local restore = widgets.install()
    local stub = {}
    local HEAD, CHEST, WEAPON = 1, 3, 9
    local function installClient()
        stub.status, stub.durability, stub.error, stub.repairDisabled = {}, {}, nil, false
        DurabilityFrame = CreateFrame("Frame", "DurabilityFrame", UIParent)
        GetInventoryAlertStatus = function(index)
            if stub.error then error(stub.error) end
            return stub.status[index] or 0
        end
        GetInventoryItemDurability = function(slot)
            local value = stub.durability[slot]
            if value then return value[1], value[2] end
        end
        Enum.GameRule = { RepairArmorDisabled = 7 }
        C_GameRules = { IsGameRuleActive = function(rule) return rule == 7 and stub.repairDisabled end }
    end
    local function load(profile, combat, prepare)
        widgets.loadAddon(env, { "durability.lua" }, profile, combat, function()
            installClient()
            if prepare then prepare() end
        end)
        return RikUI.Durability
    end
    local function alerts(status)
        stub.status = status
        env.fire("UPDATE_INVENTORY_ALERTS")
    end
    local function tooltipContains(text)
        if tostring(GameTooltip.text):find(text, 1, true) then return true end
        for _, line in ipairs(GameTooltip.lines) do
            if tostring(line.text):find(text, 1, true) then return true end
        end
        return false
    end
    local function hover(frame)
        GameTooltip.lines, GameTooltip.text = {}, nil
        env.runScript(frame, "OnEnter")
    end
    local function parked(frame) return frame.parent == RikUIHiddenFrames and RikUI.Hide.IsHidden(frame) end
    local ok, reason = pcall(function()
        local module = load()
        local pill, group = module.Pill, RikUI.Layout.Groups.durability
        check("the pill registers with the layout under key durability at the top of the screen", pill and group
            and group.frames[1] == pill and group.defaults.point == "TOP")
        check("undamaged gear shows nothing", pill.shown == false)
        check("the pill is flat with the RikUI font", #pill.rikBorder == 4 and pill.label.fontPath == RikUI.Media.font)

        alerts({ [HEAD] = 1, [CHEST] = 1 })
        check("worn gear shows a yellow pill with the count and a fade", pill.shown == true
            and pill.label.text == "2 worn" and pill.label.textColor[2] > 0.5 and pill.label.textColor[3] < 0.5
            and module.Fade.plays == 1 and not module.Pulse.playing)
        stub.durability[1], stub.durability[5] = { 12, 60 }, { 5, 100 }
        hover(pill)
        check("hovering lists each worn slot with its percent", GameTooltip.owner == pill
            and tooltipContains("Durability") and tooltipContains("Head") and tooltipContains("20%")
            and tooltipContains("Chest") and tooltipContains("5%") and not tooltipContains("Legs"))

        alerts({ [HEAD] = 1, [CHEST] = 1, [WEAPON] = 2 })
        check("a broken piece turns the pill red, counts it first and pulses", pill.label.text == "1 broken, 2 worn"
            and pill.label.textColor[2] < 0.5 and module.Pulse.playing == true and module.Fade.plays == 1)
        alerts({ [HEAD] = 1, [CHEST] = 1, [WEAPON] = 2 })
        check("a repeated alert does not restart the pulse", module.Pulse.plays == 1)
        hover(pill)
        check("a slot without a readable durability is listed without a percent", tooltipContains("Main hand")
            and tooltipContains("broken"))
        stub.durability[16] = { env.SECRET, env.SECRET }
        hover(pill)
        check("a secret durability leaves the percent out without an error", tooltipContains("Main hand")
            and #env.printed == 0)
        env.runScript(pill, "OnLeave")

        alerts({})
        check("repaired gear hides the pill and stops the pulse", pill.shown == false and not module.Pulse.playing)
        alerts({ [HEAD] = 1 })
        check("the next alert fades the pill in again", pill.shown == true and module.Fade.plays == 2
            and pill.label.text == "1 worn")

        stub.repairDisabled = true
        env.fire("UPDATE_INVENTORY_ALERTS")
        check("a game mode without repairs hides the pill", pill.shown == false)
        stub.repairDisabled = false

        stub.error = "alert status unavailable"
        env.fire("UPDATE_INVENTORY_ALERTS")
        env.fire("UPDATE_INVENTORY_ALERTS")
        check("a failing status read is reported once and hides the pill",
            widgets.printedContains(env, "Durability status") and #env.printed == 1 and pill.shown == false)
        stub.error, env.printed = nil, {}

        check("the stock figure is parked once the pill exists", parked(DurabilityFrame))
        SlashCmdList.RIKUI("debug")
        check("debug reports the pill state", widgets.printedContains(env, "Durability pill=true worn=0 broken=0"))

        module = load(nil, false, function() stub.pending = true end)
        stub.status = { [CHEST] = 2 }
        env.fire("PLAYER_ENTERING_WORLD")
        check("entering the world picks up existing damage", module.Pill.shown == true
            and module.Pill.label.text == "1 broken")

        module = load(nil, true)
        env.fire("UPDATE_INVENTORY_ALERTS")
        check("a combat login builds nothing, parks nothing and survives an alert", module.Pill == nil
            and DurabilityFrame.parent == UIParent and #env.printed == 0)
        stub.status = { [HEAD] = 1 }
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat builds the pill with the current damage and parks the stock figure",
            module.Pill ~= nil and module.Pill.shown == true and parked(DurabilityFrame))

        module = load(nil, false, function() GetInventoryAlertStatus, DurabilityFrame = nil, nil end)
        check("a client without the alert status builds nothing and says nothing", module.Pill == nil
            and #env.printed == 0)
        module = load(nil, false, function() C_GameRules, Enum.GameRule = nil, nil end)
        alerts({ [HEAD] = 1 })
        check("a client without game rules still shows the pill", module.Pill.shown == true)

        module = load({ modules = { durability = false } })
        check("a disabled module leaves the stock figure untouched", module.Pill == nil
            and DurabilityFrame.parent == UIParent and RikUI.Layout.Groups.durability == nil)
    end)
    restore()
    for _, name in ipairs(API) do _G[name] = saved[name] end
    Enum.GameRule = savedRule
    env.inCombat = false
    check("durability suite completes", ok, reason)
end
