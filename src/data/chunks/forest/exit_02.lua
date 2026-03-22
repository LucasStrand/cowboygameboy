-- Exit: mid elevation, enters from left at y=300, door on elevated platform
return {
    id = "exit_02",
    world = "forest",
    chunkType = "exit",
    width = 400, height = 400,
    edges = { left = 300, right = false, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 300, w = 200, h = 40},
        {x = 180, y = 260, w = 80,  h = 16},
        {x = 240, y = 220, w = 160, h = 40},
    },
    exitDoor = {x = 340, y = 188, w = 32, h = 32},
}
