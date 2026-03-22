-- Traversal 1: three cars with 35 px gaps — wind makes the jumps trickier.
-- Straightforward left-to-right hop across boxcars.
return {
    id = "train_traversal_01",
    world = "train",
    chunkType = "traversal",
    width = 400,
    height = 400,
    edges = {
        left  = 340,
        right = 340,
        top   = false,
        bottom = false,
    },
    platforms = {
        -- Car 1
        {x = 0,   y = 340, w = 110, h = 60, trainCar = true, carType = "boxcar",   noFill = true},
        -- 35 px gap
        -- Car 2
        {x = 145, y = 340, w = 110, h = 60, trainCar = true, carType = "passenger", noFill = true},
        -- 35 px gap
        -- Car 3
        {x = 290, y = 340, w = 110, h = 60, trainCar = true, carType = "boxcar",   noFill = true},
    },
}
