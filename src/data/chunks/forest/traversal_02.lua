-- Traversal: vertical climb with top exit
return {
    id = "traversal_02",
    world = "forest",
    chunkType = "traversal",
    width = 400, height = 400,
    edges = { left = 360, right = false, top = true, bottom = false },
    platforms = {
        {x = 0,   y = 360, w = 400, h = 40},
        {x = 240, y = 290, w = 80,  h = 16},
        {x = 80,  y = 220, w = 80,  h = 16},
        {x = 240, y = 150, w = 80,  h = 16},
        {x = 80,  y = 80,  w = 80,  h = 16},
        {x = 160, y = 30,  w = 100, h = 16},
    },
}
