-- Exit 1: standard exit on a wide boxcar — door on the right end.
return {
    id = "train_exit_01",
    world = "train",
    chunkType = "exit",
    width = 400,
    height = 400,
    edges = {
        left  = 340,
        right = false,
        top   = false,
        bottom = false,
    },
    platforms = {
        {x = 0,   y = 340, w = 400, h = 60, trainCar = true, carType = "boxcar", noFill = true},
        -- Crate ramp leading up toward door
        {x = 260, y = 308, w = 80,  h = 32},
    },
    exitDoor = {x = 352, y = 308, w = 32, h = 32},
}
