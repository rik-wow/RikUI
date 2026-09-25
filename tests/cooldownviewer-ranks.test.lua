local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Duplicate spell ranks in the native cooldown manager: read-only detection, one prompt,
-- and hiding through the provider's own calls followed by a reload.
return function(check)
    local env = require("wow_stub")
    local globals = { "CooldownViewerSettings", "StaticPopupDialogs", "StaticPopup_Show", "ReloadUI", "UnitClass" }
    local saved = {}
    for _, name in ipairs(globals) do saved[name] = _G[name] end
    local savedEnum = { Enum.CooldownViewerCategory, Enum.CooldownLayoutStatus }
    local CATEGORY = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3, HiddenActive = -1, HiddenPassive = -2 }
    local STATUS = { Success = 0, AttemptToModifyDefaultLayoutWouldCreateTooManyLayouts = 7 }
    local popups, writes, saves, reloads, infos, order, status

    local function entry(id, spellID, category, known)
        infos[id] = { cooldownID = id, spellID = spellID, overrideSpellID = spellID,
            category = category, isKnown = known ~= false }
        order[#order + 1] = id
    end
    local function fresh()
        env.frames, env.printed, env.inCombat, env.timers = {}, {}, false, {}
        RikUIDB, RikUICharDB = nil, nil
        popups, writes, saves, reloads, infos, order, status = {}, {}, 0, 0, {}, {}, STATUS.Success
        Enum.CooldownViewerCategory, Enum.CooldownLayoutStatus = CATEGORY, STATUS
        UnitClass = function() return "Warlock", "WARLOCK", 9 end
        ReloadUI = function() reloads = reloads + 1 end
        local provider = {
            GetDisplayData = function() return { orderedCooldownIDs = order, cooldownInfoByID = infos } end,
            GetOrderedCooldownIDs = function() return order end,
            SetCooldownToCategory = function(_, id, category)
                writes[#writes + 1] = { id = id, category = category }
                if status == STATUS.Success then infos[id].category = category end
                return status
            end,
            GetLayoutManager = function() return { SaveLayouts = function() saves = saves + 1 end } end,
        }
        CooldownViewerSettings = { GetDataProvider = function() return provider end }
        StaticPopupDialogs = {}
        StaticPopup_Show = function(which, text1, _, data)
            local dialog = { which = which, data = data, text = string.format(StaticPopupDialogs[which].text, text1) }
            popups[#popups + 1] = dialog
            return dialog
        end
        for _, file in ipairs({ "src/core/core.lua", "data/spells.lua", "data/spells-warlock.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        RikUI.CooldownViewer = {}
        assert(loadfile("src/modules/cooldownviewer/cooldownviewer-ranks.lua"))("RikUI", {})
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        return RikUI.CooldownViewer
    end
    local function start(viewer)
        viewer.EnableRanks()
        env.flushTimers()
    end
    local function click(handler)
        local dialog = popups[#popups]
        StaticPopupDialogs[dialog.which][handler](dialog, dialog.data, "clicked")
    end
    local function printed(fragment)
        for _, line in ipairs(env.printed) do if line:find(fragment, 1, true) then return true end end
    end

    local ok, reason = pcall(function()
        local viewer = fresh()
        entry(199797, 348, CATEGORY.Essential)    -- Immolate rank 1
        entry(199803, 11668, CATEGORY.Essential)  -- Immolate rank 7
        entry(199900, 172, CATEGORY.Essential)    -- Corruption rank 1, no duplicate
        start(viewer)
        check("two Immolate ranks prompt once, naming the spell", #popups == 1
            and popups[1].text:find("Immolate", 1, true) and not popups[1].text:find("Corruption", 1, true))
        check("detection writes nothing before a click", #writes == 0 and saves == 0)
        env.fire("SPELLS_CHANGED"); env.flushTimers()
        check("later spell changes do not repeat the prompt", #popups == 1)
        click("OnAccept")
        check("accept hides only the lower rank through the provider", #writes == 1
            and writes[1].id == 199797 and writes[1].category == CATEGORY.HiddenActive)
        check("accept saves the native layout and reloads", saves == 1 and reloads == 1)
        check("accepted entries are remembered", RikUICharDB.cooldownRanksHandled[199797] == true)

        viewer = fresh()
        entry(1, 348, CATEGORY.Essential)
        entry(2, 11668, CATEGORY.Essential)
        start(viewer)
        click("OnAlt")
        check("keep both remembers the choice without writing", #writes == 0 and reloads == 0
            and RikUICharDB.cooldownRanksHandled[1] == true and #viewer.FindDuplicateRanks(
                CooldownViewerSettings:GetDataProvider():GetDisplayData()) == 0)
        SlashCmdList.RIKUI("cooldownranks"); env.flushTimers()
        check("/rik cooldownranks forgets choices and asks again", #popups == 2)

        viewer = fresh()
        entry(1, 348, CATEGORY.Essential)
        entry(2, 11668, CATEGORY.Essential)
        start(viewer)
        click("OnCancel")
        check("not now writes and remembers nothing", #writes == 0
            and next(RikUICharDB.cooldownRanksHandled or {}) == nil)

        viewer = fresh()
        entry(1, 348, CATEGORY.Essential)
        entry(2, 11668, CATEGORY.TrackedBuff)
        entry(3, 707, CATEGORY.Utility, false)
        entry(4, 999999, CATEGORY.Essential)
        entry(5, 999999, CATEGORY.Essential)
        entry(6, 1094, env.SECRET)
        start(viewer)
        check("ranks in separate row groups, unknown, uncatalogued or opaque entries never prompt", #popups == 0)

        viewer = fresh()
        entry(1, 980, CATEGORY.TrackedBar)   -- Bane of Agony rank 1
        entry(2, 1014, CATEGORY.TrackedBuff) -- rank 2
        start(viewer)
        click("OnAccept")
        check("buff rows hide lower ranks into the passive hidden category",
            #writes == 1 and writes[1].id == 1 and writes[1].category == CATEGORY.HiddenPassive)

        viewer = fresh()
        entry(1, 348, CATEGORY.Essential)
        entry(2, 11668, CATEGORY.Essential)
        env.inCombat = true
        start(viewer)
        check("prompt waits for combat to end", #popups == 0)
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
        check("prompt appears after combat", #popups == 1)
        env.inCombat = true
        click("OnAccept")
        check("accept in combat changes nothing", #writes == 0 and reloads == 0 and printed("in combat"))

        viewer = fresh()
        entry(1, 348, CATEGORY.Essential)
        entry(2, 11668, CATEGORY.Essential)
        status = STATUS.AttemptToModifyDefaultLayoutWouldCreateTooManyLayouts
        start(viewer)
        click("OnAccept")
        check("a refused layout write neither saves nor reloads", saves == 0 and reloads == 0
            and printed("Cooldown ranks unchanged") and next(RikUICharDB.cooldownRanksHandled) == nil)

        viewer = fresh()
        CooldownViewerSettings = nil
        start(viewer)
        check("missing native manager is quiet", #popups == 0 and #env.printed == 0)
    end)
    for _, name in ipairs(globals) do _G[name] = saved[name] end
    Enum.CooldownViewerCategory, Enum.CooldownLayoutStatus = savedEnum[1], savedEnum[2]
    env.inCombat = false
    check("cooldown rank suite completes", ok, reason)
end
