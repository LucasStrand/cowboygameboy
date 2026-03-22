-- Traversal: platforming at ground level (360→360)
return {
    id = "traversal_01",
    world = "forest",
    chunkType = "traversal",
    width = 400, height = 400,
    edges = { left = 360, right = 360, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 360, w = 80,  h = 40},
        {x = 140, y = 320, w = 70,  h = 16},
        {x = 260, y = 280, w = 70,  h = 16},
        {x = 320, y = 360, w = 80,  h = 40},
        {x = 80,  y = 200, w = 80,  h = 16},
        {x = 220, y = 160, w = 80,  h = 16},
    },
}
