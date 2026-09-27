local loadfile = dofile("tests/load_addon.lua").Loadfile
-- The list reads the same globals the stock LootFrame reads and calls LootSlot from a plain click.
-- Event registration, auto-loot timing and the roll frames' live regions need a beta check.
return function(check)
    local env = require("wow_stub")
    local originalCreate = CreateFrame
    local API = { "LootFrame", "GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3", "GroupLootFrame4",
        "GetNumLootItems", "GetLootSlotInfo", "GetLootSlotLink", "GetLootSlotType", "LootSlot", "CloseLoot",
        "GetCursorPosition", "IsModifiedClick", "HandleModifiedItemClick", "UISpecialFrames" }
    local saved, savedColor, savedLootItem = {}, C_Item.GetItemQualityColor, GameTooltip.SetLootItem
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local stub = {}
    local function region(value)
        function value:CreateAnimationGroup() return require("widget_stub").animationGroup() end
        function value:SetTexture(texture) self.texture = texture end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetTextColor(...) self.color = { ... } end
        function value:SetAlpha(alpha) self.alpha = alpha end
        function value:SetShown(value) self.visible = value end
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
        function frame:SetHeight(h) self.height = h end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:ClearAllPoints() self.point = nil end
        function frame:GetEffectiveScale() return 1 end
        function frame:SetStatusBarTexture(texture) self.barTexture = texture end
        function frame:UnregisterAllEvents() self.events, self.eventsDropped = {}, true end
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
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.00001 end
    local function rollFrame(index)
        local frame = CreateFrame("Frame", "GroupLootFrame" .. index, UIParent)
        frame.Background, frame.Border = frame:CreateTexture(), frame:CreateTexture()
        frame.Name = frame:CreateFontString()
        frame.IconFrame = CreateFrame("Button", nil, frame)
        frame.IconFrame.Icon, frame.IconFrame.Border = frame.IconFrame:CreateTexture(), frame.IconFrame:CreateTexture()
        frame.Timer = CreateFrame("StatusBar", nil, frame)
        frame.NeedButton = CreateFrame("Button", nil, frame)
        frame.NeedButton:SetScript("OnClick", function() stub.rolled = (stub.rolled or 0) + 1 end)
    end
    local function installStock()
        LootFrame = CreateFrame("Frame", "LootFrame", UIParent)
        LootFrame:RegisterEvent("LOOT_OPENED")
        for index = 1, 4 do rollFrame(index) end
        stub.slots = {
            { 133784, "12 Copper", 0, nil, 0, false, false, nil, false, true },
            { 132889, "Linen Cloth", 3, nil, 1, false, false, nil, false, false },
            { 135274, "Sentry Blade", 1, nil, 2, false, false, nil, false, false },
        }
        stub.looted, stub.closed, stub.linked, stub.modified, stub.rolled = {}, 0, {}, false, 0
        GetNumLootItems = function() return #stub.slots end
        GetLootSlotInfo = function(slot)
            if stub.infoError then error(stub.infoError) end
            return unpack(stub.slots[slot] or {}, 1, 10)
        end
        GetLootSlotLink = function(slot) return "link:" .. slot end
        LootSlot = function(slot) stub.looted[#stub.looted + 1] = slot end
        CloseLoot = function() stub.closed = stub.closed + 1 end
        GetCursorPosition = function() return 500, 400 end
        IsModifiedClick = function() return stub.modified end
        HandleModifiedItemClick = function(link) stub.linked[#stub.linked + 1] = link end
        UISpecialFrames = {}
        C_Item.GetItemQualityColor = function(quality) return quality / 10, 1, 0 end
        GameTooltip.SetLootItem = function(self, slot) self.lootSlot = slot end
    end
    -- The unit frame module stays off: only its edge helper is under test here.
    local function load(profile, combat, prepare)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        stub.infoError = nil
        installStock()
        if prepare then prepare() end
        profile = profile or {}
        profile.modules = profile.modules or {}
        profile.modules.unitframes = false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, nil
        for _, file in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/ui/skin.lua", "src/ui/motion.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua",
            "src/modules/unitframes/unitframes.lua", "src/modules/unitframes/unitframes-status.lua", "src/modules/loot/loot.lua", "src/modules/loot/loot-rolls.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.Loot
    end
    local function shownRows(module)
        local count = 0
        for _, row in ipairs(module.Rows) do
            if row:IsShown() then count = count + 1 end
        end
        return count
    end
    local ok, reason = pcall(function()
        local module = load()
        local holder, group = module.Holder, RikUI.Layout.Groups.loot
        check("the list registers with the layout under key loot and starts hidden", holder and group
            and group.frames[1] == holder and holder:IsShown() == false and stub.closed == 0)
        check("the list closes on Escape through UISpecialFrames", UISpecialFrames[1] == "RikUILoot")
        check("the stock loot frame is parked with its events dropped", LootFrame.parent == RikUIHiddenFrames
            and LootFrame.eventsDropped == true and RikUI.Hide.IsHidden(LootFrame))

        env.fire("LOOT_OPENED", false)
        check("loot header counts remaining rows", holder.title and holder.title.text == "Loot  |  3 items")
        check("loot window has header chrome and close glyph", holder.rikChrome and holder.close
            and holder.close.icon.rikIcon == "close")
        check("opening loot shows one row per slot", holder:IsShown() and shownRows(module) == 3)
        check("loot entrance fades and slides", holder.rikEntry.plays == 1
            and holder.rikEntry.animation.kind == "Translation")
        GroupLootFrame1:Hide()
        GroupLootFrame1:Show()
        check("native roll frames gain entry motion without replacing their scripts", GroupLootFrame1.rikEntry.plays == 1)
        check("the list opens at the cursor by default", holder.point[1] == "TOPLEFT" and holder.point[3] == "BOTTOMLEFT"
            and holder.point[4] < 500 and holder.point[5] > 400)
        RikUI.Layout.Apply()
        check("a layout pass leaves a list that stands at the cursor where it is", holder.point[3] == "BOTTOMLEFT"
            and holder.point[5] > 400)
        check("a list at the cursor floats: it neither blocks other groups nor is settled",
            RikUI.Layout.Floats(group) == true)
        local coin, cloth, blade = module.Rows[1], module.Rows[2], module.Rows[3]
        check("loot cards provide larger readable hit targets", cloth.width == 280 and cloth.height == 38)
        check("loot quantity has a dark backing only for stacks", cloth.rikCountBacking
            and cloth.rikCountBacking.visible and not blade.rikCountBacking.visible)
        check("loot cards crop and frame their icons", cloth.rikIconBorder and #cloth.rikIconBorder == 4)
        check("a row shows the icon, the name in the RikUI font and the quantity", cloth.icon.texture == 132889
            and cloth.name.text == "Linen Cloth" and cloth.name.fontPath == RikUI.Media.font and cloth.count.text == "3")
        check("a single item and a coin row show no quantity", blade.count.text == "" and coin.count.text == "")
        check("names take the item quality colour", near(blade.name.color[1], 0.2) and near(cloth.name.color[1], 0.1))
        check("loot reveal and rail use the item rarity colour", blade.rikQualityRail and blade.rikFlashRegion
            and near(blade.rikQualityRail.color[1], 0.2) and near(blade.rikFlashRegion.color[1], 0.2))
        local revealPlays = blade.rikFlash.plays
        env.fire("LOOT_SLOT_CHANGED", 3)
        check("unchanged loot does not replay reveal", blade.rikFlash.plays == revealPlays)
        check("the holder grows with the row count", holder.height > 3 * cloth.height and holder.width >= cloth.width)

        env.click(blade)
        check("a click loots the row's slot", stub.looted[1] == 3)
        stub.modified = true
        env.click(cloth)
        check("a modified click links the item instead of looting", stub.linked[1] == "link:2" and #stub.looted == 1)
        stub.modified = false
        env.runScript(cloth, "OnEnter")
        check("hovering a row shows the stock loot tooltip", GameTooltip.owner == cloth and GameTooltip.lootSlot == 2)

        env.fire("LOOT_SLOT_CLEARED", 3)
        check("cleared loot updates the header", holder.title and holder.title.text == "Loot  |  2 items")
        check("a cleared slot hides its row and shrinks the list", not blade:IsShown() and shownRows(module) == 2)
        stub.slots[2][3] = 5
        env.fire("LOOT_SLOT_CHANGED", 2)
        check("a changed slot refreshes its row", cloth.count.text == "5")
        check("loot item updates flash without altering slot clicks", cloth.rikFlash.plays == 2)
        stub.slots[2][3] = env.SECRET
        env.fire("LOOT_SLOT_CHANGED", 2)
        check("secret quantity clears the count backing", cloth.rikCountBacking and not cloth.rikCountBacking.visible)
        check("secret quantity is not compared for animation", cloth.count.text == "")
        stub.slots[2][3] = 5
        stub.slots[2][2] = env.SECRET
        env.fire("LOOT_SLOT_CHANGED", 2)
        check("a secret item name clears the text without printing", cloth.name.text == "" and #env.printed == 0)

        env.fire("LOOT_CLOSED")
        check("closing loot immediately cancels its entrance", not holder.rikEntry:IsPlaying())
        check("closing loot hides the list", holder:IsShown() == false)
        local closed = stub.closed
        env.fire("LOOT_OPENED", false)
        if holder.close then env.click(holder.close) else holder:Hide() end
        check("hiding the list by hand closes the loot session", stub.closed == closed + 1)

        stub.slots = { { 132889, "Linen Cloth", 1, nil, 1 } }
        env.fire("LOOT_OPENED", true)
        check("reopening reuses the row pool", #module.Rows == 3 and shownRows(module) == 1)
        check("pooled rarity resets for the new item", near(module.Rows[1].rikQualityRail.color[1], 0.1)
            and near(module.Rows[1].rikFlashRegion.color[1], 0.1))
        local pooledPlays = module.Rows[1].rikFlash.plays
        env.fire("LOOT_CLOSED")
        env.fire("LOOT_OPENED", false)
        check("same item reveals once in a new session", module.Rows[1].rikFlash.plays == pooledPlays + 1)
        stub.infoError = "loot unavailable"
        env.fire("LOOT_OPENED", false)
        env.fire("LOOT_OPENED", false)
        check("a failing slot read is reported once and contained", printedContains("Loot slot") and #env.printed == 1)
        stub.infoError = nil
        env.fire("LOOT_SLOT_CHANGED", 1)
        check("unavailable opening row recovers when data arrives", shownRows(module) == 1 and module.Rows[1].name.text == "Linen Cloth")
        stub.infoError = "temporary"
        env.fire("LOOT_SLOT_CHANGED", 1)
        check("transient slot failure keeps known loot accessible", shownRows(module) == 1)
        stub.infoError = nil
        stub.slots[1] = {}
        env.fire("LOOT_SLOT_CHANGED", 1)
        check("empty loot shows guidance", holder.empty and holder.empty.visible
            and holder.title.text == "Loot  |  Empty")
        check("readable empty slot disappears", shownRows(module) == 0)
        stub.slots[1] = {132889, "Recovered cloth", 2, nil, 1}
        env.fire("LOOT_SLOT_CHANGED", 1)
        check("hidden slot recovers on later update", shownRows(module) == 1 and module.Rows[1].name.text == "Recovered cloth")
        env.fire("LOOT_SLOT_CHANGED", 3)
        check("previous session slots stay hidden", shownRows(module) == 1)
        env.fire("LOOT_CLOSED")
        env.fire("LOOT_SLOT_CHANGED", 1)
        check("closed session ignores late slot updates", not holder:IsShown())
        local roll = GroupLootFrame1
        check("roll frames lose the toast art and gain the flat border", roll.Background.alpha == 0 and roll.Border.alpha == 0
            and roll.IconFrame.Border.alpha == 0 and #roll.rikBorder == 4 and #module.SkinnedRolls == 4)
        check("the roll timer and item name take the skin media", roll.Timer.barTexture == RikUI.Media.statusbar
            and roll.Name.fontPath == RikUI.Media.font)
        env.click(roll.NeedButton)
        check("the roll buttons keep their handlers", stub.rolled == 1)

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports the list state", printedContains("Loot holder=true rows=3 rolls=4"))

        module = load({ lootAtCursor = false })
        env.fire("LOOT_OPENED", false)
        check("the layout position is kept when the cursor option is off", module.Holder:IsShown()
            and module.Holder.point[2] == UIParent and module.Holder.point[3] == "CENTER")
        check("fixed loot still uses its saved position without reserving permanent HUD space",
            RikUI.Layout.Floats(RikUI.Layout.Groups.loot) == true)
        local option = module.Options.settings[1]
        check("the options panel exposes the cursor setting", option.key == "lootAtCursor" and option.get() == false)
        option.set(true)
        check("turning the option on is saved to the profile", RikUI.Profile.lootAtCursor == true)

        module = load(nil, true)
        check("a combat login parks nothing yet", LootFrame.parent == UIParent and module.Holder ~= nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat parks the stock frame", LootFrame.parent == RikUIHiddenFrames)

        module = load(nil, false, function() GroupLootFrame3, LootFrame = nil, nil end)
        check("missing stock frames are skipped", module.Holder ~= nil and #module.SkinnedRolls == 3)

        module = load({ modules = { loot = false } })
        env.fire("LOOT_OPENED", false)
        check("a disabled module leaves the stock loot and roll frames untouched", module.Holder == nil
            and LootFrame.parent == UIParent and LootFrame.events.LOOT_OPENED == true
            and rawget(GroupLootFrame1.Background, "alpha") == nil and RikUI.Layout.Groups.loot == nil)
    end)
    CreateFrame = originalCreate
    C_Item.GetItemQualityColor, GameTooltip.SetLootItem = savedColor, savedLootItem
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat = false
    check("loot suite completes", ok, reason)
end
