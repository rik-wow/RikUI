local loadfile = dofile("tests/load_addon.lua").Loadfile
-- The strip's micro buttons are secure click delegates to the stock buttons, so panel behaviour
-- stays Blizzard's; whether a delegate reaches a parked stock button in combat needs a beta check.
return function(check)
    local env = require("wow_stub")
    local originalCreate = CreateFrame
    local MICRO = { "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton",
        "GuildMicroButton", "HelpMicroButton", "MainMenuMicroButton" }
    local API = { "MicroMenu", "MicroMenuContainer", "BagsBar", "C_Container", "ToggleBackpack", "ToggleBag",
        "KEYRING_CONTAINER", "GetInventoryItemTexture", "EJMicroButton" }
    for _, name in ipairs(MICRO) do API[#API + 1] = name end
    local saved, savedKeyring = {}, C_ActionBar.ShouldShowKeyring
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local stub = {}
    local function region(value)
        function value:CreateAnimationGroup() return require("widget_stub").animationGroup() end
        function value:SetTexture(texture) self.texture = texture end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
        return value
    end
    CreateFrame = function(kind, name, parent, template)
        local frame = originalCreate(kind, name, parent, template)
        function frame:CreateAnimationGroup() return require("widget_stub").animationGroup() end
        local methods = getmetatable(frame).__index
        setmetatable(frame, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        function frame:SetParent(value)
            assert(not InCombatLockdown(), "frame reparented in combat")
            self.parent = value
        end
        function frame:GetParent() return self.parent end
        function frame:SetSize(w, h) self.width, self.height = w, h end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:SetAttribute(key, value)
            assert(not InCombatLockdown(), "attribute written in combat")
            self.attributes[key] = value
        end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return region(texture(self, ...)) end
        function frame:CreateFontString(...) return region(font(self, ...)) end
        return frame
    end
    local function printedContains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function parked(frame) return frame.parent == RikUIHiddenFrames and RikUI.Hide.IsHidden(frame) end
    local function installStock()
        MicroMenuContainer = CreateFrame("Frame", "MicroMenuContainer", UIParent)
        function MicroMenuContainer:Layout() self.laidOut = (self.laidOut or 0) + 1 end
        MicroMenu = CreateFrame("Frame", "MicroMenu", MicroMenuContainer)
        BagsBar = CreateFrame("Frame", "BagsBar", UIParent)
        for _, name in ipairs(MICRO) do CreateFrame("Button", name, MicroMenu).tooltipText = name .. " tip" end
        HelpMicroButton.shown = false
        CreateFrame("Button", "EJMicroButton", UIParent)
        stub.free, stub.bagTextures, stub.toggled, stub.backpack = { [0] = 9, [1] = 4 }, { [31] = 133633 }, {}, 0
        C_Container = {
            GetContainerNumFreeSlots = function(bag)
                if stub.freeError then error(stub.freeError) end
                return stub.free[bag] or 0
            end,
            ContainerIDToInventoryID = function(bag) return 30 + bag end,
        }
        GetInventoryItemTexture = function(_, slot) return stub.bagTextures[slot] end
        ToggleBackpack = function() stub.backpack = stub.backpack + 1 end
        ToggleBag = function(bag) stub.toggled[#stub.toggled + 1] = bag end
        KEYRING_CONTAINER = -2
        C_ActionBar.ShouldShowKeyring = function() return stub.keyring == true end
    end
    -- The unit frame module stays off: only its edge helper is under test here.
    local function load(profile, combat, prepare)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        stub.keyring, stub.freeError = true, nil
        installStock()
        if prepare then prepare() end
        profile = profile or {}
        profile.modules = profile.modules or {}
        profile.modules.unitframes = false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, nil
        for _, file in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/ui/motion.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua",
            "src/modules/unitframes/unitframes.lua", "src/modules/unitframes/unitframes-status.lua", "src/modules/micromenu/micromenu.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.MicroMenu
    end
    local ok, reason = pcall(function()
        local module = load()
        local holder, group = module.Holder, RikUI.Layout.Groups.micromenu
        check("the strip registers with the layout under key micromenu with bottom-right defaults", holder and group
            and group.frames[1] == holder and group.defaults.point == "BOTTOMRIGHT"
            and group.defaults.relativePoint == "BOTTOMRIGHT" and group.defaults.x < 0 and group.defaults.y > 0)
        check("every shown stock micro button gets one strip button and the hidden help button none",
            #module.Buttons == #MICRO - 1)
        check("a defined button that is not a child of the menu gets no strip button",
            RikUIMicroMenuEJMicroButton == nil)
        local first = module.Buttons[1]
        check("a strip button is a 22px secure click delegate to its stock button",
            first.template == "SecureActionButtonTemplate" and first.width == 22 and first.height == 22
            and first.attributes.type == "click" and first.attributes.clickbutton == CharacterMicroButton)
        check("strip buttons carry an icon of their own and the flat border", first.icon.rikIcon == "character"
            and first.icon.texture == RikUI.Media.IconPath("character") and rawget(first, "label") == nil and #first.rikBorder == 4
            and first.rikBorder[1].texture == RikUI.Media.border)
        check("the backpack, four bag slots and the keyring follow the micro buttons", #module.Bags == 6
            and module.Bags[1].bag == 0 and module.Bags[5].bag == 4 and module.Bags[6].bag == -2)
        check("the menu fits the reserved right column instead of stretching into the bars",
            holder.width <= 260 and holder.height <= 70 and holder.height > 22)
        check("an equipped bag shows its icon and free slots", module.Bags[2].icon.texture == 133633
            and module.Bags[2].count.text == "4" and module.Bags[1].count.text == "9")
        check("an empty bag slot shows no icon and no count", rawget(module.Bags[3].icon, "texture") == nil
            and module.Bags[3].count.text == "")
        stub.free[1], stub.bagTextures[32] = 2, 133634
        env.fire("BAG_UPDATE_DELAYED")
        check("a bag update refreshes icons and counts", module.Bags[2].count.text == "2"
            and module.Bags[3].icon.texture == 133634)
        stub.free[1] = env.SECRET
        env.fire("BAG_UPDATE_DELAYED")
        check("a secret free-slot count clears the text without printing", module.Bags[2].count.text == ""
            and #env.printed == 0)
        stub.freeError = "bags unavailable"
        env.fire("BAG_UPDATE_DELAYED")
        env.fire("BAG_UPDATE_DELAYED")
        check("a failing bag read is reported once and contained", printedContains("Micro menu bags")
            and #env.printed == 1)
        stub.freeError = nil

        env.inCombat = true
        env.click(module.Bags[1])
        env.click(module.Bags[3])
        env.click(module.Bags[6])
        env.inCombat = false
        check("bag clicks route to the client's toggles, in combat too", stub.backpack == 1
            and stub.toggled[1] == 2 and stub.toggled[2] == -2)
        env.runScript(first, "OnEnter")
        check("secure micro button hover animates only its cosmetic region", first.rikHover.enter.plays == 1
            and first.attributes.clickbutton == CharacterMicroButton)
        env.runScript(first, "OnLeave")
        check("micro hover fades away", first.rikHover.leave.plays == 1)
        env.runScript(first, "OnEnter")
        check("hovering a strip button shows the stock button's tooltip text", GameTooltip.owner == first
            and GameTooltip.text == "CharacterMicroButton tip")

        check("the stock menu and bag bar are parked once the strip exists with events kept", parked(MicroMenu)
            and parked(BagsBar) and MicroMenuContainer.parent == UIParent)
        RikUI.Profile.showStockBars = true
        module.UpdateStock()
        check("showing stock bars returns both frames and refreshes the menu layout",
            MicroMenu.parent == MicroMenuContainer and BagsBar.parent == UIParent and MicroMenuContainer.laidOut == 1)
        RikUI.Profile.showStockBars = false
        module.UpdateStock()
        check("hiding stock bars parks them again", parked(MicroMenu) and parked(BagsBar))

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports the strip state", printedContains("Micro menu holder=true buttons=6 bags=6"))

        module = load(nil, true)
        check("a combat login builds nothing and parks nothing", module.Holder == nil
            and MicroMenu.parent == MicroMenuContainer and BagsBar.parent == UIParent)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat builds the strip and parks the stock frames", module.Holder ~= nil
            and parked(MicroMenu) and parked(BagsBar))

        module = load(nil, false, function() stub.keyring = false end)
        check("a client without a keyring gets no keyring button", #module.Bags == 5)

        module = load(nil, false, function() TalentMicroButton, BagsBar = nil, nil end)
        check("missing stock frames are skipped", #module.Buttons == #MICRO - 2 and parked(MicroMenu))

        module = load({ showStockBars = true })
        check("a profile that shows stock bars keeps them beside the strip", module.Holder ~= nil
            and MicroMenu.parent == MicroMenuContainer and BagsBar.parent == UIParent)

        module = load({ modules = { micromenu = false } })
        check("a disabled module leaves the stock menu and bag bar untouched", module.Holder == nil
            and MicroMenu.parent == MicroMenuContainer and BagsBar.parent == UIParent
            and RikUI.Layout.Groups.micromenu == nil)
    end)
    CreateFrame = originalCreate
    C_ActionBar.ShouldShowKeyring = savedKeyring
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat = false
    check("micro menu suite completes", ok, reason)
end
