-- Traversal 2: ascending staircase of cars — each car slightly higher than the last,
-- but the entry/exit edges stay at y=340 so the chunk assembler connects cleanly.
-- The internal height variation creates a scramble-up-then-drop finale.
return {
    id = "train_traversal_02",
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
        -- Entry car (ground level)
        {x = 0,   y = 340, w = 80,  h = 60,  trainCar = true, carType = "flatcar", noFill = true},
        -- 25 px gap
        -- Step-up car 1
        {x = 105, y = 320, w = 80,  h = 80,  trainCar = true, carType = "boxcar",  noFill = true},
        -- 25 px gap
        -- Step-up car 2 (highest point)
        {x = 210, y = 298, w = 80,  h = 102, trainCar = true, carType = "boxcar",  noFill = true},
        -- 25 px gap
        -- Exit car drops back to normal level — note it connects at y=340 right edge
        {x = 315, y = 340, w = 85,  h = 60,  trainCar = true, carType = "flatcar", noFill = true},
        -- Small jumping ledge to bridge the descent from car 2 to exit car
        {x = 295, y = 316, w = 24,  h = 12,  oneWay = true},
    },
}
