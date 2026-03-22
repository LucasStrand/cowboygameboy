return {
    id = "desert_entrance_02",
    world = "desert",
    chunkType = "entrance",
    width = 400,
    height = 400,
    edges = {
        left = false,
        right = 360,
        top = true,
        bottom = false,
    },
    platforms = {
        -- Desert floor
        {x = 0, y = 360, w = 400, h = 40},
        -- Mesa step up
        {x = 140, y = 280, w = 120, h = 16},
        -- High ledge connecting to top
        {x = 260, y = 180, w = 100, h = 16},
        -- Top platform
        {x = 140, y = 40, w = 120, h = 16},
    },
    playerSpawn = {x = 60, y = 310},
}
