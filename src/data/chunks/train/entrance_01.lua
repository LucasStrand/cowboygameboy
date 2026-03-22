-- Entrance: player spawns on a wide passenger car at the far left.
-- This is the first chunk — no left edge, one continuous car floor.
return {
    id = "train_entrance_01",
    world = "train",
    chunkType = "entrance",
    width = 400,
    height = 400,
    edges = {
        left  = false,
        right = 340,
        top   = false,
        bottom = false,
    },
    platforms = {
        -- Full-width passenger car floor
        {x = 0,   y = 340, w = 400, h = 60, trainCar = true, carType = "passenger", noFill = true},
        -- Luggage stack — low cover near right side
        {x = 280, y = 308, w = 60,  h = 32, trainCar = true, carType = "boxcar",    noFill = true},
    },
    playerSpawn = {x = 50, y = 300},
}
