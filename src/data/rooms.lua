local RoomLoader = require("src.systems.room_loader")
local Worlds = require("src.data.worlds")
local GameRng = require("src.systems.game_rng")

local RoomData = {}

RoomData.ROOMS_PER_CHECKPOINT = 5

--- Pool entries may set `night = true` for player lamp, fog-of-war, and WorldLighting shader.
--- Omit or `false` for full daylight (default). `RoomManager.nightVisualsOverride` can force all rooms.
--- Room layouts live under `src/data/rooms/<worldId>/` and are loaded via RoomLoader.
local DEFAULT_WORLD_ID = Worlds.default or "forest"

--- Get the room pool for a given world (loads from per-room files).
--- Falls back to the default world if no worldId given.
function RoomData.getPool(worldId)
    return RoomLoader.getPool(worldId or DEFAULT_WORLD_ID)
end

-- Legacy compatibility: RoomData.pool loads the default world on first access.
-- New code should use RoomData.getPool(worldId) instead.
RoomData.pool = nil
setmetatable(RoomData, {
    __index = function(t, k)
        if k == "pool" then
            local p = RoomLoader.getPool(DEFAULT_WORLD_ID)
            rawset(t, "pool", p)
            return p
        end
    end,
})

--- Sandbox: not in `pool`; used when `RoomManager.devArenaMode` is set.
RoomData.devArena = {
    id = "dev_arena",
    devArena = true,
    width = 1600,
    height = 800,
    -- Single ground strip so every spawned prop is reachable on foot (no gap jump)
    platforms = {
        { x = 0,    y = 736, w = 1600, h = 64 },
        { x = 180,  y = 580, w = 200, h = 16 },
        { x = 480,  y = 500, w = 160, h = 16 },
        { x = 780,  y = 540, w = 220, h = 16 },
        { x = 1100, y = 460, w = 140, h = 16 },
        { x = 320,  y = 380, w = 120, h = 16 },
        { x = 900,  y = 340, w = 160, h = 16 },
    },
    spawns = {},
    playerSpawn = { x = 120, y = 680 },
}

-- Foot height per type (must match src/data/enemies.lua)
local TYPE_H = {
    bandit = 28,
    gunslinger = 28,
    buzzard = 16,
    necromancer = 34,
    nightborne = 30,
    ogreboss = 44,
    blackkid = 40,
}
local PLAYER_FEET_H = 28

-- Match room_manager jump tier (~double-jump vertical budget)
local MAX_JUMP_UP = 270
-- Same-tier walk: allow wide gaps (floor often split into segments / auto-bridges in-game)
local MAX_WALK_GAP = 280

local function rngInt(channel, min_value, max_value)
    return GameRng.random("rooms." .. channel, min_value, max_value)
end

local function rngFloat(channel, min_value, max_value)
    return GameRng.randomFloat("rooms." .. channel, min_value, max_value)
end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = rngInt("shuffle", i)
        t[i], t[j] = t[j], t[i]
    end
end

local function dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

local function tooClose(x, y, placed, minD)
    local min2 = minD * minD
    for _, p in ipairs(placed) do
        if dist2(x, y, p.x, p.y) < min2 then
            return true
        end
    end
    return false
end

-- Minimum center-to-center distance from player spawn (enemies use ~22px wide; player 16px).
local MIN_SPAWN_DIST_FROM_PLAYER = 100

local function farEnoughFromPlayer(cx, cy, playerCx, playerCy)
    return dist2(cx, cy, playerCx, playerCy) >= MIN_SPAWN_DIST_FROM_PLAYER * MIN_SPAWN_DIST_FROM_PLAYER
end

local function horizGap(a, b)
    if a.x + a.w <= b.x then return b.x - (a.x + a.w) end
    if b.x + b.w <= a.x then return a.x - (b.x + b.w) end
    return 0
end

local function horizOverlapLoose(a, b, slack)
    slack = slack or 0
    return a.x + slack < b.x + b.w and a.x + a.w - slack > b.x
end

--- Undirected connectivity: walk along a tier, fall between tiers, or jump up within budget.
local function platformsConnected(P, Q)
    if P == Q then return true end
    local gap = horizGap(P, Q)
    if math.abs(P.y - Q.y) < 14 then
        return gap <= MAX_WALK_GAP
    end
    -- Fall from upper surface to lower
    if Q.y > P.y + 4 and horizOverlapLoose(P, Q, -28) then
        return true
    end
    if P.y > Q.y + 4 and horizOverlapLoose(Q, P, -28) then
        return true
    end
    -- Jump up onto higher surface (either direction)
    if P.y > Q.y + 6 and P.y - Q.y <= MAX_JUMP_UP and gap <= 130 then
        return true
    end
    if Q.y > P.y + 6 and Q.y - P.y <= MAX_JUMP_UP and gap <= 130 then
        return true
    end
    return false
end

local function findStartPlatform(room, playerSpawn)
    if not playerSpawn then return nil end
    local feetX = playerSpawn.x + 8
    local feetY = playerSpawn.y + PLAYER_FEET_H
    local best, bestDist = nil, math.huge
    for _, plat in ipairs(room.platforms) do
        if feetX >= plat.x - 4 and feetX <= plat.x + plat.w + 4 then
            local d = math.abs(plat.y - feetY)
            if d < bestDist then
                bestDist = d
                best = plat
            end
        end
    end
    if best and bestDist < 100 then
        return best
    end
    -- Feet inside platform volume (thick floor)
    for _, plat in ipairs(room.platforms) do
        if feetX >= plat.x and feetX <= plat.x + plat.w
            and feetY >= plat.y and feetY <= plat.y + plat.h then
            return plat
        end
    end
    -- Nearest thick floor under spawn
    for _, plat in ipairs(room.platforms) do
        if plat.h >= 40 and plat.y + plat.h >= room.height - 120
            and feetX >= plat.x - 20 and feetX <= plat.x + plat.w + 20 then
            return plat
        end
    end
    return room.platforms[1]
end

--- All platforms whose tops are reachable from the player spawn (BFS over movement graph).
local function collectReachablePlatforms(room, playerSpawn)
    local start = findStartPlatform(room, playerSpawn)
    if not start then
        return {}
    end
    local reachable = {}
    local queue = { start }
    reachable[start] = true
    local qi = 1
    while qi <= #queue do
        local P = queue[qi]
        qi = qi + 1
        for _, Q in ipairs(room.platforms) do
            if not reachable[Q] and platformsConnected(P, Q) then
                reachable[Q] = true
                queue[#queue + 1] = Q
            end
        end
    end
    local list = {}
    for _, plat in ipairs(room.platforms) do
        if reachable[plat] and plat.w >= 40 then
            table.insert(list, plat)
        end
    end
    return list
end

-- Pick an enemy type using the world's roster weights (if provided).
-- Falls back to hardcoded tier-based probabilities when no roster is given.
local function pickEnemyType(difficulty, playerLevel, enemyRoster)
    -- Use roster weights if available
    if enemyRoster and next(enemyRoster) then
        local total = 0
        local entries = {}
        for typeId, weight in pairs(enemyRoster) do
            if weight > 0 then
                total = total + weight
                entries[#entries + 1] = { type = typeId, weight = weight }
            end
        end
        if total > 0 then
            local r = rngFloat("roster_weight_pick", 0, total)
            local sum = 0
            for _, e in ipairs(entries) do
                sum = sum + e.weight
                if r <= sum then return e.type end
            end
            return entries[#entries].type
        end
    end

    -- Fallback: original tier-based distribution
    local tier = math.min(1, (difficulty - 1) * 0.18 + (playerLevel - 1) * 0.05)
    local nightborneChance = 0.08 + tier * 0.14
    local necromancerChance = 0.03 + tier * 0.10
    local buzzardChance = 0.10 + tier * 0.04
    local gunslingerChance = 0.18
    local banditChance = math.max(0.22, 1 - nightborneChance - necromancerChance - buzzardChance - gunslingerChance)
    local r = rngFloat("fallback_type_pick", 0, 1)
    local banditCut = banditChance
    local nightborneCut = banditCut + nightborneChance
    local gunslingerCut = nightborneCut + gunslingerChance
    local necromancerCut = gunslingerCut + necromancerChance

    if r < banditCut then
        return "bandit"
    elseif r < nightborneCut then
        return "nightborne"
    elseif r < gunslingerCut then
        return "gunslinger"
    elseif r < necromancerCut then
        return "necromancer"
    else
        return "buzzard"
    end
end

local function computeTargetCount(difficulty, playerLevel)
    local prog = (difficulty - 1) * 0.55 + (playerLevel - 1) * 0.65
    local base = 12 + math.floor(prog * 3.8)
    local n = base + rngInt("target_count_variation", -3, 6)
    return math.max(9, math.min(34, n))
end

local function eliteChance(difficulty, playerLevel)
    return math.min(0.34, 0.05 + (difficulty - 1) * 0.065 + (playerLevel - 1) * 0.028)
end

--- Random placements, mixed types, optional elite; split into instant spawns vs delayed arrivals.
function RoomData.buildSpawnPlan(room, difficulty, playerLevel, enemyRoster)
    local walkPlats = collectReachablePlatforms(room, room.playerSpawn)
    if #walkPlats == 0 then
        local s = findStartPlatform(room, room.playerSpawn)
        if s then
            walkPlats = { s }
        end
    end
    if #walkPlats == 0 then
        for _, plat in ipairs(room.platforms) do
            if plat.h >= 48 and plat.y + plat.h >= room.height - 120 and plat.w >= 120 then
                walkPlats[#walkPlats + 1] = plat
            end
        end
    end
    if #walkPlats == 0 then
        for _, plat in ipairs(room.platforms) do
            if plat.w >= 80 then
                walkPlats[#walkPlats + 1] = plat
            end
        end
    end

    local placed = {}
    local specs = {}
    local n = computeTargetCount(difficulty, playerLevel)
    local eChance = eliteChance(difficulty, playerLevel)
    local px0 = room.playerSpawn and room.playerSpawn.x or 80
    local avoidX2 = px0 + 260
    local ps = room.playerSpawn
    local playerCx = (ps and ps.x or 0) + 8
    local playerCy = (ps and ps.y or 0) + 14

    local function tryGround(typeId)
        local h = TYPE_H[typeId]
        local function groundCandidateOk(x, y, cx, cy)
            if x < 24 or x > room.width - 48 then return false end
            if tooClose(cx, cy, placed, 46) then return false end
            if not farEnoughFromPlayer(cx, cy, playerCx, playerCy) then return false end
            if x < avoidX2 and rngFloat("ground_avoid_spawn", 0, 1) < 0.42 then return false end
            return true
        end
        for _ = 1, 120 do
            local plat = walkPlats[rngInt("ground_pick_primary", #walkPlats)]
            local margin = 18
            local maxX = plat.x + plat.w - margin - 22
            if maxX > plat.x + margin then
                local x = plat.x + margin + rngFloat("ground_x_primary", 0, maxX - (plat.x + margin))
                local y = plat.y - h
                local cx, cy = x + 11, y + h * 0.5
                if groundCandidateOk(x, y, cx, cy) then
                    table.insert(placed, { x = cx, y = cy })
                    return x, y
                end
            end
        end
        -- Relax player distance (still avoid stacking on other enemies)
        for _ = 1, 100 do
            local plat = walkPlats[rngInt("ground_pick_relaxed", #walkPlats)]
            local margin = 18
            local maxX = plat.x + plat.w - margin - 22
            if maxX > plat.x + margin then
                local x = plat.x + margin + rngFloat("ground_x_relaxed", 0, maxX - (plat.x + margin))
                local y = plat.y - h
                local cx, cy = x + 11, y + h * 0.5
                if x >= 24 and x <= room.width - 48 and not tooClose(cx, cy, placed, 46) then
                    table.insert(placed, { x = cx, y = cy })
                    return x, y
                end
            end
        end
        -- Pick farthest point from player that still respects enemy spacing
        local bestX, bestY, bestD2 = nil, nil, -1
        for _, plat in ipairs(walkPlats) do
            local margin = 18
            local maxX = plat.x + plat.w - margin - 22
            if maxX > plat.x + margin then
                for _ = 1, 32 do
                    local x = plat.x + margin + rngFloat("ground_x_farthest", 0, maxX - (plat.x + margin))
                    local y = plat.y - h
                    local cx, cy = x + 11, y + h * 0.5
                    if x >= 24 and x <= room.width - 48 and not tooClose(cx, cy, placed, 46) then
                        local d2 = dist2(cx, cy, playerCx, playerCy)
                        if d2 > bestD2 then
                            bestD2 = d2
                            bestX, bestY = x, y
                        end
                    end
                end
            end
        end
        if bestX then
            local cx, cy = bestX + 11, bestY + h * 0.5
            table.insert(placed, { x = cx, y = cy })
            return bestX, bestY
        end
        local plat = walkPlats[rngInt("ground_pick_fallback", #walkPlats)]
        local x = math.max(24, math.min(room.width - 48, plat.x + plat.w * 0.5 - 10))
        local y = plat.y - h
        local cx, cy = x + 11, y + h * 0.5
        table.insert(placed, { x = cx, y = cy })
        return x, y
    end

    local function tryAir()
        local function airOk(cx, cy)
            if tooClose(cx, cy, placed, 44) then return false end
            if not farEnoughFromPlayer(cx, cy, playerCx, playerCy) then return false end
            return true
        end
        for _ = 1, 80 do
            local plat = walkPlats[rngInt("air_pick_primary", #walkPlats)]
            local margin = 20
            local maxX = plat.x + plat.w - margin - 22
            if maxX > plat.x + margin then
                local x = plat.x + margin + rngFloat("air_x_primary", 0, maxX - (plat.x + margin))
                local y = plat.y - rngInt("air_y_primary", 48, 150)
                if y < 40 then y = 40 end
                if airOk(x + 11, y + 8) then
                    table.insert(placed, { x = x + 11, y = y + 8 })
                    return x, y
                end
            end
        end
        for _ = 1, 70 do
            local plat = walkPlats[rngInt("air_pick_relaxed", #walkPlats)]
            local margin = 20
            local maxX = plat.x + plat.w - margin - 22
            if maxX > plat.x + margin then
                local x = plat.x + margin + rngFloat("air_x_relaxed", 0, maxX - (plat.x + margin))
                local y = plat.y - rngInt("air_y_relaxed", 48, 150)
                if y < 40 then y = 40 end
                if not tooClose(x + 11, y + 8, placed, 44) then
                    table.insert(placed, { x = x + 11, y = y + 8 })
                    return x, y
                end
            end
        end
        local bestX, bestY, bestD2 = nil, nil, -1
        for _, plat in ipairs(walkPlats) do
            local margin = 20
            local maxX = plat.x + plat.w - margin - 22
            if maxX > plat.x + margin then
                for _ = 1, 24 do
                    local x = plat.x + margin + rngFloat("air_x_farthest", 0, maxX - (plat.x + margin))
                    local y = plat.y - rngInt("air_y_farthest", 48, 150)
                    if y < 40 then y = 40 end
                    local cx, cy = x + 11, y + 8
                    if not tooClose(cx, cy, placed, 44) then
                        local d2 = dist2(cx, cy, playerCx, playerCy)
                        if d2 > bestD2 then
                            bestD2 = d2
                            bestX, bestY = x, y
                        end
                    end
                end
            end
        end
        if bestX then
            table.insert(placed, { x = bestX + 11, y = bestY + 8 })
            return bestX, bestY
        end
        local plat = walkPlats[rngInt("air_pick_fallback", #walkPlats)]
        local x = plat.x + plat.w * 0.5 - 11
        local y = math.max(40, plat.y - 90)
        table.insert(placed, { x = x + 11, y = y + 8 })
        return x, y
    end

    for _ = 1, n do
        local t = pickEnemyType(difficulty, playerLevel, enemyRoster)
        local elite = rngFloat("elite_roll", 0, 1) < eChance
        local x, y
        if t == "buzzard" then
            x, y = tryAir()
        else
            x, y = tryGround(t)
        end
        table.insert(specs, { type = t, x = x, y = y, elite = elite })
    end

    shuffle(specs)

    local staggerRatio = 0.38 + rngFloat("stagger_ratio", 0, 0.22)
    local nDelayed = math.floor(n * staggerRatio + rngInt("stagger_bonus", 0, 1))
    nDelayed = math.min(nDelayed, n - 1)
    nDelayed = math.max(0, nDelayed)

    local immediate = {}
    local delayed = {}
    for i, s in ipairs(specs) do
        if i <= n - nDelayed then
            table.insert(immediate, s)
        else
            s.delay = 0.12 + (rngFloat("delayed_spawn_curve", 0, 1) ^ 1.4) * 7.5 + rngFloat("delayed_spawn_bonus", 0, 0.35)
            table.insert(delayed, s)
        end
    end

    shuffle(delayed)
    return { immediate = immediate, delayed = delayed }
end

return RoomData
