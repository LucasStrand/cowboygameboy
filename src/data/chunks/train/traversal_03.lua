-- Traversal 3: two far cars with a floating crate bridge in the void between them.
-- The crate platform is one-way and narrow — one slip and you fall.
return {
    id = "train_traversal_03",
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
        -- Left car
        {x = 0,   y = 340, w = 140, h = 60, trainCar = true, carType = "boxcar",  noFill = true},
        -- Wide void — 100 px gap
        -- Floating crate mid-air (fell from a car and lodged between)
        {x = 168, y = 318, w = 64,  h = 14, oneWay = true},
        -- Right car
        {x = 260, y = 340, w = 140, h = 60, trainCar = true, carType = "tanker",  noFill = true},
    },
}
