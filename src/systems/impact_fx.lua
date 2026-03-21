-- Impact visual effects — animated sprite sheet particles that play once and die.
-- Uses "Retro Impact Effect Pack 1 A.png" (512×1536, 64×64 frames, 8 cols × 24 rows).

local Settings = require("src.systems.settings")

local ImpactFX = {}

local FRAME_SIZE = 64
local COLS       = 8       -- max frames per row in the sheet grid
local FPS        = 18
local SCALE      = 0.5     -- default for hit sparks (32×32 in world)
-- Melee: row 8 = diagonal slash streaks (reads as a swing; row 1 is a tiny hit puff on black)
local MELEE_ROW            = 8
local MELEE_SCALE          = 0.95  -- ~61px — large enough to read crisp pixels from the 64× sheet
local MELEE_ROW_FRAMES     = 8

local sheet = nil
local quads = {}   -- quads[row][col]  (1-indexed, row = animation, col = frame)

-- Row indices in the sheet (1-indexed) — chosen by visual inspection:
local ANIM = {
    hit_enemy = 1,   -- starburst (bullet-on-enemy)
    hit_wall  = 4,   -- small sparks (bullet-on-wall)
    melee     = MELEE_ROW,
}

local active = {}  -- list of playing effects

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

--- Spawn an impact effect at world position (cx, cy).
--- `kind` is one of: "hit_enemy", "hit_wall", "melee"
--- `scale` overrides the default draw scale (default = SCALE = 0.5, i.e. 32×32)
--- `angle` rotates the sprite around its center (radians, default 0)
function ImpactFX.spawn(cx, cy, kind, scale, angle)
    init()
    local row = ANIM[kind or "hit_enemy"] or 1
    local maxFrame = COLS
    local defScale = SCALE
    if kind == "melee" then
        maxFrame = MELEE_ROW_FRAMES
        defScale = MELEE_SCALE
    end
    table.insert(active, {
        x     = cx,
        y     = cy,
        row   = row,
        frame = 1,
        timer = 0,
        scale = (scale ~= nil) and scale or defScale,
        angle = angle or 0,
        maxFrame = maxFrame,
    })
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
end

function ImpactFX.draw()
    if not sheet then return end
    local a = Settings.getVfxMul()
    if a <= 0.001 then return end
    -- Pack art is on black; additive blend hides black so you see the actual painted pixels.
    local prevBlendMode, prevAlphaMode = love.graphics.getBlendMode()
    love.graphics.setBlendMode("add", "alphamultiply")
    love.graphics.setColor(1, 1, 1, a)
    for _, fx in ipairs(active) do
        local q = quads[fx.row] and quads[fx.row][fx.frame]
        if q then
            -- Draw centered with optional rotation (ox/oy = half frame size)
            love.graphics.draw(sheet, q, fx.x, fx.y, fx.angle, fx.scale, fx.scale,
                               FRAME_SIZE / 2, FRAME_SIZE / 2)
        end
    end
    love.graphics.setBlendMode(prevBlendMode, prevAlphaMode)
    love.graphics.setColor(1, 1, 1)
end

function ImpactFX.clear()
    active = {}
end

return ImpactFX
