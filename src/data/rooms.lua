local RoomData = {}

RoomData.ROOMS_PER_CHECKPOINT = 5

RoomData.pool = {
    {
        id = "canyon_run",
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
    },
    {
        id = "cliffside",
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
    },
    {
        id = "underground",
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
    },
    {
        id = "mesa_heights",
        width = 2600,
        height = 900,
        platforms = {
            -- Ground
            {x = 0,    y = 836, w = 400,  h = 64},
            {x = 500,  y = 836, w = 300,  h = 64},
            {x = 900,  y = 836, w = 500,  h = 64},
            {x = 1500, y = 836, w = 400,  h = 64},
            {x = 2000, y = 836, w = 600,  h = 64},
            -- Mesa (big raised platforms)
            {x = 200,  y = 680, w = 300, h = 32},
            {x = 900,  y = 640, w = 350, h = 32},
            {x = 1600, y = 660, w = 280, h = 32},
            {x = 2200, y = 680, w = 250, h = 32},
            -- Scattered high
            {x = 100,  y = 540, w = 100, h = 16},
            {x = 450,  y = 500, w = 120, h = 16},
            {x = 750,  y = 480, w = 100, h = 16},
            {x = 1100, y = 460, w = 140, h = 16},
            {x = 1400, y = 500, w = 100, h = 16},
            {x = 1750, y = 480, w = 120, h = 16},
            {x = 2050, y = 520, w = 100, h = 16},
            {x = 2350, y = 500, w = 120, h = 16},
            -- Sky platforms
            {x = 300,  y = 360, w = 80, h = 16},
            {x = 600,  y = 320, w = 100, h = 16},
            {x = 1000, y = 340, w = 80, h = 16},
            {x = 1300, y = 360, w = 100, h = 16},
            {x = 1900, y = 340, w = 80, h = 16},
            {x = 2300, y = 360, w = 100, h = 16},
        },
        spawns = {
            {x = 350,  y = 780, type = "bandit"},
            {x = 700,  y = 780, type = "gunslinger"},
            {x = 1100, y = 580, type = "gunslinger"},
            {x = 1600, y = 780, type = "bandit"},
            {x = 2100, y = 780, type = "bandit"},
            {x = 800,  y = 400, type = "buzzard"},
            {x = 1800, y = 400, type = "buzzard"},
        },
        playerSpawn = {x = 80, y = 780},
        exitDoor = {x = 2540, y = 804, w = 32, h = 32},
    },
}

function RoomData.getSpawnsForDifficulty(room, difficulty)
    local spawns = {}
    for _, s in ipairs(room.spawns) do
        table.insert(spawns, {x = s.x, y = s.y, type = s.type})
    end

    local extraCount = math.floor((difficulty - 1) * 0.5)
    local enemyTypes = {"bandit", "bandit", "gunslinger", "buzzard"}

    for i = 1, extraCount do
        local baseSpawn = room.spawns[math.random(#room.spawns)]
        local offsetX = math.random(-80, 80)
        local newType = enemyTypes[math.random(#enemyTypes)]
        if difficulty >= 3 then
            newType = enemyTypes[math.random(#enemyTypes)]
        end
        table.insert(spawns, {
            x = math.max(100, math.min(room.width - 100, baseSpawn.x + offsetX)),
            y = baseSpawn.y,
            type = newType,
        })
    end

    return spawns
end

return RoomData
