-- Fixed main overlays selected by native visibility drivers; no restricted snippets.
local core, bars = RikUI, RikUI.Bars
-- Native build 69913: six 12-slot pages (ActionButtonUtil.lua / MultiActionBars.lua).
local MANUAL_PAGES = {
    { name = "page2", selectedPage = 2, firstAction = 13 },
    { name = "page3", selectedPage = 3, firstAction = 25 },
    { name = "page4", selectedPage = 4, firstAction = 37 },
    { name = "page5", selectedPage = 5, firstAction = 49 },
    { name = "page6", selectedPage = 6, firstAction = 61 },
}

local function condition(page)
    if page.selectedPage then return "[bar:" .. page.selectedPage .. "]" end
    -- The native controller gives manually selected pages precedence over bonus pages.
    return "[bar:1,bonusbar:" .. page.offset .. "]"
end

local function overlays()
    local _, class = UnitClass("player")
    local pages = {}
    for _, page in ipairs(MANUAL_PAGES) do pages[#pages + 1] = page end
    for _, page in ipairs(core.Data.BonusPages[class] or {}) do pages[#pages + 1] = page end
    return pages
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
        local bar = assert(bars.Frames[page.name], "main overlay creation failed")
        RegisterStateDriver(bar, "visibility", condition(page) .. " show; hide")
        hidden[#hidden + 1] = condition(page)
    end
    RegisterStateDriver(bars.Frames.main, "visibility", table.concat(hidden) .. " hide; show")
end

function bars.EnablePaging()
    local pages = overlays()
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
