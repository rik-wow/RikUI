-- Fake of the 69913 bag surface RikUI touches. Forever (game type camelot) loads the Mainline
-- ContainerFrame files: ContainerFrame1-6 under ContainerFrameContainer, ContainerFrameCombinedBags,
-- and the global open, close and toggle functions that bindings, merchants and the mailbox call.
-- The globals only flip the stock frames' shown flag, which is all RikUI mirrors. C_Container reads
-- come from stub.slots, stub.items and stub.cooldowns; sorting and info reads are counted.
local stub = { STOCK_FRAMES = 6, HELD_BAGS = 5 }
local QUALITY_COLORS = { [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 } }

local function link(name) return "|cffffffff|Hitem:1::::::::12:::::|h[" .. name .. "]|h|r" end

local function defaultItems()
    return {
        ["0:1"] = { iconFileID = 132889, stackCount = 5, quality = 1, isLocked = false, hyperlink = link("Linen Cloth") },
        ["0:2"] = { iconFileID = 134414, stackCount = 1, quality = 1, isLocked = false, hyperlink = link("Hearthstone") },
        ["1:3"] = { iconFileID = 135274, stackCount = 1, quality = 2, isLocked = false, hyperlink = link("Sentry Blade") },
    }
end

local function installFrames()
    ContainerFrameContainer = CreateFrame("Frame", "ContainerFrameContainer", UIParent)
    stub.frames = {}
    for index = 1, stub.STOCK_FRAMES do
        local frame = CreateFrame("Frame", "ContainerFrame" .. index, ContainerFrameContainer)
        frame.shown = false
        stub.frames[index] = frame
    end
    _G["ContainerFrame" .. (stub.STOCK_FRAMES + 1)] = nil
    ContainerFrameCombinedBags = CreateFrame("Frame", "ContainerFrameCombinedBags", UIParent)
    ContainerFrameCombinedBags.shown = false
end

local function anyShown()
    for _, frame in ipairs(stub.frames) do
        if frame:IsShown() then return true end
    end
    return false
end

local function installToggles()
    function OpenBag(id) stub.frames[id + 1]:Show() end
    function CloseBag(id) stub.frames[id + 1]:Hide() end
    function ToggleBag(id) if stub.frames[id + 1]:IsShown() then CloseBag(id) else OpenBag(id) end end
    function OpenBackpack() OpenBag(0) end
    function CloseBackpack() CloseBag(0) end
    function OpenAllBags() for id = 0, stub.HELD_BAGS - 1 do OpenBag(id) end end
    function CloseAllBags()
        stub.closeAllCalls = stub.closeAllCalls + 1
        for id = 0, stub.HELD_BAGS - 1 do CloseBag(id) end
    end
    function ToggleBackpack() if stub.frames[1]:IsShown() then CloseAllBags() else OpenBackpack() end end
    function ToggleAllBags() if anyShown() then CloseAllBags() else OpenAllBags() end end
end

-- BagSearch_OnTextChanged's route: the client marks every item record, then fires the event.
function stub.setItemSearch(text)
    stub.searchText = text
    for _, item in pairs(stub.items) do
        if item ~= stub.env.SECRET then
            local name = item.hyperlink:match("%[(.-)%]"):lower()
            item.isFiltered = text ~= "" and not name:find(text, 1, true)
        end
    end
    stub.env.fire("INVENTORY_SEARCH_UPDATE")
end

local function installContainerApi()
    C_Container = {
        GetContainerNumSlots = function(bag) return stub.slots[bag] or 0 end,
        GetContainerItemInfo = function(bag, slot)
            stub.infoReads = stub.infoReads + 1
            if stub.infoError then error(stub.infoError) end
            return stub.items[bag .. ":" .. slot]
        end,
        GetContainerItemCooldown = function(bag, slot)
            local cooldown = stub.cooldowns[bag .. ":" .. slot]
            if not cooldown then return 0, 0, 1 end
            return cooldown[1], cooldown[2], 1
        end,
        SortBags = function() stub.sorted = stub.sorted + 1 end,
        SetItemSearch = stub.setItemSearch,
    }
    function GetMoney() return stub.money end
    C_Item.GetItemQualityColor = function(quality)
        local color = QUALITY_COLORS[quality]
        return color[1], color[2], color[3]
    end
    UISpecialFrames = {}
end

-- Fresh frames, globals and recorders; call again for every scenario that reloads the addon.
function stub.install(env)
    stub.env = env
    stub.slots, stub.items, stub.cooldowns = { [0] = 16, [1] = 6, [2] = 0, [3] = 0, [4] = 0 }, defaultItems(), {}
    stub.money, stub.sorted, stub.infoReads, stub.closeAllCalls, stub.infoError = 123456, 0, 0, 0, nil
    stub.templateMissing, stub.searchTemplateMissing, stub.searchText = false, false, nil
    installFrames()
    installToggles()
    installContainerApi()
end

stub.link = link
return stub
