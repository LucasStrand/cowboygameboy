return {
    id = "desert_combat_02",
    world = "desert",
    chunkType = "combat",
    width = 400,
    height = 400,
    edges = {
        left = 360,
        right = 360,
        top = false,
        bottom = false,
    },
    platforms = {
        -- Canyon floor — split by gap
        {x = 0, y = 360, w = 170, h = 40},
        {x = 230, y = 360, w = 170, h = 40},
        -- Bridge over gap only (y = floor top; x/w = open span 170–230)
        {x = 170, y = 360, w = 60, h = 16},
        -- Mesa platforms
        {x = 40, y = 240, w = 100, h = 16},
        {x = 260, y = 220, w = 100, h = 16},
    },
}
