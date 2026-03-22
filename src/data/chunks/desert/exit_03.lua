-- Exit: door reached from mesa top (left=300)
return {
    id = "desert_exit_03",
    world = "desert",
    chunkType = "exit",
    width = 400, height = 400,
    edges = { left = 300, right = false, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 300, w = 400, h = 40},
        {x = 160, y = 250, w = 80,  h = 16},
    },
    exitDoor = {x = 340, y = 268, w = 32, h = 32},
}
