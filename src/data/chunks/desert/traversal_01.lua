return {
    id = "desert_traversal_01",
    world = "desert",
    chunkType = "traversal",
    width = 400,
    height = 400,
    edges = {
        left = 360,
        right = 360,
        top = false,
        bottom = false,
    },
    platforms = {
        -- Canyon crossing — no continuous floor
        {x = 0, y = 360, w = 80, h = 40},
        {x = 150, y = 330, w = 60, h = 16},
        {x = 270, y = 300, w = 60, h = 16},
        {x = 320, y = 360, w = 80, h = 40},
    },
}
