-- Combat 5: livestock car with open-top slats — enemies fire through gaps.
-- Two cars; the right one has a mid-level platform (open livestock roof).
return {
    id = "train_combat_05",
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
        -- Left livestock car
        {x = 0,   y = 340, w = 190, h = 60, trainCar = true, carType = "livestock", noFill = true},
        -- 20 px gap
        -- Right livestock car
        {x = 210, y = 340, w = 190, h = 60, trainCar = true, carType = "livestock", noFill = true},
        -- Open-top slatted railing on right car (one-way elevated platform)
        {x = 215, y = 298, w = 180, h = 12, oneWay = true},
        -- Hay bale cover on left car
        {x = 60,  y = 316, w = 52,  h = 24},
    },
}
