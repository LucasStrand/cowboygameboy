return {
    id = "desert_connector_02",
    world = "desert",
    chunkType = "connector",
    width = 400,
    height = 400,
    edges = {
        left = 360,
        right = 360,
        top = false,
        bottom = false,
    },
    platforms = {
        -- Slight elevation change — ramp feel
        {x = 0, y = 360, w = 160, h = 40},
        {x = 160, y = 360, w = 80, h = 16},
        {x = 240, y = 360, w = 160, h = 40},
    },
}
