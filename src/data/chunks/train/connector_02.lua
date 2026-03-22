-- Connector 2: coupling walkway — two cars with a narrow exposed coupler platform
-- between them. Forces a quick hop with wind buffeting the player.
return {
    id = "train_connector_02",
    world = "train",
    chunkType = "connector",
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
        {x = 0,   y = 340, w = 160, h = 60, trainCar = true, carType = "passenger", noFill = true},
        -- Coupling gangway — very narrow, slight drop
        {x = 164, y = 354, w = 72,  h = 14, oneWay = true},
        -- Right car
        {x = 240, y = 340, w = 160, h = 60, trainCar = true, carType = "boxcar",    noFill = true},
    },
}
