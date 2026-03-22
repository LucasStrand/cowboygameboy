-- Secret: dead end entered from right (enters at left=360)
return {
    id = "secret_01",
    world = "forest",
    chunkType = "secret",
    width = 400, height = 400,
    edges = { left = 360, right = false, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 360, w = 400, h = 40},
        {x = 100, y = 260, w = 80,  h = 16},
        {x = 240, y = 200, w = 80,  h = 16},
        {x = 160, y = 130, w = 100, h = 16},
    },
}
