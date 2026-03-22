return {
    id = "desert_entrance_01",
    world = "desert",
    chunkType = "entrance",
    width = 400,
    height = 400,
    edges = {
        left = false,
        right = 360,
        top = false,
        bottom = false,
    },
    platforms = {
        -- Wide flat desert floor
        {x = 0, y = 360, w = 400, h = 40},
        -- Small rock ledge
        {x = 260, y = 290, w = 80, h = 16},
    },
    playerSpawn = {x = 60, y = 310},
}
