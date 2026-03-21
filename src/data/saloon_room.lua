-- Saloon hub room layout
-- Compact interior: 320x200 world pixels
-- Side-view platformer layout

return {
    id = "saloon_hub",
    width = 320,
    height = 200,

    -- Solid platforms (oneWay = false means player can't drop through)
    platforms = {
        -- Main floor (full width)
        { x = 0, y = 168, w = 320, h = 32, oneWay = false },
        -- Bar counter is purely decorative — no collision
    },

    -- Invisible collision walls
    walls = {
        -- Ceiling
        { x = 0, y = -16, w = 320, h = 16 },
        -- Left wall
        { x = -16, y = -16, w = 16, h = 232 },
        -- Right wall
        { x = 320, y = -16, w = 16, h = 232 },
    },

    -- NPC spawn definitions
    -- NPC hitbox is w=20, h=32. y = floor - h = 168 - 32 = 136
    npcs = {
        {
            type = "dealer",
            x = 100,
            y = 136,       -- stands on main floor
            facingRight = true,
            promptLabel = "[E] Gamble",
        },
        {
            type = "bartender",
            x = 228,
            y = 136,       -- stands on main floor behind bar counter
            facingRight = false,
            promptLabel = "[E] Buy Supplies",
        },
    },

    -- Player starts near the left side
    playerSpawn = { x = 48, y = 136 },

    -- Exit door on the right side
    exitDoor = { x = 296, y = 120, w = 24, h = 48 },
}
