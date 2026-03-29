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
        wantedX = 12,
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
            { x = 68, scale = 0.70 },
            { x = 690, scale = 0.65 },
            { x = 910, scale = 0.75 },
            { x = 925, scale = 0.55 },
        },
        -- Crate stacks (boxes asset at bigger scale)
        crates = {
            { x = 4, scale = 1.15 },
            { x = 895, scale = 1.0 },
        },
        spittoonX = 235,
        -- Chairs near dealer area
        chairs = {
            { x = 245, flip = false },
            { x = 290, flip = true },
        },

        -- Basement: each LRK floor lamp is ~16×46px — scale ~1.05–1.15 reads near player height; quads are per-column
        basementFloorLamps = {
            { x = 124, quad = "floor_lamp", scale = 1.10 },
            { x = 432, quad = "floor_lamp_b", scale = 1.06 },
            { x = 804, quad = "floor_lamp_c", scale = 1.12 },
        },
        basementWallLanterns = {
            { x = 228, yFrac = 0.30, scale = 0.36 },
            { x = 612, yFrac = 0.34, scale = 0.34 },
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
