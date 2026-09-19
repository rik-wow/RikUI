-- The skin writes textures, fonts and alpha only; health, colour and target state stay Blizzard's.
-- Whether the client accepts an aura container on a nameplate token needs a beta check.
return function(check)
    local env = require("wow_stub")
    local originalCreate = CreateFrame
    local savedNamePlate = C_NamePlate
    local stub = {}
    local function region(value)
        function value:SetTexture(texture) self.texture = texture end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetAlpha(alpha) self.alpha = alpha end
        function value:SetPoint(...)
            local points = rawget(self, "points") or {}
            points[#points + 1] = { ... }
            self.points = points
        end
        function value:ClearAllPoints() self.points = {} end
        function value:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
        function value:SetShown(shown) self.shown = shown == true end
        return value
    end
    CreateFrame = function(kind, name, parent, template)
        local frame = originalCreate(kind, name, parent, template)
        local methods = getmetatable(frame).__index
        setmetatable(frame, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        function frame:SetAlpha(alpha) self.alpha = alpha end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:GetParent() return self.parent end
        function frame:GetFrameLevel() return rawget(self, "level") or 1 end
        function frame:SetFrameLevel(level) self.level = level end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return region(texture(self, ...)) end
        function frame:CreateFontString(...) return region(font(self, ...)) end
        return frame
    end
    local function printedContains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    -- Blizzard's layout pass puts the atlases back, as NamePlateUnitFrameMixin:UpdateAnchors does.
    local function unitFrame()
        local frame = CreateFrame("Button", nil, UIParent)
        frame.HealthBarsContainer = CreateFrame("Frame", nil, frame)
        local bar = CreateFrame("StatusBar", nil, frame.HealthBarsContainer)
        bar.barTexture, bar.bgTexture = bar:CreateTexture(), bar:CreateTexture()
        bar.selectedBorder = bar:CreateTexture()
        bar.selectedBorder.shown = false
        function bar.selectedBorder:Hide() self.shown = false end
        function bar.selectedBorder:IsShown() return self.shown end
        frame.HealthBarsContainer.healthBar = bar
        frame.name = frame:CreateFontString()
        frame.PlayerLevelDiffFrame = CreateFrame("Frame", nil, frame)
        frame.PlayerLevelDiffFrame.playerLevelDiffText = frame.PlayerLevelDiffFrame:CreateFontString()
        frame.AurasFrame = CreateFrame("Frame", nil, frame)
        frame.AurasFrame.DebuffListFrame = CreateFrame("Frame", nil, frame.AurasFrame)
        function frame:UpdateAnchors()
            bar.barTexture.texture, bar.bgTexture.texture, self.name.fontPath = "atlas-bar", "atlas-bg", "stock-font"
        end
        return frame
    end
    local function plate(unit, forbidden)
        local result = { UnitFrame = unitFrame() }
        function result:IsForbidden() return forbidden == true end
        stub.plates[unit] = result
        return result
    end
    local function load(profile, combat, missingContainer)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        env.auraContainerMissing = missingContainer == true
        stub.plates = {}
        C_NamePlate = { GetNamePlateForUnit = function(unit) return stub.plates[unit] end }
        profile = profile or {}
        profile.modules = profile.modules or {}
        profile.modules.unitframes, profile.modules.auras, profile.modules.unitauras = false, false, false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, nil
        for _, file in ipairs({ "core.lua", "hide.lua", "media.lua", "setup.lua", "setup-apply.lua", "layout.lua",
            "unitframes.lua", "unitframes-status.lua", "auras.lua", "auras-button.lua", "nameplates.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        env.inCombat = combat == true
        return RikUI.Nameplates
    end
    local ok, reason = pcall(function()
        local module = load()
        local media = RikUI.Media
        local first = plate("nameplate1")
        local frame, bar = first.UnitFrame, first.UnitFrame.HealthBarsContainer.healthBar
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        check("an added plate gets the RikUI bar texture and a flat dark backing", bar.barTexture.texture == media.statusbar
            and bar.bgTexture.texture == "Interface\\BUTTONS\\WHITE8X8" and bar.bgTexture.color[1] < 0.2
            and #bar.bgTexture.points == 2)
        check("the name and level text take the RikUI font", frame.name.fontPath == media.font
            and frame.PlayerLevelDiffFrame.playerLevelDiffText.fontPath == media.font)
        check("Blizzard's selection art is faded and the flat highlight starts hidden", bar.selectedBorder.alpha == 0
            and #bar.rikHighlight == 4 and bar.rikHighlight[1].shown == false)
        bar.selectedBorder:SetShown(true)
        check("the highlight follows Blizzard showing its selection border", bar.rikHighlight[1].shown == true
            and bar.rikHighlight[4].shown == true)
        bar.selectedBorder:Hide()
        check("the highlight follows Blizzard hiding it", bar.rikHighlight[1].shown == false)
        frame:UpdateAnchors()
        check("the skin is reapplied after Blizzard's layout pass", bar.barTexture.texture == media.statusbar
            and bar.bgTexture.texture == "Interface\\BUTTONS\\WHITE8X8" and frame.name.fontPath == media.font)

        local container = module.Containers[frame]
        check("the plate gets an own-debuff container on its unit below the frame", container ~= nil
            and container.unit == "nameplate1" and container.groups.owndebuffs.filter == "HARMFUL|PLAYER"
            and container.parent == frame and container.point[1] == "TOP" and container.point[3] == "BOTTOM")
        check("Blizzard's debuff list is faded once the container exists", frame.AurasFrame.DebuffListFrame.alpha == 0)
        local hooks, updates = #env.hooks, container.updates
        env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        check("a removed plate hides its container", container:IsShown() == false and module.Active.nameplate1 == nil)
        stub.plates.nameplate7, stub.plates.nameplate1 = first, nil
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
        check("a pooled frame is reused without new hooks and its container moves to the new token", #env.hooks == hooks
            and module.Containers[frame] == container and container.unit == "nameplate7" and container:IsShown()
            and container.updates == updates + 1)

        local forbidden = plate("nameplate2", true)
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        check("a forbidden plate is never touched", rawget(forbidden.UnitFrame.HealthBarsContainer.healthBar.barTexture, "texture") == nil
            and module.Containers[forbidden.UnitFrame] == nil)
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
        env.fire("NAME_PLATE_UNIT_ADDED", env.SECRET)
        check("an unknown or secret token is ignored without printing", #env.printed == 0)
        local bare = plate("nameplate4")
        bare.UnitFrame.PlayerLevelDiffFrame, bare.UnitFrame.AurasFrame = nil, nil
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
        check("a plate without a level frame or aura frame is still skinned",
            bare.UnitFrame.HealthBarsContainer.healthBar.barTexture.texture == media.statusbar and #env.printed == 0)

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports skinned frames, active plates and containers",
            printedContains("Nameplates skinned=2 active=2 containers=2"))

        module = load(nil, true)
        local fighting = plate("nameplate1")
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        check("a plate added in combat is skinned but gets no container yet",
            fighting.UnitFrame.HealthBarsContainer.healthBar.barTexture.texture == RikUI.Media.statusbar
            and module.Containers[fighting.UnitFrame] == nil
            and rawget(fighting.UnitFrame.AurasFrame.DebuffListFrame, "alpha") == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat gives active plates their containers", module.Containers[fighting.UnitFrame] ~= nil
            and module.Containers[fighting.UnitFrame].unit == "nameplate1")

        module = load(nil, false, true)
        local plain = plate("nameplate1")
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        check("a client without the aura container keeps Blizzard's debuffs and warns once",
            module.Containers[plain.UnitFrame] == nil and rawget(plain.UnitFrame.AurasFrame.DebuffListFrame, "alpha") == nil
            and printedContains("Auras container") and #env.printed == 1)

        module = load({ modules = { nameplates = false } })
        local stock = plate("nameplate1")
        env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        check("a disabled module leaves the stock plates alone",
            rawget(stock.UnitFrame.HealthBarsContainer.healthBar.barTexture, "texture") == nil and #env.hooks == 0)
    end)
    CreateFrame = originalCreate
    C_NamePlate = savedNamePlate
    env.inCombat, env.auraContainerMissing = false, false
    check("nameplate suite completes", ok, reason)
end
