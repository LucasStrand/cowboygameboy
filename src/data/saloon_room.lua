-- Saloon hub room layout
-- Wider interior: 480x200 world pixels
-- Side-view platformer layout

return {
    id = "saloon_hub",
    width = 480,
    height = 200,

    -- Solid platforms (oneWay = false means player can't drop through)
    platforms = {
        -- Main floor (full width)
        { x = 0, y = 168, w = 480, h = 32, oneWay = false },
        -- Bar counter is purely decorative — no collision
    },

    -- Invisible collision walls
    walls = {
        -- Ceiling
        { x = 0, y = -16, w = 480, h = 16 },
        -- Left wall
        { x = -16, y = -16, w = 16, h = 232 },
        -- Right wall
        { x = 480, y = -16, w = 16, h = 232 },
    },

    -- NPC spawn definitions
    -- NPC hitbox is w=20, h=32. y = floor - h = 168 - 32 = 136
    npcs = {
        {
            type = "dealer",
            x = 140,
            y = 136,       -- stands on main floor
            facingRight = true,
            promptLabel = "[E] Gamble",
        },
        {
            type = "bartender",
            x = 348,
            y = 136,       -- stands on main floor behind bar counter
            facingRight = false,
            promptLabel = "[E] Buy Supplies",
        },
    },

    -- Player starts near the left side
    playerSpawn = { x = 60, y = 136 },

    -- Exit door on the right side
    exitDoor = { x = 450, y = 120, w = 24, h = 48 },

    -- Test room door (center of saloon, between dealer and bartender)
    testDoor = { x = 240, y = 120, w = 24, h = 48 },

    -- Slot machine (world prop + interact — center matches draw in saloon.lua ~scale 0.195)
    slotMachine = { cx = 18, cy = 146, r = 40 },
}
