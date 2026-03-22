-- Combat 4: armoured car + tender — a narrow raised coal tender in the middle
-- creates a choke point while gunslingers fire from the armoured flanks.
return {
    id = "train_combat_04",
    world = "train",
    chunkType = "combat",
    width = 400,
    height = 400,
    edges = {
        left  = 340,
        right = 340,
        top   = false,
        bottom = false,
    },
    platforms = {
        -- Left armoured car
        {x = 0,   y = 340, w = 140, h = 60, trainCar = true, carType = "armored",  noFill = true},
        -- 20 px gap
        -- Coal tender — narrower and taller (higher body = lower y)
        {x = 160, y = 310, w = 80,  h = 90, trainCar = true, carType = "tender",   noFill = true},
        -- 20 px gap
        -- Right armoured car
        {x = 260, y = 340, w = 140, h = 60, trainCar = true, carType = "armored",  noFill = true},
        -- Hatch/cover on left armoured car roof
        {x = 50,  y = 316, w = 48,  h = 24},
    },
}
