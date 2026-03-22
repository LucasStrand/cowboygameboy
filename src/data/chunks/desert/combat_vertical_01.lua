-- Vertical combat arena: tall canyon with platforms at multiple heights
return {
    id = "desert_combat_vertical_01",
    world = "desert",
    chunkType = "combat",
    width = 400,
    height = 400,
    edges = {
        left = 360,
        right = false,
        top = true,
        bottom = true,
    },
    platforms = {
        -- Ground floor
        {x = 0, y = 360, w = 180, h = 40},
        {x = 260, y = 360, w = 140, h = 40},
        -- Bridge across floor gap only (180–260); flush with floor top
        {x = 180, y = 360, w = 80, h = 16, oneWay = true},
        -- Mid tiers
        {x = 20,  y = 210, w = 100, h = 16, oneWay = true},
        {x = 260, y = 210, w = 100, h = 16, oneWay = true},
        -- Upper tier
        {x = 120, y = 140, w = 120, h = 16, oneWay = true},
        -- Top ledge
        {x = 40,  y = 60,  w = 100, h = 16, oneWay = true},
    },
}
