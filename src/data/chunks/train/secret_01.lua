-- Secret 1: a lumber car loaded with timber — vertical platforms let you reach
-- a hidden upper level with bonus loot.
return {
    id = "train_secret_01",
    world = "train",
    chunkType = "secret",
    width = 400,
    height = 400,
    edges = {
        left  = 340,
        right = 340,
        top   = false,
        bottom = false,
    },
    platforms = {
        -- Lumber car floor
        {x = 0,   y = 340, w = 400, h = 60, trainCar = true, carType = "lumber", noFill = true},
        -- Stacked timber logs — ascending ledges
        {x = 30,  y = 306, w = 80,  h = 14, oneWay = true},
        {x = 150, y = 268, w = 80,  h = 14, oneWay = true},
        {x = 270, y = 230, w = 80,  h = 14, oneWay = true},
        -- Top platform — secret stash area
        {x = 100, y = 192, w = 200, h = 14, oneWay = true},
    },
    staticLights = {
        {x = 200, y = 200, r = 80, g = 1.0, gb = 0.9, b = 0.6, intensity = 1.2},
    },
}
