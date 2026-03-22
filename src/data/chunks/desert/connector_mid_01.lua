-- Connector: flat mesa passage (300→300)
return {
    id = "desert_connector_mid_01",
    world = "desert",
    chunkType = "connector",
    width = 400, height = 400,
    edges = { left = 300, right = 300, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 300, w = 400, h = 40},
    },
}
