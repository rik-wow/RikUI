local loadfile = dofile("tests/load_addon.lua").Loadfile
-- The skinner only ever sees the chrome keys the Mainline window templates share, so the suite
-- fakes those keys. What the real windows look like, and whether Blizzard resets any stripped
-- alpha, needs a beta check.
return function(check)
    local env = require("wow_stub")
    local restoreCreate = require("widget_stub").install()
    local WINDOWS = { "CharacterFrame", "PlayerSpellsFrame", "WorldMapFrame", "MerchantFrame", "BankFrame",
        "MailFrame", "OpenMailFrame", "TradeFrame", "QuestFrame", "GossipFrame", "ClassTrainerFrame",
        "AuctionHouseFrame", "ChatConfigFrame", "TaxiFrame", "LFGParentFrame", "LFGParentFrameCloseButton",
        "DeathRecapFrame", "CalendarFrame", "BattlefieldMapFrame", "PetStableFrame" }
    local API = { "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab", "PanelTemplates_GetSelectedTab" }
    for _, name in ipairs(WINDOWS) do API[#API + 1] = name end
    local TAB_ART = { "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
        "LeftHighlight", "MiddleHighlight", "RightHighlight" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local stub = {}
    local function printedContains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function makeTab(parent, id)
        local tab = CreateFrame("Button", nil, parent)
        for _, key in ipairs(TAB_ART) do tab[key] = tab:CreateTexture() end
        tab.Text = tab:CreateFontString()
        function tab:GetID() return id end
        return tab
    end
    local function makeCloseButton(parent)
        local button = CreateFrame("Button", nil, parent)
        button.normal, button.pushed = button:CreateTexture(), button:CreateTexture()
        function button:GetNormalTexture() return self.normal end
        function button:GetPushedTexture() return self.pushed end
        button:SetScript("OnClick", function() stub.closed = stub.closed + 1 end)
        return button
    end
    local function addChrome(chrome)
        chrome.NineSlice = CreateFrame("Frame", nil, chrome)
        chrome.Bg, chrome.TopTileStreaks = chrome:CreateTexture(), chrome:CreateTexture()
        chrome.PortraitContainer = CreateFrame("Frame", nil, chrome)
        chrome.TitleContainer = CreateFrame("Frame", nil, chrome)
        chrome.TitleContainer.TitleText = chrome.TitleContainer:CreateFontString()
        chrome.CloseButton = makeCloseButton(chrome)
    end
    local function makeWindow(name, chromeKey)
        local frame = CreateFrame("Frame", name, UIParent)
        frame.shown = false
        local chrome = frame
        if chromeKey then
            chrome = CreateFrame("Frame", nil, frame)
            frame[chromeKey] = chrome
        end
        addChrome(chrome)
        frame.Inset = CreateFrame("Frame", nil, frame)
        frame.Inset.NineSlice, frame.Inset.Bg = CreateFrame("Frame", nil, frame.Inset), frame.Inset:CreateTexture()
        return frame
    end
    local function installClient()
        stub.closed = 0
        for _, name in ipairs(WINDOWS) do _G[name] = nil end
        PanelTemplates_SelectTab = function(tab) tab.selected = true end
        PanelTemplates_DeselectTab = function(tab) tab.selected = false end
        PanelTemplates_GetSelectedTab = function(frame) return frame.selectedTab end
        makeWindow("CharacterFrame")
        makeWindow("WorldMapFrame", "BorderFrame")
        makeWindow("BankFrame")
        local merchant = makeWindow("MerchantFrame")
        merchant.Tabs = { makeTab(merchant, 1), makeTab(merchant, 2) }
        merchant.selectedTab = 1
    end
    local function loadSpells()
        local frame = makeWindow("PlayerSpellsFrame")
        frame.TabSystem = { tabs = { makeTab(frame, 1), makeTab(frame, 2) } }
        for _, tab in ipairs(frame.TabSystem.tabs) do
            -- TabSystemButtonArtMixin: the selected tab is disabled, the others enabled.
            function tab:SetTabSelected(selected)
                self.selected, self.isSelected = selected, selected
                env.runScript(self, selected and "OnDisable" or "OnEnable")
            end
        end
        env.fire("ADDON_LOADED", "Blizzard_PlayerSpells")
        return frame
    end
    local function load(profile, prepare)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        installClient()
        if prepare then prepare() end
        profile = profile or {}
        profile.modules = profile.modules or {}
        profile.modules.unitframes = false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, nil
        for _, file in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/ui/motion.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua",
            "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua", "src/modules/unitframes/unitframes.lua", "src/modules/unitframes/unitframes-status.lua", "src/modules/panels/panels.lua", "src/modules/panels/panels-skin.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        return RikUI.Panels
    end
    local ok, reason = pcall(function()
        local module = load()
        local character = CharacterFrame
        check("a window that was never opened is left alone", rawget(character.NineSlice, "alpha") == nil
            and rawget(character, "rikBorder") == nil)
        character:Show()
        check("opening a window strips the frame, background, streak and portrait art",
            character.NineSlice.alpha == 0 and character.Bg.alpha == 0 and character.TopTileStreaks.alpha == 0
            and character.PortraitContainer.alpha == 0)
        check("the window gets the flat backdrop and the RikUI border", character.rikBackdrop.color[4] > 0.8
            and character.rikBackdrop.color[1] < 0.1 and #character.rikBorder == 4
            and character.rikBorder[1].texture == RikUI.Media.border)
        check("the title takes the RikUI font", character.TitleContainer.TitleText.fontPath == RikUI.Media.font)
        check("the inset goes flat too", character.Inset.NineSlice.alpha == 0 and character.Inset.Bg.alpha == 0
            and character.Inset.rikBackdrop ~= nil and #character.Inset.rikBorder == 4)
        check("the window fades in", character.rikFade.plays == 1)
        local border = character.rikBorder
        character:Hide()
        character:Show()
        check("reopening fades again without skinning twice", character.rikFade.plays == 2
            and character.rikBorder == border)

        local close = character.CloseButton
        check("the close button loses its art and gains a flat box with an x", close.normal.alpha == 0
            and close.pushed.alpha == 0 and close.rikIcon.rikIcon == "close" and #close.rikBorder == 4
            and close.rikIcon.texture == RikUI.Media.IconPath("close") and rawget(close, "rikLabel") == nil)
        env.click(close)
        check("the close button keeps Blizzard's click handler", stub.closed == 1)

        MerchantFrame:Show()
        local first, second = MerchantFrame.Tabs[1], MerchantFrame.Tabs[2]
        check("tabs lose their art and get a flat backing and the RikUI font", first.Left.alpha == 0
            and first.MiddleActive.alpha == 0 and first.RightHighlight.alpha == 0 and first.rikBacking ~= nil
            and #first.rikBorder == 4 and first.Text.fontPath == RikUI.Media.font)
        check("the selected tab shows the accent at first", first.rikAccent.shown == true
            and second.rikAccent.alpha == 0)
        PanelTemplates_DeselectTab(first)
        PanelTemplates_SelectTab(second)
        check("the accent follows Blizzard's tab selection", first.rikAccent.alpha == 0
            and second.rikAccent.shown == true and second.selected == true)

        WorldMapFrame:Show()
        check("world map has no competing panel alpha animation", rawget(WorldMapFrame, "rikFade") == nil)
        check("the map window strips the chrome on its border frame and takes no fill",
            WorldMapFrame.BorderFrame.NineSlice.alpha == 0 and #WorldMapFrame.BorderFrame.rikBorder == 4
            and rawget(WorldMapFrame, "rikBackdrop") == nil and rawget(WorldMapFrame.BorderFrame, "rikBackdrop") == nil
            and WorldMapFrame.BorderFrame.CloseButton.rikIcon.rikIcon == "close")

        local spells = loadSpells()
        check("a load-on-demand window is found when its addon loads", module.Hooked.PlayerSpellsFrame == true
            and rawget(spells, "rikBorder") == nil)
        env.inCombat = true
        spells:Show()
        env.inCombat = false
        check("a first open in combat skins without a protected write or a message", #spells.rikBorder == 4
            and spells.NineSlice.alpha == 0 and #env.printed == 0)
        local spellTab = spells.TabSystem.tabs[2]
        spellTab:SetTabSelected(true)
        check("tab system tabs are skinned and their accent follows SetTabSelected", spellTab.Left.alpha == 0
            and spellTab.rikAccent.shown == true and spellTab.selected == true)
        spellTab:SetTabSelected(false)
        check("deselecting a tab system tab clears its accent", spellTab.rikAccent.alpha == 0)

        BankFrame.NineSlice.SetAlpha = function() error("bank art locked") end
        BankFrame:Show()
        BankFrame:Hide()
        BankFrame:Show()
        check("a window that fails to skin is reported once and left stock", printedContains("Panels skin BankFrame")
            and #env.printed == 1 and module.Skinned.BankFrame == nil)

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports hooked and skinned windows", printedContains("Panels hooked=5 skinned=4"))
        check("windows the client does not have are skipped", module.Hooked.MailFrame == nil)

        module = load(nil, function() makeWindow("ClassTrainerFrame") end)
        ClassTrainerFrame:Show()
        check("a window from the extended list that exists at login is skinned on first show",
            module.Hooked.ClassTrainerFrame == true and ClassTrainerFrame.NineSlice.alpha == 0
            and #ClassTrainerFrame.rikBorder == 4 and ClassTrainerFrame.rikFade.plays == 1)
        local auction = makeWindow("AuctionHouseFrame")
        check("a load-on-demand window from the extended list is unknown until its addon loads",
            module.Hooked.AuctionHouseFrame == nil)
        env.fire("ADDON_LOADED", "Blizzard_AuctionHouseUI")
        auction:Show()
        check("the auction house is hooked when its addon loads and skinned on first show",
            module.Hooked.AuctionHouseFrame == true and auction.NineSlice.alpha == 0 and #env.printed == 0)

        module = load(nil, function()
            local config = CreateFrame("Frame", "ChatConfigFrame", UIParent)
            config.Border, config.Header = CreateFrame("Frame", nil, config), CreateFrame("Frame", nil, config)
            config.Header.CenterBG, config.Header.Text = config.Header:CreateTexture(), config.Header:CreateFontString()
            local taxi = CreateFrame("Frame", "TaxiFrame", UIParent)
            for _, key in ipairs({ "TopLeftCorner", "BotRightCorner", "BottomLeftCorner", "TopBorder", "LeftBorder" }) do
                taxi[key] = taxi:CreateTexture()
            end
            local lfg = CreateFrame("Frame", "LFGParentFrame", UIParent)
            lfg.regions = { lfg:CreateTexture(), lfg:CreateTexture(), lfg:CreateFontString() }
            function lfg:GetRegions() return unpack(self.regions) end
            LFGParentFrameCloseButton = makeCloseButton(lfg)
            local recap = CreateFrame("Frame", "DeathRecapFrame", UIParent)
            recap.CloseXButton = makeCloseButton(recap)
            for _, frame in ipairs({ config, taxi, lfg, recap }) do frame.shown = false end
        end)
        ChatConfigFrame:Show()
        check("a dialog-border window loses its border frame and header art and gets a gold heading",
            ChatConfigFrame.Border.alpha == 0 and ChatConfigFrame.Header.CenterBG.alpha == 0
            and ChatConfigFrame.Header.Text.fontPath == RikUI.Media.font and ChatConfigFrame.Header.Text.textColor[3] == 0
            and #ChatConfigFrame.rikBorder == 4)
        TaxiFrame:Show()
        check("a basic or translucent template window loses its corner and border pieces",
            TaxiFrame.TopLeftCorner.alpha == 0 and TaxiFrame.BotRightCorner.alpha == 0
            and TaxiFrame.BottomLeftCorner.alpha == 0 and TaxiFrame.LeftBorder.alpha == 0 and TaxiFrame.rikBackdrop ~= nil)
        LFGParentFrame:Show()
        check("a hand-drawn window has its own textures faded, but not its text or the RikUI regions",
            LFGParentFrame.regions[1].alpha == 0 and LFGParentFrame.regions[2].alpha == 0
            and rawget(LFGParentFrame.regions[3], "alpha") == nil and rawget(LFGParentFrame.rikBackdrop, "alpha") ~= 0)
        DeathRecapFrame:Show()
        check("the close button is also found by its global name or as CloseXButton",
            LFGParentFrameCloseButton.rikIcon.rikIcon == "close" and DeathRecapFrame.CloseXButton.rikIcon.rikIcon == "close")
        check("none of the new windows printed anything", #env.printed == 0)

        module = load(nil, function()
            local calendar = CreateFrame("Frame", "CalendarFrame", UIParent)
            calendar.regions = { calendar:CreateTexture(), calendar:CreateFontString() }
            function calendar:GetRegions() return unpack(self.regions) end
            local zone = CreateFrame("Frame", "BattlefieldMapFrame", UIParent)
            zone.BorderFrame = CreateFrame("Frame", nil, zone)
            zone.BorderFrame.regions = { zone.BorderFrame:CreateTexture(), zone.BorderFrame:CreateTexture() }
            function zone.BorderFrame:GetRegions() return unpack(self.regions) end
            zone.BorderFrame.CloseButton = makeCloseButton(zone.BorderFrame)
            local stable = makeWindow("PetStableFrame")
            for _, frame in ipairs({ calendar, zone, stable }) do frame.shown = false end
        end)
        CalendarFrame:Show()
        check("the calendar's hand-drawn chrome is faded and replaced by the flat backdrop",
            CalendarFrame.regions[1].alpha == 0 and rawget(CalendarFrame.regions[2], "alpha") == nil
            and CalendarFrame.rikBackdrop ~= nil and #CalendarFrame.rikBorder == 4)
        BattlefieldMapFrame:Show()
        check("the zone map loses its border pieces, gets an edge and keeps its canvas free of a fill",
            BattlefieldMapFrame.BorderFrame.regions[1].alpha == 0 and BattlefieldMapFrame.BorderFrame.regions[2].alpha == 0
            and #BattlefieldMapFrame.BorderFrame.rikBorder == 4
            and rawget(BattlefieldMapFrame.BorderFrame, "rikBackdrop") == nil
            and BattlefieldMapFrame.BorderFrame.CloseButton.rikIcon.rikIcon == "close")
        PetStableFrame:Show()
        check("the Camelot pet stable is skinned under its own name",
            PetStableFrame.NineSlice.alpha == 0 and PetStableFrame.rikFade.plays == 1 and #env.printed == 0)

        module = load(nil, function() PanelTemplates_SelectTab, PanelTemplates_DeselectTab = nil, nil end)
        MerchantFrame:Show()
        check("a client without the tab functions still skins tabs", MerchantFrame.Tabs[1].rikBacking ~= nil
            and #env.printed == 0)

        module = load({ modules = { panels = false } })
        CharacterFrame:Show()
        check("a disabled module leaves every window stock", rawget(CharacterFrame.NineSlice, "alpha") == nil
            and rawget(CharacterFrame, "rikBorder") == nil)
    end)
    restoreCreate()
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat = false
    check("panels suite completes", ok, reason)
end
