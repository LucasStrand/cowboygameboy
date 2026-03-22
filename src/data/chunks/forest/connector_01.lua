-- Connector: flat ground passage (360→360)
return {
    id = "connector_01",
    world = "forest",
    chunkType = "connector",
    width = 400, height = 400,
    edges = { left = 360, right = 360, top = false, bottom = false },
    platforms = {
        {x = 0, y = 360, w = 400, h = 40},
    },
}
