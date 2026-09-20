-- Target and pet aura containers hang under the unit frames; filter strings split own auras from others.
return function(check)
    local env = require("wow_stub")
    local originalCreate = CreateFrame
    local API = { "C_UnitAuras", "C_Secrets" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local auraReads = 0
    local function region(value)
        local methods = getmetatable(value).__index
        setmetatable(value, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        function value:SetTexture(texture) self.texture = texture end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
        function value:SetText(text) self.text = text end
        function value:SetFormattedText(format, ...) self.format, self.args = format, { ... } end
        return value
    end
    CreateFrame = function(kind, name, parent, template)
        local frame = originalCreate(kind, name, parent, template)
        local methods = getmetatable(frame).__index
        setmetatable(frame, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        function frame:SetSize(w, h) self.width, self.height = w, h end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:SetAlpha(value) self.alpha = value end
        function frame:GetFrameLevel() return self.level or 1 end
        function frame:SetFrameLevel(level) self.level = level end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return region(texture(self, ...)) end
        function frame:CreateFontString(...) return region(font(self, ...)) end
        return frame
    end
    C_UnitAuras = setmetatable({}, { __index = function()
        return function() auraReads = auraReads + 1 end
    end })
    C_Secrets = { ShouldAurasBeSecret = function() return false end }
    local function printedContains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.00001 end
    local function point(frame, name, relative, relativePoint, x, y)
        local p = frame.point
        return type(p) == "table" and p[1] == name and p[2] == relative and p[3] == relativePoint
            and near(p[4], x) and near(p[5], y)
    end
    local function order(container, ...)
        local expected = { ... }
        if #container.groupOrder ~= #expected then return false end
        for index, key in ipairs(expected) do
            if container.groupOrder[index] ~= key then return false end
        end
        return true
    end
    local function load(profile, combat, missingContainer)
        env.frames, env.printed, env.inCombat, env.timers, auraReads = {}, {}, false, {}, 0
        env.auraContainerMissing = missingContainer == true
        RikUI, RikUIDB, RikUICharDB = nil, profile and { profiles = { Default = profile } } or nil, nil
        for _, file in ipairs({ "core.lua", "hide.lua", "media.lua", "setup.lua", "setup-apply.lua", "layout.lua",
            "unitframes.lua", "unitframes-status.lua", "auras.lua", "auras-button.lua", "auras-units.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.UnitAuras
    end
    local ok, reason = pcall(function()
        local module = load({ modules = { auras = false } })
        local frames = RikUI.UnitFrames.Frames
        local target, pet = module.Containers.target, module.Containers.pet
        check("target and pet containers are Blizzard containers under their unit frames", target and pet
            and target.kind == "AuraContainer" and target.template == "CustomAuraContainerTemplate"
            and target.parent == frames.target and pet.parent == frames.petframe
            and target.unit == "target" and pet.unit == "pet" and target.previewEnabled == false)
        check("containers sit above their frames and flow left to right, upward",
            point(target, "BOTTOMLEFT", frames.target, "TOPLEFT", 0, 4)
            and point(pet, "BOTTOMLEFT", frames.petframe, "TOPLEFT", 0, 4)
            and target.flow.anchor == "BOTTOMLEFT" and target.flow.horizontal == 1 and target.flow.vertical == 1
            and near(target.flow.lineSize, 220) and near(pet.flow.lineSize, 110))
        check("target groups split own and other auras through filter strings",
            order(target, "owndebuffs", "debuffs", "ownbuffs", "buffs")
            and target.groups.owndebuffs.filter == "HARMFUL|PLAYER" and target.groups.debuffs.filter == "HARMFUL|!PLAYER"
            and target.groups.ownbuffs.filter == "HELPFUL|PLAYER" and target.groups.buffs.filter == "HELPFUL|!PLAYER")
        local own, others, ownBuffs, buffs = target.groups.owndebuffs.options, target.groups.debuffs.options,
            target.groups.ownbuffs.options, target.groups.buffs.options
        check("own debuffs are large, the rest small, buffs on their own line", own.layout.elementWidth == 30
            and others.layout.elementWidth == 22 and ownBuffs.layout.elementWidth == 22 and buffs.layout.elementWidth == 22
            and ownBuffs.layout.forceNewLine == true and own.layout.forceNewLine ~= true and others.layout.forceNewLine ~= true
            and own.maxFrameCount == 12 and others.maxFrameCount == 12 and ownBuffs.maxFrameCount == 16
            and buffs.maxFrameCount == 16 and own.layout.elementSpacing == 4)
        check("pet container holds the two small debuff groups", order(pet, "owndebuffs", "debuffs")
            and pet.groups.owndebuffs.filter == "HARMFUL|PLAYER" and pet.groups.owndebuffs.options.layout.elementWidth == 22
            and pet.groups.debuffs.options.maxFrameCount == 8)
        local ownButton, otherButton = target:GetAuraGroupFrame("owndebuffs", 1), target:GetAuraGroupFrame("debuffs", 1)
        local buffButton = target:GetAuraGroupFrame("buffs", 1)
        check("own debuff buttons are full size and full alpha with dispel borders", near(ownButton.width, 30)
            and ownButton.alpha == nil and #ownButton.registered.dispel == 4 and ownButton.registered.cooldown ~= nil)
        check("other casters' buttons are small and dim", near(otherButton.width, 22)
            and near(otherButton.alpha, RikUI.Auras.DimAlpha) and RikUI.Auras.DimAlpha < 1
            and near(buffButton.alpha, RikUI.Auras.DimAlpha) and #buffButton.registered.dispel == 0)
        check("unit buttons never cancel auras", ownButton.cancelButtons == nil and otherButton.cancelButtons == nil
            and buffButton.cancelButtons == nil)
        check("the module never reads auras itself", auraReads == 0)
        local focus = module.Containers.focus
        check("the focus container sits above the focus cast bar at the frame's width", focus
            and focus.parent == frames.focus and focus.unit == "focus"
            and point(focus, "BOTTOMLEFT", frames.focus, "TOPLEFT", 0, 30) and near(focus.flow.lineSize, 160))
        check("the focus container holds own debuffs at the medium size, then other debuffs and buffs",
            order(focus, "owndebuffs", "debuffs", "buffs")
            and focus.groups.owndebuffs.options.layout.elementWidth == 26
            and focus.groups.debuffs.options.layout.elementWidth == 22 and focus.groups.buffs.options.maxFrameCount == 8)
        local focusUpdates, targetBefore = focus.updates, target.updates
        env.fire("PLAYER_FOCUS_CHANGED")
        check("a focus change refreshes the focus container only", focus.updates == focusUpdates + 1
            and target.updates == targetBefore and auraReads == 0)

        local targetUpdates, petUpdates = target.updates, pet.updates
        env.fire("PLAYER_TARGET_CHANGED")
        check("a target change refreshes the target container only", target.updates == targetUpdates + 1
            and pet.updates == petUpdates)
        env.fire("UNIT_PET", "player")
        check("a pet change refreshes the pet container", pet.updates == petUpdates + 1 and target.updates == targetUpdates + 1)
        env.fire("UNIT_PET", "target")
        env.fire("UNIT_AURA", "target")
        check("other units and aura events leave the containers to themselves", pet.updates == petUpdates + 1
            and target.updates == targetUpdates + 1)
        env.fire("UNIT_PET", env.SECRET)
        check("a secret event unit refreshes the pet container", pet.updates == petUpdates + 2)
        env.inCombat = true
        env.fire("PLAYER_TARGET_CHANGED")
        check("combat target changes still refresh", target.updates == targetUpdates + 2 and auraReads == 0)
        env.inCombat = false
        local failing = target.UpdateAllAuras
        target.UpdateAllAuras = function() error("blocked") end
        env.printed = {}
        env.fire("PLAYER_TARGET_CHANGED")
        env.fire("PLAYER_TARGET_CHANGED")
        check("a refused refresh warns once", printedContains("Unit auras refresh") and #env.printed == 1)
        target.UpdateAllAuras = failing

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        local output = table.concat(env.printed, "\n")
        check("debug reports the unit containers", output:find("Unit auras containers=3", 1, true) ~= nil)

        module = load()
        check("player and unit containers coexist under both modules", RikUI.Auras.Rows.buffs.container ~= nil
            and module.Containers.target ~= nil and auraReads == 0)
        module = load({ modules = { auras = false, unitframes = false } })
        check("missing unit frames skip the containers with one line", next(module.Containers) == nil
            and printedContains("Unit auras attach") and #env.printed == 1)
        module = load({ modules = { auras = false } }, true)
        check("combat login defers container creation", next(module.Containers) == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("containers follow after combat", module.Containers.target ~= nil and module.Containers.pet ~= nil)
        module = load({ modules = { auras = false } }, false, true)
        check("a missing container template warns once and creates nothing", next(module.Containers) == nil
            and printedContains("Auras container") and #env.printed == 1)
    end)
    CreateFrame = originalCreate
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat, env.auraContainerMissing = false, false
    check("unit aura suite completes", ok, reason)
end
