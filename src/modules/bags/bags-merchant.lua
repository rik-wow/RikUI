-- Vendor conveniences are opt-in; the native merchant APIs own spending.
local core, bags = RikUI, RikUI.Bags
local merchantOpen = false

local function amount(value)
    return not core.Secret.IsSecret(value) and type(value) == "number"
        and value >= 0 and value < math.huge
end

local function junkCount()
    local api = C_MerchantFrame
    if not merchantOpen or InCombatLockdown() or type(api) ~= "table" then return nil end
    for _, key in ipairs({ "GetNumJunkItems", "IsSellAllJunkEnabled", "SellAllJunkItems" }) do
        if type(api[key]) ~= "function" then return nil end
    end
    local ok, enabled = pcall(api.IsSellAllJunkEnabled)
    if not ok or core.Secret.IsSecret(enabled) or enabled ~= true then return nil end
    local read, count = pcall(api.GetNumJunkItems)
    if read and amount(count) and count == math.floor(count) then return count end
end

function bags.RefreshMerchant()
    bags.RefreshRepair()
    local button = bags.Holder and bags.Holder.junk
    if not button then return end
    button:SetShown(merchantOpen)
    local count = junkCount()
    button:SetEnabled(count ~= nil and count > 0)
    button.label:SetText(count and ("Sell junk (" .. count .. ")") or "Sell junk")
end

function bags.SellJunk()
    local count = junkCount()
    if not count or count <= 0 then return end
    local ok, reason = pcall(C_MerchantFrame.SellAllJunkItems)
    if not ok then bags.Warn("sell junk", reason) end
    bags.RefreshMerchant()
end

local function guildFunds(cost)
    if core.Profile.bags.repairGuild ~= true then return false end
    for _, name in ipairs({ "CanGuildBankRepair", "GetGuildBankMoney", "GetGuildBankWithdrawMoney" }) do
        if type(_G[name]) ~= "function" then return false end
    end
    local ok, allowed = pcall(CanGuildBankRepair)
    if not ok or core.Secret.IsSecret(allowed) or allowed ~= true then return false end
    local bankOK, bank = pcall(GetGuildBankMoney)
    local limitOK, limit = pcall(GetGuildBankWithdrawMoney)
    if not bankOK or not amount(bank) or bank < cost or not limitOK
        or core.Secret.IsSecret(limit) then return false end
    return limit == -1 or (amount(limit) and limit >= cost)
end

local function repairState()
    if not merchantOpen or InCombatLockdown() then return nil end
    for _, name in ipairs({ "CanMerchantRepair", "GetRepairAllCost", "GetMoney", "RepairAllItems" }) do
        if type(_G[name]) ~= "function" then return nil end
    end
    local canRepair = CanMerchantRepair()
    if core.Secret.IsSecret(canRepair) or canRepair ~= true then return nil end
    local cost, needed = GetRepairAllCost()
    if core.Secret.IsSecret(needed) or needed ~= true or not amount(cost) then return nil end
    if guildFunds(cost) then return cost, cost, true end
    local money = GetMoney()
    if not amount(money) then return nil end
    return cost, money, false
end

function bags.RefreshRepair()
    local button = bags.Holder and bags.Holder.repair
    if not button then return end
    local ok, cost, money, guild = pcall(repairState)
    button:SetShown(merchantOpen)
    button:SetEnabled(ok and cost ~= nil and cost > 0 and cost <= money)
    button.label:SetText(ok and cost and cost > money and "Can't afford" or guild and "Guild repair" or "Repair all")
end

function bags.Repair()
    local ok, cost, money, guild = pcall(repairState)
    if not ok then bags.Warn("repair", cost); return end
    if not cost or cost == 0 then return end
    if cost > money then core:Print("Not enough money to repair your gear."); return end
    local repaired, reason = pcall(RepairAllItems, guild)
    if not repaired then bags.Warn("repair", reason) end
    bags.RefreshRepair()
end

local function automaticActions()
    if type(IsShiftKeyDown) ~= "function" then return end
    local ok, shifted = pcall(IsShiftKeyDown)
    if not ok or core.Secret.IsSecret(shifted) or shifted ~= false then return end
    if core.Profile.bags.autoSellJunk == true then bags.SellJunk() end
    if core.Profile.bags.autoRepair == true then bags.Repair() end
end

local function onMerchantShow()
    if merchantOpen then return end
    merchantOpen = true
    bags.RefreshMerchant()
    local ok, reason = pcall(automaticActions)
    if not ok then bags.Warn("automatic vendor actions", reason) end
end

function bags.EnableMerchant()
    core:RegisterEvent("MERCHANT_SHOW", onMerchantShow)
    core:RegisterEvent("MERCHANT_CLOSED", function() merchantOpen = false; bags.RefreshMerchant() end)
    for _, event in ipairs({ "MERCHANT_UPDATE", "PLAYER_MONEY", "UPDATE_INVENTORY_DURABILITY", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        core:RegisterEvent(event, bags.RefreshMerchant)
    end
    bags.RefreshMerchant()
end

local function nativeBagValue(name)
    local getter = C_Container and C_Container["Get" .. name]
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter)
    if ok and not core.Secret.IsSecret(value) and type(value) == "boolean" then return value end
end

local function nativeBagOption(name, label)
    return { type = "checkbox", key = name, label = label,
        description = "Native client preference shared across UI profiles. Available only when supported; change after combat.",
        get = function() return nativeBagValue(name) == true end,
        disabled = function()
            return InCombatLockdown() or nativeBagValue(name) == nil
                or type(C_Container and C_Container["Set" .. name]) ~= "function"
        end,
        set = function(value)
            local setter = C_Container and C_Container["Set" .. name]
            if InCombatLockdown() or type(value) ~= "boolean" or nativeBagValue(name) == nil
                or type(setter) ~= "function" then return nil, "Bag preference unavailable." end
            local ok, reason = pcall(setter, value)
            if not ok then return nil, "Bag preference could not be changed." end
            if nativeBagValue(name) ~= value then return nil, "Client did not accept the bag preference." end
            return true
        end }
end

bags.Options = { title = "Bags and vendors", settings = {
    nativeBagOption("SortBagsRightToLeft", "Sort bags from right to left"),
    nativeBagOption("InsertItemsLeftToRight", "Place new loot from left to right"),
    nativeBagOption("BackpackAutosortDisabled", "Exclude backpack from sorting"),
    nativeBagOption("BackpackSellJunkDisabled", "Exclude backpack from Sell junk"),
    { type = "checkbox", key = "capacityHUD", label = "Show bag capacity on the HUD",
        description = "See free general and specialized space while bags are closed. Click the indicator to open bags.",
        get = function() return core.Profile.bags.capacityHUD ~= false end,
        set = function(value) core.Profile.bags.capacityHUD = value == true; bags.UpdateCapacity() end },
    { type = "checkbox", key = "capacityLowOnly", label = "Show capacity only when space is low",
        description = "Show the HUD at the free general-slot threshold. Unknown capacity stays visible.",
        get = function() return core.Profile.bags.capacityLowOnly == true end,
        set = function(value) core.Profile.bags.capacityLowOnly = value == true; bags.UpdateCapacity() end },
    { type = "slider", key = "capacityThreshold", label = "Low-space warning threshold",
        description = "Free general slots; specialized bag space does not mask a shortage. Zero warns only when general space is full.",
        min = 0, max = 20, step = 1,
        get = function() return bags.CapacityThreshold() end,
        set = function(value) return bags.SetCapacityThreshold(value) end },
    { type = "checkbox", key = "itemLevels", label = "Show item levels on bag gear",
        description = "Show readable weapon and armor levels in the upper-right corner.",
        get = function() return core.Profile.bags.itemLevels == true end,
        set = function(value)
            core.Profile.bags.itemLevels = value == true
            if bags.Holder and bags.Holder:IsShown() then bags.Refresh() end
        end },
    { type = "slider", key = "columns", label = "Bag columns",
        description = "Wider bags show fewer rows. Layout changes wait until combat ends.",
        min = 10, max = 16, step = 1, get = bags.Columns, set = bags.SetColumns },
    { type = "checkbox", key = "autoSellJunk", label = "Automatically sell junk",
        description = "Sell native junk once when opening a vendor. Hold Shift to skip. Respects native backpack exclusions.",
        get = function() return core.Profile.bags.autoSellJunk == true end,
        set = function(value) core.Profile.bags.autoSellJunk = value == true end },
    { type = "checkbox", key = "repairGuild", label = "Prefer guild funds for repairs",
        description = "Use guild funds when permitted and sufficient; otherwise use your money. Applies to manual and automatic repairs.",
        get = function() return core.Profile.bags.repairGuild == true end,
        set = function(value) core.Profile.bags.repairGuild = value == true; bags.RefreshRepair() end },
    { type = "checkbox", key = "autoRepair", label = "Automatically repair gear",
        description = "Repair at vendors using your selected funding preference. Hold Shift when opening a vendor to skip.",
        get = function() return core.Profile.bags.autoRepair == true end,
        set = function(value) core.Profile.bags.autoRepair = value == true end },
} }

