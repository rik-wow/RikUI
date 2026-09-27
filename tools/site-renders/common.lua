-- Development fixture only; never loaded by RikUI.
assert(A_Admin and RikUI and RikUI.Runtime.loggedIn, "RikUI did not finish startup")
RikUI.Profile.reducedMotion = true
RikUI.Wizard.Close()
if GameMenuFrame then GameMenuFrame:Hide() end

function RikRenderCenter(frame, scale)
    assert(frame, "Missing preview frame")
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetScale(scale or 1)
end

-- The headless simulator does not emit OnSizeChanged. Deliver the actual
-- callbacks using calculated sizes, leaving RikUI's layout code untouched.
function RikRenderResize(root)
    local previous = {}
    local function visit(frame)
        local width, height = frame:GetSize()
        local old = previous[frame]
        if not old or old[1] ~= width or old[2] ~= height then
            previous[frame] = { width, height }
            local callback = frame:GetScript("OnSizeChanged")
            if callback then callback(frame, width, height) end
        end
        for _, child in ipairs({ frame:GetChildren() }) do visit(child) end
    end
    for pass = 1, 6 do visit(root) end
end

function RikRenderCheck(root)
    assert(root, "Scenario root is missing")
    for _, entry in ipairs(RikUI:GetErrors()) do
        error(entry.context .. ": " .. entry.detail)
    end
    CreateFrame("Frame", "RIK_RENDER_OK", root):Hide()
end
-- Inputs for two items whose artwork was extracted from the current client.
-- These supply game API data; RikUI still creates and paints every control.
function RikRenderItems()
    local items = {
        [6948] = { name = "Hearthstone", icon = 134414, count = 1 },
        [118] = { name = "Minor Healing Potion", icon = 134829, count = 5 },
    }
    local slots = { 6948, 118 }
    C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end
    C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 14 or 0, 0 end
    C_Container.GetContainerItemInfo = function(bag, slot)
        local id = bag == 0 and slots[slot]
        local item = items[id]
        if not item then return nil end
        return { itemID = id, iconFileID = item.icon, stackCount = item.count,
            quality = 1, isLocked = false, hasNoValue = false,
            hyperlink = "|cffffffff|Hitem:" .. id .. "::::::::10:::::|h[" .. item.name .. "]|h|r" }
    end
    C_Container.SetItemSearch = function() return false end
    C_Container.GetContainerItemQuestInfo = function() return { isQuestItem = false } end
    local texture, bagSlots = GetInventoryItemTexture, {}
    for bag = 1, 4 do bagSlots[C_Container.ContainerIDToInventoryID(bag)] = true end
    GetInventoryItemTexture = function(unit, slot)
        if unit == "player" and bagSlots[slot] then return nil end
        return texture(unit, slot)
    end
    GetNumLootItems = function() return 2 end
    GetLootSlotInfo = function(slot)
        local item = items[slots[slot]]
        if item then return item.icon, item.name, item.count, nil, 1, false, false end
    end
end

