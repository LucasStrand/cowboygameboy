-- Entrance: ground level, exits right at y=360
return {
    id = "entrance_01",
    world = "forest",
    chunkType = "entrance",
    width = 400, height = 400,
    edges = { left = false, right = 360, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 360, w = 400, h = 40},
        {x = 220, y = 280, w = 100, h = 16},
    },
    playerSpawn = {x = 60, y = 310},
}
