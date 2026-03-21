-- Shared visual effects for casino mini-games (blackjack, roulette).

local Font = require("src.ui.font")
local Settings = require("src.systems.settings")
local GoldCoin = require("src.ui.gold_coin")

local CasinoFx = {}

---------------------------------------------------------------------------
-- Gold rain — falling coin celebration (blackjack / roulette wins)
---------------------------------------------------------------------------
local goldParticles = {}

--- Dense “raining gold” — coins spawn above / across the table and fall with gravity (win celebration).
--- opts: count, spreadX, spawnYMin, spawnYMax (screen coords; cy = visual center of effect)
function CasinoFx.spawnGoldRain(cx, cy, opts)
    opts = opts or {}
    local count = opts.count or 72
    local spreadX = opts.spreadX or 440
    local spawnYMin = opts.spawnYMin or -100
    local spawnYMax = opts.spawnYMax or math.max(cy - 80, spawnYMin + 40)
    for _ = 1, count do
        goldParticles[#goldParticles + 1] = {
            x = cx + (math.random() - 0.5) * spreadX,
            y = spawnYMin + math.random() * (spawnYMax - spawnYMin),
            vx = (math.random() - 0.5) * 200,
            vy = 70 + math.random() * 160,
            t = 0,
            life = 1.85 + math.random() * 0.55,
            r = 3.5 + math.random() * 4,
            rot = math.random() * math.pi * 2,
            rotV = (math.random() - 0.5) * 10,
            animPhase = math.random() * 6.28,
            spinFps = 9 + math.random() * 8,
        }
    end
end

function CasinoFx.updateGold(dt)
    for i = #goldParticles, 1, -1 do
        local p = goldParticles[i]
        p.t = p.t + dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vy = p.vy + 320 * dt -- gravity
        p.rot = p.rot + p.rotV * dt
        if p.t >= p.life then
            table.remove(goldParticles, i)
        end
    end
end

function CasinoFx.drawGold()
    if #goldParticles == 0 then return end
    local vfx = Settings.getVfxMul()
    if vfx <= 0.001 then return end
    for _, p in ipairs(goldParticles) do
        local fade = math.max(0, 1 - (p.t / p.life) ^ 1.3) * vfx
        local targetH = math.max(5, p.r * 2.1)
        local animT = p.t + (p.animPhase or 0)
        if not GoldCoin.drawAnimatedCentered(p.x, p.y, targetH, animT, {
            fps = p.spinFps or 11,
            alpha = fade,
            rotation = (p.rot or 0) * 0.15,
        }) then
            love.graphics.setColor(1, 0.85, 0.2, fade)
            love.graphics.circle("fill", p.x, p.y, p.r)
            love.graphics.setColor(0.85, 0.65, 0.1, fade * 0.7)
            love.graphics.circle("line", p.x, p.y, p.r)
        end
    end
end

function CasinoFx.clearGold()
    goldParticles = {}
end

---------------------------------------------------------------------------
-- ScreenShake
---------------------------------------------------------------------------
local shake = { dx = 0, dy = 0, t = 0, duration = 0, amplitude = 0 }

function CasinoFx.startShake(amplitude, duration)
    shake.amplitude = amplitude or 4
    shake.duration = duration or 0.2
    shake.t = 0
end

function CasinoFx.updateShake(dt)
    if shake.duration <= 0 then return end
    shake.t = shake.t + dt
    if shake.t >= shake.duration then
        shake.dx = 0
        shake.dy = 0
        shake.duration = 0
        return
    end
    local decay = 1 - (shake.t / shake.duration)
    shake.dx = (math.random() - 0.5) * 2 * shake.amplitude * decay
    shake.dy = (math.random() - 0.5) * 2 * shake.amplitude * decay
end

function CasinoFx.getShakeOffset()
    return shake.dx, shake.dy
end

---------------------------------------------------------------------------
-- FloatingText — text that scales in and fades up
---------------------------------------------------------------------------
local floats = {}
local floatFont

local function getFloatFont()
    if not floatFont then floatFont = Font.new(28) end
    return floatFont
end

function CasinoFx.spawnFloat(cx, cy, text, color, opts)
    opts = opts or {}
    floats[#floats + 1] = {
        x = cx,
        y = cy,
        text = text,
        color = color or {1, 1, 1},
        t = 0,
        life = opts.life or 1.2,
        vy = opts.vy or -30,
        scale = 0,
        targetScale = opts.scale or 1,
        font = opts.font or nil,
    }
end

function CasinoFx.updateFloats(dt)
    for i = #floats, 1, -1 do
        local f = floats[i]
        f.t = f.t + dt
        f.y = f.y + f.vy * dt
        -- elastic scale-in over first 0.4s
        local scaleT = math.min(1, f.t / 0.4)
        local elastic = 1 - math.sin(scaleT * math.pi * 1.5) * (1 - scaleT) ^ 2 * 0.3
        f.scale = f.targetScale * math.min(1, scaleT * (1 + (1 - scaleT) * 0.5)) * elastic
        if f.t >= f.life then
            table.remove(floats, i)
        end
    end
end

function CasinoFx.drawFloats()
    if #floats == 0 then return end
    local vfx = Settings.getVfxMul()
    if vfx <= 0.001 then return end
    local defaultF = getFloatFont()
    for _, f in ipairs(floats) do
        local fade = math.max(0, 1 - (f.t / f.life) ^ 1.5) * vfx
        local font = f.font or defaultF
        love.graphics.setFont(font)
        local tw = font:getWidth(f.text) * f.scale
        local th = font:getHeight() * f.scale
        -- shadow
        love.graphics.setColor(0, 0, 0, fade * 0.6)
        love.graphics.print(f.text, f.x - tw * 0.5 + 2, f.y - th * 0.5 + 2, 0, f.scale, f.scale)
        -- main
        love.graphics.setColor(f.color[1], f.color[2], f.color[3], fade)
        love.graphics.print(f.text, f.x - tw * 0.5, f.y - th * 0.5, 0, f.scale, f.scale)
    end
end

function CasinoFx.clearFloats()
    floats = {}
end

---------------------------------------------------------------------------
-- ChipStack — draw a stack of chips at a position
---------------------------------------------------------------------------
local CHIP_COLORS = {
    {0.9, 0.9, 0.9},   -- $5 white
    {0.85, 0.15, 0.15}, -- $10 red
    {0.15, 0.7, 0.2},   -- $25 green
    {0.2, 0.35, 0.85},  -- $50 blue
    {0.12, 0.12, 0.12}, -- $100 black
}

local CHIP_DENOMS = {100, 50, 25, 10, 5}

function CasinoFx.chipBreakdown(amount)
    local chips = {}
    local rem = amount
    for i, d in ipairs(CHIP_DENOMS) do
        local n = math.floor(rem / d)
        if n > 0 then
            for _ = 1, n do
                chips[#chips + 1] = { denom = d, colorIdx = i }
            end
            rem = rem - n * d
        end
    end
    return chips
end

function CasinoFx.drawChipStack(cx, cy, amount, maxChips)
    maxChips = maxChips or 10
    local chips = CasinoFx.chipBreakdown(amount)
    local count = math.min(#chips, maxChips)
    if count == 0 then return end
    local chipR = 10
    local stackOffset = 2
    for i = 1, count do
        local c = chips[i]
        local color = CHIP_COLORS[c.colorIdx] or CHIP_COLORS[1]
        local y = cy - (i - 1) * stackOffset
        -- chip body
        love.graphics.setColor(color[1], color[2], color[3], 0.95)
        love.graphics.circle("fill", cx, y, chipR)
        -- rim
        love.graphics.setColor(color[1] * 0.6, color[2] * 0.6, color[3] * 0.6, 0.8)
        love.graphics.circle("line", cx, y, chipR)
        -- inner ring
        love.graphics.setColor(1, 1, 1, 0.2)
        love.graphics.circle("line", cx, y, chipR * 0.6)
    end
end

---------------------------------------------------------------------------
-- Combined update / draw / clear
---------------------------------------------------------------------------
function CasinoFx.update(dt)
    CasinoFx.updateGold(dt)
    CasinoFx.updateShake(dt)
    CasinoFx.updateFloats(dt)
end

function CasinoFx.draw()
    CasinoFx.drawGold()
    CasinoFx.drawFloats()
end

function CasinoFx.clear()
    CasinoFx.clearGold()
    CasinoFx.clearFloats()
    shake.dx = 0
    shake.dy = 0
    shake.duration = 0
end

return CasinoFx
