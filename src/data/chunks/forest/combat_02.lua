-- Combat: ground level, gap in floor (360→360)
return {
    id = "combat_02",
    world = "forest",
    chunkType = "combat",
    width = 400, height = 400,
    edges = { left = 360, right = 360, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 360, w = 160, h = 40},
        {x = 240, y = 360, w = 160, h = 40},
        {x = 120, y = 280, w = 140, h = 16},
        {x = 20,  y = 220, w = 80,  h = 16},
        {x = 300, y = 200, w = 80,  h = 16},
    },
}
