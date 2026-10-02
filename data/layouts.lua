-- Whole-screen layouts. Every movable frame has a place in each one. Positions are written from the
-- constants below and never as bare numbers, so edges line up and spacing is the same everywhere:
-- MARGIN to the screen edge, GAP between neighbours. Each frame anchors to the screen edge or corner
-- it sits nearest (or to the bottom centre, where the bars are), so a layout holds on 16:10 and 21:9
-- as well as on 16:9. layout-audit.lua checks all of it; tests/layouts.test.lua runs the check.
local core = RikUI
local layouts = { Order = { "centered", "classic", "hud", "healer" }, MARGIN = 16, GAP = 4 }
core.Layouts = layouts

local MARGIN, GAP = layouts.MARGIN, layouts.GAP
local BAR_WIDTH, BAR_HEIGHT, BAR_GAP = 498, 36, 6
local BAR_LEFT = -BAR_WIDTH / 2
local UNIT_WIDTH, UNIT_HEIGHT, SMALL_WIDTH, SMALL_HEIGHT, FOCUS_WIDTH, FOCUS_HEIGHT = 220, 44, 110, 30, 160, 36
local CAST_HEIGHT, ROW_HEIGHT = 22, 30
-- The cooldown strip (src/modules/cooldowns/cooldowns-strip.lua): 280 wide, two rows of 36 px icons at rest.
local STRIP_WIDTH, STRIP_HEIGHT = 280, 2 * (36 + GAP) - GAP
-- The combat column: the strip, the resource strip, the player cast bar and the weapon timers share this width.
local COLUMN_WIDTH = STRIP_WIDTH

-- Nominal footprints. A frame whose size is not fixed (tracker, bags, chat, damage meter, loot list)
-- gets the room a layout keeps free for it; the rest are the frames' real sizes, which the suite pins.
layouts.Sizes = {
    main = { width = BAR_WIDTH, height = BAR_HEIGHT }, bar2 = { width = BAR_WIDTH, height = BAR_HEIGHT },
    bar3 = { width = BAR_WIDTH, height = BAR_HEIGHT }, bar4 = { width = BAR_HEIGHT, height = BAR_WIDTH },
    bar5 = { width = BAR_HEIGHT, height = BAR_WIDTH }, stance = { width = 102, height = ROW_HEIGHT },
    pet = { width = 354, height = ROW_HEIGHT }, xpbar = { width = BAR_WIDTH, height = 18 },
    player = { width = UNIT_WIDTH, height = UNIT_HEIGHT }, target = { width = UNIT_WIDTH, height = UNIT_HEIGHT },
    focus = { width = FOCUS_WIDTH, height = FOCUS_HEIGHT }, tot = { width = SMALL_WIDTH, height = SMALL_HEIGHT },
    petframe = { width = SMALL_WIDTH, height = SMALL_HEIGHT }, party = { width = 150, height = 186 },
    raid = { width = 604, height = 166 }, castplayer = { width = COLUMN_WIDTH, height = CAST_HEIGHT },
    casttarget = { width = UNIT_WIDTH, height = CAST_HEIGHT }, castfocus = { width = FOCUS_WIDTH, height = CAST_HEIGHT },
    castpet = { width = SMALL_WIDTH, height = CAST_HEIGHT }, buffs = { width = 268, height = 132 },
    debuffs = { width = 268, height = 64 }, minimap = { width = 200, height = 270 },
    micromenu = { width = 238, height = 70 }, bagspace = { width = 210, height = 22 }, durability = { width = 132, height = 18 },
    mirrortimers = { width = 220, height = 56 }, swingtimer = { width = COLUMN_WIDTH, height = 76 },
    combopoints = { width = 58, height = 10 }, totems = { width = 121, height = 28 },
    combattimer = { width = 110, height = 20 }, stopwatch = { width = 110, height = 20 },
    druidmana = { width = 121, height = 18 },
    cooldowns = { width = STRIP_WIDTH, height = STRIP_HEIGHT },
    classbuffs = { width = 188, height = 60 }, classeffects = { width = 188, height = 60 },
    questtracker = { width = 240, height = 120 }, questtimers = { width = 220, height = 38 },
    loot = { width = 228, height = 174 }, tooltip = { width = 250, height = 150 },
    bags = { width = 394, height = 360 }, chat = { width = 344, height = 214 },
    damagemeter = { width = 260, height = 180 },
    combatresource = { width = COLUMN_WIDTH, height = 18 },
}
-- Room outside the frame: the reputation row under the experience row.
-- The minimap header and status footer are included in its nominal footprint.
layouts.Pads = { minimap = { top = 0, bottom = 0 }, xpbar = { bottom = 14 } }
-- The chat's rectangle is everything you see of it, not only the message area: the panel's border
-- left and right, the tabs above, the channel strip and the input bar below. chat-move.lua sizes its
-- holder with these, so the layout, the overlay and the audit all mean the same rectangle. The nominal
-- chat above is a 336x136 message area plus this.
layouts.ChatFootprint = { left = 4, right = 4, top = 28, bottom = 50 }
-- Windows that float over the screen block nothing; party and raid are never shown together.
layouts.Floating = { tooltip = true, bags = true, loot = true }
layouts.Exclusive = { party = "group", raid = "group" }
-- The message area a layout gives the chat on the narrowest screen; layout-presets.lua widens it.
layouts.ChatSize = { width = layouts.Sizes.chat.width - layouts.ChatFootprint.left - layouts.ChatFootprint.right,
    height = layouts.Sizes.chat.height - layouts.ChatFootprint.top - layouts.ChatFootprint.bottom }

local function at(point, relativePoint, x, y) return { point = point, relativePoint = relativePoint, x = x, y = y } end
local function bottom(x, y) return at("BOTTOM", "BOTTOM", x, y) end
local function bottomLeftOfCentre(x, y) return at("BOTTOMLEFT", "BOTTOM", x, y) end
local function bottomRightOfCentre(x, y) return at("BOTTOMRIGHT", "BOTTOM", x, y) end
local function topRight(x, y) return at("TOPRIGHT", "TOPRIGHT", x, y) end
local function topLeft(x, y) return at("TOPLEFT", "TOPLEFT", x, y) end
local function bottomRight(x, y) return at("BOTTOMRIGHT", "BOTTOMRIGHT", x, y) end

-- The bar stack, bottom centre, the same in every layout.
local XP_TOP = MARGIN + layouts.Sizes.xpbar.height + layouts.Pads.xpbar.bottom
local MAIN_Y = XP_TOP + GAP
local BAR_PITCH = BAR_HEIGHT + BAR_GAP
local STANCE_Y = MAIN_Y + 3 * BAR_PITCH
local PET_BAR_Y = STANCE_Y + ROW_HEIGHT + BAR_GAP
local STACK_TOP = PET_BAR_Y + ROW_HEIGHT
-- The right edge: two vertical bars at the margin, then one column that shares a right edge.
local SIDE_BAR_2 = -(MARGIN + BAR_HEIGHT + BAR_GAP)
local COLUMN = SIDE_BAR_2 - BAR_HEIGHT - GAP
local MENU_TOP = MARGIN + layouts.Sizes.micromenu.height
local BAGSPACE_Y = MENU_TOP + GAP
local METER_Y = BAGSPACE_Y + layouts.Sizes.bagspace.height + GAP
local METER_TOP = METER_Y + layouts.Sizes.damagemeter.height
-- The top right column: minimap card, aura rows to its left, timers and tracker under it.
local MINIMAP_Y = -(MARGIN + layouts.Pads.minimap.top)
local MINIMAP_BOTTOM = MINIMAP_Y - layouts.Sizes.minimap.height - layouts.Pads.minimap.bottom
local AURAS_X = COLUMN - layouts.Sizes.minimap.width - GAP
local TIMERS_Y = MINIMAP_BOTTOM - GAP
local TRACKER_Y = TIMERS_Y - layouts.Sizes.questtimers.height - GAP
-- The chat's rectangle sits in the bottom left corner at the margin; it is anchored by its centre.
local CHAT = at("CENTER", "BOTTOMLEFT", MARGIN + layouts.Sizes.chat.width / 2, MARGIN + layouts.Sizes.chat.height / 2)

local function shared()
    return {
        xpbar = at("TOP", "BOTTOM", 0, XP_TOP), main = bottom(0, MAIN_Y), bar2 = bottom(0, MAIN_Y + BAR_PITCH),
        bar3 = bottom(0, MAIN_Y + 2 * BAR_PITCH), stance = bottomLeftOfCentre(BAR_LEFT, STANCE_Y),
        pet = bottomLeftOfCentre(BAR_LEFT, PET_BAR_Y),
        bar4 = bottomRight(-MARGIN, MARGIN), bar5 = bottomRight(SIDE_BAR_2, MARGIN),
        micromenu = bottomRight(COLUMN, MARGIN), bagspace = bottomRight(COLUMN, BAGSPACE_Y),
        damagemeter = bottomRight(COLUMN, METER_Y),
        tooltip = bottomRight(COLUMN, METER_TOP + GAP), bags = bottomRight(COLUMN, METER_TOP + GAP),
        minimap = topRight(COLUMN, MINIMAP_Y), buffs = topRight(AURAS_X, -MARGIN),
        debuffs = topRight(AURAS_X, -MARGIN - layouts.Sizes.buffs.height - GAP),
        questtimers = topRight(COLUMN, TIMERS_Y), questtracker = topRight(COLUMN, TRACKER_Y),
        combattimer = at("TOP", "TOP", 66, -110), stopwatch = at("TOP", "TOP", 66, -134),
        durability = at("TOP", "TOP", 0, -MARGIN),
        mirrortimers = at("TOP", "TOP", 0, -MARGIN - layouts.Sizes.durability.height - 2 * GAP),
        classbuffs = bottomLeftOfCentre(-328, 652), classeffects = bottomLeftOfCentre(-544, 652),
        chat = CHAT, loot = at("TOPLEFT", "CENTER", 20, 162),
        party = topLeft(MARGIN, -120), raid = topLeft(MARGIN, -120),
    }
end

local function layout(label, description, own)
    local positions = shared()
    for key, position in pairs(own) do positions[key] = position end
    return { label = label, description = description, positions = positions }
end

-- Centered: unit frames above the bar stack, flush with its ends; pets and focus outside them.
local CAST_ROW = STACK_TOP + GAP
local UNIT_ROW = CAST_ROW + CAST_HEIGHT + GAP
local ABOVE_UNITS = UNIT_ROW + UNIT_HEIGHT + GAP
local UNIT_X = BAR_LEFT + UNIT_WIDTH / 2
local OUTSIDE = BAR_LEFT - GAP
layouts.LegacySwingCentered = bottom(0, ABOVE_UNITS + layouts.Sizes.combopoints.height + GAP)
local FOCUS_ROW = UNIT_ROW + SMALL_HEIGHT + GAP

layouts.centered = layout("Centered", "Unit frames above the action bars in the middle of the screen, the way ElvUI "
    .. "and pfUI arrange them. You never look away from your character.", {
    player = bottom(UNIT_X, UNIT_ROW), target = bottom(-UNIT_X, UNIT_ROW),
    castplayer = bottom(UNIT_X, CAST_ROW), casttarget = bottom(-UNIT_X, CAST_ROW),
    petframe = bottomRightOfCentre(OUTSIDE, UNIT_ROW), castpet = bottomRightOfCentre(OUTSIDE, CAST_ROW),
    tot = bottomLeftOfCentre(-OUTSIDE, UNIT_ROW),
    focus = bottomRightOfCentre(OUTSIDE, FOCUS_ROW),
    castfocus = bottomRightOfCentre(OUTSIDE, FOCUS_ROW + FOCUS_HEIGHT + GAP),
    totems = bottomLeftOfCentre(BAR_LEFT, ABOVE_UNITS), combopoints = bottom(0, ABOVE_UNITS),
    druidmana = bottomRightOfCentre(-BAR_LEFT, ABOVE_UNITS),
    swingtimer = bottom(UNIT_X, ABOVE_UNITS + layouts.Sizes.totems.height + GAP),
})

-- Classic: Blizzard's corners. Player and target top left, the player's cast bar over the bars.
local TARGET_X = MARGIN + UNIT_WIDTH + 5 * GAP
local UNDER_UNITS = -(MARGIN + UNIT_HEIGHT + GAP)
local SECOND_ROW = UNDER_UNITS - SMALL_HEIGHT - GAP - 2 * GAP
local GROUP_Y = SECOND_ROW - FOCUS_HEIGHT - GAP - CAST_HEIGHT - 2 * GAP
local CLASS_ROW = CAST_ROW + CAST_HEIGHT + GAP

layouts.classic = layout("Classic", "Blizzard's arrangement: player and target in the top left corner, the party "
    .. "under them, your cast bar over the action bars.", {
    combattimer = at("TOP", "TOP", 66, -190), stopwatch = topLeft(MARGIN, -136),
    classbuffs = bottomLeftOfCentre(-316, 296), classeffects = bottomLeftOfCentre(104, 280),
    player = topLeft(MARGIN, -MARGIN), target = topLeft(TARGET_X, -MARGIN),
    petframe = topLeft(MARGIN, UNDER_UNITS), castpet = topLeft(MARGIN, UNDER_UNITS - SMALL_HEIGHT - GAP),
    casttarget = topLeft(TARGET_X, UNDER_UNITS),
    focus = topLeft(TARGET_X, SECOND_ROW), castfocus = topLeft(TARGET_X, SECOND_ROW - FOCUS_HEIGHT - GAP),
    tot = topLeft(TARGET_X + FOCUS_WIDTH + GAP, SECOND_ROW),
    party = topLeft(MARGIN, GROUP_Y), raid = topLeft(MARGIN, GROUP_Y),
    castplayer = bottom(0, CAST_ROW), swingtimer = bottom(0, CLASS_ROW),
    combopoints = bottom(0, CLASS_ROW + layouts.Sizes.swingtimer.height + GAP),
    totems = bottom(-100, CLASS_ROW + layouts.Sizes.swingtimer.height + layouts.Sizes.combopoints.height + 2 * GAP),
    druidmana = bottomRightOfCentre(-layouts.Sizes.swingtimer.width / 2 - GAP, CLASS_ROW),
})

-- HUD: a bottom-anchored combat cluster above the bars, leaving the character clear.
local HUD_SPREAD = 120
local HUD_SWING = STACK_TOP + GAP + layouts.Sizes.classbuffs.height + GAP
local HUD_Y = HUD_SWING + UNIT_HEIGHT + CAST_HEIGHT - GAP
local HUD_X = HUD_SPREAD + UNIT_WIDTH / 2
local HUD_EDGE = HUD_SPREAD + UNIT_WIDTH
local HUD_UNDER = HUD_Y - GAP - CAST_HEIGHT
local HUD_CAST = HUD_SWING + layouts.Sizes.swingtimer.height + GAP

-- The class rows here are placeholders: layouts.CombatPositions below overrides them in every layout.
layouts.hud = layout("HUD", "A central stack of cooldowns, resources, casts and weapon timers above the action bars, "
    .. "with unit frames and class effects nearby.", {
    classbuffs = bottomLeftOfCentre(-HUD_EDGE, HUD_Y + UNIT_HEIGHT + GAP),
    classeffects = bottomLeftOfCentre(HUD_SPREAD, HUD_Y + UNIT_HEIGHT + GAP),
    player = bottom(-HUD_X, HUD_Y), target = bottom(HUD_X, HUD_Y),
    swingtimer = bottom(0, HUD_SWING), castplayer = bottom(0, HUD_CAST),
    combopoints = bottom(0, HUD_CAST + CAST_HEIGHT + 2 * GAP),
    totems = bottom(0, HUD_CAST + CAST_HEIGHT + layouts.Sizes.combopoints.height + 3 * GAP),
    druidmana = bottomRightOfCentre(-layouts.Sizes.swingtimer.width / 2 - GAP, HUD_SWING),
    casttarget = bottom(HUD_X, HUD_UNDER), tot = bottomLeftOfCentre(HUD_SPREAD, HUD_UNDER - GAP - SMALL_HEIGHT),
    petframe = bottomRightOfCentre(BAR_LEFT - GAP, HUD_UNDER - GAP - SMALL_HEIGHT),
    castpet = bottomRightOfCentre(BAR_LEFT - SMALL_WIDTH - 2 * GAP, HUD_UNDER - GAP - SMALL_HEIGHT),
    focus = bottomRightOfCentre(-HUD_EDGE - GAP, HUD_Y + GAP),
    castfocus = bottomRightOfCentre(-HUD_EDGE - GAP, HUD_Y - CAST_HEIGHT),
    party = topLeft(MARGIN, -120),
})

local CORE_HALF = layouts.Sizes.cooldowns.width / 2
local CORE_SWING = STACK_TOP + GAP
local CORE_CAST = CORE_SWING + layouts.Sizes.swingtimer.height + GAP
local CORE_POWER = CORE_CAST + CAST_HEIGHT + GAP
local CORE_COOLDOWNS = CORE_POWER + layouts.Sizes.combatresource.height + GAP
local CORE_EXTRA = CORE_COOLDOWNS + layouts.Sizes.cooldowns.height + GAP
-- Healer: the grid clears the combat column; own units sit above, focus and pets beside it.
local GRID_LEFT = -layouts.Sizes.raid.width / 2
-- Reserve the tallest supporting stack, including the gaps after combo points and form mana.
local GRID_Y = CORE_EXTRA + layouts.Sizes.combopoints.height + layouts.Sizes.druidmana.height + 2 * GAP
local HEALER_CAST = GRID_Y + layouts.Sizes.party.height + GAP
local HEALER_UNITS = HEALER_CAST + CAST_HEIGHT + GAP
local HEALER_PET = HEALER_CAST - SMALL_HEIGHT - GAP
local SECOND_X = GRID_LEFT + UNIT_WIDTH + GAP
local THIRD_X = SECOND_X + UNIT_WIDTH + GAP

layouts.healer = layout("Healer", "Party and raid frames over the action bars, where a healer looks, with your own "
    .. "frames above them and focus and pet frames beside them.", {
    combattimer = topLeft(MARGIN, -MARGIN), stopwatch = topLeft(MARGIN, -MARGIN - 20 - GAP),
    raid = bottom(0, GRID_Y), party = bottom(0, GRID_Y),
    player = bottomLeftOfCentre(GRID_LEFT, HEALER_UNITS),
    target = bottomLeftOfCentre(SECOND_X, HEALER_UNITS),
    tot = bottomLeftOfCentre(THIRD_X, HEALER_UNITS),
    casttarget = bottomLeftOfCentre(SECOND_X, HEALER_CAST),
    focus = bottomRightOfCentre(GRID_LEFT - GAP, HEALER_UNITS),
    castfocus = bottomRightOfCentre(GRID_LEFT - GAP, HEALER_CAST),
    petframe = bottomRightOfCentre(GRID_LEFT - GAP, HEALER_PET),
    castpet = bottomRightOfCentre(GRID_LEFT - GAP, HEALER_PET - CAST_HEIGHT - GAP),
    loot = at("TOPLEFT", "LEFT", MARGIN, 100),
})
-- On 16:10 the grid reaches under the tracker's column, so this layout keeps room for a header and one quest;
-- the tracker caps itself at whatever is under it and says how many quests it hides.
layouts.healer.sizes = { questtracker = { width = 240, height = 56 } }

-- The same combat information belongs in the same viewing area for every class
-- and every preset. The cooldown strip owns the middle; the class effect rows flank
-- the cast bar and the resource strip on either side.
layouts.CombatPositions = {
    castplayer = bottom(0, CORE_CAST),
    combatresource = bottom(0, CORE_POWER),
    cooldowns = bottom(0, CORE_COOLDOWNS),
    classbuffs = bottomRightOfCentre(-CORE_HALF - GAP, CORE_CAST),
    classeffects = bottomLeftOfCentre(CORE_HALF + GAP, CORE_CAST),
    combopoints = bottom(0, CORE_EXTRA),
    totems = bottom(0, CORE_EXTRA),
    druidmana = bottom(0, CORE_EXTRA + layouts.Sizes.combopoints.height + GAP),
    swingtimer = bottom(0, CORE_SWING),
}
-- The unit row sits above the supporting rows a class uses: combo points (rogue, druid), totems
-- (shaman) and form mana (druid), then the target cast bar's own row under the target frame. Any
-- other class keeps only that cast row between the strip and its unit frames, so the HUD has no
-- empty band reserved for displays it never shows. No class shows all three rows, so an unknown
-- class keeps the room of the tallest stack a class has, not the sum of every row.
layouts.SupportingRows = {
    { key = "combopoints", classes = { ROGUE = true, DRUID = true } },
    { key = "totems", classes = { SHAMAN = true } },
    { key = "druidmana", classes = { DRUID = true } },
}
layouts.CombatUnitKeys = { "player", "target", "tot", "focus", "casttarget", "castfocus" }
layouts.CombatRowLayouts = { centered = true, hud = true }
local function classRows(class)
    local places, y = {}, CORE_EXTRA
    for _, row in ipairs(layouts.SupportingRows) do
        if row.classes[class] then
            places[row.key] = y
            y = y + layouts.Sizes[row.key].height + GAP
        end
    end
    return places, y
end
-- Where each supporting row a class shows stands, and the top of its stack. For an unknown class
-- every row stands where its highest class puts it, under the tallest stack.
function layouts.SupportingRowPlaces(class)
    if class ~= nil then return classRows(class) end
    local places, top = {}, CORE_EXTRA
    for _, row in ipairs(layouts.SupportingRows) do
        for name in pairs(row.classes) do
            local own, y = classRows(name)
            top = math.max(top, y)
            for key, place in pairs(own) do places[key] = math.max(places[key] or place, place) end
        end
    end
    return places, top
end
-- Two supporting rows share the screen only when some class shows both.
function layouts.RowsMeet(first, second)
    local a, b
    for _, row in ipairs(layouts.SupportingRows) do
        if row.key == first then a = row.classes elseif row.key == second then b = row.classes end
    end
    if not a or not b then return true end
    for class in pairs(a) do
        if b[class] then return true end
    end
    return false
end
function layouts.CombatUnitRow(class)
    local _, top = layouts.SupportingRowPlaces(class)
    return top + CAST_HEIGHT + GAP
end
local COMBAT_UNIT_ROW = layouts.CombatUnitRow(nil)
for _, name in ipairs({ "centered", "hud" }) do
    local positions = layouts[name].positions
    positions.player.y, positions.target.y = COMBAT_UNIT_ROW, COMBAT_UNIT_ROW
    positions.casttarget.y = COMBAT_UNIT_ROW - CAST_HEIGHT - GAP
    positions.tot = bottomLeftOfCentre(CORE_HALF + GAP + UNIT_WIDTH + GAP, COMBAT_UNIT_ROW)
    positions.focus = bottomRightOfCentre(-CORE_HALF - GAP - UNIT_WIDTH - GAP, COMBAT_UNIT_ROW)
    positions.castfocus = bottomRightOfCentre(-CORE_HALF - GAP - UNIT_WIDTH - GAP, COMBAT_UNIT_ROW - CAST_HEIGHT - GAP)
    positions.petframe = bottomRightOfCentre(-CORE_HALF - GAP - UNIT_WIDTH - GAP, CORE_CAST)
    positions.castpet = bottomRightOfCentre(-CORE_HALF - GAP - UNIT_WIDTH - 2 * GAP - SMALL_WIDTH, CORE_CAST)
end
-- A short screen (768 units high at the default UI scale) has no room for every recipe place. The
-- combat column keeps its place there and these give way by design, before the packer has to:
-- the group frames go up to the top margin, clear of the unit row; the target of target goes above
-- the target where it would otherwise reach into the minimap column; and the HUD's player and
-- target close in until the target clears that column.
layouts.SHORT_SCREEN = 900
local function short(name, screen)
    return screen ~= nil and screen.height < layouts.SHORT_SCREEN
end
-- Where the class effect row reaches under the tracker's column (16:10), the tracker takes the quest
-- timers' place under the minimap and keeps the room down to that row; the tracker caps itself.
local EFFECTS_RIGHT = CORE_HALF + GAP + layouts.Sizes.classeffects.width
local EFFECTS_TOP = CORE_CAST + layouts.Sizes.classeffects.height
local function crowded(screen)
    return screen.width / 2 + EFFECTS_RIGHT + GAP > screen.width + COLUMN - layouts.Sizes.questtracker.width
end
function layouts.CompactSizes(name, screen)
    if not short(name, screen) or not crowded(screen) then return nil end
    return { questtracker = { width = layouts.Sizes.questtracker.width,
        height = screen.height + TIMERS_Y - EFFECTS_TOP - GAP } }
end
function layouts.Compact(name, screen, positions)
    if not short(name, screen) then return positions end
    if crowded(screen) then positions.questtracker = topRight(COLUMN, TIMERS_Y) end
    if name == "classic" then
        -- Keep corner units fixed and fit the wide raid footprint between them and the column.
        local focusX = TARGET_X + UNIT_WIDTH + GAP
        positions.focus = topLeft(focusX, -MARGIN)
        positions.castfocus = topLeft(focusX, -MARGIN - FOCUS_HEIGHT - GAP)
        positions.tot = topLeft(focusX + FOCUS_WIDTH + GAP, -MARGIN)
        positions.castpet = topLeft(MARGIN + SMALL_WIDTH + GAP, UNDER_UNITS)
        positions.raid, positions.party = topLeft(MARGIN, UNDER_UNITS - SMALL_HEIGHT - GAP),
            topLeft(MARGIN, UNDER_UNITS - SMALL_HEIGHT - GAP)
    end
    if not layouts.CombatRowLayouts[name] then return positions end
    local half = screen.width / 2
    local column = screen.width + COLUMN - layouts.Sizes.minimap.width - GAP
    if name == "hud" then
        local spread = math.max(0, math.min(HUD_SPREAD, math.floor(column - half - UNIT_WIDTH)))
        local x = spread + UNIT_WIDTH / 2
        positions.player.x, positions.target.x, positions.casttarget.x = -x, x, x
    end
    local row, target = positions.player.y, positions.target.x + UNIT_WIDTH / 2
    if half + positions.tot.x + SMALL_WIDTH > column then
        positions.tot = bottomRightOfCentre(target, row + UNIT_HEIGHT + GAP)
    end
    positions.raid, positions.party = topLeft(MARGIN, -MARGIN), topLeft(MARGIN, -MARGIN)
    return positions
end

for _, name in ipairs(layouts.Order) do
    for key, place in pairs(layouts.CombatPositions) do
        layouts[name].positions[key] = { point=place.point, relativePoint=place.relativePoint, x=place.x, y=place.y }
    end
end
