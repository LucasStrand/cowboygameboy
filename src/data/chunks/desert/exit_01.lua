return {
    id = "desert_exit_01",
    world = "desert",
    chunkType = "exit",
    width = 400,
    height = 400,
    edges = {
        left = 360,
        right = false,
        top = false,
        bottom = false,
    },
    platforms = {
        -- Desert floor
        {x = 0, y = 360, w = 400, h = 40},
        -- Rocky outcrop near door
        {x = 200, y = 280, w = 100, h = 16},
    },
    exitDoor = {x = 340, y = 328, w = 32, h = 32},
}
