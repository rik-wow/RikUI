-- The stub cannot show taint: the suite proves the bag travels in the parent's ID and that no field
-- Blizzard's item button reads is written. Item use, selling and rendering need a beta check.
return function(check)
    local env = require("wow_stub")
    local stub = require("bags_stub")
    local originalCreate = CreateFrame
    local TEMPLATE = "ContainerFrameItemButtonTemplate"
    local API = { "C_Container", "GetMoney", "UISpecialFrames", "ContainerFrameContainer", "ContainerFrameCombinedBags",
        "OpenBag", "CloseBag", "ToggleBag", "OpenBackpack", "CloseBackpack", "ToggleBackpack", "OpenAllBags",
        "CloseAllBags", "ToggleAllBags" }
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
        capitalOnly(frame)
        function frame:SetParent(value)
            assert(not InCombatLockdown(), "frame reparented in combat")
            self.parent = value
        end
        function frame:GetParent() return self.parent end
        function frame:SetID(id) self.id = id end
        function frame:GetID() return self.id or 0 end
        function frame:SetSize(w, h) self.width, self.height = w, h end
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
        if template == TEMPLATE then frame.Cooldown = cooldown(frame) end
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
        for _, file in ipairs({ "core.lua", "hide.lua", "media.lua", "setup.lua", "setup-apply.lua", "layout-geometry.lua", "layout.lua", "layout-rects.lua",
            "motion.lua", "skin.lua", "layout-unlock.lua", "layout-drag.lua", "unitframes.lua", "unitframes-status.lua", "bags.lua", "bags-items.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.Bags
    end
    local ok, reason = pcall(function()
        local module = load()
        local media, holder = RikUI.Media, module.Holder
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
        local cloth, stone, blade, empty = button(0, 1), button(0, 2), button(1, 3), button(0, 3)
        check("buttons come from the Blizzard item template", cloth.kind == "ItemButton" and cloth.template == TEMPLATE)
        check("the slot is the button ID and the bag is the parent's ID", cloth:GetID() == 1 and cloth.parent:GetID() == 0
            and blade:GetID() == 3 and blade.parent:GetID() == 1 and blade.parent.parent == holder)
        check("no field Blizzard's item button reads is written", rawget(cloth, "bagID") == nil
            and rawget(cloth, "hasItem") == nil and rawget(cloth, "count") == nil and rawget(cloth, "readable") == nil
            and cloth.attributes.bagid == nil)
        check("items show their icon and a count above one", cloth.rikIcon.texture == 132889 and cloth.rikCount.text == "5"
            and stone.rikIcon.texture == 134414 and stone.rikCount.text == ""
            and cloth.rikCount.fontPath == media.font)
        check("empty slots show no icon or count", empty.rikIcon.texture == nil and empty.rikCount.text == "")
        check("uncommon and better items get a quality-coloured border", color(blade.rikBorder[1].color, { 0.12, 1, 0 })
            and color(blade.rikBorder[4].color, { 0.12, 1, 0 }))
        check("common items and empty slots keep the neutral border", color(cloth.rikBorder[1].color, { 0.25, 0.28, 0.32 })
            and color(empty.rikBorder[1].color, { 0.25, 0.28, 0.32 }))
        check("slots flow ten to a row across bags", cloth.point[2] == holder.grid and cloth.point[4] == 0
            and cloth.point[5] == 0 and button(0, 10).point[4] == 342 and button(0, 11).point[4] == 0
            and button(0, 11).point[5] == -38 and button(1, 1).point[4] == 228 and button(1, 1).point[5] == -38)
        check("the holder fits the grid and the title counts used slots", holder.width == 394 and holder.height == 170
            and holder.title.text == "Bags 3/22")
        check("the money line shows gold, silver and copper", holder.money.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            == "12g 34s 56c")

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

        env.click(holder.sort)
        check("the sort button calls C_Container.SortBags", stub.sorted == 1)
        stub.items["0:1"], stub.items["0:3"] = nil, { iconFileID = 132889, stackCount = 20, quality = 1,
            hyperlink = stub.link("Linen Cloth") }
        env.fire("BAG_UPDATE_DELAYED")
        check("BAG_UPDATE_DELAYED redraws the grid", cloth.rikIcon.texture == nil and empty.rikIcon.texture == 132889
            and empty.rikCount.text == "20")
        stub.items["0:3"].isLocked = true
        env.fire("ITEM_LOCK_CHANGED", 0, 3)
        check("a locked item is desaturated", empty.rikIcon.desaturated == true and stone.rikIcon.desaturated == false)
        stub.cooldowns["0:2"] = { 100, 3600 }
        env.fire("BAG_UPDATE_COOLDOWN")
        check("an item on cooldown drives the template's cooldown frame", stone.Cooldown.start == 100
            and stone.Cooldown.duration == 3600 and rawget(empty.Cooldown, "duration") == nil)
        stub.cooldowns["0:2"] = nil
        env.fire("BAG_UPDATE_COOLDOWN")
        check("a finished cooldown is cleared", rawget(stone.Cooldown, "duration") == nil)
        stub.money = 99
        env.fire("PLAYER_MONEY")
        check("PLAYER_MONEY rewrites the money line without empty units",
            holder.money.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") == "99c")

        stub.slots[1] = 4
        env.fire("BAG_UPDATE_DELAYED")
        check("a smaller bag hides its surplus buttons", shownButtons() == 20 and not button(1, 5):IsShown()
            and holder.title.text == "Bags 3/20" and holder.height == 132)
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

        module = load(nil, false, function() ContainerFrameCombinedBags = nil end)
        check("an absent combined frame is skipped", #module.Parked == 6)

        module = load({ modules = { bags = false } })
        OpenAllBags()
        check("a disabled module leaves the Blizzard bags alone", module.Holder == nil
            and ContainerFrame1.parent == ContainerFrameContainer and ContainerFrame1:IsShown() and #env.hooks == 0
            and RikUI.Layout.Groups.bags == nil and RikUIBags == nil)
    end)
    CreateFrame = originalCreate
    C_Item.GetItemQualityColor = savedQualityColor
    UIParent.GetCenter, UIParent.GetEffectiveScale = savedCenter, savedScale
    for name, value in pairs(saved) do _G[name] = value end
    env.inCombat = false
    check("bags suite completes", ok, reason)
end
