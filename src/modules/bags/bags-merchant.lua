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

local function repair()
    if InCombatLockdown() or (type(IsShiftKeyDown) == "function" and IsShiftKeyDown()) then return end
    for _, name in ipairs({ "CanMerchantRepair", "GetRepairAllCost", "GetMoney", "RepairAllItems" }) do
        if type(_G[name]) ~= "function" then return bags.Warn("repair", name .. " unavailable") end
    end
    local canRepair = CanMerchantRepair()
    if core.Secret.IsSecret(canRepair) or canRepair ~= true then return end
    local cost = GetRepairAllCost()
    local money = GetMoney()
    if not amount(cost) or not amount(money) or cost == 0 then return end
    if cost > money then core:Print("Not enough money to repair your gear."); return end
    RepairAllItems(false)
end

local function onMerchantShow()
    if merchantOpen then return end
    merchantOpen = true
    bags.RefreshMerchant()
    if not core.Profile.bags.autoRepair then return end
    local ok, reason = pcall(repair)
    if not ok then bags.Warn("repair", reason) end
end

function bags.EnableMerchant()
    core:RegisterEvent("MERCHANT_SHOW", onMerchantShow)
    core:RegisterEvent("MERCHANT_CLOSED", function() merchantOpen = false; bags.RefreshMerchant() end)
    for _, event in ipairs({ "MERCHANT_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        core:RegisterEvent(event, bags.RefreshMerchant)
    end
    bags.RefreshMerchant()
end

bags.Options = { title = "Bags and vendors", settings = {
    { type = "checkbox", key = "capacityHUD", label = "Show bag capacity on the HUD",
        description = "See free general and specialized space while bags are closed. Click the indicator to open bags.",
        get = function() return core.Profile.bags.capacityHUD ~= false end,
        set = function(value) core.Profile.bags.capacityHUD = value == true; bags.UpdateCapacity() end },
    { type = "slider", key = "columns", label = "Bag columns",
        description = "Wider bags show fewer rows. Layout changes wait until combat ends.",
        min = 10, max = 16, step = 1, get = bags.Columns, set = bags.SetColumns },
    { type = "checkbox", key = "autoRepair", label = "Automatically repair gear",
        description = "Use personal funds at repair vendors. Hold Shift when opening a vendor to skip.",
        get = function() return core.Profile.bags.autoRepair == true end,
        set = function(value) core.Profile.bags.autoRepair = value == true end },
} }

