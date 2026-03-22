return {
    id = "desert_secret_02",
    world = "desert",
    chunkType = "secret",
    width = 400,
    height = 400,
    edges = {
        left = false,
        right = 360,
        top = false,
        bottom = false,
    },
    platforms = {
        -- Hidden cave from right side
        {x = 0, y = 360, w = 400, h = 40},
        {x = 200, y = 280, w = 80, h = 16},
        {x = 60, y = 200, w = 80, h = 16},
        {x = 140, y = 120, w = 100, h = 16},
    },
}
