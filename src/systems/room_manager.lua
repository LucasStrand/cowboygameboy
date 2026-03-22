local RoomData = require("src.data.rooms")
local Vision = require("src.data.vision")
local RoomLoader = require("src.systems.room_loader")
local ChunkLoader = require("src.systems.chunk_loader")
local ChunkAssembler = require("src.systems.chunk_assembler")
local Worlds = require("src.data.worlds")
local RoomProps = require("src.systems.room_props")
local Enemy = require("src.entities.enemy")
local Chest = require("src.entities.chest")
local bump = require("lib.bump")

local RoomManager = {}
RoomManager.__index = RoomManager

function RoomManager.new(worldId)
    local self = setmetatable({}, RoomManager)
    self.currentRoomIndex = 0
    self.roomSequence = {}
    self.difficulty = 1
    self.roomsCleared = 0
    self.totalRoomsCleared = 0
    self.checkpointReached = false
    --- nil = use `room.night` in data; true/false = whole cycle/segment override
    self.nightVisualsOverride = nil
    --- When true, `generateSequence` uses only `RoomData.devArena` (sandbox).
    self.devArenaMode = false
    self.worldId = worldId or "forest"
    self.worldDef = Worlds.get(self.worldId)
    return self
end

function RoomManager:setWorld(worldId)
    self.worldId = worldId
    self.worldDef = Worlds.get(worldId)
end

--- Get the active theme table for rendering (includes _atlasPath).
function RoomManager:getTheme()
    if not self.worldDef then return nil end
    local theme = {}
    for k, v in pairs(self.worldDef.theme) do
        theme[k] = v
    end
    theme._atlasPath = self.worldDef.tileAtlas
    return theme
end

function RoomManager:generateSequence()
    if self.devArenaMode then
        self.roomSequence = { RoomData.devArena }
        self.currentRoomIndex = 0
        self.roomsCleared = 0
        self.checkpointReached = false
        self.difficulty = 1
        return
    end
    self.roomSequence = {}
    local roomsPerCheckpoint = (self.worldDef and self.worldDef.roomsPerCheckpoint)
        or RoomData.ROOMS_PER_CHECKPOINT

    -- Check if this world has chunks for procedural assembly
    local chunks = ChunkLoader.getPool(self.worldId)
    local useChunks = #chunks > 0

    for i = 1, roomsPerCheckpoint do
        if useChunks then
            -- Procedural: assemble a room from chunks (Dead Cells-style)
            local room = ChunkAssembler.generate(self.worldId, self.difficulty)
            table.insert(self.roomSequence, room)
        else
            -- Legacy: pick a random hand-crafted room
            local pool = RoomLoader.getPool(self.worldId)
            if #pool == 0 then
                pool = RoomData.pool or {}
            end
            local room = pool[math.random(#pool)]
            table.insert(self.roomSequence, room)
        end
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

local MAX_FLOOR_GAP_FILL = 1200
local MIN_FLOOR_GAP_FILL = 14
-- Platforms within this Y tolerance count as the same "floor tier" for merging and gap-fill.
-- Without this, a mid-level ledge + ground chunk merge into one span and produce bogus gaps,
-- floating bridges, and vertical water slices between unrelated tiers.
local SAME_FLOOR_TOP_TOL = 20

local function mergeFloorSegments(segs)
    table.sort(segs, function(a, b) return a.x1 < b.x1 end)
    local merged = {}
    for _, s in ipairs(segs) do
        if #merged == 0 then
            merged[1] = {x1 = s.x1, x2 = s.x2, top = s.top}
        else
            local m = merged[#merged]
            local sameTier = math.abs(s.top - m.top) <= SAME_FLOOR_TOP_TOL
            if sameTier and s.x1 <= m.x2 + 4 then
                m.x2 = math.max(m.x2, s.x2)
                m.top = math.min(m.top, s.top)
            else
                table.insert(merged, {x1 = s.x1, x2 = s.x2, top = s.top})
            end
        end
    end
    return merged
end

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

function RoomManager:loadRoom(room, world, player, opts)
    local platforms = {}
    for _, plat in ipairs(room.platforms) do
        local oneWay = plat.oneWay
        if oneWay == nil then
            oneWay = plat.h <= 24
        end
        local p = {}
        for k, v in pairs(plat) do p[k] = v end
        p.isPlatform = true
        p.oneWay = oneWay
        world:add(p, p.x, p.y, p.w, p.h)
        table.insert(platforms, p)
    end

    -- Mark thin platforms sitting above/near the water surface as bridges (plank rendering)
    local waterStripH = self.worldDef and self.worldDef.theme and self.worldDef.theme._waterStripH or 0
    if waterStripH > 0 then
        local waterY = room.height - waterStripH
        for _, plat in ipairs(platforms) do
            if not plat.isGapBridge and plat.oneWay and plat.h <= 28
                and plat.y + plat.h >= waterY - 8 then
                plat.isGapBridge = true
            end
        end
    end

    local floorBand = room.height - 110
    local segs = {}
    local waterGapRects = {}
    local floorExtentX, floorExtentW
    local themeWantsWaterGaps = self.worldDef and self.worldDef.theme and self.worldDef.theme._waterTexture
    local noFillEdges = {}
    for _, plat in ipairs(room.platforms) do
        if plat.h >= 36 and plat.y + plat.h >= floorBand - 24 then
            if not plat.noFill then
                table.insert(segs, {x1 = plat.x, x2 = plat.x + plat.w, top = plat.y})
            else
                table.insert(segs, {x1 = plat.x, x2 = plat.x + plat.w, top = plat.y, noFill = true})
                noFillEdges[plat.x + plat.w] = true
            end
        end
    end
    if #segs > 0 then
        local merged = mergeFloorSegments(segs)

        floorExtentX = merged[1].x1
        floorExtentW = merged[#merged].x2 - merged[1].x1

        for i = 1, #merged - 1 do
            local left, right = merged[i], merged[i + 1]
            local gw = right.x1 - left.x2
            local sameTier = math.abs(left.top - right.top) <= SAME_FLOOR_TOP_TOL
            if sameTier and gw >= MIN_FLOOR_GAP_FILL and gw <= MAX_FLOOR_GAP_FILL and not noFillEdges[left.x2] then
                local topY = math.min(left.top, right.top)
                -- Don't place a bridge if one already exists in this gap (avoids bridge-on-bridge)
                local alreadyBridged = false
                for _, existing in ipairs(platforms) do
                    if existing.x < left.x2 + gw and existing.x + existing.w > left.x2
                        and existing.y < topY + 36 and existing.y + existing.h > topY - 20 then
                        alreadyBridged = true
                        -- Mark the existing platform as a gap bridge so it renders as planks
                        if existing.oneWay then existing.isGapBridge = true end
                        break
                    end
                end
                if themeWantsWaterGaps and gw >= 8 then
                    waterGapRects[#waterGapRects + 1] = {
                        x = left.x2, y = topY, w = gw, h = room.height - topY,
                    }
                end
                if not alreadyBridged then
                    local bridge = {
                        x = left.x2, y = topY, w = gw, h = 28,
                        isPlatform = true, oneWay = true, isGapBridge = true,
                    }
                    world:add(bridge, bridge.x, bridge.y, bridge.w, bridge.h)
                    table.insert(platforms, bridge)
                end
            end
        end
    end

    addJumpChainsIfNeeded(room, world, platforms)

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

    local enemies = {}
    local pendingEnemySpawns = {}
    if not (opts and opts.skipEnemies) and not room.devArena then
        local roster = self.worldDef and self.worldDef.enemyRoster
        local plan = RoomData.buildSpawnPlan(room, self.difficulty, player.level or 1, roster)
        for _, spawn in ipairs(plan.immediate) do
            local enemy = Enemy.new(spawn.type, spawn.x, spawn.y, self.difficulty, { elite = spawn.elite })
            if enemy then
                world:add(enemy, enemy.x, enemy.y, enemy.w, enemy.h)
                table.insert(enemies, enemy)
            end
        end
        for _, spawn in ipairs(plan.delayed) do
            table.insert(pendingEnemySpawns, {
                type = spawn.type,
                x = spawn.x,
                y = spawn.y,
                elite = spawn.elite,
                time = spawn.delay or 0.5,
            })
        end
    end

    -- Exit door (dev arena has no exit / saloon progression)
    local door = nil
    if not room.devArena and room.exitDoor then
        door = {
            x = room.exitDoor.x,
            y = room.exitDoor.y,
            w = room.exitDoor.w,
            h = room.exitDoor.h,
            isDoor = true,
            locked = true,
        }
        world:add(door, door.x, door.y, door.w, door.h)
    end

    player.x = room.playerSpawn.x
    player.y = room.playerSpawn.y
    player.vx = 0
    player.vy = 0
    world:update(player, player.x, player.y)

    local nightMode
    if opts and opts.nightMode ~= nil then
        nightMode = opts.nightMode
    elseif self.nightVisualsOverride ~= nil then
        nightMode = self.nightVisualsOverride
    else
        nightMode = room.night == true
    end

    local chests = {}
    if not room.devArena and room.chests then
        for _, cd in ipairs(room.chests) do
            local chest = Chest.new(cd.x, cd.y, {
                tier        = cd.tier,
                spriteRow   = cd.spriteRow,
                bonePiles   = cd.bonePiles or {},
                fakeAmbush  = cd.fakeAmbush or false,
            })
            table.insert(chests, chest)
        end
    end

    local out = {
        platforms = platforms,
        walls = walls,
        enemies = enemies,
        pendingEnemySpawns = pendingEnemySpawns,
        chests = chests,
        door = door,
        width = room.width,
        height = room.height,
        --- Room `boss = true` in room data forces boss BGM; can also toggle at runtime for boss fights.
        bossFight = room.boss or false,
        nightMode = nightMode,
        --- Original `room.night` from data (for dev time sim / override resolution).
        sourceNight = room.night == true,
        --- Map-placed point lights (lanterns, etc.); see `WorldLighting.computeStaticLightPack`.
        staticLights = room.staticLights or {},
        devArena = room.devArena == true,
        waterGapRects = (#waterGapRects > 0) and waterGapRects or nil,
        waterStripX = floorExtentX,
        waterStripW = floorExtentW,
    }
    if nightMode then
        local fog = Vision.initFogForRoom(room)
        out.fogCellSize = fog.fogCellSize
        out.fogGridW = fog.fogGridW
        out.fogGridH = fog.fogGridH
        out.fogExplored = fog.fogExplored
        out.fogCanvasLQ = fog.fogCanvasLQ
        out.fogDirty = fog.fogDirty
    end

    out.decorProps = RoomProps.buildForRoom(self.worldId, room, out, {
        roomIndex = self.currentRoomIndex,
        totalCleared = self.totalRoomsCleared,
    })
    return out
end

function RoomManager:onRoomCleared()
    self.roomsCleared = self.roomsCleared + 1
    self.totalRoomsCleared = self.totalRoomsCleared + 1
    self.difficulty = 1 + self.totalRoomsCleared * 0.3
end

function RoomManager:isCheckpoint()
    local roomsPerCheckpoint = (self.worldDef and self.worldDef.roomsPerCheckpoint)
        or RoomData.ROOMS_PER_CHECKPOINT
    return self.roomsCleared >= roomsPerCheckpoint
end

function RoomManager:startNewCycle()
    self:generateSequence()
end

return RoomManager
