-- Combat 1: two boxcars side by side with a small gap between them.
-- One crate stack mid-car for cover.
return {
    id = "train_combat_01",
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
        -- Car 1 (left boxcar)
        {x = 0,   y = 340, w = 185, h = 60, trainCar = true, carType = "boxcar",  noFill = true},
        -- 30 px gap
        -- Car 2 (right boxcar)
        {x = 215, y = 340, w = 185, h = 60, trainCar = true, carType = "boxcar",  noFill = true},
        -- Crate cover on left car
        {x = 90,  y = 316, w = 48,  h = 24},
        -- Higher crate on right car — sniper perch
        {x = 260, y = 300, w = 48,  h = 40},
    },
}
