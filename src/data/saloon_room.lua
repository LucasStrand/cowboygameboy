-- Saloon hub: single floor, side-view platformer layout.
-- Bump `ROOM_WIDTH` to widen the space; `decor` + `lrk` positions derive from it.

local ROOM_WIDTH = 720
local FLOOR_TOP = 168
local FLOOR_H = 32

-- Bar cluster anchored from the right wall (same offsets as the old 480-wide room).
local BAR_X = ROOM_WIDTH - 178

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
            x = 180,
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
    testDoor = { x = math.floor(ROOM_WIDTH / 2 - 12), y = 120, w = 24, h = 48 },

    slotMachine = { cx = 22, cy = 146, r = 40 },

    --- Prop anchors (world pixels). Used by `saloon.lua` draw + enter.
    decor = {
        barCounterX = BAR_X,
        fridgeX = BAR_X - 22,
        shelfX = BAR_X + 10,
        bottlesX = BAR_X + 18,
        jarsX = BAR_X + 40,
        greenboardX = math.floor(ROOM_WIDTH * 0.31),
        watchX = BAR_X + 80,
        wantedX = 12,
        umbrellaX = ROOM_WIDTH - 60,
        stoolStartX = BAR_X + 5,
        glass1X = BAR_X + 20,
        glass2X = BAR_X + 36,
        monsterX = BAR_X + 48,
        -- LRK “lounge” band between casino left and bar cluster
        lrkLoungeLeft = 268,
        lrkLoungeRight = BAR_X - 40,
    },
}
