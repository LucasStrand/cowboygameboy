-- Combat 2: three cars — left and right are boxcars, centre is a low flatcar.
-- The height difference forces players to account for vertical positioning.
return {
    id = "train_combat_02",
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
        -- Left boxcar
        {x = 0,   y = 340, w = 120, h = 60, trainCar = true, carType = "boxcar",   noFill = true},
        -- 20 px gap
        -- Centre flatcar — slightly higher (lower y = higher up)
        {x = 140, y = 328, w = 120, h = 72, trainCar = true, carType = "flatcar",  noFill = true},
        -- 20 px gap
        -- Right boxcar
        {x = 280, y = 340, w = 120, h = 60, trainCar = true, carType = "boxcar",   noFill = true},
        -- Barrel on centre flatcar
        {x = 175, y = 312, w = 24,  h = 16},
        -- Crate on right car
        {x = 320, y = 316, w = 36,  h = 24},
    },
}
