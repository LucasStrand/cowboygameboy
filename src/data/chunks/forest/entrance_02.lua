-- Entrance: ground level, exits right at y=360, also has top connection
return {
    id = "entrance_02",
    world = "forest",
    chunkType = "entrance",
    width = 400, height = 400,
    edges = { left = false, right = 360, top = true, bottom = false },
    platforms = {
        {x = 0,   y = 360, w = 400, h = 40},
        {x = 50,  y = 280, w = 90,  h = 16},
        {x = 200, y = 200, w = 100, h = 16},
        {x = 280, y = 40,  w = 120, h = 16},
    },
    playerSpawn = {x = 60, y = 310},
}
