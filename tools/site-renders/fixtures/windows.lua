-- Blizzard's windows, opened through the client's own entry points so RikUI's panel, interior and
-- control modules skin them as they do in the game. Fixtures supply the data a window shows.

-- Client globals the simulator lacks that Blizzard's window handlers call on show. Each is defined only
-- when missing; the values describe the sample character's guild bank and no taxi map.
local GUILD_BANK = { [1] = { 2589, 2589, 117, 2070, 118, 6948 }, [2] = { 25, 4865, 3300 } }
function RikRenderClientStubs()
    local stubs = {
        -- Current Forever PaperDollFrame_OnShow reads this client API; the fixture paladin uses no ammunition.
        UnitUsesAmmo = function() return false end,
        ResetSetMerchantFilter = function() end, FlashClientIcon = function() end,
        QuestIsFromAdventureMap = function() return false end, QuestGetAutoAccept = function() return false end,
        QuestIsFromAreaTrigger = function() return false end,
        QueryGuildBankTab = function() end, GetCurrentGuildBankTab = function() return 1 end,
        GetNumGuildBankTabs = function() return 2 end,
        GetGuildBankTabInfo = function(tab) return ({ "Consumables", "Materials" })[tab] or "", "Interface/Icons/INV_Misc_Bag_10", true, true, 0, 0 end,
        GetGuildBankMoney = function() return 1273450 end, CanWithdrawGuildBankMoney = function() return true end,
        GetGuildBankWithdrawMoney = function() return 500000 end,
        GetGuildBankItemInfo = function(tab, slot)
            local id = GUILD_BANK[tab] and GUILD_BANK[tab][slot]
            if not id then return nil end
            local _, _, quality, _, _, _, _, _, _, icon = GetItemInfo(id)
            return icon, id == 2589 and 20 or 1, false, false, quality
        end,
        GetGuildBankItemLink = function(tab, slot)
            local id = GUILD_BANK[tab] and GUILD_BANK[tab][slot]
            return id and select(2, GetItemInfo(id)) or nil
        end,
        SetTaxiMap = function() end, NumTaxiNodes = function() return 0 end,
    }
    for name, fn in pairs(stubs) do
        if _G[name] == nil then _G[name] = fn end
    end
    if type(C_Trainer) ~= "table" then C_Trainer = {} end
    if Enum.TrainerType == nil then Enum.TrainerType = { Class = 0, Mount = 1, Tradeskill = 2, Pet = 3 } end
    if C_Trainer.GetTrainerType == nil then C_Trainer.GetTrainerType = function() return Enum.TrainerType.Class end end
    -- The Camelot gossip frame's theme hook and the talent tree's group display are absent in the simulator.
    for _, frame in ipairs({ GossipFrame, QuestFrame }) do
        if frame and frame.UpdateTheme == nil then frame.UpdateTheme = function() end end
    end
    if type(C_Traits) == "table" and C_Traits.GetGroupDisplayInfoByTreeID == nil then C_Traits.GetGroupDisplayInfoByTreeID = function() return {} end end
    -- The auction house's category table names item subclasses the simulator's Enum lacks.
    local SUBCLASSES = {
        ItemContainerSubclass = { Bag = 0, Soul = 1, Herb = 2, Enchanting = 3, Engineering = 4, Gem = 5, Mining = 6, Leatherworking = 7, Inscription = 8, Tackle = 9, Cooking = 10, Reagent = 11 },
        ItemQuiverSubclass = { Quiver = 2, AmmoPouch = 3 },
        ItemGemSubclass = { Intellect = 0, Agility = 1, Strength = 2, Stamina = 3, Spirit = 4, Criticalstrike = 5, Mastery = 6, Haste = 7, Versatility = 8, Other = 9, Multiplestats = 10, Artifactrelic = 11 },
        ItemRecipeSubclass = { Book = 0, Leatherworking = 1, Tailoring = 2, Engineering = 3, Blacksmithing = 4, Cooking = 5, Alchemy = 6, Firstaid = 7, Enchanting = 8, Fishing = 9, Jewelcrafting = 10, Inscription = 11 },
        ItemMiscellaneousSubclass = { Junk = 0, Reagent = 1, CompanionPet = 2, Holiday = 3, Other = 4, Mount = 5, MountEquipment = 6 },
        ItemReagentSubclass = { Reagent = 0, Keystone = 1, ContextToken = 2 },
        ItemProfessionSubclass = { Blacksmithing = 0, Leatherworking = 1, Alchemy = 2, Herbalism = 3, Cooking = 4, Mining = 5, Tailoring = 6, Engineering = 7, Enchanting = 8, Fishing = 9, Skinning = 10, Jewelcrafting = 11, Inscription = 12, Archaeology = 13 },
        ItemGlyphSubclass = { Major = 0, Minor = 1 },
    }
    for name, values in pairs(SUBCLASSES) do
        if Enum[name] == nil then Enum[name] = values end
    end
    -- Quest text contrast, vendor affordability, guild bank repairs and the talent tree's display groups.
    if QuestTextContrast == nil then QuestTextContrast = {} end
    if QuestTextContrast.IsEnabled == nil then QuestTextContrast.IsEnabled = function() return false end end
    if GetQuestBackgroundMaterial == nil then GetQuestBackgroundMaterial = function() return "Parchment" end end
    if GetQuestPortraitGiver == nil then GetQuestPortraitGiver = function() return 0, "", "", 0, 0 end end
    if GetQuestPortraitTurnIn == nil then GetQuestPortraitTurnIn = function() return 0, "", "", 0, 0 end end
    -- Auction categories name item classes the simulator has no names for.
    if type(C_Item) == "table" and not RikRenderItemClassWrapped then
        RikRenderItemClassWrapped = true
        local classInfo, subClassInfo = C_Item.GetItemClassInfo, C_Item.GetItemSubClassInfo
        C_Item.GetItemClassInfo = function(classID) return (type(classInfo) == "function" and classInfo(classID)) or ("Class " .. tostring(classID)) end
        C_Item.GetItemSubClassInfo = function(classID, subClassID)
            local name, plural = nil, nil
            if type(subClassInfo) == "function" then name, plural = subClassInfo(classID, subClassID) end
            return name or ("Type " .. tostring(classID) .. "." .. tostring(subClassID)), plural
        end
    end
    if CanAffordMerchantItem == nil then CanAffordMerchantItem = function() return true end end
    if CanGuildBankRepair == nil then CanGuildBankRepair = function() return false end end
    if GetNumGuildBankTransactions == nil then GetNumGuildBankTransactions = function() return 0 end end
    if GetNumGuildBankMoneyTransactions == nil then GetNumGuildBankMoneyTransactions = function() return 0 end end
    if GetGuildBankText == nil then GetGuildBankText = function() return "" end end
    if QueryGuildBankText == nil then QueryGuildBankText = function() end end
    if type(C_Traits) == "table" and not RikRenderTraitGroupsWrapped then
        RikRenderTraitGroupsWrapped = true
        local groups = C_Traits.GetGroupDisplayInfoByTreeID
        C_Traits.GetGroupDisplayInfoByTreeID = function(...) return (type(groups) == "function" and groups(...)) or {} end
    end
end

-- The inspect window on a party member: the simulator's target becomes Mira the priest.
function RikRenderInspect()
    A_Admin.SetTarget("Mira", 10, 5, false)
    if A_Admin.SetTargetType then pcall(A_Admin.SetTargetType, "player") end
    if type(InspectUnit) == "function" then pcall(InspectUnit, "target") end
    return RikRenderInterior("InspectFrame")
end

local ADDONS = {
    AchievementFrame = "Blizzard_AchievementUI", CalendarFrame = "Blizzard_Calendar", AuctionHouseFrame = "Blizzard_AuctionHouseUI",
    CollectionsJournal = "Blizzard_Collections", TransmogFrame = "Blizzard_Collections", InspectFrame = "Blizzard_InspectUI",
    ClassTrainerFrame = "Blizzard_TrainerUI", ProfessionsFrame = "Blizzard_Professions", GuildBankFrame = "Blizzard_GuildBankUI",
    MacroFrame = "Blizzard_MacroUI", PlayerChoiceFrame = "Blizzard_PlayerChoice", GenericTraitFrame = "Blizzard_GenericTraitUI",
    CommunitiesFrame = "Blizzard_Communities", PetStableFrame = "Blizzard_StableUI", PlayerSpellsFrame = "Blizzard_PlayerSpells",
    SplashFrame = "Blizzard_SplashScreen", PVPMatchResults = "Blizzard_PVPMatch", RaidInfoFrame = "Blizzard_RaidUI",
}

-- Show a window the way the client does and make sure RikUI's skin ran. The simulator drops a window's
-- OnShow chain when Blizzard's handler reaches a client API it lacks; with the stubs in place the chain
-- is run once more so RikUI's OnShow hooks apply exactly as in the client.
function RikRenderWindow(name)
    RikRenderClientStubs()
    if not _G[name] and ADDONS[name] then C_AddOns.LoadAddOn(ADDONS[name]) end
    local frame = assert(_G[name], "Window is missing: " .. name)
    -- Blizzard's show handlers measure the window (the bank's bags anchor to its right edge); give an unplaced window a point first.
    if frame:GetNumPoints() == 0 then frame:SetPoint("CENTER") end
    if frame:GetAttribute("UIPanelLayout-area") then ShowUIPanel(frame) else frame:Show() end
    assert(frame:IsShown(), "Window did not open: " .. name)
    if not (RikUI.Panels.Skinned[name] or (RikUI.Dialogs and RikUI.Dialogs.Skinned[name])) then
        local onShow = frame:GetScript("OnShow")
        if onShow then
            local ok, reason = pcall(onShow, frame)
            assert(ok, name .. " OnShow: " .. tostring(reason))
        end
    end
    assert(RikUI.Panels.Skinned[name] or (RikUI.Dialogs and RikUI.Dialogs.Skinned[name]), "RikUI did not skin " .. name)
    RikRenderCenter(frame)
    RikRenderResize(frame)
    RikRenderRemeasure(frame)
    return frame
end

-- The character window on one of its tabs: "PaperDollFrame", "ReputationFrame" or "SkillFrame"; the
-- stats pane is part of the paper doll.
function RikRenderCharacter(tab)
    local frame = RikRenderWindow("CharacterFrame")
    if tab and tab ~= "PaperDollFrame" then
        for index = 1, 4 do
            local button = _G["CharacterFrameTab" .. index]
            local subframe = button and PanelTemplates_GetTabFrame and PanelTemplates_GetTabFrame(frame, index)
            if button and (subframe == _G[tab] or (button.frame == tab)) then button:Click() end
        end
        if type(ToggleCharacter) == "function" and not (_G[tab] and _G[tab]:IsShown()) then ToggleCharacter(tab) end
    end
    if RikUI.Interiors then RikUI.Interiors.Walk(frame, "character") end
    RikRenderResize(frame)
    return frame
end

-- The spellbook or the talents page of the player spells window.
function RikRenderSpells(page)
    local frame = RikRenderWindow("PlayerSpellsFrame")
    if page == "talents" and frame.SetTab and frame.talentTabID then frame:SetTab(frame.talentTabID) end
    if page == "spellbook" and frame.SetTab and frame.spellBookTabID then frame:SetTab(frame.spellBookTabID) end
    if RikUI.Interiors then RikUI.Interiors.Walk(frame, "spells") end
    RikRenderResize(frame)
    return frame
end

local KOBOLD = {
    title = "Kobold Camp Cleanup",
    text = "Your first task is one of cleansing, $n. A rabble of kobold vermin have settled into the woods to the north, "
        .. "and they are as thick as fleas on a dog. Marshal McBride wants them cleared out before they spread any further.",
    objectives = "Kill 10 Kobold Vermin, then return to Marshal McBride.",
    reward = "You will be able to choose one of these rewards:",
}

-- The quest detail page for Kobold Camp Cleanup: the greeting comes from the simulator's quest giver,
-- the text from the fixture.
function RikRenderQuestDetail()
    RikRenderClientStubs()
    GetTitleText = function() return KOBOLD.title end
    GetQuestText = function() return KOBOLD.text:gsub("%$n", "Rik") end
    GetObjectiveText = function() return KOBOLD.objectives end
    GetRewardText = function() return KOBOLD.reward end
    GetProgressText = function() return "Have you dealt with the kobolds, Rik?" end
    A_Admin.OpenQuestNpc(7, KOBOLD.title)
    C_GossipInfo.SelectAvailableQuest(7)
    QuestFrame_OnEvent(QuestFrame, "QUEST_DETAIL")
    local frame = RikRenderWindow("QuestFrame")
    if RikUI.Interiors then RikUI.Interiors.Walk(frame, "quests") end
    RikRenderResize(frame)
    return frame
end

-- The quest giver's greeting with the quests he offers and the conversation choices.
function RikRenderGossip()
    RikRenderClientStubs()
    A_Admin.OpenQuestNpc(7, KOBOLD.title)
    local available = C_GossipInfo.GetAvailableQuests
    C_GossipInfo.GetAvailableQuests = function()
        local rows = available()
        rows[#rows + 1] = { questID = 15, questInfoID = 15, questLevel = 3, title = "Investigate Echo Ridge", isComplete = false, frequency = 0, repeatable = false, isTrivial = false, isLegendary = false, isIgnored = false, isImportant = false, isMeta = false }
        return rows
    end
    C_GossipInfo.GetOptions = function()
        return { { gossipOptionID = 1, name = "Marshal, what should I know about Northshire?", icon = 132053, flags = 0, orderIndex = 1, status = 0, spellID = nil, overrideIconID = nil, selectOptionWhenOnlyOption = false, rewards = {} },
            { gossipOptionID = 2, name = "I need training.", icon = 132053, flags = 0, orderIndex = 2, status = 0, spellID = nil, overrideIconID = nil, selectOptionWhenOnlyOption = false, rewards = {} } }
    end
    C_GossipInfo.GetText = function() return "Greetings, Rik. The kobolds grow bold in the woods, and Northshire needs every able hand." end
    A_Admin.FireEvent("GOSSIP_SHOW")
    local frame = RikRenderWindow("GossipFrame")
    if GossipFrame.Update then GossipFrame:Update() end
    if RikUI.Interiors then RikUI.Interiors.Walk(frame, "quests") end
    RikRenderResize(frame)
    return frame
end

-- A vendor's goods: the bag fixture's items, priced.
function RikRenderVendor()
    RikRenderBagItems()
    local goods = { 118, 117, 2070, 2589, 25, 3300 }
    local prices = { [118] = 300, [117] = 125, [2070] = 250, [2589] = 40, [25] = 1640, [3300] = 8 }
    A_Admin.SetMerchantItems(goods)
    GetMerchantNumItems = function() return #goods end
    GetMerchantItemInfo = function(index)
        local id = goods[index]
        if not id then return nil end
        local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(id)
        return name, icon, prices[id], id == 2589 and 5 or 1, 0, true, false, nil, nil, false, id == 6948
    end
    GetMerchantItemLink = function(index) local id = goods[index]; return id and select(2, GetItemInfo(id)) end
    if type(C_MerchantFrame) ~= "table" then C_MerchantFrame = {} end
    C_MerchantFrame.GetNumItems = GetMerchantNumItems
    C_MerchantFrame.GetItemInfo = function(index)
        local id = goods[index]
        if not id then return nil end
        local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(id)
        return { name = name, texture = icon, price = prices[id], stackCount = id == 2589 and 5 or 1, numAvailable = -1, isPurchasable = true,
            isUsable = true, hasExtendedCost = false, currencyID = nil, spellID = nil, isQuestStartItem = false, quality = quality }
    end
    GetMerchantItemID = function(index) return goods[index] end
    GetMerchantItemMaxStack = function() return 20 end
    GetMerchantItemCostInfo = function() return 0 end
    GetRepairAllCost = function() return 1240, true end
    CanMerchantRepair = function() return true end
    A_Admin.FireEvent("MERCHANT_SHOW")
    local frame = RikRenderWindow("MerchantFrame")
    if MerchantFrame_Update then MerchantFrame_Update() end
    if RikUI.Interiors then RikUI.Interiors.Walk(frame, "commerce") end
    RikRenderResize(frame)
    return frame
end

-- The bank with a few stored items.
function RikRenderBank()
    RikRenderBagItems()
    for slot, id in ipairs({ 2589, 2070, 6948, 25, 4865, 117 }) do A_Admin.AddBagItem(-1, slot, id, id == 2589 and 20 or 1) end
    local frame = RikRenderWindow("BankFrame")
    if RikUI.Interiors then RikUI.Interiors.Walk(frame, "commerce") end
    RikRenderResize(frame)
    return frame
end

local MAIL = {
    { "Mira", "Linen for your tailoring", "Found these in Goldshire. Put them to good use.", 0, { { 2589, 20 } } },
    { "Toddrick", "Guild dues", "Thanks for the help on Sunday.", 12500, {} },
    { "Auction House", "Auction successful: Worn Shortsword", "", 16000, {} },
}

-- The inbox with three letters.
function RikRenderInbox()
    RikRenderBagItems()
    for _, mail in ipairs(MAIL) do A_Admin.AddMail(mail[1], mail[2], mail[3], mail[4], mail[5]) end
    -- The simulator draws the |4 plural token raw; the inbox shows the resolved word.
    DAYS_ABBR = "%d Days"
    local header = GetInboxHeaderInfo
    GetInboxHeaderInfo = function(index)
        local packageIcon, stationeryIcon, sender, subject, money, cod, daysLeft, itemCount, wasRead, wasReturned, textCreated, canReply, isGM = header(index)
        local mail = MAIL[index]
        local icon = mail and #mail[5] > 0 and 132889 or "Interface/Icons/INV_Letter_15"
        return packageIcon or icon, stationeryIcon, sender, subject, money, cod, daysLeft or 30, itemCount, wasRead, wasReturned, textCreated, canReply, isGM
    end
    A_Admin.OpenMailbox()
    local frame = RikRenderWindow("MailFrame")
    if InboxFrame_Update then InboxFrame_Update() end
    if RikUI.Interiors then RikUI.Interiors.Walk(frame, "commerce") end
    RikRenderResize(frame)
    return frame
end

-- The first letter opened.
function RikRenderOpenMail()
    RikRenderInbox()
    InboxFrame.openMailID = 1
    GetInboxInvoiceInfo = function() return nil end
    local inboxText = GetInboxText
    GetInboxText = function(index)
        local body, stationery1, stationery2, isTakeable = inboxText(index)
        return (body and body ~= "" and body) or MAIL[index][3], stationery1, stationery2, isTakeable, false, false
    end
    if OpenMail_Update then OpenMail_Update() end
    local frame = RikRenderWindow("OpenMailFrame")
    if RikUI.Interiors then RikUI.Interiors.Walk(frame, "commerce") end
    RikRenderResize(frame)
    return frame
end

-- A trade with Mira: the window opens on the trade event.
function RikRenderTrade()
    RikRenderBagItems()
    local offered = { player = { [1] = { 2589, 12 }, [2] = { 118, 2 } }, target = { [1] = { 2070, 3 } } }
    local function item(side, slot)
        local entry = offered[side][slot]
        if not entry then return nil end
        local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(entry[1])
        return name, icon, entry[2], quality, entry[1]
    end
    -- name, texture, numItems, quality, enchantment, canLoseTransmog, isBound, itemID
    GetTradePlayerItemInfo = function(slot)
        local name, icon, count, quality, id = item("player", slot)
        if not name then return nil, nil, 0, nil, nil, false, false, 0 end
        return name, icon, count, quality, nil, false, false, id
    end
    -- name, texture, numItems, quality, isUsable, enchantment, itemID
    GetTradeTargetItemInfo = function(slot)
        local name, icon, count, quality, id = item("target", slot)
        if not name then return nil, nil, 0, nil, true, nil, 0 end
        return name, icon, count, quality, true, nil, id
    end
    GetTradePlayerItemLink = function(slot) local entry = offered.player[slot]; return entry and select(2, GetItemInfo(entry[1])) end
    GetTradeTargetItemLink = function(slot) local entry = offered.target[slot]; return entry and select(2, GetItemInfo(entry[1])) end
    A_Admin.FireEvent("TRADE_SHOW")
    local frame = RikRenderWindow("TradeFrame")
    if TradeFrameRecipientNameText then TradeFrameRecipientNameText:SetText("Mira") end
    if TradeFramePlayerNameText then TradeFramePlayerNameText:SetText("Rik") end
    if RikUI.Interiors then RikUI.Interiors.Walk(frame, "commerce") end
    RikRenderResize(frame)
    return frame
end

-- The guild bank with the stub tabs and items.
function RikRenderGuildBank()
    RikRenderBagItems()
    RikRenderClientStubs()
    for tab, slots in pairs(GUILD_BANK) do
        for slot, id in ipairs(slots) do A_Admin.AddGuildBankItem(tab, slot, id, id == 2589 and 20 or 1) end
    end
    local frame = RikRenderWindow("GuildBankFrame")
    if frame.Update then pcall(frame.Update, frame) end
    if RikUI.Interiors then RikUI.Interiors.Walk(frame, "services") end
    RikRenderResize(frame)
    return frame
end

-- Any other window by name, walked by the interior family RikUI registers for it.
function RikRenderInterior(name)
    local frame = RikRenderWindow(name)
    -- A panel that lives inside another window (raid information in the friends window) stands alone here.
    if not frame:IsVisible() then frame:SetParent(UIParent); RikRenderCenter(frame) end
    local family = RikUI.Interiors and RikUI.Interiors.Roots[name]
    if family then RikUI.Interiors.Walk(frame, family) end
    RikRenderResize(frame)
    return frame
end

-- A detail of a window: a named holder the size of the detail, with the window re-parented into it so the
-- region at (x, y) from the window's top-left corner fills the holder. The rest of the window lies
-- outside the crop.
function RikRenderDetail(frame, name, x, y, width, height)
    local holder = CreateFrame("Frame", name, UIParent)
    holder:SetSize(width, height)
    holder:SetPoint("CENTER")
    frame:SetParent(holder)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", holder, "TOPLEFT", -x, y)
    return holder
end

-- The friends list with three contacts, two online.
function RikRenderFriends()
    local friends = {
        { name = "Mira", level = 10, className = "Priest", area = "Goldshire", connected = true, notes = "Healer" },
        { name = "Toddrick", level = 12, className = "Warrior", area = "Westfall", connected = true, notes = "" },
        { name = "Remy", level = 8, className = "Mage", area = "", connected = false, notes = "Tailor" },
    }
    C_FriendList.GetNumFriends = function() return #friends end
    C_FriendList.GetNumOnlineFriends = function() return 2 end
    C_FriendList.GetFriendInfoByIndex = function(index)
        local f = friends[index]
        if not f then return nil end
        return { name = f.name, level = f.level, className = f.className, area = f.area, connected = f.connected, notes = f.notes,
            afk = false, dnd = false, guid = "Player-1-0000000" .. index, rafLinkType = 0, mobile = false, referAFriend = false }
    end
    C_FriendList.GetFriendInfo = function(name)
        for index, f in ipairs(friends) do if f.name == name then return C_FriendList.GetFriendInfoByIndex(index) end end
    end
    local frame = RikRenderInterior("FriendsFrame")
    if FriendsList_Update then FriendsList_Update(true) end
    if RikUI.Interiors then RikUI.Interiors.Walk(frame, "social") end
    RikRenderResize(frame)
    return frame
end

-- The reputation tab with Classic Alliance factions.
function RikRenderFactions()
    local rows = {
        { name = "Alliance", isHeader = true, isCollapsed = false, isHeaderWithRep = false },
        { name = "Stormwind", reaction = 6, low = 3000, high = 6000, standing = 4350, description = "The humans of Stormwind." },
        { name = "Ironforge", reaction = 5, low = 0, high = 3000, standing = 1250, description = "The dwarves of Ironforge." },
        { name = "Darnassus", reaction = 4, low = 0, high = 3000, standing = 400, description = "The night elves of Darnassus." },
        { name = "Gnomeregan Exiles", reaction = 4, low = 0, high = 3000, standing = 120, description = "The gnomes in exile." },
        { name = "Other", isHeader = true, isCollapsed = false, isHeaderWithRep = false },
        { name = "Argent Dawn", reaction = 4, low = 0, high = 3000, standing = 0, description = "The Argent Dawn." },
    }
    local function data(index)
        local row = rows[index]
        if not row then return nil end
        return { name = row.name, description = row.description or "", reaction = row.reaction or 4, currentReactionThreshold = row.low or 0,
            nextReactionThreshold = row.high or 3000, currentStanding = row.standing or 0, atWarWith = false, canToggleAtWar = false,
            isHeader = row.isHeader == true, isHeaderWithRep = false, isCollapsed = false, isWatched = row.name == "Stormwind",
            hasBonusRepGain = false, factionID = 70 + index, canSetInactive = row.isHeader ~= true, isAccountWide = false, isChild = false }
    end
    if type(C_Reputation) == "table" then
        C_Reputation.GetNumFactions = function() return #rows end
        C_Reputation.GetFactionDataByIndex = data
        C_Reputation.GetFactionDataByID = function(id) return data(id - 70) end
        C_Reputation.GetWatchedFactionData = function() return data(2) end
        C_Reputation.IsFactionParagon = function() return false end
        C_Reputation.IsMajorFaction = function() return false end
        C_Reputation.GetSelectedFaction = function() return 2 end
    end
    GetNumFactions = function() return #rows end
    local frame = RikRenderCharacter("ReputationFrame")
    if ReputationFrame and ReputationFrame.Update then pcall(ReputationFrame.Update, ReputationFrame) end
    if RikUI.Interiors then RikUI.Interiors.Walk(frame, "character") end
    RikRenderResize(frame)
    return frame
end
