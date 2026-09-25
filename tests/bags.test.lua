local loadfile = dofile("tests/load_addon.lua").Loadfile
-- The stub cannot show taint: the suite proves the bag travels in the parent's ID and that no field
-- Blizzard's item button reads is written. Item use, selling and rendering need a beta check.
return function(check)
    local env = require("wow_stub")
    local stub = require("bags_stub")
    local originalCreate = CreateFrame
    local TEMPLATE = "ContainerFrameItemButtonTemplate"
    local API = { "C_Container", "GetMoney", "UISpecialFrames", "ContainerFrameContainer", "ContainerFrameCombinedBags",
        "OpenBag", "CloseBag", "ToggleBag", "OpenBackpack", "CloseBackpack", "ToggleBackpack", "OpenAllBags",
        "CloseAllBags", "ToggleAllBags", "CursorHasItem", "PutItemInBag", "PickupBagFromSlot",
        "GetInventoryItemTexture", "GetInventorySlotInfo" }
    local saved, savedQualityColor = {}, C_Item.GetItemQualityColor
    local savedCenter, savedScale = rawget(UIParent, "GetCenter"), rawget(UIParent, "GetEffectiveScale")
    function UIParent:GetCenter() return 400, 300 end
    function UIParent:GetEffectiveScale() return 1 end
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local function capitalOnly(value)
        local methods = getmetatable(value).__index
        setmetatable(value, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
    end
    local function region(value)
        function value:CreateAnimationGroup() return require("widget_stub").animationGroup() end
        capitalOnly(value)
        function value:SetTexture(texture) self.texture = texture end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetPoint(...) self.point = { ... } end
        function value:SetDesaturated(flag) self.desaturated = flag end
        function value:SetShown(flag) self.visible = flag end
        function value:SetAlpha(alpha) self.alpha = alpha end
        function value:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
        return value
    end
    local function cooldown(button)
        local widget = originalCreate("Cooldown", nil, button)
        function widget:SetCooldown(start, duration) self.start, self.duration = start, duration end
        function widget:Clear() self.start, self.duration = nil, nil end
        return widget
    end
    CreateFrame = function(kind, name, parent, template)
        if template == TEMPLATE and stub.templateMissing then error("CreateFrame: Unknown frame template") end
        if template == "BagSearchBoxTemplate" and stub.searchTemplateMissing then error("CreateFrame: Unknown frame template") end
        local frame = originalCreate(kind, name, parent, template)
        function frame:CreateAnimationGroup() return require("widget_stub").animationGroup() end
        capitalOnly(frame)
        function frame:SetParent(value)
            assert(not InCombatLockdown(), "frame reparented in combat")
            self.parent = value
        end
        function frame:GetParent() return self.parent end
        function frame:SetID(id) self.id = id end
        function frame:GetID() return self.id or 0 end
        function frame:SetSize(w, h) self.width, self.height = w, h end
        function frame:SetShown(value) if value then self:Show() else self:Hide() end end
        function frame:SetEnabled(value) self.enabled = value end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:SetAlpha(alpha) self.alpha = alpha end
        function frame:SetMovable(flag) self.movable = flag end
        function frame:RegisterForDrag(button) self.dragButton = button end
        function frame:StartMoving() self.moving = true end
        function frame:StopMovingOrSizing() self.moving = false end
        function frame:GetCenter() return self.centerX, self.centerY end
        function frame:GetEffectiveScale() return 1 end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return region(texture(self, ...)) end
        function frame:CreateFontString(...) return region(font(self, ...)) end
        if template == TEMPLATE then
            frame.Cooldown = cooldown(frame)
            for _, key in ipairs({ "NormalTexture", "PushedTexture", "NewItemTexture", "IconBorder",
                "flash", "AugmentBorderAnimTexture", "BattlepayItemTexture", "ExtendedSlot" }) do
                frame[key] = frame:CreateTexture()
                frame[key]:SetTexture("native-glow")
            end
            frame.IconQuestTexture, frame.JunkIcon = frame:CreateTexture(), frame:CreateTexture()
        end
        if template == "BagSearchBoxTemplate" then
            frame.Left, frame.Middle, frame.Right = frame:CreateTexture(), frame:CreateTexture(), frame:CreateTexture()
        end
        return frame
    end
    local function printedContains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function contains(list, value)
        for _, entry in ipairs(list) do
            if entry == value then return true end
        end
        return false
    end
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.00001 end
    local function color(actual, expected)
        return type(actual) == "table" and near(actual[1], expected[1]) and near(actual[2], expected[2])
            and near(actual[3], expected[3])
    end
    local function parked(frame) return frame and frame.parent == RikUIHiddenFrames and RikUI.Hide.IsHidden(frame) end
    local function button(bag, slot) return _G["RikUIBag" .. bag .. "Slot" .. slot] end
    local function shownButtons()
        local total = 0
        for bag = 0, 4 do
            local slot = 1
            while button(bag, slot) do
                if button(bag, slot):IsShown() then total = total + 1 end
                slot = slot + 1
            end
        end
        return total
    end
    local function typeSearch(text)
        RikUIBagsSearch.text = text
        env.runScript(RikUIBagsSearch, "OnTextChanged")
    end
    -- The unit frame module stays off: only its edge helper is under test here.
    local function load(profile, combat, prepare)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        for bag = 0, 4 do
            for slot = 1, 40 do _G["RikUIBag" .. bag .. "Slot" .. slot] = nil end
        end
        RikUIBags, RikUIBagsSearch = nil, nil
        stub.install(env)
        if prepare then prepare() end
        profile = profile or {}
        profile.modules = profile.modules or {}
        profile.modules.unitframes = false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, nil
        local selected = {}
        for _, file in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua",
            "src/ui/motion.lua", "src/ui/skin.lua", "src/layout/layout-unlock.lua", "src/layout/layout-drag.lua", "src/modules/unitframes/unitframes.lua", "src/modules/unitframes/unitframes-status.lua", "src/modules/bags/bags.lua", "src/modules/bags/bags-items.lua", "src/modules/bags/bags-equipped.lua", "src/modules/bags/bags-feedback.lua", "src/modules/bags/bags-merchant.lua" }) do selected[file] = true end
        -- Use the client manifest order, including Skin loading after the bag module.
        for line in io.lines("RikUI.toc") do
            local file = line:match("^%s*(.-)%s*$")
            if selected[file] then
                assert(loadfile(file))("RikUI", {})
                selected[file] = nil
            end
        end
        assert(next(selected) == nil, "bag test dependency missing from TOC")
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.Bags
    end
    local ok, reason = pcall(function()
        do
            local module = load()
            local originalSearch = C_Container.SetItemSearch
            C_Container.SetItemSearch = nil
            local item = stub.items["0:1"]
            local link, icon = item.hyperlink, item.iconFileID
            item.itemID, item.hyperlink, item.iconFileID = 2589, nil, nil
            OpenAllBags()
            module.SetSearch("linen")
            check("uncached item has no guessed search match", button(0, 1).rikDimmed)
            item.hyperlink, item.iconFileID = link, icon
            local reads = stub.infoReads
            env.fire("ITEM_DATA_LOAD_RESULT", 2589, false)
            env.fire("ITEM_DATA_LOAD_RESULT", 777, true)
            env.fire("ITEM_DATA_LOAD_RESULT", env.SECRET, true)
            env.fire("ITEM_DATA_LOAD_RESULT", 2589, env.SECRET)
            check("irrelevant or unreadable cache events do not read inventory", stub.infoReads == reads)
            env.fire("ITEM_DATA_LOAD_RESULT", 2589, true)
            check("late item data recovers the icon and search match", button(0, 1).rikIcon.texture == icon
                and not button(0, 1).rikDimmed and module.Holder.title:GetText():find("1 match", 1, true))
            check("late item data only reads matching visible slots", stub.infoReads == reads + 1)
            stub.items["0:3"] = { itemID = 2589, stackCount = 2, hyperlink = link, iconFileID = icon }
            module.Refresh()
            reads = stub.infoReads
            env.fire("GET_ITEM_INFO_RECEIVED", 2589, true)
            check("all visible copies of a cached item refresh", stub.infoReads == reads + 2)
            CloseAllBags()
            reads = stub.infoReads
            env.fire("GET_ITEM_INFO_RECEIVED", 2589, true)
            check("closed inventory ignores item cache events", stub.infoReads == reads)
            C_Container.SetItemSearch = originalSearch
        end
        local module = load()
        local media, holder = RikUI.Media, module.Holder
        local cooldownReads, cooldownAPI = 0, C_Container.GetContainerItemCooldown
        C_Container.GetContainerItemCooldown = function(...)
            cooldownReads = cooldownReads + 1
            return cooldownAPI(...)
        end
        env.fire("BAG_UPDATE_COOLDOWN")
        check("hidden bags skip cooldown reads", cooldownReads == 0)
        local group = RikUI.Layout.Groups.bags
        check("the holder registers with the layout under key bags with bottom-right defaults", holder and group
            and group.frames[1] == holder and group.defaults.point == "BOTTOMRIGHT"
            and group.defaults.relativePoint == "BOTTOMRIGHT" and group.defaults.x < 0 and group.defaults.y > 0)
        check("the holder starts hidden, closes on Escape and has the flat border", not holder:IsShown()
            and contains(UISpecialFrames, "RikUIBags") and #holder.rikBorder == 4
            and holder.rikBorder[1].texture == media.border)
        check("every stock container frame and the combined frame are parked", parked(ContainerFrame1)
            and parked(ContainerFrame6) and parked(ContainerFrameCombinedBags) and #module.Parked == 7)
        check("the bag functions are post-hooked, not replaced", contains(env.hooks, "ToggleAllBags")
            and contains(env.hooks, "OpenAllBags") and contains(env.hooks, "CloseAllBags")
            and contains(env.hooks, "ToggleBackpack") and contains(env.hooks, "OpenBag"))
        check("nothing is read from the bags before they open", stub.infoReads == 0 and button(0, 1) == nil)

        ToggleAllBags()
        check("the bag key opens one frame with every slot of every bag", holder:IsShown() and shownButtons() == 22
            and button(0, 16) ~= nil and button(1, 6) ~= nil and button(2, 1) == nil)
        check("bag opening fades and slides without changing its saved anchor", holder.rikEntry.plays == 1
            and holder.rikEntry.animation.kind == "Translation" and holder.rikEntry.animation.offset[2] == 6)
        local originalSlots = C_Container.GetContainerNumSlots
        C_Container.GetContainerNumSlots = function(bag)
            if bag == 1 then error("inventory unavailable") end
            return originalSlots(bag)
        end
        module.Refresh()
        check("failed size read preserves the complete bag grid", shownButtons() == 22 and module.Total == 22)
        for _, invalid in ipairs({ -1, 1.5, 0/0, math.huge, 201, "unknown" }) do
            C_Container.GetContainerNumSlots = function(bag) return bag == 1 and invalid or originalSlots(bag) end
            module.Refresh()
            check("invalid size preserves the complete bag grid", shownButtons() == 22 and module.Total == 22)
        end
        check("unavailable size is reported once", #env.printed == 1)
        env.printed = {}
        C_Container.GetContainerNumSlots = originalSlots
        module.Refresh()
        local cloth, stone, blade, empty = button(0, 1), button(0, 2), button(1, 3), button(0, 3)
        local itemReadsBefore, cooldownBefore = stub.infoReads, cooldownReads
        env.fire("BAG_UPDATE_COOLDOWN")
        check("cooldown event skips item and layout work", stub.infoReads == itemReadsBefore and cooldownReads > cooldownBefore)
        check("buttons come from the Blizzard item template", cloth.kind == "ItemButton" and cloth.template == TEMPLATE)
        check("default store glow is blank for occupied and empty slots", cloth.BattlepayItemTexture.texture == nil
            and empty.BattlepayItemTexture.texture == nil and cloth.NewItemTexture.texture == nil)
        cloth.BattlepayItemTexture:SetAlpha(1)
        module.UpdateButton(cloth)
        check("native glow alpha resets cannot resurrect its art", cloth.BattlepayItemTexture.texture == nil)
        check("semantic item regions and cooldown remain available", cloth.IconQuestTexture and cloth.JunkIcon
            and cloth.Cooldown and rawget(cloth.JunkIcon, "alpha") == nil)
        check("the slot is the button ID and the bag is the parent's ID", cloth:GetID() == 1 and cloth.parent:GetID() == 0
            and blade:GetID() == 3 and blade.parent:GetID() == 1 and blade.parent.parent == holder)
        check("no field Blizzard's item button reads is written", rawget(cloth, "bagID") == nil
            and rawget(cloth, "hasItem") == nil and rawget(cloth, "count") == nil and rawget(cloth, "readable") == nil
            and cloth.attributes.bagid == nil)
        check("items show their icon and a count above one", cloth.rikIcon.texture == 132889 and cloth.rikCount.text == "5"
            and stone.rikIcon.texture == 134414 and stone.rikCount.text == ""
            and cloth.rikCount.fontPath == media.font)
        check("empty slots show no icon or count", empty.rikIcon.texture == nil and empty.rikCount.text == "")
        check("initial inventory does not flash every slot", cloth.rikFlash == nil)
        stub.items["0:1"].quality = 2
        stub.items["0:1"].stackCount = 6
        module.UpdateButton(cloth)
        check("changed item stacks flash once", cloth.rikFlash.plays == 1)
        check("inventory highlight follows item rarity", cloth.rikFlashRegion and color(cloth.rikFlashRegion.color, { 0.12, 1, 0 }))
        stub.items["0:1"].quality = 1
        module.UpdateButton(cloth)
        check("unchanged refresh does not replay the flash", cloth.rikFlash.plays == 1)
        stub.items["0:1"].stackCount = 5
        module.UpdateButton(cloth)
        check("common replacement resets the flash to gold", color(cloth.rikFlashRegion.color, { 1, 0.82, 0 }))
        local flashes = cloth.rikFlash.plays
        local knownCount = stub.items["0:1"].stackCount
        stub.items["0:1"].stackCount = env.SECRET
        module.UpdateButton(cloth)
        check("unknown stack count adds no inventory flash", cloth.rikFlash.plays == flashes)
        stub.items["0:1"].stackCount = knownCount
        module.UpdateButton(cloth)
        check("uncommon and better items get a quality-coloured border", color(blade.rikBorder[1].color, { 0.12, 1, 0 })
            and color(blade.rikBorder[4].color, { 0.12, 1, 0 }))
        check("common items and empty slots keep the neutral border", color(cloth.rikBorder[1].color, { 0.25, 0.28, 0.32 })
            and color(empty.rikBorder[1].color, { 0.25, 0.28, 0.32 }))
        check("slots flow ten to a row across bags", cloth.point[2] == holder.grid and cloth.point[4] == 0
            and cloth.point[5] == 0 and button(0, 10).point[4] == 342 and button(0, 11).point[4] == 0
            and button(0, 11).point[5] == -38 and button(1, 1).point[4] == 228 and button(1, 1).point[5] == -38)
        check("the holder fits the grid and the title counts used slots", holder.width == 394 and holder.height == 260
            and holder.title.text == "Bags 3/22")
        check("the money line shows gold, silver and copper", holder.money.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            == "12g 34s 56c")

        local moneyAPI = GetMoney
        local balance = 123456
        GetMoney = function() return balance end
        balance = balance + 1000; env.fire("PLAYER_MONEY")
        balance = balance - 300; env.fire("PLAYER_MONEY")
        local session = module.MoneySession()
        check("session money tracks income spending and net", session.income == 1000 and session.spent == 300 and session.net == 700)
        balance = env.SECRET; env.fire("PLAYER_MONEY")
        check("unreadable money clears the displayed balance", holder.money.text == "")
        balance = 500; env.fire("PLAYER_MONEY")
        check("money gaps do not invent spending", module.MoneySession().spent == 300 and module.MoneySession().partial)
        balance = 550; env.fire("PLAYER_MONEY")
        check("money observation resumes after a gap", module.MoneySession().income == 1050)
        env.click(holder.moneyButton)
        check("money reset clears only session counters", module.MoneySession().net == 0 and not module.MoneySession().partial)
        GetMoney = moneyAPI
        module.ResetMoneySession()
        check("the search box is Blizzard's bag search box with its art faded", RikUIBagsSearch.template == "BagSearchBoxTemplate"
            and RikUIBagsSearch.Left.alpha == 0 and RikUIBagsSearch.Middle.alpha == 0 and #RikUIBagsSearch.rikBorder == 4)
        typeSearch("LINEN ")
        check("dimmed slots get a dark overlay and the title counts the matches", stone.rikDim.visible == true
            and cloth.rikDim.visible == false and holder.title.text == "Bags 3/22  1 match")
        check("the text goes to Blizzard's bag search trimmed and lower-cased", stub.searchText == "linen")
        check("search dims every slot whose item name does not match", cloth.alpha == 1 and stone.alpha == 0.25
            and blade.alpha == 0.25 and empty.alpha == 0.25)
        typeSearch("")
        check("clearing the search restores every slot", cloth.alpha == 1 and stone.alpha == 1 and blade.alpha == 1
            and empty.alpha == 1)
        typeSearch("[")
        check("search text is matched literally", cloth.alpha == 0.25 and #env.printed == 0
            and holder.title.text == "Bags 3/22  0 matches")
        typeSearch("")
        check("an empty search drops the match count", holder.title.text == "Bags 3/22")

        local preferenceNames = { "SortBagsRightToLeft", "InsertItemsLeftToRight",
            "BackpackAutosortDisabled", "BackpackSellJunkDisabled" }
        for _, preference in ipairs(preferenceNames) do
            local nativeValue, writes = false, 0
            C_Container["Get" .. preference] = function() return nativeValue end
            C_Container["Set" .. preference] = function(value) nativeValue = value; writes = writes + 1 end
            local option
            for _, setting in ipairs(module.Options.settings) do
                if setting.key == preference then option = setting end
            end
            check("native bag preference exposed " .. preference, option ~= nil)
            check("native bag preference read does not write " .. preference, option.get() == false and writes == 0)
            check("native bag preference applies " .. preference, option.set(true) and nativeValue == true and writes == 1)
            env.inCombat = true
            option.set(false)
            check("native bag preference refuses combat " .. preference, nativeValue == true and writes == 1)
            env.inCombat = false
            C_Container["Set" .. preference] = function() end
            check("native bag preference detects refusal " .. preference, not option.set(false))
            nativeValue = env.SECRET
            check("native bag secret preference unavailable " .. preference, option.disabled())
            C_Container["Get" .. preference], C_Container["Set" .. preference] = nil, nil
            check("native bag absent preference unavailable " .. preference, option.disabled())
        end

        local oldMerchant, sold = C_MerchantFrame, 0
        C_MerchantFrame = { GetNumJunkItems = function() return 3 end,
            IsSellAllJunkEnabled = function() return true end,
            SellAllJunkItems = function() sold = sold + 1 end }
        env.fire("MERCHANT_SHOW")
        check("vendor shows junk count without selling automatically", holder.junk:IsShown() and holder.junk.label.text == "Sell junk (3)" and sold == 0)
        env.click(holder.junk)
        check("junk button delegates exactly one native sale", sold == 1)
        env.inCombat = true
        env.click(holder.junk)
        check("combat blocks junk sale", sold == 1)
        env.inCombat = false
        C_MerchantFrame.GetNumJunkItems = function() return env.SECRET end
        env.click(holder.junk)
        check("secret junk count blocks sale", sold == 1)
        env.fire("MERCHANT_CLOSED")
        env.click(holder.junk)
        check("closed merchant hides and refuses junk action", not holder.junk:IsShown() and sold == 1)
        local savedShift = IsShiftKeyDown
        IsShiftKeyDown = function() return false end
        C_MerchantFrame.GetNumJunkItems = function() return 3 end
        RikUI.Profile.bags.autoSellJunk = true
        env.fire("MERCHANT_SHOW"); env.fire("MERCHANT_SHOW"); env.fire("MERCHANT_UPDATE")
        check("automatic junk sells once per visit", sold == 2)
        env.fire("MERCHANT_CLOSED")
        IsShiftKeyDown = function() return true end
        env.fire("MERCHANT_SHOW")
        check("shift skips automatic junk", sold == 2)
        env.click(holder.junk)
        check("shift still permits manual junk sale", sold == 3)
        env.fire("MERCHANT_CLOSED")
        IsShiftKeyDown = function() return false end
        env.inCombat = true; env.fire("MERCHANT_SHOW")
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
        check("combat skips auto sale without deferring it", sold == 3)
        env.fire("MERCHANT_CLOSED")
        IsShiftKeyDown = function() return env.SECRET end
        env.fire("MERCHANT_SHOW"); env.fire("MERCHANT_CLOSED")
        check("unknown modifier skips auto sale", sold == 3)
        IsShiftKeyDown = savedShift
        RikUI.Profile.bags.autoSellJunk = false
        stub.items["0:1"].itemID, stub.items["0:1"].quality = 123, 0
        RikUI.Profile.bags.favorites = "123"
        env.fire("MERCHANT_SHOW")
        local beforeGuard = sold
        module.SellJunk()
        check("favorite junk blocks bulk sale", sold == beforeGuard and holder.junk.enabled == false)
        stub.items["0:1"].quality = env.SECRET
        module.SellJunk()
        check("unknown favorite quality blocks bulk sale", sold == beforeGuard)
        stub.items["0:1"].quality = 1
        module.SellJunk()
        check("readable nonjunk favorites allow bulk sale", sold == beforeGuard + 1)
        stub.items["0:1"].quality = 0
        RikUI.Profile.bags.protectFavorites = false
        module.SellJunk()
        check("explicitly disabled favorite protection allows sale", sold == beforeGuard + 2)
        RikUI.Profile.bags.favorites = ""
        stub.items["0:1"].itemID, stub.items["0:1"].quality = nil, 1
        env.fire("MERCHANT_CLOSED")
        C_MerchantFrame = oldMerchant
        local oldRepair, oldCost, oldCan, oldShift = RepairAllItems, GetRepairAllCost, CanMerchantRepair, IsShiftKeyDown
        local repairs, cost, canRepair, shifted = 0, 50, true, false
        RepairAllItems = function(guild) check("repair uses personal funds", guild == false); repairs = repairs + 1 end
        GetRepairAllCost = function() return cost, true end
        CanMerchantRepair = function() return canRepair end
        IsShiftKeyDown = function() return shifted end
        env.fire("MERCHANT_SHOW"); env.fire("MERCHANT_CLOSED")
        check("automatic repair is opt-in", repairs == 0)
        env.fire("MERCHANT_SHOW")
        check("manual repair button available without automatic spending", holder.repair and holder.repair:IsShown())
        env.click(holder.repair)
        check("manual repair click spends once", repairs == 1)
        env.inCombat = true
        module.Repair()
        check("manual repair refuses combat", repairs == 1)
        env.inCombat = false
        cost = stub.money + 1
        module.Repair()
        check("manual repair refuses insufficient funds", repairs == 1)
        env.fire("MERCHANT_CLOSED")
        cost = 50
        module.Repair()
        check("manual repair refuses closed merchant", repairs == 1 and not holder.repair:IsShown())
        repairs = 0
        RikUI.Profile.bags.autoRepair = true
        env.fire("MERCHANT_SHOW"); env.fire("MERCHANT_SHOW"); env.fire("MERCHANT_CLOSED")
        check("opening merchant repairs once", repairs == 1)
        cost = stub.money + 1
        env.fire("MERCHANT_SHOW"); env.fire("MERCHANT_CLOSED")
        check("unaffordable repairs are skipped", repairs == 1)
        cost, shifted = 10, true
        env.fire("MERCHANT_SHOW"); env.fire("MERCHANT_CLOSED")
        check("shift bypasses automatic repair", repairs == 1)
        shifted, cost = false, env.SECRET
        env.fire("MERCHANT_SHOW"); env.fire("MERCHANT_CLOSED")
        check("unreadable repair costs never spend", repairs == 1)
        RikUI.Profile.bags.autoRepair = false
        do
            local oldGuildCan, oldGuildMoney, oldGuildLimit = CanGuildBankRepair, GetGuildBankMoney, GetGuildBankWithdrawMoney
            local permission, bank, allowance, funding = true, 1000, 100, {}
            CanGuildBankRepair = function() return permission end
            GetGuildBankMoney = function() return bank end
            GetGuildBankWithdrawMoney = function() return allowance end
            RepairAllItems = function(guild) funding[#funding + 1] = guild end
            RikUI.Profile.bags.repairGuild = true
            cost = 50
            env.fire("MERCHANT_SHOW")
            module.RefreshRepair(); module.Repair()
            check("guild repair preference uses guild money", funding[1] == true and holder.repair.label.text == "Guild repair")
            allowance = 10; module.Repair()
            check("low guild allowance falls back to personal funds", funding[2] == false)
            allowance = -1; module.Repair()
            check("unlimited guild allowance is supported", funding[3] == true)
            bank = env.SECRET; module.Repair()
            check("opaque guild balance falls back to personal funds", funding[4] == false)
            bank, permission, cost = 1000, false, stub.money + 1
            module.Repair()
            check("no affordable funding refuses repair", #funding == 4)
            cost, permission = 50, true
            RepairAllItems = function() error("guild request failed") end
            module.Repair()
            check("failed guild repair is reported without fallback spending", printedContains("guild request failed"))
            env.fire("MERCHANT_CLOSED")
            RikUI.Profile.bags.repairGuild = false
            CanGuildBankRepair, GetGuildBankMoney, GetGuildBankWithdrawMoney = oldGuildCan, oldGuildMoney, oldGuildLimit
        end
        RepairAllItems, GetRepairAllCost, CanMerchantRepair, IsShiftKeyDown = oldRepair, oldCost, oldCan, oldShift
        env.printed = {}
        local oldNew, marked = C_NewItems, true
        C_NewItems = { IsNewItem = function(bag, slot) return marked and bag == 0 and slot == 1 end,
            RemoveNewItem = function(bag, slot) if bag == 0 and slot == 1 then marked = false end end }
        module.Refresh()
        check("new loot has a compact marker", cloth.rikNew.visible and not stone.rikNew.visible)
        check("new-loot filter exists", holder.filters.new ~= nil)
        env.click(holder.filters.new)
        check("new-loot filter isolates newly acquired items", cloth.alpha == 1 and stone.alpha == 0.25
            and holder.title.text == "Bags 3/22  1 match")
        env.runScript(cloth, "OnEnter")
        check("acknowledgement refreshes active filter and count", cloth.alpha == 0.25
            and holder.title.text == "Bags 3/22  0 matches")
        env.click(holder.filters.all)
        check("hover acknowledges native new-item status", not marked and not cloth.rikNew.visible)
        C_NewItems.IsNewItem = function() return env.SECRET end
        module.Refresh()
        check("secret new-item status hides the badge", not cloth.rikNew.visible)
        C_NewItems = nil
        module.Refresh()
        check("missing new-item API is optional", not cloth.rikNew.visible)
        C_NewItems = oldNew
        local oldFree = C_Container.GetContainerNumFreeSlots
        C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 2 or 4, bag == 0 and 0 or 1 end
        module.Refresh()
        check("capacity separates general from specialized slots", holder.capacity.text == "2 free (+16 special)")
        C_Container.GetContainerNumFreeSlots = function() return 0, 0 end
        env.fire("BAG_UPDATE_DELAYED")
        check("full bags display an explicit warning", holder.capacity.text == "Bags full")
        C_Container.GetContainerNumFreeSlots = function() return env.SECRET, 0 end
        module.Refresh()
        check("unreadable capacity is not called free space", holder.capacity.text == "Space unavailable")
        C_Container.GetContainerNumFreeSlots = oldFree
        local oldInstant = C_Item.GetItemInfoInstant
        C_Item.GetItemInfoInstant = function(link)
            local class = link:find("Linen", 1, true) and 7 or (link:find("Hearth", 1, true) and 0 or 2)
            return 1, "", "", "", 1, class
        end
        module.Refresh()
        check("materials filter is available", holder.filters.materials ~= nil)
        env.click(holder.filters.materials)
        check("materials selects cloth and dims gear and empty slots", cloth.alpha == 1 and blade.alpha == 0.25 and empty.alpha == 0.25)
        typeSearch("Hearth")
        check("materials intersects text search", cloth.alpha == 0.25 and stone.alpha == 0.25)
        typeSearch("")
        env.click(holder.filters.gear)
        check("gear filter dims non-equipment and empty slots", blade.alpha == 1 and cloth.alpha == 0.25 and empty.alpha == 0.25)
        typeSearch("Hearth")
        check("text search intersects quick filters", blade.alpha == 0.25 and stone.alpha == 0.25)
        env.click(holder.filters.use)
        check("consumable filter combines with text search", stone.alpha == 1 and blade.alpha == 0.25)
        typeSearch("")
        stub.items["0:1"].quality = 0
        module.Refresh()
        env.click(holder.filters.junk)
        check("junk filter uses item quality", cloth.alpha == 1 and stone.alpha == 0.25)
        stub.items["0:1"].quality = env.SECRET
        module.Refresh()
        check("secret quality never matches junk", cloth.alpha == 0.25)
        stub.items["0:1"].quality = 1
        C_Item.GetItemInfoInstant = function() return 1, "", "", "", 1, 12 end
        module.Refresh()
        env.click(holder.filters.quest)
        check("quest category finds quest items", cloth.alpha == 1 and empty.alpha == 0.25)
        C_Item.GetItemInfoInstant = oldInstant
        env.click(holder.filters.all)
        check("all restores every slot", blade.alpha == 1 and empty.alpha == 1)
        C_Item.GetItemInfoInstant = function(link) return 1, "", "", "", 1, link:find("Blade") and 2 or 7 end
        module.Refresh()
        typeSearch("type:gear q:uncommon blade")
        check("combined selectors find matching gear", blade.alpha == 1 and cloth.alpha == 0.25)
        do
            local oldLevel = C_Item.GetDetailedItemLevelInfo
            C_Item.GetDetailedItemLevelInfo = function() return 42 end
            RikUI.Profile.bags.itemLevels = true
            module.Refresh()
            check("gear shows readable item level", blade.rikLevel and blade.rikLevel.text == "42")
            check("materials do not show gear levels", cloth.rikLevel and cloth.rikLevel.text == "")
            C_Item.GetDetailedItemLevelInfo = function() return env.SECRET end
            module.Refresh()
            check("unreadable item level clears stale label", blade.rikLevel and blade.rikLevel.text == "")
            C_Item.GetDetailedItemLevelInfo = function() return 42 end
            RikUI.Profile.bags.itemLevels = false
            module.Refresh()
            check("item level option hides labels", blade.rikLevel and blade.rikLevel.text == "")
            C_Item.GetDetailedItemLevelInfo = oldLevel
        end
        typeSearch("type:gear !blade")
        check("negative literal excludes a matching item", blade.alpha == 0.25)
        stub.items["1:3"].itemID = 123
        module.Refresh()
        typeSearch("id:123")
        check("item ID selector finds exact item", blade.alpha == 1 and cloth.alpha == 0.25)
        check("favorite command is registered", RikUI:HasCommand("favorite"))
        if module.ToggleFavorite then
            local savedFavorites = RikUI.Profile.bags.favorites
            check("favorite accepts an item link", module.ToggleFavorite("|cffffffff|Hitem:123:0|h[Blade]|h|r"))
            typeSearch(""); env.click(holder.filters.favorites)
            check("favorites filter selects by identity", blade.alpha == 1 and cloth.alpha == 0.25)
            check("favorite marker is visible", blade.rikFavorite and blade.rikFavorite.text == "F")
            typeSearch("!blade")
            check("favorites combine with exclusions", blade.alpha == 0.25)
            env.click(holder.filters.all); typeSearch("type:favorites")
            check("favorites are available as a search selector", blade.alpha == 1 and cloth.alpha == 0.25)
            check("invalid favorite input is rejected", not module.ToggleFavorite("0") and not module.ToggleFavorite("1.5"))
            module.ToggleFavorite("123")
            check("toggling favorite removes it", not module.IsFavorite(123) and blade.alpha == 0.25)
            RikUI.Profile.bags.favorites = "123,456"
            module.Refresh()
            check("saved favorite IDs are restored", module.IsFavorite(123) and module.IsFavorite(456))
            RikUI.Profile.bags.favorites = savedFavorites
            typeSearch(""); module.Refresh()
        end
        typeSearch("q:common !hearth")
        check("quality and exclusion combine", cloth.alpha == 1 and stone.alpha == 0.25)
        typeSearch("q:invalid")
        check("unknown quality cannot match", cloth.alpha == 0.25 and blade.alpha == 0.25)
        typeSearch("!q:invalid")
        check("negated invalid selector cannot match", cloth.alpha == 0.25 and blade.alpha == 0.25)
        typeSearch("type:gear [")
        check("structured literal punctuation is not a pattern", blade.alpha == 0.25)
        C_Item.GetItemInfoInstant = oldInstant
        typeSearch("")
        env.click(holder.sort)
        check("the sort button calls C_Container.SortBags", stub.sorted == 1)
        env.inCombat = true; env.fire("PLAYER_REGEN_DISABLED")
        check("sort button disables during combat", holder.sort.enabled == false)
        module.Sort()
        check("combat sort neither executes nor queues", stub.sorted == 1 and RikUI.Combat.Pending() == 0)
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
        stub.cursor = { icon = 777 }; env.fire("CURSOR_CHANGED")
        check("held item disables sorting", holder.sort.enabled == false)
        module.Sort()
        check("sort leaves cursor item untouched", stub.sorted == 1 and stub.cursor.icon == 777)
        stub.cursor = nil; env.fire("CURSOR_CHANGED")
        check("clearing cursor re-enables sort without executing it", holder.sort.enabled == true and stub.sorted == 1)
        local cursorReader = CursorHasItem
        CursorHasItem = function() return env.SECRET end
        module.Sort()
        check("unreadable cursor blocks sort", stub.sorted == 1)
        CursorHasItem = cursorReader
        env.printed = {}
        stub.items["0:1"], stub.items["0:3"] = nil, { iconFileID = 132889, stackCount = 20, quality = 1,
            hyperlink = stub.link("Linen Cloth") }
        env.fire("BAG_UPDATE_DELAYED")
        check("BAG_UPDATE_DELAYED redraws the grid", cloth.rikIcon.texture == nil and empty.rikIcon.texture == 132889
            and empty.rikCount.text == "20")
        stub.items["0:3"].isLocked = true
        local lockReads, lockCooldowns = stub.infoReads, cooldownReads
        env.fire("ITEM_LOCK_CHANGED", 0, 3)
        check("lock changes read only their slot and skip cooldowns", stub.infoReads == lockReads + 1
            and cooldownReads == lockCooldowns)
        lockReads = stub.infoReads
        env.fire("ITEM_LOCK_CHANGED", 20)
        env.fire("ITEM_LOCK_CHANGED", -1, 3)
        env.fire("ITEM_LOCK_CHANGED", env.SECRET, 3)
        env.fire("ITEM_LOCK_CHANGED", 0, env.SECRET)
        env.fire("ITEM_LOCK_CHANGED", 0, 0/0)
        env.fire("ITEM_LOCK_CHANGED", 0, 999)
        check("noninventory or unreadable lock events do no item reads", stub.infoReads == lockReads)
        check("a locked item is desaturated", empty.rikIcon.desaturated == true and stone.rikIcon.desaturated == false)
        stub.items["0:3"].isLocked = env.SECRET
        env.fire("ITEM_LOCK_CHANGED", 0, 3)
        check("unreadable lock clears stale shading", empty.rikIcon.desaturated == false)
        stub.items["0:3"].isLocked = false
        env.fire("ITEM_LOCK_CHANGED", 0, 3)
        check("unlock updates its slot", empty.rikIcon.desaturated == false)
        stub.cooldowns["0:2"] = { 100, 3600 }
        env.fire("BAG_UPDATE_COOLDOWN")
        check("an item on cooldown drives the template's cooldown frame", stone.Cooldown.start == 100
            and stone.Cooldown.duration == 3600 and rawget(empty.Cooldown, "duration") == nil)
        stub.cooldowns["0:2"] = nil
        env.fire("BAG_UPDATE_COOLDOWN")
        check("a finished cooldown is cleared", rawget(stone.Cooldown, "duration") == nil)
        do
            local reader = C_Container.GetContainerItemCooldown
            local failures = {
                function() error("cooldown unavailable") end,
                function() return env.SECRET, 10, 1 end,
                function() return 1, math.huge, 1 end,
                function() return 0/0, 10, 1 end,
                function() return -1, 10, 1 end,
                function() return 1, 10, env.SECRET end,
                function() return 1, 10, nil end,
                function() return 1, 10, 0 end,
            }
            for index, failing in ipairs(failures) do
                stone.Cooldown:SetCooldown(100, 3600)
                C_Container.GetContainerItemCooldown = failing
                local refreshed = pcall(module.UpdateButton, stone)
                check("unavailable cooldown clears stale swipe " .. index, refreshed and rawget(stone.Cooldown, "duration") == nil)
            end
            C_Container.GetContainerItemCooldown = function() return 200, 90, 1 end
            module.UpdateButton(stone)
            check("cooldown recovers on readable data", stone.Cooldown.start == 200 and stone.Cooldown.duration == 90)
            local item = stub.items["0:2"]
            stub.items["0:2"] = nil
            module.UpdateButton(stone)
            check("empty item never retains a cooldown", rawget(stone.Cooldown, "duration") == nil)
            stub.items["0:2"] = item
            C_Container.GetContainerItemCooldown = reader
        end
        stub.money = 99
        env.fire("PLAYER_MONEY")
        check("PLAYER_MONEY rewrites the money line without empty units",
            holder.money.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") == "99c")

        stub.slots[1] = 4
        env.fire("BAG_UPDATE_DELAYED")
        check("a smaller bag hides its surplus buttons", shownButtons() == 20 and not button(1, 5):IsShown()
            and holder.title.text == "Bags 3/20" and holder.height == 222)
        stub.items["0:2"] = env.SECRET
        env.fire("BAG_UPDATE_DELAYED")
        check("a secret item record draws an empty slot without printing", stone.rikIcon.texture == nil
            and #env.printed == 0)
        stub.infoError = "bags unavailable"
        env.fire("BAG_UPDATE_DELAYED")
        env.fire("BAG_UPDATE_DELAYED")
        check("a failing item read is reported once and contained", printedContains("Bags items") and #env.printed == 1)
        stub.infoError = nil

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports the holder state and samples",
            printedContains("Bags holder=true parked=7 slots=20 open=true search=\"\" dimmed=0")
            and printedContains("bags.GetContainerNumSlots(0)"))

        typeSearch("blade")
        ToggleAllBags()
        check("the bag key closes the frame again", not holder:IsShown() and not ContainerFrame1:IsShown())
        check("closing clears the search", RikUIBagsSearch.text == "" and blade.alpha == 1 and stone.alpha == 1
            and stub.searchText == "")
        local reads = stub.infoReads
        check("capacity HUD exists outside bag window", module.CapacityHUD and module.CapacityHUD.parent == UIParent
            and module.CapacityHUD:IsShown() and RikUI.Layout.Groups.bagspace)
        local capacityReader = C_Container.GetContainerNumFreeSlots
        C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 3 or 0, 0 end
        env.fire("BAG_UPDATE_DELAYED")
        check("closed bag HUD updates without item reads", module.CapacityHUD and module.CapacityHUD.label.text == "3 free"
            and stub.infoReads == reads)
        C_Container.GetContainerNumFreeSlots = function() return math.huge, 0 end
        env.fire("BAG_UPDATE_DELAYED")
        check("infinite capacity is unavailable", module.CapacityHUD and module.CapacityHUD.label.text == "Space unavailable")
        RikUI.Profile.bags.capacityLowOnly = true
        RikUI.Profile.bags.capacityThreshold = 3
        C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 4 or 0, 0 end
        module.UpdateCapacity()
        check("low-space HUD hides above threshold", not module.CapacityHUD:IsShown())
        C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 3 or 0, 0 end
        module.UpdateCapacity()
        check("low-space HUD shows at threshold", module.CapacityHUD:IsShown())
        C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 0 or 16, bag == 0 and 0 or 1 end
        module.UpdateCapacity()
        check("specialized slots cannot hide low general space", module.CapacityHUD:IsShown())
        C_Container.GetContainerNumFreeSlots = function() return env.SECRET, 0 end
        module.UpdateCapacity()
        check("unknown capacity remains visible in alert mode", module.CapacityHUD:IsShown())
        RikUI.Profile.bags.capacityThreshold = math.huge
        check("invalid saved capacity threshold falls back", module.CapacityThreshold() == 4)
        local threshold
        for _, option in ipairs(module.Options.settings) do if option.key == "capacityThreshold" then threshold = option end end
        check("capacity threshold rejects invalid input", not threshold.set(-1) and not threshold.set(0/0))
        check("capacity threshold accepts zero", threshold.set(0) and module.CapacityThreshold() == 0)
        RikUI.Profile.bags.capacityLowOnly, RikUI.Profile.bags.capacityThreshold = false, 4
        RikUI.Profile.bags.capacityHUD = false; module.UpdateCapacity()
        check("capacity HUD can be hidden", module.CapacityHUD and not module.CapacityHUD:IsShown())
        RikUI.Profile.bags.capacityHUD = true
        C_Container.GetContainerNumFreeSlots = capacityReader
        env.click(module.CapacityHUD)
        check("capacity HUD opens inventory through native toggle", holder:IsShown())
        CloseAllBags()
        reads = stub.infoReads
        env.fire("BAG_UPDATE_DELAYED")
        check("a closed frame ignores bag events", stub.infoReads == reads)

        OpenBag(1)
        check("opening a single bag shows the whole frame", holder:IsShown())
        stub.closeAllCalls = 0
        holder:Hide()
        check("hiding the frame, as Escape does, closes Blizzard's bags too", stub.closeAllCalls == 1
            and not ContainerFrame2:IsShown())
        OpenAllBags()
        env.click(holder.close)
        check("the close button closes both", not holder:IsShown() and not ContainerFrame1:IsShown())
        ToggleBackpack()
        check("the backpack binding opens the frame", holder:IsShown())

        check("the frame drags by itself with the left button", holder.movable == true
            and holder.dragButton == "LeftButton" and not RikUI.Layout.IsMoving())
        env.runScript(holder, "OnDragStart")
        check("a drag starts without /rik move", holder.moving == true)
        holder.centerX, holder.centerY = 700, 250
        env.runScript(holder, "OnDragStop")
        local dropped = RikUIDB.profiles.Default.positions.bags
        check("the drop is saved in the profile relative to the screen centre", holder.moving == false
            and type(dropped) == "table" and dropped.point == "CENTER" and dropped.relativePoint == "CENTER"
            and dropped.x == 300 and dropped.y == -50)
        check("the saved position is applied back through the layout", holder.point[1] == "CENTER"
            and holder.point[2] == UIParent and holder.point[4] == 300 and holder.point[5] == -50)
        env.runScript(holder, "OnDragStart")
        holder.centerX, holder.centerY = nil, nil
        env.runScript(holder, "OnDragStop")
        check("a drop without a readable position keeps the last one and says so", holder.moving == false
            and RikUIDB.profiles.Default.positions.bags.x == 300 and printedContains("Bags position"))
        env.printed = {}
        env.runScript(holder, "OnDragStart")
        holder:Hide()
        check("closing the frame ends an unfinished drag", holder.moving == false)
        CloseAllBags()

        module = load({ positions = { bags = { point = "CENTER", relativePoint = "CENTER", x = 300, y = -50 } } })
        check("a saved position is used at the next login", module.Holder.point[1] == "CENTER"
            and module.Holder.point[4] == 300 and module.Holder.point[5] == -50)

        module = load()
        OpenAllBags()
        local columns
        for _, setting in ipairs(module.Options.settings) do
            if setting.key == "columns" then columns = setting end
        end
        check("bag columns setting exists", columns ~= nil)
        columns.set(12)
        check("wider grid reduces rows without replacing item buttons", module.Holder.width == 470
            and button(0, 13).point[4] == 0 and button(0, 13).point[5] == -38
            and button(0, 1):GetID() == 1 and RikUI.Profile.bags.columns == 12)
        env.inCombat = true
        columns.set(14)
        env.fire("BAG_UPDATE_DELAYED")
        check("combat keeps prior column geometry", module.Holder.width == 470)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("queued columns apply after combat", module.Holder.width == 546)
        columns.set(0/0)
        check("invalid column count is rejected", RikUI.Profile.bags.columns == 14)
        columns.set(1)
        check("minimum width fits the header", module.Holder.width == 394)
        columns.set(100)
        check("column count is bounded", module.Holder.width == 622)
        module = load({ bags = { columns = 12 } })
        OpenAllBags()
        check("column preference survives reload", module.Holder.width == 470)

        module = load(nil, true)
        check("a combat login builds the holder and queues the parking", module.Holder ~= nil
            and ContainerFrame1.parent == ContainerFrameContainer)
        OpenAllBags()
        check("the frame opens in combat", module.Holder:IsShown() and shownButtons() == 22)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat parks the stock frames", parked(ContainerFrame1) and parked(ContainerFrameCombinedBags))

        module = load(nil, false, function() stub.templateMissing = true end)
        OpenAllBags()
        OpenAllBags()
        check("a missing item template prints one line", printedContains("Bags buttons") and #env.printed == 1)

        module = load(nil, false, function() C_Container.SortBags = function() error("sort failed") end end)
        OpenAllBags()
        check("sort API exceptions stay inside callback", pcall(module.Sort))
        check("sort API exception is reported", printedContains("sort failed"))

        module = load(nil, false, function() C_Container.SortBags = nil end)
        OpenAllBags()
        env.click(module.Holder.sort)
        check("a client without SortBags prints one line", printedContains("Bags sort") and #env.printed == 1)

        module = load(nil, false, function() stub.searchTemplateMissing = true end)
        OpenAllBags()
        typeSearch("hearth")
        check("a client without the search template gets a plain box that still searches",
            RikUIBagsSearch.template == nil and button(0, 2).alpha == 1 and button(0, 1).alpha == 0.25
            and #env.printed == 0)

        module = load(nil, false, function() C_Container.SetItemSearch = nil end)
        OpenAllBags()
        typeSearch("Hearth")
        check("a client without SetItemSearch matches on the item name", button(0, 2).alpha == 1
            and button(0, 1).alpha == 0.25 and button(0, 3).alpha == 0.25 and #env.printed == 0)
        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug names the search text and how many slots it dims", printedContains("search=\"hearth\" dimmed=21"))

        module = load(nil, false, function() C_Container.SetItemSearch = function() error("search unavailable") end end)
        OpenAllBags()
        typeSearch("Hearth")
        check("failed native search falls back to readable names", button(0, 2).alpha == 1 and button(0, 1).alpha == 0.25)
        typeSearch("[")
        check("failed native search fallback is literal", button(0, 2).alpha == 0.25)
        module = load(nil, false, function() C_Container.SetItemSearch = function() return false end end)
        OpenAllBags()
        stub.items["0:1"].isFiltered, stub.items["0:2"].isFiltered = env.SECRET, nil
        typeSearch("Hearth")
        module.Refresh()
        check("refused search and opaque flags fall back to names", button(0, 2).alpha == 1 and button(0, 1).alpha == 0.25)

        check("search failures only warn once", printedContains("Bags search") and #env.printed == 1)
        C_Container.SetItemSearch = function() end
        typeSearch("Hearth")
        module.Refresh()
        check("accepted search with unreadable flags uses names", button(0, 2).alpha == 1 and button(0, 1).alpha == 0.25)
        stub.items["0:1"].isFiltered, stub.items["0:2"].isFiltered = false, true
        module.Refresh()
        check("readable native flags take precedence over name fallback", button(0, 1).alpha == 1 and button(0, 2).alpha == 0.25)
        typeSearch("")
        check("clearing fallback search restores empty slots", button(0, 3).alpha == 1)

        module = load(nil, false, function() ContainerFrameCombinedBags = nil end)
        check("an absent combined frame is skipped", #module.Parked == 6)

        module = load()
        OpenAllBags()
        local first, fourth = module.Holder.equipped[1], module.Holder.equipped[4]
        check("four equipped targets show capacity and empty slots", #module.Holder.equipped == 4
            and first.icon.texture == 133634 and first.count.text == "6" and fourth.count.text == "+")
        stub.cursor = { icon = 777, size = 12 }
        env.runScript(first, "OnReceiveDrag")
        check("dropping a bag swaps the chosen inventory slot and resizes the grid", stub.equips[1] == 20
            and stub.cursor.icon == 133634 and first.icon.texture == 777 and first.count.text == "12"
            and module.Total == 28)
        stub.cursor = { icon = 888, size = 8 }
        env.click(fourth)
        check("cursor click equips into an empty target", stub.equips[2] == 23 and stub.cursor == nil
            and fourth.icon.texture == 888 and fourth.count.text == "8")
        env.click(fourth)
        check("empty-cursor clicks do not unequip bags", #stub.equips == 2)
        stub.cursor, stub.rejectSwap = { icon = 999, size = 1 }, true
        env.runScript(first, "OnReceiveDrag")
        check("a rejected replacement stays on cursor and keeps equipped contents", stub.cursor.icon == 999
            and first.icon.texture == 777 and first.count.text == "12")
        stub.cursor, stub.rejectSwap = nil, false
        env.runScript(first, "OnDragStart")
        check("dragging an equipped bag uses its inventory slot", stub.pickups[1] == 20 and stub.cursor.icon == 777)
        env.inCombat = true
        local calls = #stub.equips
        env.runScript(fourth, "OnReceiveDrag"); env.runScript(fourth, "OnDragStart")
        check("combat refuses swaps and pickups without clearing the cursor", #stub.equips == calls
            and #stub.pickups == 1 and stub.cursor.icon == 777 and printedContains("after combat"))
        env.inCombat = false
        C_Container.ContainerIDToInventoryID = nil
        env.runScript(first, "OnReceiveDrag")
        check("inventory slot names provide the mapping fallback", stub.equips[#stub.equips] == 20)
        PickupBagFromSlot = nil
        local beforeMissingPickup = #stub.equips
        env.runScript(fourth, "OnDragStart")
        check("missing pickup API never falls through to depositing an item", #stub.equips == beforeMissingPickup)
        PutItemInBag = nil
        stub.cursor = { icon = 666, size = 2 }
        env.runScript(first, "OnReceiveDrag")
        check("missing replacement API keeps cursor and reports availability", stub.cursor.icon == 666
            and printedContains("bag replacement unavailable"))

        module = load()
        OpenAllBags()
        SlashCmdList.RIKUI("bagsearch save cloth q:common linen")
        check("named search persists query", RikUI.Profile.bags.searches and RikUI.Profile.bags.searches.cloth == "q:common linen")
        CloseAllBags()
        SlashCmdList.RIKUI("bagsearch use cloth")
        check("recall opens bags and applies query", module.Holder:IsShown() and button(0, 1).alpha == 1 and button(0, 2).alpha == 0.25)
        SlashCmdList.RIKUI("bagsearch save bad " .. string.rep("a", 257))
        check("oversized query rejected", not (RikUI.Profile.bags.searches and RikUI.Profile.bags.searches.bad))
        for i = 1, 8 do SlashCmdList.RIKUI("bagsearch save s" .. i .. " hearth") end
        local savedCount = 0
        for _ in pairs(RikUI.Profile.bags.searches or {}) do savedCount = savedCount + 1 end
        check("saved searches capped at eight", savedCount == 8)
        SlashCmdList.RIKUI("bagsearch delete cloth")
        check("saved search can be deleted", RikUI.Profile.bags.searches and RikUI.Profile.bags.searches.cloth == nil)
        check("shared searches validate bounds", not pcall(RikUI.ProfileSchema.Project, {bags={searches={bad=string.rep("x",257)}}}))
        module = load({ bags = { searches = { cloth = "linen" } } })
        SlashCmdList.RIKUI("bagsearch use cloth")
        check("named search survives profile reload", module.Holder:IsShown() and button(0, 1).alpha == 1 and button(0, 2).alpha == 0.25)

        module = load()
        OpenAllBags()
        typeSearch("count:>=5")
        check("stack threshold finds material stacks", button(0, 1).alpha == 1 and button(0, 2).alpha == 0.25)
        typeSearch("count:<5 !hearth")
        check("numeric comparison combines exclusions", button(0, 1).alpha == 0.25 and button(1, 3).alpha == 1)
        local oldLevel = C_Item.GetDetailedItemLevelInfo
        C_Item.GetDetailedItemLevelInfo = function(link) return link:find("Blade") and 23 or nil end
        module.Refresh()
        typeSearch("level:>=20")
        check("item level search works without level badges", button(1, 3).alpha == 1 and button(0, 1).alpha == 0.25)
        typeSearch("!level:>=20")
        check("unknown level cannot match negated comparison", button(0, 1).alpha == 0.25)
        stub.items["1:3"].stackCount = env.SECRET
        module.Refresh()
        typeSearch("!count:1")
        check("opaque counts never match exclusions", button(1, 3).alpha == 0.25)
        typeSearch("count:=>5")
        check("malformed operator matches nothing", button(0, 1).alpha == 0.25)
        C_Item.GetDetailedItemLevelInfo = oldLevel

        module = load()
        local questInfo = { isQuestItem = false, questID = 42, isActive = false }
        C_Container.GetContainerItemQuestInfo = function(bag, slot)
            if bag == 0 and slot == 1 then return questInfo end
            return { isQuestItem = false, isActive = false }
        end
        OpenAllBags()
        module.SetFilter("quest")
        check("quest starters join quest filter", button(0, 1).alpha == 1 and button(0, 2).alpha == 0.25)
        check("inactive quest item carries exclamation", button(0, 1).rikQuestStart and button(0, 1).rikQuestStart.text == "!")
        questInfo.isActive = true
        env.fire("QUEST_LOG_UPDATE")
        check("accepting quest clears starter marker", button(0, 1).rikQuestStart and button(0, 1).rikQuestStart.text == "")
        questInfo.isActive, questInfo.questID = false, env.SECRET
        module.Refresh()
        check("protected quest id never gets a marker", button(0, 1).rikQuestStart and button(0, 1).rikQuestStart.text == "")
        questInfo.questID = 0
        module.Refresh()
        check("zero quest sentinel is not a starter", button(0, 1).alpha == 0.25)
        questInfo.questID = 42
        module.Refresh()
        stub.items["0:1"] = nil
        module.Refresh()
        check("empty slot clears starter marker", button(0, 1).rikQuestStart and button(0, 1).rikQuestStart.text == "")

        module = load({ modules = { bags = false } })
        OpenAllBags()
        check("a disabled module leaves the Blizzard bags alone", module.Holder == nil
            and ContainerFrame1.parent == ContainerFrameContainer and ContainerFrame1:IsShown() and #env.hooks == 0
            and RikUI.Layout.Groups.bags == nil and RikUIBags == nil)
    end)
    CreateFrame = originalCreate
    C_Item.GetItemQualityColor = savedQualityColor
    UIParent.GetCenter, UIParent.GetEffectiveScale = savedCenter, savedScale
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat = false
    check("bags suite completes", ok, reason)
end
