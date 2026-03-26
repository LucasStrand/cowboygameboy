-- Saloon hub: single floor, side-view platformer layout.
-- Bump `ROOM_WIDTH` to widen the space; `decor` + `lrk` positions derive from it.

local ROOM_WIDTH = 960
local FLOOR_TOP = 168
local FLOOR_H = 32

-- Bar cluster anchored from the right wall (same offsets as the old 480-wide room).
local BAR_X = ROOM_WIDTH - 200

return {
    id = "saloon_hub",
    width = ROOM_WIDTH,
    height = 200,

    -- Solid platforms (oneWay = false means player can't drop through)
    platforms = {
        { x = 0, y = FLOOR_TOP, w = ROOM_WIDTH, h = FLOOR_H, oneWay = false },
    },

    walls = {
        { x = 0, y = -16, w = ROOM_WIDTH, h = 16 },
        { x = -16, y = -16, w = 16, h = 232 },
        { x = ROOM_WIDTH, y = -16, w = 16, h = 232 },
    },

    npcs = {
        {
            type = "dealer",
            x = 200,
            y = 136,
            facingRight = true,
            promptLabel = "[E] Gamble",
        },
        {
            type = "bartender",
            x = BAR_X + 28,
            y = 136,
            facingRight = false,
            promptLabel = "[E] Buy Supplies",
        },
    },

    playerSpawn = { x = 72, y = 136 },

    exitDoor = { x = ROOM_WIDTH - 30, y = 120, w = 24, h = 48 },
    testDoor = { x = math.floor(ROOM_WIDTH * 0.45), y = 120, w = 24, h = 48 },

    slotMachine = { cx = 30, cy = 146, r = 40 },

    --- Prop anchors (world pixels). Used by `saloon.lua` draw + enter.
    decor = {
        -- bar.png 127×47 — balance visibility vs height (0.68 read too tall vs stools).
        barCounterScale = 0.52,
        -- Tile bar.png this many times side-by-side for a longer counter
        barCounterSegments = 3,
        -- Nudge can toward the right (pixels, after centering on full counter width)
        monsterCanOffsetX = 48,
        -- Stools: count + gap between stools (pixels between inner edges); X is computed in draw from bar width
        stoolCount = 8,
        stoolGapBetween = 6,
        barCounterX = BAR_X,
        fridgeX = BAR_X - 22,
        shelfX = BAR_X + 10,
        bottlesX = BAR_X + 18,
        jarsX = BAR_X + 40,
        greenboardX = math.floor(ROOM_WIDTH * 0.38),
        watchX = BAR_X + 100,
        wantedX = 12,
        -- Coat rack: left lounge (not behind the bar cluster)
        umbrellaX = 120,
        -- Second back-bar shelf: horizontal offset from first shelf (pixels, same scale)
        shelfSecondOffsetX = 66,

        -- === New depth props ===
        -- Wooden support pillars (x positions)
        pillars = { 150, 380, 600 },
        -- Back wall windows (x positions, drawn high on wall)
        windows = { 310, 520 },
        -- Procedural piano in the lounge zone
        pianoX = 440,
        -- Card table near the gambling area
        cardTableX = 270,
        -- Barrel positions {x, y_offset_from_floor}
        barrels = {
            { x = 80, yOff = 0 },
            { x = 700, yOff = 0 },
            { x = 920, yOff = 0 },
        },
        -- Spittoon near the gambling area
        spittoonX = 240,
    },
}
