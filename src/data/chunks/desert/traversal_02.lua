return {
    id = "desert_traversal_02",
    world = "desert",
    chunkType = "traversal",
    width = 400,
    height = 400,
    edges = {
        left = 360,
        right = 360,
        top = true,
        bottom = false,
    },
    platforms = {
        -- Canyon wall climb
        {x = 0, y = 360, w = 100, h = 40},
        {x = 300, y = 360, w = 100, h = 40},
        -- Zigzag up
        {x = 220, y = 290, w = 80, h = 16},
        {x = 100, y = 220, w = 80, h = 16},
        {x = 240, y = 150, w = 80, h = 16},
        {x = 100, y = 80, w = 80, h = 16},
        -- Top
        {x = 180, y = 30, w = 80, h = 16},
    },
}
