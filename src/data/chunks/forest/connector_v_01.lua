-- Connector: vertical shaft (top/bottom open)
return {
    id = "connector_v_01",
    world = "forest",
    chunkType = "connector",
    width = 400, height = 400,
    edges = { left = false, right = false, top = true, bottom = true },
    platforms = {
        {x = 100, y = 360, w = 200, h = 40},
        {x = 240, y = 280, w = 80,  h = 16},
        {x = 100, y = 200, w = 80,  h = 16},
        {x = 240, y = 120, w = 80,  h = 16},
        {x = 100, y = 40,  w = 200, h = 16},
    },
}
