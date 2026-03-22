-- Exit: ground level, enters from left at y=360
return {
    id = "exit_01",
    world = "forest",
    chunkType = "exit",
    width = 400, height = 400,
    edges = { left = 360, right = false, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 360, w = 400, h = 40},
        {x = 160, y = 280, w = 120, h = 16},
    },
    exitDoor = {x = 340, y = 328, w = 32, h = 32},
}
