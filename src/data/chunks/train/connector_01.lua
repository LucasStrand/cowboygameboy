-- Connector 1: single long flatcar — breathing room between combat sections.
return {
    id = "train_connector_01",
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
        {x = 0, y = 340, w = 400, h = 60, trainCar = true, carType = "flatcar", noFill = true},
    },
}
