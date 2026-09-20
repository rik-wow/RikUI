-- Fake Blizzard_Menu frames: a pooled background texture with the 69913 atlas name and a compositor
-- that refuses new regions on the menu. The suite checks the backing pool and that the menu frame
-- itself only ever gets an alpha write on Blizzard's background.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local saved = EventRegistry
    local restore = widgets.install()
    local ATLAS = "common-dropdown-bg"
    local function registry()
        local value = { callbacks = {} }
        function value:RegisterCallback(event, callback, owner)
            self.callbacks[event] = function(...) callback(owner, ...) end
        end
        function value:TriggerEvent(event, ...)
            if self.callbacks[event] then self.callbacks[event](...) end
        end
        return value
    end
    local function texture(parent, atlas)
        local value = widgets.region(parent:CreateTexture())
        function value:GetAtlas() return atlas end
        return value
    end
    local function menu(level)
        local frame = CreateFrame("Frame", nil, UIParent)
        frame.background, frame.other = texture(frame, ATLAS), texture(frame, "common-dropdown-icon")
        frame.title = frame:CreateFontString()
        function frame:GetRegions() return self.background, self.other, self.title end
        function frame:GetFrameLevel() return level end
        function frame:GetFrameStrata() return "FULLSCREEN_DIALOG" end
        function frame:CreateTexture() error("Use of function 'CreateTexture' is disallowed") end
        function frame:CreateAnimationGroup() error("Use of function 'CreateAnimationGroup' is disallowed") end
        function frame.title:SetFont() error("Use of function 'SetFont' is disallowed") end
        return frame
    end
    local function load(profile, prepare)
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/menus/menus.lua" }, profile, false, function()
            EventRegistry = registry()
            if prepare then prepare() end
        end)
        return RikUI.Menus
    end
    local function open(frame) EventRegistry:TriggerEvent("MenuProxy.OnShow", frame) end
    local function close(frame) EventRegistry:TriggerEvent("MenuProxy.OnHide", frame) end
    local ok, reason = pcall(function()
        local module = load()
        local first = menu(10)
        open(first)
        local backing = module.Active[first]
        check("a shown menu fades Blizzard's background and leaves its other art alone",
            first.background.alpha == 0 and rawget(first.other, "alpha") == nil)
        check("the menu gets a flat backing with a one-pixel edge", backing ~= nil
            and backing.rikFill.texture == RikUI.Skin.FLAT and #backing.rikBorder == 4 and backing:IsShown())
        check("the backing sits one level under the menu in its strata and is anchored to it",
            backing.level == 9 and backing.strata == "FULLSCREEN_DIALOG" and backing.points[1][2] == first
            and backing.points[2][2] == first and backing.parent == UIParent)
        check("the backing fades in", backing.rikFade.plays == 1)
        check("nothing was created on the menu, reparented or printed", first.parent == UIParent
            and first.points == nil and #env.printed == 0)

        local submenu = menu(20)
        open(submenu)
        check("a submenu open at the same time gets a backing of its own",
            module.Active[submenu] ~= nil and module.Active[submenu] ~= backing)
        close(first)
        check("hiding a menu hides its backing and returns it to the pool", not backing:IsShown()
            and module.Active[first] == nil and module.Active[submenu] ~= nil)
        local third = menu(0)
        open(third)
        check("the next menu reuses the pooled backing, fades in again and never goes under level zero",
            module.Active[third] == backing and backing.rikFade.plays == 2 and backing.level == 0
            and backing.points[1][2] == third)
        open(third)
        check("a repeated show for an open menu keeps its one backing", module.Active[third] == backing
            and backing.rikFade.plays == 2)
        close(menu(5))
        check("hiding a menu that was never skinned does nothing", #env.printed == 0)
        env.inCombat = true
        close(third)
        open(third)
        env.inCombat = false
        check("menus open and close in combat without a protected write", module.Active[third] == backing
            and #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports the pool", widgets.printedContains(env, "Menus shown=4 active=2 pooled=0"))

        module = load()
        local bare = CreateFrame("Frame", nil, UIParent)
        open(bare)
        check("a menu without regions, level or strata still gets a backing", module.Active[bare] ~= nil
            and #env.printed == 0)
        local broken = menu(3)
        function broken.background:SetAlpha() error("alpha refused") end
        open(broken)
        open(menu(4))
        check("a failing skin is reported once and later menus still work",
            widgets.printedContains(env, "Menus skin") and #env.printed == 1)

        module = load(nil, function() EventRegistry = nil end)
        check("a client without the event registry says nothing", #env.printed == 0)

        module = load({ modules = { menus = false } })
        local stock = menu(10)
        open(stock)
        check("a disabled module leaves menus stock", rawget(stock.background, "alpha") == nil
            and module.Active[stock] == nil)
    end)
    restore()
    EventRegistry = saved
    env.inCombat = false
    check("menus suite completes", ok, reason)
end
