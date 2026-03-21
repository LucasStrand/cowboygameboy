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

local MAX_FLOOR_GAP_FILL = 300
local MIN_FLOOR_GAP_FILL = 14

local function mergeFloorSegments(segs)
    table.sort(segs, function(a, b) return a.x1 < b.x1 end)
    local merged = {}
    for _, s in ipairs(segs) do
        if #merged == 0 then
            merged[1] = {x1 = s.x1, x2 = s.x2, top = s.top}
        else
            local m = merged[#merged]
            if s.x1 <= m.x2 + 4 then
                m.x2 = math.max(m.x2, s.x2)
                m.top = math.min(m.top, s.top)
            else
                table.insert(merged, {x1 = s.x1, x2 = s.x2, top = s.top})
            end
        end
    end
    return merged
end

-- Vertical rise per hop: double jump with default stats (~-380 vy, g 900) ≈ 130–145px; use margin.
local MAX_JUMP_TIER = 138
local STEP_W = 56
local STEP_H = 16

local function horizOverlap(a, b, slack)
    slack = slack or 0
    return a.x + slack < b.x + b.w and a.x + a.w - slack > b.x
end

local function overlapCenterX(a, b)
    local x0 = math.max(a.x, b.x)
    local x1 = math.min(a.x + a.w, b.x + b.w)
    return (x0 + x1) / 2
end

--- Nearest walkable surface strictly below `upper` (higher y), preferring small vertical gap.
local function findLandingBelow(upper, list, slack)
    local best, bestY = nil, math.huge
    for _, p in ipairs(list) do
        if p ~= upper and p.y > upper.y + 2 and horizOverlap(upper, p, slack) then
            if p.y < bestY then
                bestY = p.y
                best = p
            end
        end
    end
    return best
end

local function hasSimilarStep(platforms, x, y)
    for _, p in ipairs(platforms) do
        if p.oneWay and p.h and p.h <= 20 and math.abs(p.x - x) < 6 and math.abs(p.y - y) < 4 then
            return true
        end
    end
    return false
end

local function addStepPlatform(world, platforms, room, x, y, w, h)
    x = math.floor(math.max(8, math.min(x, room.width - w - 8)))
    if hasSimilarStep(platforms, x, y) then
        return
    end
    local p = {
        x = x, y = y, w = w, h = h,
        isPlatform = true,
        oneWay = true,
    }
    world:add(p, p.x, p.y, p.w, p.h)
    table.insert(platforms, p)
end

local function addJumpChainsIfNeeded(room, world, platforms)
    for _ = 1, 6 do
        local snapshot = {}
        for i = 1, #platforms do
            snapshot[i] = platforms[i]
        end
        local addedAny = false

        for _, u in ipairs(snapshot) do
            local L = findLandingBelow(u, snapshot, 4) or findLandingBelow(u, snapshot, 80)
            if L then
                local gap = L.y - u.y
                if gap > MAX_JUMP_TIER then
                    local cx = overlapCenterX(u, L)
                    local sx = cx - STEP_W / 2
                    local anchorY = L.y
                    local targetY = u.y
                    while anchorY - targetY > MAX_JUMP_TIER do
                        anchorY = anchorY - MAX_JUMP_TIER
                        addStepPlatform(world, platforms, room, sx, anchorY, STEP_W, STEP_H)
                        addedAny = true
                    end
                end
            end
        end

        if not addedAny then
            break
        end
    end
end

function RoomManager:loadRoom(room, world, player)
    -- Add platform colliders (thin ledges are one-way; thick floors are solid)
    local platforms = {}
    for _, plat in ipairs(room.platforms) do
        local oneWay = plat.oneWay
        if oneWay == nil then
            oneWay = plat.h <= 24
        end
        local p = {
            x = plat.x, y = plat.y, w = plat.w, h = plat.h,
            isPlatform = true,
            oneWay = oneWay,
        }
        world:add(p, p.x, p.y, p.w, p.h)
        table.insert(platforms, p)
    end

    -- Auto-bridge walkable gaps between thick floor segments so the level stays traversable
    local floorBand = room.height - 110
    local segs = {}
    for _, plat in ipairs(room.platforms) do
        if plat.h >= 36 and plat.y + plat.h >= floorBand - 24 then
            table.insert(segs, {x1 = plat.x, x2 = plat.x + plat.w, top = plat.y})
        end
    end
    if #segs > 0 then
        local merged = mergeFloorSegments(segs)
        for i = 1, #merged - 1 do
            local left, right = merged[i], merged[i + 1]
            local gw = right.x1 - left.x2
            if gw >= MIN_FLOOR_GAP_FILL and gw <= MAX_FLOOR_GAP_FILL then
                local topY = math.min(left.top, right.top)
                local bridge = {
                    x = left.x2,
                    y = topY,
                    w = gw,
                    h = 28,
                    isPlatform = true,
                    oneWay = true,
                }
                world:add(bridge, bridge.x, bridge.y, bridge.w, bridge.h)
                table.insert(platforms, bridge)
            end
        end
    end

    -- One-way stepping ledges so every platform top is reachable with double-jump tiers (~138px each).
    addJumpChainsIfNeeded(room, world, platforms)

    -- Add walls (left, right, ceiling) — extra tall to cover camera overshoot
    local walls = {}
    local wallH = room.height + 400
    local leftWall  = {x = -32, y = -200, w = 32, h = wallH, isWall = true}
    local rightWall = {x = room.width, y = -200, w = 32, h = wallH, isWall = true}
    local ceiling   = {x = -32, y = -32, w = room.width + 64, h = 32, isWall = true}
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
