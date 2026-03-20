local RoomData = require("src.data.rooms")
local Enemy = require("src.entities.enemy")
local bump = require("lib.bump")

local RoomManager = {}
RoomManager.__index = RoomManager

function RoomManager.new()
    local self = setmetatable({}, RoomManager)
    self.currentRoomIndex = 0
    self.roomSequence = {}
    self.difficulty = 1
    self.roomsCleared = 0
    self.totalRoomsCleared = 0
    self.checkpointReached = false
    return self
end

function RoomManager:generateSequence()
    self.roomSequence = {}
    local pool = RoomData.pool
    for i = 1, RoomData.ROOMS_PER_CHECKPOINT do
        local room = pool[math.random(#pool)]
        table.insert(self.roomSequence, room)
    end
    self.currentRoomIndex = 0
    self.roomsCleared = 0
    self.checkpointReached = false
end

function RoomManager:nextRoom()
    self.currentRoomIndex = self.currentRoomIndex + 1
    if self.currentRoomIndex > #self.roomSequence then
        self.checkpointReached = true
        return nil
    end
    return self.roomSequence[self.currentRoomIndex]
end

function RoomManager:loadRoom(room, world, player)
    -- Add platform colliders
    local platforms = {}
    for _, plat in ipairs(room.platforms) do
        local p = {x = plat.x, y = plat.y, w = plat.w, h = plat.h, isPlatform = true}
        world:add(p, p.x, p.y, p.w, p.h)
        table.insert(platforms, p)
    end

    -- Add walls (left, right, top)
    local walls = {}
    local leftWall = {x = -16, y = 0, w = 16, h = room.height, isWall = true}
    local rightWall = {x = room.width, y = 0, w = 16, h = room.height, isWall = true}
    local ceiling = {x = 0, y = -16, w = room.width, h = 16, isWall = true}
    world:add(leftWall, leftWall.x, leftWall.y, leftWall.w, leftWall.h)
    world:add(rightWall, rightWall.x, rightWall.y, rightWall.w, rightWall.h)
    world:add(ceiling, ceiling.x, ceiling.y, ceiling.w, ceiling.h)
    table.insert(walls, leftWall)
    table.insert(walls, rightWall)
    table.insert(walls, ceiling)

    -- Spawn enemies
    local enemies = {}
    local spawns = RoomData.getSpawnsForDifficulty(room, self.difficulty)
    for _, spawn in ipairs(spawns) do
        local enemy = Enemy.new(spawn.type, spawn.x, spawn.y, self.difficulty)
        if enemy then
            world:add(enemy, enemy.x, enemy.y, enemy.w, enemy.h)
            table.insert(enemies, enemy)
        end
    end

    -- Exit door
    local door = {
        x = room.exitDoor.x,
        y = room.exitDoor.y,
        w = room.exitDoor.w,
        h = room.exitDoor.h,
        isDoor = true,
        locked = true,
    }
    world:add(door, door.x, door.y, door.w, door.h)

    -- Position player
    player.x = room.playerSpawn.x
    player.y = room.playerSpawn.y
    player.vx = 0
    player.vy = 0
    world:update(player, player.x, player.y)

    return {
        platforms = platforms,
        walls = walls,
        enemies = enemies,
        door = door,
        width = room.width,
        height = room.height,
    }
end

function RoomManager:onRoomCleared()
    self.roomsCleared = self.roomsCleared + 1
    self.totalRoomsCleared = self.totalRoomsCleared + 1
    self.difficulty = 1 + self.totalRoomsCleared * 0.3
end

function RoomManager:isCheckpoint()
    return self.roomsCleared >= RoomData.ROOMS_PER_CHECKPOINT
end

function RoomManager:startNewCycle()
    self:generateSequence()
end

return RoomManager
