-- Secret: dead end entered from left (enters at right=360)
return {
    id = "secret_02",
    world = "forest",
    chunkType = "secret",
    width = 400, height = 400,
    edges = { left = false, right = 360, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 360, w = 400, h = 40},
        {x = 220, y = 260, w = 80,  h = 16},
        {x = 80,  y = 200, w = 80,  h = 16},
        {x = 140, y = 130, w = 100, h = 16},
    },
}
