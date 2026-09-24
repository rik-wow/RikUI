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
    raid = { width = 604, height = 166 }, castplayer = { width = UNIT_WIDTH, height = CAST_HEIGHT },
    casttarget = { width = UNIT_WIDTH, height = CAST_HEIGHT }, castfocus = { width = FOCUS_WIDTH, height = CAST_HEIGHT },
    castpet = { width = SMALL_WIDTH, height = CAST_HEIGHT }, buffs = { width = 268, height = 132 },
    debuffs = { width = 268, height = 64 }, minimap = { width = 200, height = 200 },
    micromenu = { width = 118, height = 22 }, durability = { width = 132, height = 18 },
    mirrortimers = { width = 220, height = 56 }, swingtimer = { width = 200, height = 76 },
    combopoints = { width = 58, height = 10 }, totems = { width = 121, height = 28 },
    questtracker = { width = 240, height = 120 }, questtimers = { width = 220, height = 38 },
    loot = { width = 228, height = 174 }, tooltip = { width = 250, height = 150 },
    bags = { width = 394, height = 360 }, chat = { width = 344, height = 214 },
    damagemeter = { width = 260, height = 180 },
}
-- Room outside the frame: the minimap's zone line above and clock below, the reputation row under the
-- experience row.
layouts.Pads = { minimap = { top = 16, bottom = 16 }, xpbar = { bottom = 14 } }
-- The chat's rectangle is everything you see of it, not only the message area: the panel's border
-- left and right, the tabs above, the channel strip and the input bar below. chat-move.lua sizes its
-- holder with these, so the layout, the overlay and the audit all mean the same rectangle. The nominal
-- chat above is a 336x136 message area plus this.
layouts.ChatFootprint = { left = 4, right = 4, top = 28, bottom = 50 }
-- Windows that float over the screen block nothing; party and raid are never shown together.
layouts.Floating = { tooltip = true, bags = true }
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
local METER_Y = MENU_TOP + GAP
local METER_TOP = METER_Y + layouts.Sizes.damagemeter.height
-- The top right corner: minimap under its zone line, aura rows to its left, timers and tracker under it.
local MINIMAP_Y = -(MARGIN + layouts.Pads.minimap.top)
local MINIMAP_BOTTOM = MINIMAP_Y - layouts.Sizes.minimap.height - layouts.Pads.minimap.bottom
local AURAS_X = -(MARGIN + layouts.Sizes.minimap.width + GAP)
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
        micromenu = bottomRight(COLUMN, MARGIN), damagemeter = bottomRight(COLUMN, METER_Y),
        tooltip = bottomRight(COLUMN, METER_TOP + GAP), bags = bottomRight(COLUMN, METER_TOP + GAP),
        minimap = topRight(-MARGIN, MINIMAP_Y), buffs = topRight(AURAS_X, -MARGIN),
        debuffs = topRight(AURAS_X, -MARGIN - layouts.Sizes.buffs.height - GAP),
        questtimers = topRight(COLUMN, TIMERS_Y), questtracker = topRight(COLUMN, TRACKER_Y),
        durability = at("TOP", "TOP", 0, -MARGIN),
        mirrortimers = at("TOP", "TOP", 0, -MARGIN - layouts.Sizes.durability.height - 2 * GAP),
        chat = CHAT, loot = at("TOPLEFT", "CENTER", 20, 162),
        party = at("LEFT", "LEFT", MARGIN, 0), raid = topLeft(MARGIN, -120),
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
    player = topLeft(MARGIN, -MARGIN), target = topLeft(TARGET_X, -MARGIN),
    petframe = topLeft(MARGIN, UNDER_UNITS), castpet = topLeft(MARGIN, UNDER_UNITS - SMALL_HEIGHT - GAP),
    casttarget = topLeft(TARGET_X, UNDER_UNITS),
    focus = topLeft(TARGET_X, SECOND_ROW), castfocus = topLeft(TARGET_X, SECOND_ROW - FOCUS_HEIGHT - GAP),
    tot = topLeft(TARGET_X + FOCUS_WIDTH + GAP, SECOND_ROW),
    party = topLeft(MARGIN, GROUP_Y), raid = topLeft(MARGIN, GROUP_Y),
    castplayer = bottom(0, CAST_ROW), swingtimer = bottom(0, CLASS_ROW),
    combopoints = bottom(0, CLASS_ROW + layouts.Sizes.swingtimer.height + GAP),
    totems = bottom(-100, CLASS_ROW + layouts.Sizes.swingtimer.height + layouts.Sizes.combopoints.height + 2 * GAP),
})

-- HUD: player and target either side of the character, the cast bar and class widgets between them.
local HUD_Y, HUD_SPREAD = STACK_TOP + UNIT_HEIGHT + CAST_HEIGHT - GAP, 120
local HUD_X = HUD_SPREAD + UNIT_WIDTH / 2
local HUD_EDGE = HUD_SPREAD + UNIT_WIDTH
local HUD_UNDER = HUD_Y - GAP - CAST_HEIGHT
local HUD_SWING = STACK_TOP + GAP
local HUD_CAST = HUD_SWING + layouts.Sizes.swingtimer.height + GAP

layouts.hud = layout("HUD", "Player and target close beside your character with the cast bar between them, "
    .. "everything else pushed to the edges.", {
    player = bottom(-HUD_X, HUD_Y), target = bottom(HUD_X, HUD_Y),
    swingtimer = bottom(0, HUD_SWING), castplayer = bottom(0, HUD_CAST),
    combopoints = bottom(0, HUD_CAST + CAST_HEIGHT + 2 * GAP),
    totems = bottom(-100, HUD_CAST + CAST_HEIGHT + layouts.Sizes.combopoints.height + 3 * GAP),
    casttarget = bottom(HUD_X, HUD_UNDER), tot = bottomLeftOfCentre(HUD_SPREAD, HUD_UNDER - GAP - SMALL_HEIGHT),
    petframe = bottomRightOfCentre(BAR_LEFT - GAP, HUD_UNDER - GAP - SMALL_HEIGHT),
    castpet = bottomRightOfCentre(BAR_LEFT - SMALL_WIDTH - 2 * GAP, HUD_UNDER - GAP - SMALL_HEIGHT),
    focus = bottomRightOfCentre(-HUD_EDGE - GAP, HUD_Y + GAP),
    castfocus = bottomRightOfCentre(-HUD_EDGE - GAP, HUD_Y - CAST_HEIGHT),
    party = at("LEFT", "LEFT", MARGIN, 90),
})

-- Healer: the group over the bars where the eyes are, your own frames in rows above its left end.
local GRID_LEFT = -layouts.Sizes.raid.width / 2
local GRID_Y = STACK_TOP + GAP
local ROW_A = GRID_Y + layouts.Sizes.party.height + GAP
local ROW_B = ROW_A + UNIT_HEIGHT + GAP
local ROW_C = ROW_B + CAST_HEIGHT + GAP
local ROW_D = ROW_C + FOCUS_HEIGHT + GAP
local ROW_E = ROW_D + CAST_HEIGHT + GAP
local SECOND_X = GRID_LEFT + UNIT_WIDTH + GAP
local THIRD_X = SECOND_X + UNIT_WIDTH + GAP

layouts.healer = layout("Healer", "Party and raid frames over the action bars, where a healer looks, with your own "
    .. "frames in rows above them.", {
    raid = bottom(0, GRID_Y), party = bottom(0, GRID_Y),
    player = bottomLeftOfCentre(GRID_LEFT, ROW_A), target = bottomLeftOfCentre(SECOND_X, ROW_A),
    tot = bottomLeftOfCentre(THIRD_X, ROW_A),
    castplayer = bottomLeftOfCentre(GRID_LEFT, ROW_B), casttarget = bottomLeftOfCentre(SECOND_X, ROW_B),
    petframe = bottomLeftOfCentre(GRID_LEFT, ROW_C), castpet = bottomLeftOfCentre(GRID_LEFT, ROW_D),
    focus = bottomLeftOfCentre(SECOND_X, ROW_C), castfocus = bottomLeftOfCentre(SECOND_X, ROW_D),
    totems = bottomLeftOfCentre(GRID_LEFT, ROW_E),
    combopoints = bottomLeftOfCentre(GRID_LEFT + layouts.Sizes.totems.width + GAP, ROW_E),
    swingtimer = bottomLeftOfCentre(SECOND_X, ROW_E),
    loot = at("TOPLEFT", "LEFT", MARGIN, 100),
})
-- On 16:10 the grid reaches under the tracker's column, so this layout keeps room for a header and one quest;
-- the tracker caps itself at whatever is under it and says how many quests it hides.
layouts.healer.sizes = { questtracker = { width = 240, height = 56 } }
