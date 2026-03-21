-- Floating damage / heal-style popups in world space (drawn with camera attached).

local Font = require("src.ui.font")
local Settings = require("src.systems.settings")

local DamageNumbers = {}

local items = {}
local font

local function getFont()
    if not font then
        font = Font.new(15)
    end
    return font
end

function DamageNumbers.clear()
    items = {}
end

function DamageNumbers.spawn(x, y, amount, kind)
    if not amount or amount <= 0 then return end
    table.insert(items, {
        x = x + (math.random() - 0.5) * 14,
        y = y,
        text = tostring(math.floor(amount)),
        kind = kind == "in" and "in" or "out",
        t = 0,
        life = 0.9,
        vy = -38 - math.random() * 18,
        vx = (math.random() - 0.5) * 24,
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

    local f = getFont()
    local prev = love.graphics.getFont()
    love.graphics.setFont(f)

    for _, p in ipairs(items) do
        local fade = math.max(0, 1 - (p.t / p.life) ^ 1.15) * vfx
        local r, g, b = 1, 0.92, 0.38
        if p.kind == "in" then
            r, g, b = 1, 0.42, 0.38
        elseif p.kind == "xp" then
            r, g, b = 0.4, 0.82, 1.0
        elseif p.kind == "gold" then
            r, g, b = 1, 0.88, 0.28
        elseif p.kind == "health" then
            r, g, b = 0.4, 0.95, 0.45
        elseif p.kind == "weapon" then
            r, g, b = 1.0, 0.6, 0.1
        end
        local w = (p.kind == "xp" or p.kind == "gold" or p.kind == "health" or p.kind == "weapon") and 96 or 72
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
