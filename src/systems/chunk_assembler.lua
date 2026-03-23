-- Chunk assembler — Dead Cells-style procedural level generation.
-- Assembles hand-crafted chunks on a grid to produce a standard room table
-- compatible with RoomManager:loadRoom() and RoomData.buildSpawnPlan().
--
-- EDGE FORMAT:
--   Horizontal edges (left, right): a NUMBER = the Y coordinate of the floor
--     at that connection point. false/nil = closed (no connection).
--   Vertical edges (top, bottom): true = open, false/nil = closed.
--   Backward compat: true on a horizontal edge is treated as Y=360.

local ChunkLoader = require("src.systems.chunk_loader")
local Worlds = require("src.data.worlds")
local GameRng = require("src.systems.game_rng")

local ChunkAssembler = {}

local function rngInt(channel, min_value, max_value)
    return GameRng.random("chunk_assembler." .. channel, min_value, max_value)
end

local function rngFloat(channel, min_value, max_value)
    return GameRng.randomFloat("chunk_assembler." .. channel, min_value, max_value)
end

-- Grid cell size in pixels
local CELL_W = 400
local CELL_H = 400

-- Default grid dimensions (used if world has no chunkGen config)
local DEFAULT_COLS = 8
local DEFAULT_ROWS = 3

-- Default directional weights
local DEFAULT_RIGHT_WEIGHT = 3
local DEFAULT_VERTICAL_WEIGHT = 1

-- Critical path constraints
local MIN_PATH_LENGTH = 5
local MAX_REGEN_ATTEMPTS = 12

-- Branching defaults
local DEFAULT_BRANCH_CHANCE = 0.4
local MAX_BRANCH_LENGTH = 2

-- How close two horizontal connection heights need to be to be compatible
local HEIGHT_TOLERANCE = 8

-- Default floor Y used for backward-compat (edges = {left = true})
local DEFAULT_FLOOR_Y = 360

---------------------------------------------------------------------------
-- Edge helpers
---------------------------------------------------------------------------

--- Get the connection height for a horizontal edge (left/right).
--- Returns a number, or nil if closed.
local function hEdgeHeight(chunk, side)
    local e = chunk.edges and chunk.edges[side]
    if not e then return nil end
    if e == true then return DEFAULT_FLOOR_Y end  -- backward compat
    if type(e) == "number" then return e end
    return nil
end

--- Get whether a vertical edge (top/bottom) is open.
local function vEdgeOpen(chunk, side)
    local e = chunk.edges and chunk.edges[side]
    return e == true
end

--- Generic: is this edge open at all?
local function hasEdge(chunk, side)
    if side == "left" or side == "right" then
        return hEdgeHeight(chunk, side) ~= nil
    else
        return vEdgeOpen(chunk, side)
    end
end

--- Opposite side name.
local OPP = { left = "right", right = "left", top = "bottom", bottom = "top" }

---------------------------------------------------------------------------
-- Chunk matching
---------------------------------------------------------------------------

--- Find chunks whose edges satisfy all requirements.
--- requirements: table of side → value, where:
---   horizontal sides: value = number (required height) or true (any height)
---   vertical sides:   value = true (must be open)
local function chunksMatchingEdges(pool, requirements)
    local result = {}
    for _, c in ipairs(pool) do
        local ok = true
        for side, req in pairs(requirements) do
            if side == "left" or side == "right" then
                local h = hEdgeHeight(c, side)
                if not h then
                    ok = false; break
                end
                if type(req) == "number" and math.abs(h - req) > HEIGHT_TOLERANCE then
                    ok = false; break
                end
                -- req == true means any height is fine
            else
                -- vertical
                if req and not vEdgeOpen(c, side) then
                    ok = false; break
                end
            end
        end
        if ok then result[#result + 1] = c end
    end
    return result
end

local function pickRandom(list)
    if #list == 0 then return nil end
    return list[rngInt("pick_random", #list)]
end

local function cellKey(col, row)
    return col .. "," .. row
end

---------------------------------------------------------------------------
-- Critical path generation
---------------------------------------------------------------------------

local function generateCriticalPath(cols, rows, rightW, vertW)
    rightW = rightW or DEFAULT_RIGHT_WEIGHT
    vertW  = vertW  or DEFAULT_VERTICAL_WEIGHT

    local startCol, startRow = 1, rows
    local path = {{col = startCol, row = startRow}}
    local visited = {[cellKey(startCol, startRow)] = true}
    local col, row = startCol, startRow

    while col < cols do
        local moves = {}
        if not visited[cellKey(col + 1, row)] then
            moves[#moves + 1] = {dc = 1, dr = 0, weight = rightW}
        end
        if row > 1 and not visited[cellKey(col, row - 1)] then
            moves[#moves + 1] = {dc = 0, dr = -1, weight = vertW}
        end
        if row < rows and not visited[cellKey(col, row + 1)] then
            moves[#moves + 1] = {dc = 0, dr = 1, weight = vertW}
        end

        if #moves == 0 then
            if col + 1 <= cols then
                col = col + 1
                row = math.max(1, math.min(rows, row))
                local key = cellKey(col, row)
                if not visited[key] then
                    visited[key] = true
                    path[#path + 1] = {col = col, row = row}
                end
            else
                break
            end
        else
            local totalWeight = 0
            for _, m in ipairs(moves) do totalWeight = totalWeight + m.weight end
            local roll = rngFloat("critical_path.weight", 0, totalWeight)
            local chosen = moves[1]
            local acc = 0
            for _, m in ipairs(moves) do
                acc = acc + m.weight
                if roll <= acc then chosen = m; break end
            end
            col = col + chosen.dc
            row = row + chosen.dr
            local key = cellKey(col, row)
            visited[key] = true
            path[#path + 1] = {col = col, row = row}
        end
    end

    return path
end

---------------------------------------------------------------------------
-- Path chunk assignment (height-aware)
---------------------------------------------------------------------------

--- Determine which edges a path cell needs open, and what height constraints
--- come from its already-placed neighbor.
--- Returns: openReqs (sides that must exist), heightReqs (side→number constraints)
local function requiredEdges(path, index)
    local openReqs = {}   -- side = true  (must have this edge open)
    local heightReqs = {} -- side = number (must match this height)

    local cur = path[index]

    -- From previous cell
    if index > 1 then
        local prev = path[index - 1]
        local dc = cur.col - prev.col
        local dr = cur.row - prev.row

        if dc > 0 then  -- came from left
            openReqs.left = true
            -- If the previous cell recorded its outgoing right height, require it
            if prev.outHeight then
                heightReqs.left = prev.outHeight
            end
        elseif dc < 0 then  -- came from right
            openReqs.right = true
            if prev.outHeight then
                heightReqs.right = prev.outHeight
            end
        elseif dr > 0 then  -- came from above
            openReqs.top = true
        elseif dr < 0 then  -- came from below
            openReqs.bottom = true
        end
    end

    -- Toward next cell (just needs to be open — any height is fine here)
    if index < #path then
        local nxt = path[index + 1]
        if nxt.col > cur.col then openReqs.right = openReqs.right or true end
        if nxt.col < cur.col then openReqs.left  = openReqs.left  or true end
        if nxt.row < cur.row then openReqs.top   = openReqs.top   or true end
        if nxt.row > cur.row then openReqs.bottom = openReqs.bottom or true end
    end

    -- Merge: height constraints override plain true
    local merged = {}
    for side, v in pairs(openReqs) do
        merged[side] = v
    end
    for side, h in pairs(heightReqs) do
        merged[side] = h  -- number constraint overrides bare true
    end

    return merged
end

--- After a chunk is placed, record the height its outgoing edge connects at.
--- This constrains the next cell in the path.
local function recordOutHeight(cell, path, index)
    if index >= #path then return end
    local nxt = path[index + 1]
    local dc = nxt.col - cell.col
    local dr = nxt.row - cell.row

    if dc > 0 then
        cell.outHeight = hEdgeHeight(cell.chunk, "right")
    elseif dc < 0 then
        cell.outHeight = hEdgeHeight(cell.chunk, "left")
    else
        cell.outHeight = nil  -- vertical: no height to propagate
    end
end

---------------------------------------------------------------------------
-- Branch generation
---------------------------------------------------------------------------

local function generateBranches(path, cols, rows, chunksByType, branchChance)
    branchChance = branchChance or DEFAULT_BRANCH_CHANCE
    local branches = {}
    local occupied = {}
    for _, cell in ipairs(path) do
        occupied[cellKey(cell.col, cell.row)] = true
    end

    for _, cell in ipairs(path) do
        if rngFloat("branch.chance", 0, 1) > branchChance then goto continue end
        if not cell.chunk then goto continue end

        local chunk = cell.chunk
        local dirMap = {
            {side = "left",   dc = -1, dr = 0},
            {side = "right",  dc = 1,  dr = 0},
            {side = "top",    dc = 0,  dr = -1},
            {side = "bottom", dc = 0,  dr = 1},
        }

        -- Find unused open edges that point to an empty cell
        local unusedDirs = {}
        for _, d in ipairs(dirMap) do
            if hasEdge(chunk, d.side) then
                local nc, nr = cell.col + d.dc, cell.row + d.dr
                if nc >= 1 and nc <= cols and nr >= 1 and nr <= rows
                    and not occupied[cellKey(nc, nr)] then
                    unusedDirs[#unusedDirs + 1] = d
                end
            end
        end
        if #unusedDirs == 0 then goto continue end

        local dir = pickRandom(unusedDirs)
        local branchLen = rngInt("branch.length", 1, MAX_BRANCH_LENGTH)
        local bc, br = cell.col + dir.dc, cell.row + dir.dr

        -- Determine the height constraint coming out of this cell
        local outH = nil
        if dir.dc ~= 0 then  -- horizontal branch
            outH = hEdgeHeight(chunk, dir.side)
        end

        for step = 1, branchLen do
            if bc < 1 or bc > cols or br < 1 or br > rows then break end
            if occupied[cellKey(bc, br)] then break end

            local isEnd = (step == branchLen)
            local oppSide = OPP[dir.side]

            -- Build requirements for this branch cell
            local needEdges = {}
            if dir.dc ~= 0 then
                needEdges[oppSide] = outH or true  -- height or any
            else
                needEdges[oppSide] = true
            end
            if not isEnd then
                needEdges[dir.side] = true  -- continue the branch
            end

            local typePool = isEnd and (chunksByType["secret"] or {})
                or (chunksByType["connector"] or chunksByType["combat"] or {})

            local candidates = chunksMatchingEdges(typePool, needEdges)
            if #candidates == 0 then
                local allChunks = {}
                for _, list in pairs(chunksByType) do
                    for _, c in ipairs(list) do allChunks[#allChunks + 1] = c end
                end
                candidates = chunksMatchingEdges(allChunks, needEdges)
            end
            if #candidates == 0 then break end

            local chosen = pickRandom(candidates)
            occupied[cellKey(bc, br)] = true
            branches[#branches + 1] = {col = bc, row = br, chunk = chosen}

            -- Update outH for next branch step
            if dir.dc ~= 0 then
                outH = hEdgeHeight(chosen, dir.side)
            end

            bc = bc + dir.dc
            br = br + dir.dr
        end

        ::continue::
    end

    return branches
end

---------------------------------------------------------------------------
-- Flatten + stitch
---------------------------------------------------------------------------

local function offsetPlatforms(chunk, col, row)
    local ox = (col - 1) * CELL_W
    local oy = (row - 1) * CELL_H
    local platforms = {}
    for _, p in ipairs(chunk.platforms) do
        -- Copy all fields so world-specific metadata (trainCar, carType, noFill…) survives assembly
        local np = {}
        for k, v in pairs(p) do np[k] = v end
        np.x = p.x + ox
        np.y = p.y + oy
        platforms[#platforms + 1] = np
    end
    return platforms, ox, oy
end

--- Stitch horizontal chunk boundaries using declared edge heights.
--- If chunkA.right = 280 and chunkB.left = 280, the floors meet at y=280.
--- Inserts a tiny bridge if the floors don't quite touch pixel-perfectly.
local function stitchEdges(allPlatforms, cells)
    local bridges = {}

    for _, cell in ipairs(cells) do
        local col, row = cell.col, cell.row
        local ox = (col - 1) * CELL_W
        local oy = (row - 1) * CELL_H

        -- Horizontal stitch: right edge of this cell → left edge of right neighbor
        local rightH = hEdgeHeight(cell.chunk, "right")
        if rightH then
            local rightNeighbor = nil
            for _, other in ipairs(cells) do
                if other.col == col + 1 and other.row == row then
                    rightNeighbor = other; break
                end
            end
            if rightNeighbor then
                local leftH = hEdgeHeight(rightNeighbor.chunk, "left")
                if leftH and math.abs(rightH - leftH) <= HEIGHT_TOLERANCE then
                    local boundary = ox + CELL_W
                    -- Use the declared heights (offset by row) to place bridge
                    local floorY = math.min(rightH, leftH) + oy
                    -- Only add bridge if there's actually a gap (scan nearby platforms)
                    local hasLeft, hasRight = false, false
                    for _, p in ipairs(allPlatforms) do
                        if p.x + p.w >= boundary - 2 and p.x < boundary then
                            hasLeft = true
                        end
                        if p.x <= boundary + 2 and p.x + p.w > boundary then
                            hasRight = true
                        end
                    end
                    if not (hasLeft and hasRight) then
                        bridges[#bridges + 1] = {
                            x = boundary - 8,
                            y = floorY,
                            w = 16,
                            h = 16,
                            oneWay = true,
                        }
                    end
                end
            end
        end

        -- Vertical stitch: bottom edge of this cell → top edge of lower neighbor
        if vEdgeOpen(cell.chunk, "bottom") then
            local bottomNeighbor = nil
            for _, other in ipairs(cells) do
                if other.col == col and other.row == row + 1 then
                    bottomNeighbor = other; break
                end
            end
            if bottomNeighbor and vEdgeOpen(bottomNeighbor.chunk, "top") then
                local boundary = oy + CELL_H
                local midX = ox + CELL_W * 0.5
                bridges[#bridges + 1] = {
                    x = midX - 28,
                    y = boundary - 8,
                    w = 56,
                    h = 16,
                    oneWay = true,
                }
            end
        end
    end

    for _, b in ipairs(bridges) do
        allPlatforms[#allPlatforms + 1] = b
    end
end

local function flattenToRoom(cells, cols, rows)
    local allPlatforms = {}
    local playerSpawn = nil
    local exitDoor = nil

    for _, cell in ipairs(cells) do
        local chunk = cell.chunk
        local platforms, ox, oy = offsetPlatforms(chunk, cell.col, cell.row)
        for _, p in ipairs(platforms) do
            allPlatforms[#allPlatforms + 1] = p
        end

        if chunk.chunkType == "entrance" and chunk.playerSpawn then
            playerSpawn = {
                x = chunk.playerSpawn.x + ox,
                y = chunk.playerSpawn.y + oy,
            }
        end

        if chunk.chunkType == "exit" and chunk.exitDoor then
            exitDoor = {
                x = chunk.exitDoor.x + ox,
                y = chunk.exitDoor.y + oy,
                w = chunk.exitDoor.w or 32,
                h = chunk.exitDoor.h or 32,
            }
        end
    end

    stitchEdges(allPlatforms, cells)

    local maxCol, maxRow = 0, 0
    for _, cell in ipairs(cells) do
        if cell.col > maxCol then maxCol = cell.col end
        if cell.row > maxRow then maxRow = cell.row end
    end

    return {
        id = "generated_" .. tostring(rngInt("generated_id", 100000, 999999)),
        width  = maxCol * CELL_W,
        height = maxRow * CELL_H,
        platforms = allPlatforms,
        playerSpawn = playerSpawn or {x = 60, y = (rows - 1) * CELL_H + 310},
        exitDoor = exitDoor or {
            x = (maxCol * CELL_W) - 60,
            y = (rows - 1) * CELL_H + 328,
            w = 32, h = 32,
        },
        spawns = {},
        generated = true,
    }
end

---------------------------------------------------------------------------
-- Validation (BFS reachability)
---------------------------------------------------------------------------

local MAX_JUMP_UP  = 270
local MAX_WALK_GAP = 280

local function horizGap(a, b)
    if a.x + a.w <= b.x then return b.x - (a.x + a.w) end
    if b.x + b.w <= a.x then return a.x - (b.x + b.w) end
    return 0
end

local function horizOverlapLoose(a, b, slack)
    slack = slack or 0
    return a.x + slack < b.x + b.w and a.x + a.w - slack > b.x
end

local function platformsConnected(P, Q)
    if P == Q then return true end
    local gap = horizGap(P, Q)
    if math.abs(P.y - Q.y) < 14 then return gap <= MAX_WALK_GAP end
    if Q.y > P.y + 4 and horizOverlapLoose(P, Q, -28) then return true end
    if P.y > Q.y + 4 and horizOverlapLoose(Q, P, -28) then return true end
    if P.y > Q.y + 6 and P.y - Q.y <= MAX_JUMP_UP and gap <= 130 then return true end
    if Q.y > P.y + 6 and Q.y - P.y <= MAX_JUMP_UP and gap <= 130 then return true end
    return false
end

local function findNearestPlatform(room, x, y)
    local best, bestDist = nil, math.huge
    for _, plat in ipairs(room.platforms) do
        if x >= plat.x - 4 and x <= plat.x + plat.w + 4 then
            local d = math.abs(plat.y - y)
            if d < bestDist then bestDist = d; best = plat end
        end
    end
    if best and bestDist < 120 then return best end
    for _, plat in ipairs(room.platforms) do
        if x >= plat.x and x <= plat.x + plat.w
            and y >= plat.y and y <= plat.y + plat.h then
            return plat
        end
    end
    return room.platforms[1]
end

local function validateRoom(room)
    local ps = room.playerSpawn
    local ed = room.exitDoor
    if not ps or not ed then return false end

    local startPlat = findNearestPlatform(room, ps.x + 8, ps.y + 28)
    local exitPlat  = findNearestPlatform(room, ed.x + 16, ed.y + 32)
    if not startPlat or not exitPlat then return false end

    local reachable = {}
    local queue = {startPlat}
    reachable[startPlat] = true
    local qi = 1
    while qi <= #queue do
        local P = queue[qi]; qi = qi + 1
        for _, Q in ipairs(room.platforms) do
            if not reachable[Q] and platformsConnected(P, Q) then
                reachable[Q] = true
                queue[#queue + 1] = Q
            end
        end
    end

    return reachable[exitPlat] == true
end

---------------------------------------------------------------------------
-- Main generate
---------------------------------------------------------------------------

function ChunkAssembler.generate(worldId, difficulty, opts)
    opts = opts or {}

    local worldDef = Worlds.get(worldId)
    local gen = (worldDef and worldDef.chunkGen) or {}

    local cols          = opts.cols          or gen.cols          or DEFAULT_COLS
    local rows          = opts.rows          or gen.rows          or DEFAULT_ROWS
    local rightWeight   = opts.rightWeight   or gen.rightWeight   or DEFAULT_RIGHT_WEIGHT
    local verticalWeight = opts.verticalWeight or gen.verticalWeight or DEFAULT_VERTICAL_WEIGHT
    local branchChance  = opts.branchChance  or gen.branchChance  or DEFAULT_BRANCH_CHANCE

    local chunksByType = ChunkLoader.getPoolByType(worldId)

    if not chunksByType["entrance"] or #chunksByType["entrance"] == 0 then
        error("[ChunkAssembler] No entrance chunks for world: " .. worldId)
    end
    if not chunksByType["exit"] or #chunksByType["exit"] == 0 then
        error("[ChunkAssembler] No exit chunks for world: " .. worldId)
    end

    local fillPool = {}
    for _, t in ipairs({"combat", "traversal", "connector"}) do
        for _, c in ipairs(chunksByType[t] or {}) do
            fillPool[#fillPool + 1] = c
        end
    end

    for attempt = 1, MAX_REGEN_ATTEMPTS do
        local path = generateCriticalPath(cols, rows, rightWeight, verticalWeight)

        if #path < MIN_PATH_LENGTH then goto retry end

        -- Assign chunks to path cells, tracking connection heights
        for i, cell in ipairs(path) do
            local req = requiredEdges(path, i)

            local pool
            if i == 1 then
                pool = chunksByType["entrance"]
            elseif i == #path then
                pool = chunksByType["exit"]
            else
                pool = fillPool
            end

            local candidates = chunksMatchingEdges(pool, req)

            -- Fallback: relax to any chunk type that fits
            if #candidates == 0 then
                local allChunks = {}
                for _, list in pairs(chunksByType) do
                    for _, c in ipairs(list) do allChunks[#allChunks + 1] = c end
                end
                candidates = chunksMatchingEdges(allChunks, req)
            end

            if #candidates == 0 then goto retry end

            cell.chunk = pickRandom(candidates)

            -- Record outgoing height so the next cell can match it
            recordOutHeight(cell, path, i)
        end

        local branches = generateBranches(path, cols, rows, chunksByType, branchChance)

        local allCells = {}
        for _, cell in ipairs(path) do allCells[#allCells + 1] = cell end
        for _, cell in ipairs(branches) do allCells[#allCells + 1] = cell end

        local room = flattenToRoom(allCells, cols, rows)

        if validateRoom(room) then
            return room
        end

        ::retry::
    end

    print("[ChunkAssembler] WARNING: all attempts failed, using fallback")
    return ChunkAssembler.generateFallback(worldId)
end

local function poolFirst(list)
    return (type(list) == "table" and list[1]) or nil
end

local function poolAnyChunk(chunksByType)
    for _, list in pairs(chunksByType) do
        local c = poolFirst(list)
        if c then return c end
    end
    return nil
end

function ChunkAssembler.generateFallback(worldId)
    local chunksByType = ChunkLoader.getPoolByType(worldId)
    local entrance = poolFirst(chunksByType["entrance"])
    local exitChunk = poolFirst(chunksByType["exit"])
    local combat = poolFirst(chunksByType["combat"] or chunksByType["connector"])

    if not entrance or not exitChunk then
        local any = poolAnyChunk(chunksByType)
        entrance = entrance or any
        exitChunk = exitChunk or any
    end
    if entrance and not exitChunk then exitChunk = entrance end
    if exitChunk and not entrance then entrance = exitChunk end

    if not entrance or not exitChunk then
        print("[ChunkAssembler] ERROR: generateFallback: empty chunk pool for world " .. tostring(worldId))
        return {
            id = "fallback_empty_" .. tostring(worldId),
            width = 3 * CELL_W,
            height = CELL_H,
            platforms = {},
            playerSpawn = { x = 60, y = 310 },
            exitDoor = { x = 3 * CELL_W - 60, y = 328, w = 32, h = 32 },
            spawns = {},
            generated = true,
        }
    end

    local cells = {{col = 1, row = 1, chunk = entrance}}
    if combat then
        cells[#cells + 1] = {col = 2, row = 1, chunk = combat}
        cells[#cells + 1] = {col = 3, row = 1, chunk = exitChunk}
    else
        cells[#cells + 1] = {col = 2, row = 1, chunk = exitChunk}
    end

    return flattenToRoom(cells, 3, 1)
end

function ChunkAssembler.getCellSize()
    return CELL_W, CELL_H
end

-- Player AABB height matches src/entities/player.lua (standing on platform top).
local PREVIEW_PLAYER_H = 28

--- Build a one-cell room table from a single chunk (editor playtest of a specific level file).
function ChunkAssembler.chunkToPreviewRoom(chunk)
    if not chunk then return nil end
    local w = chunk.width or CELL_W
    local h = chunk.height or CELL_H
    local platforms = {}
    for _, p in ipairs(chunk.platforms or {}) do
        local np = {}
        for k, v in pairs(p) do np[k] = v end
        platforms[#platforms + 1] = np
    end

    local playerSpawn = chunk.playerSpawn
    if playerSpawn then
        playerSpawn = { x = playerSpawn.x, y = playerSpawn.y }
    else
        local floorPlat = nil
        local bestY = -1e9
        for _, p in ipairs(platforms) do
            if p.y > bestY then
                bestY = p.y
                floorPlat = p
            end
        end
        if floorPlat then
            local px = math.floor(floorPlat.x + 40)
            px = math.min(px, floorPlat.x + floorPlat.w - 40)
            px = math.max(floorPlat.x + 8, px)
            playerSpawn = { x = px, y = floorPlat.y - PREVIEW_PLAYER_H }
        else
            playerSpawn = { x = 60, y = h - 100 }
        end
    end

    local exitDoor = chunk.exitDoor
    if exitDoor then
        exitDoor = {
            x = exitDoor.x, y = exitDoor.y,
            w = exitDoor.w or 32, h = exitDoor.h or 32,
        }
    else
        exitDoor = { x = w - 60, y = h - 72, w = 32, h = 32 }
    end

    return {
        id = "preview_" .. tostring(chunk.id or "chunk"),
        width = w,
        height = h,
        platforms = platforms,
        playerSpawn = playerSpawn,
        exitDoor = exitDoor,
        spawns = {},
        generated = true,
        editorPreviewChunk = true,
    }
end

return ChunkAssembler
