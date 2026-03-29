-- Saloon hub: two-level side-view platformer layout (main floor + basement).
-- Bump `ROOM_WIDTH` to widen the space; `decor` + prop positions derive from it.

local ROOM_WIDTH = 992
local FLOOR_TOP = 168
local FLOOR_H = 32
local BASEMENT_GAP = 80   -- vertical space between main floor bottom and basement floor
local BASEMENT_FLOOR_Y = FLOOR_TOP + FLOOR_H + BASEMENT_GAP
local BASEMENT_FLOOR_H = 20

-- Keep a narrow gap at the far right so the exit door can sit clear of the bar.
local BAR_X = 760

return {
    id = "saloon_hub",
    width = ROOM_WIDTH,
    height = BASEMENT_FLOOR_Y + BASEMENT_FLOOR_H + 16,  -- tall enough for basement

    -- Main floor is oneWay (press down to drop to basement); basement is solid
    platforms = {
        { x = 0, y = FLOOR_TOP, w = ROOM_WIDTH, h = FLOOR_H, oneWay = true },
        { x = 0, y = BASEMENT_FLOOR_Y, w = ROOM_WIDTH, h = BASEMENT_FLOOR_H, oneWay = false },
    },

    walls = {
        { x = 0, y = -16, w = ROOM_WIDTH, h = 16 },
        { x = -16, y = -16, w = 16, h = BASEMENT_FLOOR_Y + BASEMENT_FLOOR_H + 48 },
        { x = ROOM_WIDTH, y = -16, w = 16, h = BASEMENT_FLOOR_Y + BASEMENT_FLOOR_H + 48 },
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

    -- Multiple slot machines in gambling zone
    slotMachine = { cx = 30, cy = 146, r = 40 },
    slotMachines = {
        { x = 4,  scale = 0.195 },
        { x = 52, scale = 0.195 },
        { x = 94, scale = 0.195 },
    },

    -- Basement layout info
    basementFloorY = BASEMENT_FLOOR_Y,
    basementFloorH = BASEMENT_FLOOR_H,

    --- Prop anchors (world pixels). Used by `saloon.lua` draw + enter.
    decor = {
        -- bar.png 127x47
        barCounterScale = 0.52,
        barCounterSegments = 2,
        monsterCanOffsetX = 10,  -- shifted left from 48
        -- Stools: placed with sporadic offsets in draw code
        stoolCount = 5,
        stoolGapBetween = 8,
        stoolStartOffsetX = 0,
        barCounterX = BAR_X,
        fridgeX = BAR_X - 22,
        shelfX = BAR_X + 2,
        bottlesX = BAR_X + 10,
        jarsX = BAR_X + 32,
        greenboardX = math.floor(ROOM_WIDTH * 0.42),
        wantedX = nil,
        -- Umbrella: left end of bar (patron side), leans on counter — keep offset small; large negative x lands on the fridge (fridgeX = barCounterX - 22)
        umbrellaBarOffsetX = -5,
        umbrellaLeanRad = 0.22,
        umbrellaScale = 0.55,
        shelfSecondOffsetX = 70,

        -- === Structural / depth ===
        -- Pillars: SWAPPED — old foreground positions are now back, old back are now foreground
        backPillars = { 300, 740 },          -- normal color, behind player
        foregroundPillars = { 160, 410, 620 }, -- opaque, drawn over player for depth
        -- Windows with warm glow (asset-based) — added a left-side window so visible from spawn
        windows = { { x = 180, scale = 0.55 }, { x = 420, scale = 0.6 }, { x = 650, scale = 0.55 } },
        -- Wall clock (asset, on back wall — NOT on shelves)
        clockX = 470,
        -- Antler trophy mount
        antlerX = 580,

        -- === Floor props ===
        pianoX = 350,  -- moved away from test door
        -- Poker table removed (generated asset didn't fit)
        pokerTableX = nil,
        barrels = {
            { x = 690, scale = 0.65 },
            { x = 910, scale = 0.75 },
            { x = 925, scale = 0.55 },
        },
        -- Crate stacks (boxes asset at bigger scale)
        crates = {
            {
                x = 880,
                scale = 1.0,
                layers = {
                    { dx = 0, dy = 0 },
                    { dx = 14, dy = 0 },
                    { dx = 7, dy = 9 },
                    { dx = 3, dy = 19 },
                },
            },
        },
        spittoonX = 235,
        -- Chairs near dealer area
        chairs = {
            { x = 245, flip = false },
            { x = 290, flip = true },
        },

        -- Basement lighting: frontier-style (torches, hanging lanterns, candles)
        basementTorchSconces = {
            { x = 180, yFrac = 0.55, scale = 0.7 },
            { x = 520, yFrac = 0.58, scale = 0.7 },
            { x = 860, yFrac = 0.52, scale = 0.7 },
        },
        basementHangingLanterns = {
            { x = 320, scale = 0.85 },
            { x = 680, scale = 0.85 },
        },
        basementCandles = {
            { x = 695, y = BASEMENT_FLOOR_Y, scale = 0.55 },
            { x = 915, y = BASEMENT_FLOOR_Y, scale = 0.6 },
            { x = 888, y = BASEMENT_FLOOR_Y, scale = 0.5 },
        },
        -- Main saloon floor — one of each LRK plant quad, grouped (bar vase stays on counter in saloon.lua)
        saloonPlants = {
            { quad = "plant_potted_mid_a", x = 448, scale = 0.90 },
            { quad = "plant_potted_small", x = 478, scale = 0.90 },
            { quad = "plant_potted_mid_b", x = 508, scale = 0.88 },
            { quad = "plant_potted_low", x = 538, scale = 0.95 },
        },
    },
}
