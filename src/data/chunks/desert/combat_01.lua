return {
    id = "desert_combat_01",
    world = "desert",
    chunkType = "combat",
    width = 400,
    height = 400,
    edges = {
        left = 360,
        right = 360,
        top = false,
        bottom = false,
    },
    platforms = {
        -- Flat open desert — wide fighting area
        {x = 0, y = 360, w = 400, h = 40},
        -- Low rock cover
        {x = 140, y = 320, w = 60, h = 16},
        -- Elevated sniper perch
        {x = 280, y = 240, w = 80, h = 16},
    },
}
