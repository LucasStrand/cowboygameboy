-- Secret: dead end at mid elevation (enters at left=300)
return {
    id = "secret_03",
    world = "forest",
    chunkType = "secret",
    width = 400, height = 400,
    edges = { left = 300, right = false, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 300, w = 400, h = 40},
        {x = 120, y = 230, w = 80,  h = 16},
        {x = 260, y = 170, w = 80,  h = 16},
    },
}
