return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore, saved = widgets.install(), SpellActivationOverlayFrame
    local function install()
        SpellActivationOverlayFrame = CreateFrame("Frame", nil, UIParent)
        SpellActivationOverlayFrame.overlaysInUse = {}
    end
    local ok, reason = pcall(function()
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/extrabuttons/proc-overlay.lua" }, nil, false, install)
        local owner = SpellActivationOverlayFrame
        local overlay = CreateFrame("Frame", nil, owner)
        overlay.texture = overlay:CreateTexture()
        owner.overlaysInUse[123] = { overlay }
        env.inCombat = true
        env.runScript(owner, "OnEvent", "SPELL_ACTIVATION_OVERLAY_SHOW")
        local art = RikUI.ProcOverlay.Regions[overlay]
        check("native proc gets flat art", art and rawget(overlay.texture, "texture") == nil)
        check("native geometry and attributes stay untouched", overlay.points == nil
            and next(overlay.attributes) == nil and next(overlay.scripts) == nil)
        overlay.texture:SetTexture("native reuse")
        env.runScript(owner, "OnEvent", "SPELL_ACTIVATION_OVERLAY_SHOW")
        check("reuse reblanks stock without duplicate art", RikUI.ProcOverlay.Regions[overlay] == art
            and rawget(overlay.texture, "texture") == nil)
        env.inCombat = false
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/extrabuttons/proc-overlay.lua" }, nil, false,
            function() SpellActivationOverlayFrame = nil end)
        check("missing proc container is harmless", #env.printed == 0)
    end)
    restore()
    SpellActivationOverlayFrame, env.inCombat = saved, false
    check("proc overlay suite completes", ok, reason)
end

