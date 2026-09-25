local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Spell ranks in the native cooldown manager: show only the highest rank the spellbook holds,
-- read-only detection, one prompt per set of changes, writes through the provider then reload.
return function(check)
    local env = require("wow_stub")
    local globals = { "CooldownViewerSettings", "StaticPopupDialogs", "StaticPopup_Show", "ReloadUI", "UnitClass" }
    local saved = {}
    for _, name in ipairs(globals) do saved[name] = _G[name] end
    local savedEnum = { Enum.CooldownViewerCategory, Enum.CooldownLayoutStatus }
    local CATEGORY = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3, HiddenActive = -1, HiddenPassive = -2 }
    local STATUS = { Success = 0, AttemptToModifyDefaultLayoutWouldCreateTooManyLayouts = 7 }
    local popups, writes, saves, reloads, infos, order, status, learned

    local function entry(id, spellID, category)
        infos[id] = { cooldownID = id, spellID = spellID, overrideSpellID = spellID, category = category, isKnown = true }
        order[#order + 1] = id
    end
    local function fresh()
        env.frames, env.printed, env.inCombat, env.timers = {}, {}, false, {}
        RikUIDB, RikUICharDB = nil, nil
        popups, writes, saves, reloads, infos, order = {}, {}, 0, 0, {}, {}
        status, learned = STATUS.Success, {}
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
        RikUI.Spells.HighestKnownRank = function(name)
            local rank = learned[name]
            if rank then return RikUI.Spells.Entry(name).ranks[rank], nil, rank end
            return nil, "Spellbook lookup unavailable"
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
    local function spellsChanged()
        env.fire("SPELLS_CHANGED")
        env.flushTimers()
    end
    local function click(handler)
        local dialog = popups[#popups]
        StaticPopupDialogs[dialog.which][handler](dialog, dialog.data, "clicked")
    end
    local function printed(fragment)
        for _, line in ipairs(env.printed) do if line:find(fragment, 1, true) then return true end end
    end
    local function immolate(learnedRank)
        local viewer = fresh()
        learned.Immolate = learnedRank
        entry(199797, 348, CATEGORY.Essential)   -- Immolate rank 1
        entry(199803, 11668, CATEGORY.Essential) -- Immolate rank 7
        return viewer
    end

    local ok, reason = pcall(function()
        local viewer = immolate(1)
        entry(199900, 172, CATEGORY.Essential) -- Corruption rank 1, no duplicate
        learned.Corruption = 1
        start(viewer)
        check("a level 3 Warlock is asked about Immolate only", #popups == 1
            and popups[1].text:find("Immolate", 1, true) and not popups[1].text:find("Corruption", 1, true))
        check("detection writes nothing before a click", #writes == 0 and saves == 0)
        spellsChanged()
        check("the same changes are not offered twice", #popups == 1)
        click("OnAccept")
        check("accept hides the unlearned rank 7 and keeps the learned rank 1", #writes == 1
            and writes[1].id == 199803 and writes[1].category == CATEGORY.HiddenActive)
        check("accept saves the native layout and reloads", saves == 1 and reloads == 1)
        check("RikUI remembers the entry it hid", RikUICharDB.cooldownRankMarks[199803] == "hidden")

        learned.Immolate = 7
        spellsChanged()
        check("learning rank 7 offers the swap", #popups == 2)
        click("OnAccept")
        check("the swap shows rank 7 in rank 1's row, then hides rank 1", #writes == 3
            and writes[2].id == 199803 and writes[2].category == CATEGORY.Essential
            and writes[3].id == 199797 and writes[3].category == CATEGORY.HiddenActive)
        check("marks follow the swap", RikUICharDB.cooldownRankMarks[199803] == nil
            and RikUICharDB.cooldownRankMarks[199797] == "hidden")

        viewer = fresh()
        learned.Immolate = 1
        entry(199797, 348, CATEGORY.HiddenActive) -- hidden by the first release
        entry(199803, 11668, CATEGORY.Essential)
        RikUICharDB.cooldownRanksHandled = { [199797] = true }
        start(viewer)
        check("rank 1 hidden by the first release is offered back", #popups == 1)
        click("OnAccept")
        check("the repair shows rank 1 and hides rank 7", #writes == 2
            and writes[1].id == 199797 and writes[1].category == CATEGORY.Essential
            and writes[2].id == 199803 and writes[2].category == CATEGORY.HiddenActive)
        check("the old flag table is retired", RikUICharDB.cooldownRanksHandled == nil
            and RikUICharDB.cooldownRankMarks[199797] == nil and RikUICharDB.cooldownRankMarks[199803] == "hidden")

        viewer = fresh()
        learned.Immolate = 1
        entry(199797, 348, CATEGORY.HiddenActive) -- hidden, record lost
        entry(199803, 11668, CATEGORY.Essential)
        start(viewer)
        click("OnAccept")
        check("a learned rank is shown when only unlearned ranks are visible, even without a record",
            #writes == 2 and writes[1].id == 199797 and writes[2].id == 199803)

        viewer = immolate(2)
        start(viewer)
        click("OnAccept")
        check("rank 2 without its own entry keeps the rank 1 entry", #writes == 1 and writes[1].id == 199803)

        viewer = fresh()
        learned.Immolate = 1
        entry(1, 11665, CATEGORY.Essential) -- rank 5
        entry(2, 11668, CATEGORY.Essential) -- rank 7
        start(viewer)
        check("no entry at or below the learned rank changes nothing", #popups == 0)

        viewer = immolate(nil)
        start(viewer)
        check("an unreadable spellbook never prompts", #popups == 0)

        viewer = immolate(1)
        start(viewer)
        click("OnAlt")
        check("keep as is remembers the choice without writing", #writes == 0 and reloads == 0
            and RikUICharDB.cooldownRankMarks[199803] == "kept"
            and #viewer.FindRankChanges(CooldownViewerSettings:GetDataProvider():GetDisplayData()) == 0)
        SlashCmdList.RIKUI("cooldownranks"); env.flushTimers()
        check("/rik cooldownranks forgets kept choices and asks again", #popups == 2)

        viewer = immolate(1)
        start(viewer)
        click("OnCancel")
        check("not now writes and remembers nothing", #writes == 0 and next(RikUICharDB.cooldownRankMarks) == nil)

        viewer = fresh()
        learned.Immolate = 7
        entry(1, 348, CATEGORY.Essential)
        entry(2, 11668, CATEGORY.HiddenActive)
        start(viewer)
        check("an entry the player hid is never shown again by RikUI", #popups == 0)

        viewer = fresh()
        learned.Immolate, learned["Bane of Agony"] = 7, 2
        entry(1, 348, CATEGORY.Essential)
        entry(2, 11668, CATEGORY.TrackedBuff)
        entry(4, 999999, CATEGORY.Essential)
        entry(5, 999999, CATEGORY.Essential)
        entry(6, 1094, env.SECRET)
        start(viewer)
        check("separate row groups, uncatalogued and opaque entries never prompt", #popups == 0)

        viewer = fresh()
        learned["Bane of Agony"] = 1
        entry(1, 980, CATEGORY.TrackedBar)   -- Bane of Agony rank 1
        entry(2, 1014, CATEGORY.TrackedBuff) -- rank 2
        start(viewer)
        click("OnAccept")
        check("buff rows hide into the passive hidden category",
            #writes == 1 and writes[1].id == 2 and writes[1].category == CATEGORY.HiddenPassive)

        viewer = immolate(1)
        env.inCombat = true
        start(viewer)
        check("prompt waits for combat to end", #popups == 0)
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
        check("prompt appears after combat", #popups == 1)
        env.inCombat = true
        click("OnAccept")
        check("accept in combat changes nothing", #writes == 0 and reloads == 0 and printed("in combat"))

        viewer = immolate(1)
        status = STATUS.AttemptToModifyDefaultLayoutWouldCreateTooManyLayouts
        start(viewer)
        click("OnAccept")
        check("a refused layout write neither saves nor reloads", saves == 0 and reloads == 0
            and printed("Cooldown ranks unchanged") and next(RikUICharDB.cooldownRankMarks) == nil)

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
