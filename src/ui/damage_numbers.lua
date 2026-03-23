-- Floating damage / heal-style popups in world space (drawn with camera attached).

local Font = require("src.ui.font")
local Settings = require("src.systems.settings")

local DamageNumbers = {}

local items = {}
local font
local fontCrit

local function getFont()
    if not font then
        font = Font.new(15)
    end
    return font
end

local function getFontCrit()
    if not fontCrit then
        fontCrit = Font.new(20)
    end
    return fontCrit
end

function DamageNumbers.clear()
    items = {}
end

--- opts.was_crit: larger, warmer popup for critical hits (outgoing damage only).
function DamageNumbers.spawn(x, y, amount, kind, opts)
    opts = opts or {}
    if not amount or amount <= 0 then return end
    local isIn = kind == "in"
    local wasCrit = not isIn and opts.was_crit == true
    table.insert(items, {
        x = x + (math.random() - 0.5) * (wasCrit and 18 or 14),
        y = y,
        text = tostring(math.floor(amount)),
        kind = isIn and "in" or "out",
        crit = wasCrit,
        t = 0,
        life = wasCrit and 1.05 or 0.9,
        vy = wasCrit and (-50 - math.random() * 24) or (-38 - math.random() * 18),
        vx = (math.random() - 0.5) * (wasCrit and 30 or 24),
    })
end

-- typ: "xp" | "gold" | "health"
function DamageNumbers.spawnPickup(x, y, amount, typ)
    if not amount then return end
    local text
    local kind
    if typ == "weapon" then
        text = tostring(amount)  -- amount is the weapon name string
        kind = "weapon"
    else
        if amount <= 0 then return end
        text = "+" .. tostring(math.floor(amount))
        if typ == "xp" then
            text = text .. " XP"
        elseif typ == "gold" then
            text = text .. " $"
        elseif typ == "health" then
            text = text .. " HP"
        end
        kind = typ == "gold" and "gold" or (typ == "health" and "health" or "xp")
    end
    table.insert(items, {
        x = x + (math.random() - 0.5) * 10,
        y = y,
        text = text,
        kind = kind,
        t = 0,
        life = 0.85,
        vy = -32 - math.random() * 14,
        vx = (math.random() - 0.5) * 18,
    })
end

function DamageNumbers.update(dt)
    for i = #items, 1, -1 do
        local p = items[i]
        p.t = p.t + dt
        p.y = p.y + p.vy * dt
        p.x = p.x + p.vx * dt
        p.vy = p.vy + 40 * dt
        if p.t >= p.life then
            table.remove(items, i)
        end
    end
end

function DamageNumbers.draw()
    if #items == 0 then return end
    local vfx = Settings.getVfxMul()
    if vfx <= 0.001 then return end

    local prev = love.graphics.getFont()

    for _, p in ipairs(items) do
        local f = p.crit and getFontCrit() or getFont()
        love.graphics.setFont(f)

        local fade = math.max(0, 1 - (p.t / p.life) ^ 1.15) * vfx
        local r, g, b = 1, 0.92, 0.38
        if p.kind == "in" then
            r, g, b = 1, 0.42, 0.38
        elseif p.crit then
            r, g, b = 1, 0.52, 0.16
        elseif p.kind == "xp" then
            r, g, b = 0.4, 0.82, 1.0
        elseif p.kind == "gold" then
            r, g, b = 1, 0.88, 0.28
        elseif p.kind == "health" then
            r, g, b = 0.4, 0.95, 0.45
        elseif p.kind == "weapon" then
            r, g, b = 1.0, 0.6, 0.1
        end
        local w = (p.kind == "xp" or p.kind == "gold" or p.kind == "health" or p.kind == "weapon") and 96
            or (p.crit and 88 or 72)
        local tx = p.x - w * 0.5
        love.graphics.setColor(r * 0.15, g * 0.15, b * 0.15, fade * 0.95)
        love.graphics.printf(p.text, tx, p.y + 1, w, "center")
        love.graphics.setColor(r, g, b, fade)
        love.graphics.printf(p.text, tx, p.y, w, "center")
    end

    love.graphics.setFont(prev)
    love.graphics.setColor(1, 1, 1)
end

return DamageNumbers
