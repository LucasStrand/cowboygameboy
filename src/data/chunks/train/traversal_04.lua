-- Traversal 4: the gauntlet — four cars at alternating heights with wind pressure.
-- Fast-paced, forces quick reads of each gap. Any hesitation and wind pushes you back.
return {
    id = "train_traversal_04",
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
        -- Car 1 (low)
        {x = 0,   y = 350, w = 80,  h = 50, trainCar = true, carType = "flatcar",  noFill = true},
        -- 30 px gap
        -- Car 2 (high)
        {x = 110, y = 320, w = 80,  h = 80, trainCar = true, carType = "boxcar",   noFill = true},
        -- 25 px gap
        -- Car 3 (low again)
        {x = 215, y = 350, w = 80,  h = 50, trainCar = true, carType = "flatcar",  noFill = true},
        -- 30 px gap
        -- Car 4 (high)
        {x = 325, y = 320, w = 75,  h = 80, trainCar = true, carType = "boxcar",   noFill = true},
        -- Tiny ledge between car2 and car3 (barely enough to land on)
        {x = 195, y = 334, w = 20,  h = 10, oneWay = true},
    },
}
