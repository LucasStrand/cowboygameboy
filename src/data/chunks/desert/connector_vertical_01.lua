-- Vertical shaft connector: open top and bottom with zigzag platforms
return {
    id = "desert_connector_vertical_01",
    world = "desert",
    chunkType = "connector",
    width = 400,
    height = 400,
    edges = {
        left = false,
        right = false,
        top = true,
        bottom = true,
    },
    platforms = {
        -- Zigzag climb/drop through the shaft
        {x = 40,  y = 360, w = 120, h = 40},
        {x = 240, y = 280, w = 120, h = 16, oneWay = true},
        {x = 60,  y = 200, w = 120, h = 16, oneWay = true},
        {x = 220, y = 120, w = 120, h = 16, oneWay = true},
        {x = 100, y = 40,  w = 120, h = 16, oneWay = true},
    },
}
