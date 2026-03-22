return {
    id = "desert_combat_04",
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
        -- Wide open desert with scattered rocks
        {x = 0, y = 360, w = 400, h = 40},
        -- Low rocks for cover (gunfight arena)
        {x = 80, y = 330, w = 50, h = 16},
        {x = 270, y = 330, w = 50, h = 16},
        -- Elevated platform
        {x = 160, y = 260, w = 80, h = 16},
    },
}
