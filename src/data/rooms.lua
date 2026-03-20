local RoomData = {}

RoomData.ROOMS_PER_CHECKPOINT = 5

RoomData.pool = {
    {
        id = "room_flat",
        mapFile = nil,
        width = 800,
        height = 400,
        platforms = {
            {x = 0, y = 368, w = 800, h = 32},
            {x = 200, y = 280, w = 120, h = 16},
            {x = 500, y = 240, w = 120, h = 16},
            {x = 50, y = 180, w = 80, h = 16},
            {x = 650, y = 300, w = 100, h = 16},
        },
        spawns = {
            {x = 300, y = 300, type = "bandit"},
            {x = 500, y = 300, type = "bandit"},
        },
        playerSpawn = {x = 50, y = 300},
        exitDoor = {x = 750, y = 336, w = 32, h = 32},
    },
    {
        id = "room_elevated",
        mapFile = nil,
        width = 800,
        height = 400,
        platforms = {
            {x = 0, y = 368, w = 300, h = 32},
            {x = 350, y = 320, w = 150, h = 16},
            {x = 550, y = 260, w = 250, h = 32},
            {x = 150, y = 220, w = 100, h = 16},
            {x = 350, y = 180, w = 100, h = 16},
            {x = 0, y = 140, w = 80, h = 16},
        },
        spawns = {
            {x = 400, y = 260, type = "gunslinger"},
            {x = 600, y = 200, type = "bandit"},
        },
        playerSpawn = {x = 50, y = 300},
        exitDoor = {x = 750, y = 228, w = 32, h = 32},
    },
    {
        id = "room_pit",
        mapFile = nil,
        width = 800,
        height = 400,
        platforms = {
            {x = 0, y = 368, w = 200, h = 32},
            {x = 300, y = 368, w = 200, h = 32},
            {x = 600, y = 368, w = 200, h = 32},
            {x = 220, y = 300, w = 60, h = 16},
            {x = 520, y = 300, w = 60, h = 16},
            {x = 100, y = 240, w = 100, h = 16},
            {x = 600, y = 240, w = 100, h = 16},
            {x = 350, y = 200, w = 100, h = 16},
        },
        spawns = {
            {x = 350, y = 300, type = "bandit"},
            {x = 650, y = 300, type = "bandit"},
            {x = 400, y = 150, type = "buzzard"},
        },
        playerSpawn = {x = 50, y = 300},
        exitDoor = {x = 750, y = 336, w = 32, h = 32},
    },
    {
        id = "room_towers",
        mapFile = nil,
        width = 800,
        height = 400,
        platforms = {
            {x = 0, y = 368, w = 800, h = 32},
            {x = 100, y = 290, w = 80, h = 16},
            {x = 100, y = 200, w = 80, h = 16},
            {x = 350, y = 260, w = 100, h = 16},
            {x = 600, y = 290, w = 80, h = 16},
            {x = 600, y = 200, w = 80, h = 16},
            {x = 300, y = 140, w = 200, h = 16},
        },
        spawns = {
            {x = 130, y = 160, type = "gunslinger"},
            {x = 630, y = 160, type = "gunslinger"},
            {x = 400, y = 100, type = "buzzard"},
        },
        playerSpawn = {x = 50, y = 300},
        exitDoor = {x = 750, y = 336, w = 32, h = 32},
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
        local offsetX = math.random(-50, 50)
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
