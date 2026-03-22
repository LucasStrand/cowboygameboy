-- Combat: high elevation both sides (240→240)
return {
    id = "combat_04",
    world = "forest",
    chunkType = "combat",
    width = 400, height = 400,
    edges = { left = 240, right = 240, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 240, w = 400, h = 40},
        {x = 80,  y = 170, w = 100, h = 16},
        {x = 240, y = 150, w = 100, h = 16},
    },
}
