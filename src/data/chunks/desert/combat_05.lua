-- Combat: mesa top elevation (300→300) — elevated gunfight arena
return {
    id = "desert_combat_05",
    world = "desert",
    chunkType = "combat",
    width = 400, height = 400,
    edges = { left = 300, right = 300, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 300, w = 400, h = 40},
        {x = 100, y = 255, w = 60,  h = 16},
        {x = 240, y = 235, w = 80,  h = 16},
    },
}
