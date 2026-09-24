local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Tooltip colours and lines are guarded by issecretvalue and the health bar is Blizzard's GUID watch;
-- native rendering of the flat backdrop and the watched bar needs a beta check.
return function(check)
    local env = require("wow_stub")
    local stub = require("tooltip_stub")
    local API = { "UnitHealth", "UnitIsPlayer", "RAID_CLASS_COLORS", "FACTION_BAR_COLORS", "TooltipDataProcessor",
        "GameTooltip_SetDefaultAnchor" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local healthReads = 0
    UnitHealth = function() healthReads = healthReads + 1; return 42 end
    RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
    FACTION_BAR_COLORS = { [2] = { r = 1, g = 0, b = 0 }, [4] = { r = 1, g = 1, b = 0 }, [5] = { r = 0, g = 1, b = 0 } }
    local function printedContains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.00001 end
    local function color(actual, expected)
        return type(actual) == "table" and near(actual[1], expected.r or expected[1])
            and near(actual[2], expected.g or expected[2]) and near(actual[3], expected.b or expected[3])
    end
    local function anchoredTo(tip, frame)
        local p = rawget(tip, "point")
        return type(p) == "table" and p[1] == "BOTTOMRIGHT" and p[2] == frame and p[3] == "BOTTOMRIGHT"
            and near(p[4], 0) and near(p[5], 0)
    end
    local function lastLine(tip) return tip.lines[#tip.lines] end
    local function watched(bar) return rawget(bar, "watched") end
    -- The unit frame module stays off: only its colour helpers are under test here.
    local function load(profile, combat, prepare)
        env.frames, env.printed, env.inCombat, env.hooks, healthReads = {}, {}, false, {}, 0
        stub.install(env)
        if prepare then prepare() end
        profile = profile or {}
        profile.modules = profile.modules or {}
        profile.modules.unitframes = false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, nil
        for _, file in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/ui/motion.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua",
            "src/modules/tooltip/tooltip.lua", "src/modules/tooltip/tooltip-data.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.Tooltip
    end
    local ok, reason = pcall(function()
        local module = load()
        local media, anchor, tip = RikUI.Media, module.Anchor, GameTooltip
        local group = RikUI.Layout.Groups.tooltip
        check("anchor proxy registers with the layout under key tooltip with bottom-right defaults", anchor and group
            and group.frames[1] == anchor and group.defaults.point == "BOTTOMRIGHT"
            and group.defaults.relativePoint == "BOTTOMRIGHT" and group.defaults.x < 0 and group.defaults.y > 0)
        GameTooltip_SetDefaultAnchor(tip, UIParent)
        check("default-anchored tooltips attach to the anchor proxy", anchoredTo(tip, anchor) and tip.owner == UIParent
            and tip.anchorType == "ANCHOR_NONE")
        GameTooltip_SetDefaultAnchor(ItemRefTooltip, UIParent)
        check("other tooltips asking for the default anchor follow too", anchoredTo(ItemRefTooltip, anchor))

        local background, border = rawget(tip, "rikBackground"), rawget(tip, "rikBorder")
        check("the tooltip gets a flat background and four edge lines", background and background.allPoints
            and background.layer == "BACKGROUND" and color(background.color, { 0.055, 0.065, 0.08 })
            and type(border) == "table" and #border == 4 and border[1].texture == media.border)
        check("the NineSlice backdrop is hidden", tip.NineSlice.shown == false)
        SharedTooltip_SetBackdropStyle(tip)
        check("the backdrop stays hidden after Blizzard re-applies its style", tip.NineSlice.shown == false)
        check("item ref and shopping tooltips are skinned too", rawget(ItemRefTooltip, "rikBackground")
            and rawget(ShoppingTooltip1, "rikBackground") and rawget(ShoppingTooltip2, "rikBackground")
            and ShoppingTooltip2.NineSlice.shown == false)
        check("tooltip font objects carry the media font", GameTooltipText.fontPath == media.font
            and GameTooltipText.fontSize == media.sizes.label and GameTooltipHeaderText.fontPath == media.font
            and GameTooltipTextSmall.fontSize == media.sizes.small)

        tip:Hide()
        tip:Show()
        check("tooltips fade on show", tip.rikEntry.plays == 1)
        tip:Hide()
        check("tooltip hiding cancels entry without delaying native hide", not tip.rikEntry:IsPlaying()
            and not tip:IsShown())
        local bar = tip.StatusBar
        stub.setLines(tip, { "Boar", "Level 5 Beast" })
        stub.process("Unit", tip, { guid = "Creature-0-1" })
        check("NPC names are reaction coloured", color(tip.lines[1].color, FACTION_BAR_COLORS[5])
            and tip.lines[2].color[1] == 1 and tip.lines[2].color[2] == 1)
        check("the health bar is watched by guid with our texture and colour", watched(bar) == "Creature-0-1"
            and bar.shown == true and bar.texture == media.statusbar and color(bar.color, FACTION_BAR_COLORS[5])
            and rawget(bar, "lockColor") == true)
        check("the module never reads UnitHealth or writes the bar value", healthReads == 0
            and rawget(bar, "valueWrites") == nil)
        stub.process("Unit", tip, { guid = "Creature-0-1" })
        check("a refresh while the bar is shown does not re-watch", bar.watches == 1)
        tip:Hide()
        check("hiding the tooltip clears the watch", watched(bar) == nil and bar.shown == false)

        stub.guilds.player = "Rik Guild"
        stub.setLines(tip, { "Probey", "Rik Guild", "Level 12 Warrior" })
        stub.process("Unit", tip, { guid = "Player-1" })
        check("player names are class coloured", color(tip.lines[1].color, RAID_CLASS_COLORS.WARRIOR)
            and color(bar.color, RAID_CLASS_COLORS.WARRIOR))
        check("the guild line is tinted", tip.lines[2].color[3] > tip.lines[2].color[1]
            and tip.lines[3].color[1] == 1)
        tip:Hide()
        stub.guilds.player = nil
        stub.setLines(tip, { "Probey", "Level 12 Warrior" })
        stub.process("Unit", tip, { guid = "Player-1" })
        check("without a guild the second line keeps its colour", tip.lines[2].color[1] == 1
            and tip.lines[2].color[3] == 1)
        tip:Hide()

        stub.guids["Creature-0-9"] = env.SECRET
        env.printed = {}
        stub.setLines(tip, { "Hidden", "Level ?? Beast" })
        stub.process("Unit", tip, { guid = "Creature-0-9" })
        check("a secret unit token skips colouring, still watches and prints nothing", tip.lines[1].color[1] == 1
            and watched(bar) == "Creature-0-9" and #env.printed == 0)
        tip:Hide()
        stub.setLines(tip, { "Nobody" })
        stub.process("Unit", tip, {})
        check("a unit without a guid leaves the bar alone", watched(bar) == nil and #env.printed == 0)

        stub.itemLevels["item:6948"] = 23
        stub.setLines(tip, { "Hearthstone" })
        stub.process("Item", tip, { id = 6948, hyperlink = "item:6948" })
        check("item tooltips end with the item level", lastLine(tip).text == "Item level 23" and #tip.lines == 2)
        stub.itemLevels[6948] = 23
        stub.setLines(tip, { "Hearthstone" })
        stub.process("Item", tip, { id = 6948 })
        check("an item id works when there is no hyperlink", lastLine(tip).text == "Item level 23")
        stub.itemLevels["item:1"] = env.SECRET
        stub.setLines(tip, { "Secret item" })
        stub.process("Item", tip, { id = 1, hyperlink = "item:1" })
        check("a secret item level adds no line", #tip.lines == 1)
        stub.setLines(tip, { "Unknown item" })
        stub.process("Item", tip, { id = 2, hyperlink = "item:2" })
        check("a missing item level adds no line", #tip.lines == 1)

        local oldCount = C_Item.GetItemCount
        C_Item.GetItemCount = function(_, bank) return bank and 12 or 3 end
        stub.setLines(tip, { "Owned item" })
        stub.process("Item", tip, { id = 2 })
        check("ownership separates carried and bank counts", lastLine(tip).text == "Carried/equipped: 3  Bank: 9")
        stub.process("Item", tip, { id = 2 })
        check("reprocessing does not duplicate ownership", #tip.lines == 2)
        RikUI.Profile.tooltip.ownedCounts = false
        stub.setLines(tip, { "Owned item" })
        stub.process("Item", tip, { id = 2 })
        check("ownership setting suppresses counts", #tip.lines == 1)
        RikUI.Profile.tooltip.ownedCounts = true
        C_Item.GetItemCount = function() return env.SECRET end
        stub.process("Item", tip, { id = 2 })
        check("secret counts do not add a line", #tip.lines == 1)
        C_Item.GetItemCount = oldCount

        stub.setLines(tip, { "Fireball" })
        stub.process("Spell", tip, { id = 133 })
        check("spell tooltips end with the spell id", lastLine(tip).text == "Spell ID 133" and #tip.lines == 2)
        stub.setLines(tip, { "Secret spell" })
        stub.process("Spell", tip, { id = env.SECRET })
        check("a secret spell id adds no line", #tip.lines == 1)

        C_Item.GetDetailedItemLevelInfo = function() error("item level unavailable") end
        env.printed = {}
        stub.setLines(tip, { "Broken" })
        stub.process("Item", tip, { id = 3, hyperlink = "item:3" })
        stub.process("Item", tip, { id = 3, hyperlink = "item:3" })
        check("a failing item read is reported once and contained", printedContains("Tooltip item level")
            and #env.printed == 1 and #tip.lines == 1)

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports the tooltip state and samples", printedContains("Tooltip anchor=true")
            and printedContains("tooltip.UnitTokenFromGUID(player)")
            and printedContains("tooltip.GetDetailedItemLevelInfo(6948)"))

        module = load({ tooltip = { hideInCombat = true } }, true)
        tip = GameTooltip
        check("combat login still installs the anchor and hooks", module.Anchor ~= nil and #env.hooks == 2)
        stub.setLines(tip, { "Boar" })
        stub.process("Unit", tip, { guid = "Creature-0-1" })
        check("hideInCombat hides unit tooltips in combat", tip.shown == false and watched(tip.StatusBar) == nil)
        env.inCombat = false
        stub.setLines(tip, { "Boar" })
        stub.process("Unit", tip, { guid = "Creature-0-1" })
        check("hideInCombat leaves tooltips alone out of combat", tip.shown == true)
        local setting = module.Options.settings[1]
        check("the option page exposes hideInCombat", module.Options.title == "Tooltips" and setting.key == "hideInCombat"
            and setting.type == "checkbox" and setting.get() == true)
        setting.set(false)
        check("the option writes the profile", RikUI.Profile.tooltip.hideInCombat == false and setting.get() == false)

        module = load(nil, true)
        tip = GameTooltip
        env.inCombat = true
        stub.setLines(tip, { "Boar" })
        stub.process("Unit", tip, { guid = "Creature-0-1" })
        check("hideInCombat defaults to off", RikUI.Profile.tooltip.hideInCombat == false and tip.shown == true)
        env.inCombat = false

        module = load(nil, false, function() TooltipDataProcessor = nil end)
        check("a missing data processor prints one line and keeps the anchor", printedContains("Tooltip data processor")
            and #env.printed == 1 and module.Anchor ~= nil)
        GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
        check("the anchor hook works without the processor", anchoredTo(GameTooltip, module.Anchor))

        module = load(nil, false, function() GameTooltip_SetDefaultAnchor = nil end)
        check("a missing anchor function prints one line and keeps the skin", printedContains("GameTooltip_SetDefaultAnchor")
            and #env.printed == 1 and rawget(GameTooltip, "rikBackground") ~= nil)

        module = load(nil, false, function()
            EmbeddedItemTooltip, QuickKeybindTooltip = stub.tooltip("EmbeddedItemTooltip"), nil
        end)
        check("a secondary tooltip gets the same flat background, edge and hidden backdrop",
            rawget(EmbeddedItemTooltip, "rikBackground") ~= nil and #EmbeddedItemTooltip.rikBorder == 4
            and EmbeddedItemTooltip.NineSlice.shown == false)
        QuickKeybindTooltip = stub.tooltip("QuickKeybindTooltip")
        env.fire("ADDON_LOADED", "Blizzard_QuickKeybind")
        check("a tooltip that arrives with a later add-on is skinned when that add-on loads",
            rawget(QuickKeybindTooltip, "rikBackground") ~= nil and QuickKeybindTooltip.NineSlice.shown == false
            and #env.printed == 0)
        EmbeddedItemTooltip, QuickKeybindTooltip = nil, nil

        module = load({ modules = { tooltip = false } })
        check("a disabled module leaves the tooltips untouched", module.Anchor == nil
            and rawget(GameTooltip, "rikBackground") == nil and GameTooltip.NineSlice.shown == true
            and GameTooltipText.fontPath == nil and #env.hooks == 0 and next(stub.postCalls) == nil)
        GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
        check("a disabled module keeps the Blizzard anchor", anchoredTo(GameTooltip, GameTooltipDefaultContainer))
    end)
    for name, value in pairs(saved) do _G[name] = value end
    env.inCombat = false
    check("tooltip suite completes", ok, reason)
end
