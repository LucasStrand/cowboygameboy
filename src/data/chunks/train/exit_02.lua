-- Exit 2: the engine — wide locomotive cab at the front of the train.
-- Player must cross a gap from a boxcar onto the engine roof to reach the exit.
return {
    id = "train_exit_02",
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
        -- Approach car (left)
        {x = 0,   y = 340, w = 150, h = 60, trainCar = true, carType = "boxcar",  noFill = true},
        -- 40 px gap — dramatic leap onto the engine
        -- Engine (right) — taller/heavier car body
        {x = 190, y = 320, w = 210, h = 80, trainCar = true, carType = "engine",  noFill = true},
        -- Chimney/cab overhang — one-way standing spot near exit
        {x = 310, y = 284, w = 60,  h = 12, oneWay = true},
    },
    exitDoor = {x = 352, y = 284, w = 32, h = 32},
}
