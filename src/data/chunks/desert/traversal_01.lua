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
        -- Canyon crossing — single bridge flush with floor (no floating steps)
        {x = 0, y = 360, w = 80, h = 40},
        {x = 80, y = 360, w = 240, h = 16, oneWay = true},
        {x = 320, y = 360, w = 80, h = 40},
    },
}
