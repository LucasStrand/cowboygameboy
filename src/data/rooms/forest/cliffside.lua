return {
    id = "cliffside",
    world = "forest",
    width = 2800,
    height = 900,
    platforms = {
        -- Ground segments with gaps
        {x = 0,    y = 836, w = 500,  h = 64},
        {x = 600,  y = 836, w = 300,  h = 64},
        {x = 1050, y = 836, w = 400,  h = 64},
        {x = 1600, y = 836, w = 350,  h = 64},
        {x = 2100, y = 836, w = 700,  h = 64},
        -- Stepping stones over gaps
        {x = 520,  y = 760, w = 60, h = 16},
        {x = 940,  y = 760, w = 80, h = 16},
        {x = 1480, y = 760, w = 80, h = 16},
        {x = 2000, y = 760, w = 70, h = 16},
        -- Mid-level platforms
        {x = 200,  y = 680, w = 160, h = 16},
        {x = 700,  y = 640, w = 140, h = 16},
        {x = 1100, y = 660, w = 180, h = 16},
        {x = 1550, y = 620, w = 120, h = 16},
        {x = 1900, y = 680, w = 200, h = 16},
        {x = 2400, y = 640, w = 160, h = 16},
        -- High tier
        {x = 400,  y = 500, w = 120, h = 16},
        {x = 850,  y = 460, w = 100, h = 16},
        {x = 1250, y = 480, w = 140, h = 16},
        {x = 1700, y = 440, w = 100, h = 16},
        {x = 2200, y = 480, w = 120, h = 16},
        {x = 2600, y = 500, w = 100, h = 16},
    },
    spawns = {
        {x = 400,  y = 780, type = "bandit"},
        {x = 800,  y = 780, type = "gunslinger"},
        {x = 1200, y = 780, type = "bandit"},
        {x = 1700, y = 780, type = "bandit"},
        {x = 2300, y = 780, type = "gunslinger"},
        {x = 1300, y = 420, type = "buzzard"},
    },
    playerSpawn = {x = 80, y = 780},
    exitDoor = {x = 2740, y = 804, w = 32, h = 32},
}
