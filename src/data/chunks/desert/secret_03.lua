-- Secret: dead end at mesa elevation (enters at left=300)
return {
    id = "desert_secret_03",
    world = "desert",
    chunkType = "secret",
    width = 400, height = 400,
    edges = { left = 300, right = false, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 300, w = 400, h = 40},
        {x = 120, y = 240, w = 80,  h = 16},
        {x = 260, y = 185, w = 80,  h = 16},
    },
}
