-- Combat: mid elevation both sides (300→300)
return {
    id = "combat_03",
    world = "forest",
    chunkType = "combat",
    width = 400, height = 400,
    edges = { left = 300, right = 300, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 300, w = 400, h = 40},
        {x = 60,  y = 220, w = 120, h = 16},
        {x = 240, y = 240, w = 100, h = 16},
        {x = 140, y = 150, w = 100, h = 16},
    },
}
