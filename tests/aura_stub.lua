-- Fake of Blizzard_AuraContainer's CustomAuraContainerTemplate and CustomAuraButtonTemplate:
-- records configuration and creates a batch of buttons through initializeFrame like the client.
local FILTERS = { HELPFUL = true, HARMFUL = true, PLAYER = true, RAID = true, CANCELABLE = true }
local BATCH_SIZE, ENCHANT_SLOTS = 10, { [0] = true, [1] = true, [2] = true }
local stub = {}

local function validFilter(filter)
    if type(filter) ~= "string" then return false end
    for component in string.gmatch(filter, "[^| ]+") do
        if component:sub(1, 1) == "!" then component = component:sub(2) end
        if component == "" or not FILTERS[component] then return false end
    end
    return true
end

local function validateGroupOptions(options)
    assert(options == nil or type(options) == "table", "options must be a table or nil.")
    options = options or {}
    assert(options.initializeFrame == nil or type(options.initializeFrame) == "function", "initializeFrame must be a function or nil.")
    local count = options.maxFrameCount
    assert(count == nil or (type(count) == "number" and count >= 0), "maxFrameCount must be a non-negative integer or infinity.")
    assert(options.layout == nil or type(options.layout) == "table", "layout must be a table or nil.")
    return options
end

local function forbidden()
    error("AuraButton forbids untrusted script execution", 2)
end

function stub.installButton(button)
    button.registered = { dispel = {} }
    function button:SetIcon(texture) self.registered.icon = texture end
    function button:SetApplicationCount(fontString, options)
        self.registered.count, self.registered.countOptions = fontString, options
    end
    function button:SetDurationCooldown(cooldown) self.registered.cooldown = cooldown end
    function button:AddDispelTypeTexture(texture, options)
        table.insert(self.registered.dispel, { texture = texture, options = options })
    end
    function button:SetCancelAuraButtons(buttons) self.cancelButtons = buttons end
    function button:SetTooltipAnchorPoint(point, x, y) self.tooltipAnchor = { point, x, y } end
    function button:SetHideTooltipInCombat(hide) self.tooltipHideInCombat = hide end
    function button:AddAuraShownAnimation(group) self.registered.fade = group end
    function button:AddPandemicRegion(region) self.registered.pandemic = region end
    function button:AddPandemicActiveAnimation(group) self.registered.pulse = group end
    button.SetScript, button.HookScript = forbidden, forbidden
end

local function createButton(container, options)
    local button = CreateFrame("AuraButton", nil, container, "CustomAuraButtonTemplate")
    if options.initializeFrame then options.initializeFrame(button) end
    button:Hide() -- the client's first display update hides a button without an aura
    return button
end

function stub.installContainer(container)
    container.groups, container.groupOrder, container.enchants = {}, {}, {}
    container.flow = { anchor = "TOPLEFT", horizontal = 1, vertical = -1, lineSize = math.huge }
    container.updates, container.previewEnabled = 0, true
    function container:SetUnit(unit) assert(type(unit) == "string"); self.unit = unit end
    function container:GetUnit() return self.unit end
    function container:SetEditModePreviewEnabled(enabled) self.previewEnabled = enabled end
    function container:SetFlowLayoutAnchorPoint(point) self.flow.anchor = point end
    function container:SetFlowLayoutGrowthDirection(horizontal, vertical)
        self.flow.horizontal, self.flow.vertical = horizontal, vertical
    end
    function container:SetFlowLayoutMaximumLineSize(size) self.flow.lineSize = size end
    function container:SetFlowLayoutPadding(left, right, top, bottom) self.flow.padding = { left, right, top, bottom } end
    function container:UpdateAllAuras() self.updates = self.updates + 1 end
    function container:HasAuraGroup(key) return self.groups[key] ~= nil end
    function container:AddAuraGroup(key, filter, options)
        assert(type(key) == "string" and key ~= "", "groupKey must be a non-empty string.")
        assert(validFilter(filter), "Unknown aura filter component: " .. tostring(filter))
        assert(not self.groups[key], "aura group '" .. key .. "' already exists with this key.")
        options = validateGroupOptions(options)
        local group = { key = key, filter = filter, options = options, frames = {} }
        for index = 1, BATCH_SIZE do group.frames[index] = createButton(self, options) end
        self.groups[key] = group
        table.insert(self.groupOrder, key)
        self.updates = self.updates + 1
    end
    function container:GetAuraGroupFrame(key, index)
        local group = self.groups[key]
        return group and group.frames[index] or nil
    end
    function container:GetAuraGroupFrameCount(key)
        local group = self.groups[key]
        return group and #group.frames or 0
    end
    function container:AddItemEnchantment(slot, options)
        assert(ENCHANT_SLOTS[slot], "itemEnchantmentSlot must be a valid AuraContainerItemEnchantmentSlot.")
        assert(not self.enchants[slot], "item enchantment already exists with this slot.")
        options = validateGroupOptions(options)
        local frame = createButton(self, options)
        self.enchants[slot] = { frame = frame, options = options }
        return frame
    end
    function container:SetItemEnchantmentLayout(options) self.enchantLayout = options end
end

return stub
