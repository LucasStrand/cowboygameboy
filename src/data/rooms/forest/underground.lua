return {
    id = "underground",
    world = "forest",
    width = 2200,
    height = 850,
    platforms = {
        -- Main ground
        {x = 0,    y = 786, w = 800,  h = 64},
        {x = 900,  y = 786, w = 600,  h = 64},
        {x = 1600, y = 786, w = 600,  h = 64},
        -- Raised sections
        {x = 300,  y = 680, w = 200, h = 32},
        {x = 1000, y = 660, w = 250, h = 32},
        {x = 1700, y = 680, w = 200, h = 32},
        -- Mid platforms
        {x = 100,  y = 580, w = 120, h = 16},
        {x = 500,  y = 540, w = 140, h = 16},
        {x = 800,  y = 560, w = 100, h = 16},
        {x = 1150, y = 520, w = 160, h = 16},
        {x = 1500, y = 560, w = 120, h = 16},
        {x = 1850, y = 540, w = 140, h = 16},
        -- High platforms
        {x = 250,  y = 420, w = 100, h = 16},
        {x = 650,  y = 380, w = 120, h = 16},
        {x = 1050, y = 400, w = 100, h = 16},
        {x = 1400, y = 380, w = 120, h = 16},
        {x = 1750, y = 420, w = 100, h = 16},
        {x = 2050, y = 380, w = 100, h = 16},
        -- Bridge over gap
        {x = 820,  y = 730, w = 60, h = 16},
        {x = 1520, y = 730, w = 60, h = 16},
    },
    spawns = {
        {x = 400,  y = 730, type = "bandit"},
        {x = 700,  y = 730, type = "bandit"},
        {x = 1100, y = 600, type = "gunslinger"},
        {x = 1800, y = 730, type = "bandit"},
        {x = 600,  y = 320, type = "buzzard"},
    },
    playerSpawn = {x = 80, y = 730},
    exitDoor = {x = 2140, y = 754, w = 32, h = 32},
}
