-- Combat: ground level both sides (360→360)
return {
    id = "combat_01",
    world = "forest",
    chunkType = "combat",
    width = 400, height = 400,
    edges = { left = 360, right = 360, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 360, w = 400, h = 40},
        {x = 40,  y = 260, w = 120, h = 16},
        {x = 240, y = 280, w = 120, h = 16},
        {x = 140, y = 180, w = 100, h = 16},
    },
}
