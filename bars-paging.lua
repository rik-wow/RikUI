-- One fixed main overlay per observed bonus page; no restricted snippets.
local core, bars = RikUI, RikUI.Bars

local function condition(page)
    -- The native controller gives manually selected pages precedence over bonus pages.
    return "[bar:1,bonusbar:" .. page.offset .. "]"
end

local function restoreBase(pages)
    for _, page in ipairs(pages) do
        local bar = bars.Frames[page.name]
        if bar then
            local ok, reason = pcall(UnregisterStateDriver, bar, "visibility")
            if not ok then core:Print("Bars paging cleanup: " .. tostring(reason)) end
            bar:Hide()
        end
    end
    local main = bars.Frames.main
    if not main then return end
    local ok, reason = pcall(UnregisterStateDriver, main, "visibility")
    if not ok then core:Print("Bars paging cleanup: " .. tostring(reason)) end
    main:Show()
end

local function installDrivers(pages)
    local hidden = {}
    for _, page in ipairs(pages) do
        local bar = assert(bars.Frames[page.name], "bonus overlay creation failed")
        RegisterStateDriver(bar, "visibility", condition(page) .. " show; hide")
        hidden[#hidden + 1] = condition(page)
    end
    RegisterStateDriver(bars.Frames.main, "visibility", table.concat(hidden) .. " hide; show")
end

function bars.EnablePaging()
    local _, class = UnitClass("player")
    local pages = core.Data.BonusPages[class]
    if not pages or #pages == 0 then return end
    for _, page in ipairs(pages) do
        bars.Create(page.name, page.firstAction, { positionKey = "main" })
    end
    -- Queue after Create: even a combat login builds every page before hiding main.
    core.Combat.Queue(function()
        local ok, reason = pcall(installDrivers, pages)
        if ok then return end
        restoreBase(pages)
        core:Print("Bars paging unavailable: " .. tostring(reason))
    end)
end
