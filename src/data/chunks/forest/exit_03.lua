-- Exit: high elevation, enters from left at y=240
return {
    id = "exit_03",
    world = "forest",
    chunkType = "exit",
    width = 400, height = 400,
    edges = { left = 240, right = false, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 240, w = 400, h = 40},
        {x = 100, y = 180, w = 100, h = 16},
    },
    exitDoor = {x = 340, y = 208, w = 32, h = 32},
}
