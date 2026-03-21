return {
    id = "canyon_run",
    world = "forest",
    width = 2400,
    height = 800,
    platforms = {
        -- Ground level
        {x = 0,    y = 736, w = 600,  h = 64},
        {x = 700,  y = 736, w = 400,  h = 64},
        {x = 1200, y = 736, w = 500,  h = 64},
        {x = 1800, y = 736, w = 600,  h = 64},
        -- Mid platforms
        {x = 150,  y = 620, w = 140, h = 16},
        {x = 450,  y = 560, w = 160, h = 16},
        {x = 750,  y = 620, w = 120, h = 16},
        {x = 1000, y = 540, w = 180, h = 16},
        {x = 1350, y = 600, w = 140, h = 16},
        {x = 1650, y = 560, w = 160, h = 16},
        {x = 2000, y = 620, w = 120, h = 16},
        -- High platforms
        {x = 300,  y = 440, w = 120, h = 16},
        {x = 600,  y = 400, w = 100, h = 16},
        {x = 1100, y = 420, w = 140, h = 16},
        {x = 1500, y = 380, w = 120, h = 16},
        {x = 1900, y = 440, w = 100, h = 16},
        {x = 2200, y = 400, w = 120, h = 16},
    },
    spawns = {
        {x = 500,  y = 680, type = "bandit"},
        {x = 900,  y = 680, type = "bandit"},
        {x = 1400, y = 680, type = "gunslinger"},
        {x = 2000, y = 680, type = "bandit"},
    },
    playerSpawn = {x = 80, y = 680},
    exitDoor = {x = 2340, y = 704, w = 32, h = 32},
}
