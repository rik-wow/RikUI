-- Vendor conveniences are opt-in; the native merchant APIs own spending.
local core, bags = RikUI, RikUI.Bags
local merchantOpen = false

local function amount(value)
    return not core.Secret.IsSecret(value) and type(value) == "number"
        and value >= 0 and value < math.huge
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
    if not core.Profile.bags.autoRepair then return end
    local ok, reason = pcall(repair)
    if not ok then bags.Warn("repair", reason) end
end

function bags.EnableMerchant()
    core:RegisterEvent("MERCHANT_SHOW", onMerchantShow)
    core:RegisterEvent("MERCHANT_CLOSED", function() merchantOpen = false end)
end

bags.Options = { title = "Bags and vendors", settings = {
    { type = "checkbox", key = "autoRepair", label = "Automatically repair gear",
        description = "Use personal funds at repair vendors. Hold Shift when opening a vendor to skip.",
        get = function() return core.Profile.bags.autoRepair == true end,
        set = function(value) core.Profile.bags.autoRepair = value == true end },
} }

