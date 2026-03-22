return {
    id = "desert_combat_03",
    world = "desert",
    chunkType = "combat",
    width = 400,
    height = 400,
    edges = {
        left = 360,
        right = 360,
        top = true,
        bottom = false,
    },
    platforms = {
        -- Full floor
        {x = 0, y = 360, w = 400, h = 40},
        -- Tiered mesa platforms
        {x = 80, y = 290, w = 100, h = 16},
        {x = 220, y = 220, w = 100, h = 16},
        {x = 100, y = 150, w = 100, h = 16},
        -- Top edge
        {x = 240, y = 40, w = 100, h = 16},
    },
}
