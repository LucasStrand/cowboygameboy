return {
    id = "desert_exit_02",
    world = "desert",
    chunkType = "exit",
    width = 400,
    height = 400,
    edges = {
        left = 360,
        right = false,
        top = true,
        bottom = false,
    },
    platforms = {
        -- Lower floor
        {x = 0, y = 360, w = 200, h = 40},
        -- Mesa with door on top
        {x = 220, y = 240, w = 180, h = 40},
        -- Stepping stone to mesa
        {x = 100, y = 300, w = 80, h = 16},
        -- Top edge platform
        {x = 160, y = 40, w = 100, h = 16},
    },
    exitDoor = {x = 350, y = 208, w = 32, h = 32},
}
