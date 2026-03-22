-- Procedural decorative props on walkable platforms (desert, etc.).
-- Uses a local RNG so we never reseed global math.random.

local WorldProps = require("src.data.world_props")

local RoomProps = {}

local imageCache = {}

local function getImage(path)
    local cached = imageCache[path]
    if cached ~= nil then
        return cached
    end
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
        img:setFilter("nearest", "nearest")
        imageCache[path] = img
        return img
    end
    imageCache[path] = false
    return nil
end

--- Deterministic 32-bit seed from strings / numbers (djb2-ish mix).
local function mixSeed(...)
    local h = 5381
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        local s = type(v) == "string" and v or tostring(v)
        for j = 1, #s do
            h = ((h * 33) + string.byte(s, j)) % 4294967296
        end
    end
    if h == 0 then h = 1 end
    return h
end

--- Park–Miller LCG — returns rng() in [0, 1)
local function makeRNG(seed)
    local s = seed % 2147483646
    if s < 1 then s = 1 end
    return function()
        s = (s * 48271) % 2147483647
        return (s - 1) / 2147483646
    end
end

local function pickWeighted(rng, defs)
    local sum = 0
    for _, d in ipairs(defs) do
        sum = sum + (d.weight or 1)
    end
    if sum <= 0 then return nil end
    local r = rng() * sum
    local acc = 0
    for _, d in ipairs(defs) do
        acc = acc + (d.weight or 1)
        if r <= acc then return d end
    end
    return defs[#defs]
end

local function dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

local function tooCloseToPlaced(px, footY, placed, minDist)
    local min2 = minDist * minDist
    for _, q in ipairs(placed) do
        if dist2(px, footY, q.x, q.footY) < min2 then
            return true
        end
    end
    return false
end

local function clearOfSpawn(x, footY, px, py, pw, ph, clearR)
    if not px then return true end
    local pfx = px + pw * 0.5
    local pfy = py + ph
    return dist2(x, footY, pfx, pfy) >= clearR * clearR
end

local function clearOfDoor(x, footY, door, clearR)
    if not door then return true end
    local cx = door.x + door.w * 0.5
    local cy = door.y + door.h * 0.5
    return dist2(x, footY, cx, cy) >= clearR * clearR
end

--- @param worldId string
--- @param rawRoom table room source (id, playerSpawn, exitDoor, …)
--- @param loadedRoom table from RoomManager:loadRoom (platforms after bridges, width, height)
--- @param opts table|nil optional: roomIndex, totalCleared
--- @return table[] list of draw instances { id, path, x, footY, scale, flip }
function RoomProps.buildForRoom(worldId, rawRoom, loadedRoom, opts)
    opts = opts or {}
    local defs = WorldProps.getDecorDefinitions(worldId)
    if #defs == 0 then return {} end

    local spawnCfg = WorldProps.spawn[worldId] or WorldProps.spawn.desert
    local defaultSink = spawnCfg.defaultSink or 0
    local slotW = spawnCfg.slotWidth or 88
    local placeChance = spawnCfg.placeChance or 0.4
    local minSpacing = spawnCfg.minSpacing or 32
    local marginX = spawnCfg.marginX or 24
    local spawnClearR = spawnCfg.spawnClearR or 80
    local doorClearR = spawnCfg.doorClearR or 64

    local seed = mixSeed(
        worldId,
        rawRoom.id or "",
        loadedRoom.width or 0,
        loadedRoom.height or 0,
        #loadedRoom.platforms,
        opts.roomIndex or 0,
        opts.totalCleared or 0
    )
    local rng = makeRNG(seed)

    local ps = rawRoom.playerSpawn
    local door = loadedRoom.door

    local placed = {}
    local instances = {}

    for _, plat in ipairs(loadedRoom.platforms) do
        if not plat.isGapBridge and plat.w and plat.w >= marginX * 2 + 16 and plat.y then
            local innerL = plat.x + marginX
            local innerR = plat.x + plat.w - marginX
            if innerR > innerL then
                local span = innerR - innerL
                local slots = math.max(1, math.floor(span / slotW))
                for s = 1, slots do
                    if rng() < placeChance then
                        local slotL = innerL + (s - 1) * (span / slots)
                        local slotR = innerL + s * (span / slots)
                        local x = slotL + rng() * math.max(4, slotR - slotL - 8)
                        local footY = plat.y

                        local okDefs = {}
                        for _, d in ipairs(defs) do
                            local minW = d.minPlatformW or 40
                            if plat.w >= minW then
                                okDefs[#okDefs + 1] = d
                            end
                        end

                        if #okDefs > 0
                            and clearOfSpawn(x, footY, ps and ps.x, ps and ps.y, 28, 28, spawnClearR)
                            and clearOfDoor(x, footY, door, doorClearR)
                            and not tooCloseToPlaced(x, footY, placed, minSpacing)
                        then
                            local def = pickWeighted(rng, okDefs)
                            if def then
                                local sc = def.scale or 1
                                --- Sink: move draw position down so visible base meets platform (transparent rim on PNG).
                                local sink = (defaultSink + (def.sink or 0)) * sc
                                instances[#instances + 1] = {
                                    id = def.id,
                                    path = def.path,
                                    x = x,
                                    footY = footY,
                                    sink = sink,
                                    scale = sc,
                                    flip = rng() < 0.5,
                                    vegetation = def.vegetation == true,
                                }
                                placed[#placed + 1] = { x = x, footY = footY }
                            end
                        end
                    end
                end
            end
        end
    end

    return instances
end

--- World AABB for a decor instance (for melee vs vegetation). Returns left, top, width, height or nil.
function RoomProps.getDecorBounds(p)
    local img = getImage(p.path)
    if not img then return nil end
    local iw, ih = img:getDimensions()
    local sc = p.scale or 1
    local w = iw * sc
    local h = ih * sc
    local sink = p.sink or 0
    local left = p.x - w * 0.5
    local top = p.footY + sink - h
    return left, top, w, h
end

--- Draw props (world space). Call after platforms, before door if sprites should sit on geometry.
function RoomProps.drawDecor(loadedRoom)
    if not loadedRoom or not loadedRoom.decorProps then return end

    for _, p in ipairs(loadedRoom.decorProps) do
        local img = getImage(p.path)
        if img then
            local iw, ih = img:getDimensions()
            local sc = p.scale or 1
            local sx = sc * (p.flip and -1 or 1)
            love.graphics.setColor(1, 1, 1)
            local sink = p.sink or 0
            if p.cut then
                if not p._quadBot then
                    p._quadBot = love.graphics.newQuad(0, ih / 2, iw, ih / 2, iw, ih)
                    p._quadTop = love.graphics.newQuad(0, 0, iw, ih / 2, iw, ih)
                end
                love.graphics.draw(img, p._quadBot, p.x, p.footY + sink, 0, sx, sc, iw * 0.5, ih / 2)
                local dx = p.cutFallDx or 0
                local ang = p.cutFallAngle or 0.35
                love.graphics.draw(
                    img, p._quadTop,
                    p.x + dx, p.footY + sink - sc * (ih / 2), ang,
                    sx, sc, iw * 0.5, ih / 2
                )
            else
                love.graphics.draw(img, p.x, p.footY + sink, 0, sx, sc, iw * 0.5, ih)
            end
        end
    end
end

return RoomProps
