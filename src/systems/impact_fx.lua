-- Impact visual effects: sprite-sheet hits plus procedural flashes, sparks, and rings.
-- Uses "Retro Impact Effect Pack 1 A.png" (512x1536, 64x64 frames, 8 cols x 24 rows).

local Settings = require("src.systems.settings")

local ImpactFX = {}

local FRAME_SIZE = 64
local COLS = 8
local FPS = 18
local SCALE = 0.5
local MELEE_ROW = 8
local MELEE_SCALE = 0.95
local MELEE_ROW_FRAMES = 8

local sheet = nil
local quads = {}

local ANIM = {
    hit_enemy = 1,
    explosion = 2,
    hit_wall = 4,
    melee = MELEE_ROW,
}

local active = {}
local glows = {}
local sparks = {}
local rings = {}

local function init()
    if sheet then return end
    sheet = love.graphics.newImage("assets/Retro Impact Effect Pack ALL/Retro Impact Effect Pack 1 A.png")
    sheet:setFilter("nearest", "nearest")
    local sw, sh = sheet:getDimensions()
    local rows = math.floor(sh / FRAME_SIZE)
    for r = 1, rows do
        quads[r] = {}
        for c = 1, COLS do
            quads[r][c] = love.graphics.newQuad(
                (c - 1) * FRAME_SIZE, (r - 1) * FRAME_SIZE,
                FRAME_SIZE, FRAME_SIZE, sw, sh
            )
        end
    end
end

local function spawnSprite(cx, cy, kind, scale, angle, maxFrame)
    local row = ANIM[kind or "hit_enemy"] or 1
    table.insert(active, {
        x = cx,
        y = cy,
        row = row,
        frame = 1,
        timer = 0,
        scale = scale,
        angle = angle or 0,
        maxFrame = maxFrame or COLS,
    })
end

local function addGlow(cx, cy, radius, life, rgb, alpha, grow)
    table.insert(glows, {
        x = cx,
        y = cy,
        radius = radius,
        life = life,
        age = 0,
        rgb = rgb or { 1, 0.85, 0.6 },
        alpha = alpha or 0.45,
        grow = grow or 0,
    })
end

local function addRing(cx, cy, radius, life, rgb, alpha, grow)
    table.insert(rings, {
        x = cx,
        y = cy,
        radius = radius,
        life = life,
        age = 0,
        rgb = rgb or { 1, 0.75, 0.35 },
        alpha = alpha or 0.45,
        grow = grow or 50,
    })
end

local function addSparkBurst(cx, cy, count, speed, rgb, life, spread, angleBias)
    local cone = spread or math.pi
    local baseAngle = angleBias or 0
    local minSpeed = speed * 0.45
    for _ = 1, count do
        local ang
        if angleBias then
            ang = baseAngle + (math.random() - 0.5) * cone
        else
            ang = math.random() * math.pi * 2
        end
        local vel = minSpeed + math.random() * (speed - minSpeed)
        table.insert(sparks, {
            x = cx,
            y = cy,
            vx = math.cos(ang) * vel,
            vy = math.sin(ang) * vel,
            life = life,
            age = 0,
            rgb = rgb or { 1, 0.82, 0.55 },
            alpha = 0.9,
        })
    end
end

function ImpactFX.spawn(cx, cy, kind, scale, angle)
    init()
    local finalKind = kind or "hit_enemy"
    local maxFrame = COLS
    local defScale = SCALE
    if finalKind == "melee" then
        maxFrame = MELEE_ROW_FRAMES
        defScale = MELEE_SCALE
    elseif finalKind == "explosion" then
        defScale = math.max(1.0, scale or 1.0)
    end
    local finalScale = (scale ~= nil) and scale or defScale

    spawnSprite(cx, cy, finalKind, finalScale, angle, maxFrame)

    if finalKind == "hit_enemy" then
        addGlow(cx, cy, 10 * finalScale, 0.12, { 1.0, 0.62, 0.28 }, 0.5, 14)
        addRing(cx, cy, 5 * finalScale, 0.14, { 1.0, 0.78, 0.42 }, 0.38, 38)
        addSparkBurst(cx, cy, 6, 95 * finalScale, { 1.0, 0.68, 0.35 }, 0.16, math.pi * 1.4)
    elseif finalKind == "hit_wall" then
        addGlow(cx, cy, 8 * finalScale, 0.1, { 1.0, 0.86, 0.6 }, 0.32, 10)
        addSparkBurst(cx, cy, 4, 80 * finalScale, { 1.0, 0.9, 0.72 }, 0.14, math.pi * 1.15)
    elseif finalKind == "melee" then
        addGlow(cx, cy, 14 * finalScale, 0.1, { 1.0, 0.9, 0.52 }, 0.28, 16)
        addSparkBurst(cx, cy, 5, 88 * finalScale, { 1.0, 0.82, 0.45 }, 0.12, 0.6, angle or 0)
    elseif finalKind == "explosion" then
        addGlow(cx, cy, 18 * finalScale, 0.18, { 1.0, 0.72, 0.24 }, 0.62, 52)
        addGlow(cx, cy, 10 * finalScale, 0.22, { 1.0, 0.94, 0.62 }, 0.3, 34)
        addRing(cx, cy, 9 * finalScale, 0.2, { 1.0, 0.78, 0.32 }, 0.48, 74)
        addSparkBurst(cx, cy, 14, 170 * finalScale, { 1.0, 0.72, 0.35 }, 0.24, math.pi * 2)
    end
end

function ImpactFX.spawnMuzzle(cx, cy, angle, hostile, intensity)
    init()
    local scale = intensity or 1
    local rgb = hostile and { 1.0, 0.46, 0.36 } or { 1.0, 0.88, 0.52 }
    local white = hostile and { 1.0, 0.72, 0.66 } or { 1.0, 0.96, 0.78 }
    addGlow(cx, cy, 8 * scale, 0.08, rgb, 0.42, 12)
    addGlow(cx, cy, 4 * scale, 0.06, white, 0.26, 8)
    addRing(cx, cy, 4 * scale, 0.08, rgb, 0.22, 24)
    addSparkBurst(cx, cy, hostile and 4 or 5, 120 * scale, rgb, 0.08, 0.55, angle or 0)
end

function ImpactFX.spawnExplosion(cx, cy, radius)
    local scale = math.max(1.0, (radius or 60) / 60)
    ImpactFX.spawn(cx, cy, "explosion", scale)
end

function ImpactFX.update(dt)
    local interval = 1 / FPS
    local i = 1
    while i <= #active do
        local fx = active[i]
        fx.timer = fx.timer + dt
        if fx.timer >= interval then
            fx.timer = fx.timer - interval
            fx.frame = fx.frame + 1
        end
        if fx.frame > (fx.maxFrame or COLS) then
            table.remove(active, i)
        else
            i = i + 1
        end
    end

    i = 1
    while i <= #glows do
        local glow = glows[i]
        glow.age = glow.age + dt
        if glow.age >= glow.life then
            table.remove(glows, i)
        else
            i = i + 1
        end
    end

    i = 1
    while i <= #rings do
        local ring = rings[i]
        ring.age = ring.age + dt
        if ring.age >= ring.life then
            table.remove(rings, i)
        else
            i = i + 1
        end
    end

    i = 1
    while i <= #sparks do
        local spark = sparks[i]
        spark.age = spark.age + dt
        spark.x = spark.x + spark.vx * dt
        spark.y = spark.y + spark.vy * dt
        spark.vx = spark.vx * (1 - math.min(0.8, dt * 5.5))
        spark.vy = spark.vy * (1 - math.min(0.65, dt * 4.2)) + 26 * dt
        if spark.age >= spark.life then
            table.remove(sparks, i)
        else
            i = i + 1
        end
    end
end

function ImpactFX.draw()
    local a = Settings.getVfxMul()
    if a <= 0.001 then return end

    local prevBlendMode, prevAlphaMode = love.graphics.getBlendMode()
    local prevLineWidth = love.graphics.getLineWidth()
    love.graphics.setBlendMode("add", "alphamultiply")

    for _, glow in ipairs(glows) do
        local t = glow.age / glow.life
        local life = 1 - t
        local radius = glow.radius + glow.grow * glow.age
        love.graphics.setColor(glow.rgb[1], glow.rgb[2], glow.rgb[3], glow.alpha * life * life * a)
        love.graphics.circle("fill", glow.x, glow.y, radius)
    end

    for _, ring in ipairs(rings) do
        local t = ring.age / ring.life
        local life = 1 - t
        local radius = ring.radius + ring.grow * ring.age
        love.graphics.setLineWidth(math.max(1, 3 * life))
        love.graphics.setColor(ring.rgb[1], ring.rgb[2], ring.rgb[3], ring.alpha * life * a)
        love.graphics.circle("line", ring.x, ring.y, radius)
    end

    for _, spark in ipairs(sparks) do
        local t = spark.age / spark.life
        local life = 1 - t
        local tailMul = 0.018 + life * 0.028
        local tx = spark.x - spark.vx * tailMul
        local ty = spark.y - spark.vy * tailMul
        love.graphics.setLineWidth(1 + life)
        love.graphics.setColor(spark.rgb[1], spark.rgb[2], spark.rgb[3], spark.alpha * life * a)
        love.graphics.line(tx, ty, spark.x, spark.y)
        love.graphics.setColor(1, 1, 1, 0.5 * life * a)
        love.graphics.points(spark.x, spark.y)
    end

    if sheet then
        love.graphics.setColor(1, 1, 1, a)
        for _, fx in ipairs(active) do
            local q = quads[fx.row] and quads[fx.row][fx.frame]
            if q then
                love.graphics.draw(sheet, q, fx.x, fx.y, fx.angle, fx.scale, fx.scale,
                    FRAME_SIZE / 2, FRAME_SIZE / 2)
            end
        end
    end

    love.graphics.setLineWidth(prevLineWidth)
    love.graphics.setBlendMode(prevBlendMode, prevAlphaMode)
    love.graphics.setColor(1, 1, 1)
end

function ImpactFX.clear()
    active = {}
    glows = {}
    sparks = {}
    rings = {}
end

return ImpactFX
