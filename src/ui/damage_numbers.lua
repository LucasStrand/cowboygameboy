-- Floating damage / heal-style popups in world space (drawn with camera attached).

local Font = require("src.ui.font")
local Settings = require("src.systems.settings")
local HUD = require("src.ui.hud")
local GoldCoin = require("src.ui.gold_coin")

local DamageNumbers = {}

local items = {}
local hudXpItems = {}
local hudGoldItems = {}
--- Single world-space "+N" for wallet; merges rapid gold/silver pickups into one total.
local walletWorld = nil
local WALLET_MERGE_SEC = 0.45
local font

local function getFont()
    if not font then
        font = Font.new(15)
    end
    return font
end

function DamageNumbers.clear()
    items = {}
    hudXpItems = {}
    hudGoldItems = {}
    walletWorld = nil
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

-- typ: "xp" | "gold" | "silver" | "health"
function DamageNumbers.spawnPickup(x, y, amount, typ)
    if not amount then return end
    if typ == "xp" then
        if amount <= 0 then return end
        local n = #hudXpItems
        table.insert(hudXpItems, {
            text = "+" .. tostring(math.floor(amount)),
            t = 0,
            life = 0.85,
            vy = -26 - math.random() * 12,
            vx = (math.random() - 0.5) * 16,
            x = 0,
            y = 0,
            ix = (n % 5) * 16 - 32,
        })
        return
    end
    if typ == "gold" or typ == "silver" then
        if amount <= 0 then return end
        local n = #hudGoldItems
        table.insert(hudGoldItems, {
            amount = math.floor(amount),
            kind = typ,
            wx = x,
            wy = y,
            t = 0,
            life = 0.62,
            ix = (n % 5) * 14 - 28,
        })
        -- One merged +N in world space (rapid pickups stack into a single number).
        local amt = math.floor(amount)
        local now = love.timer.getTime()
        if walletWorld and (now - walletWorld.lastAddTime) <= WALLET_MERGE_SEC then
            walletWorld.total = walletWorld.total + amt
            walletWorld.text = "+" .. tostring(walletWorld.total)
            walletWorld.x = x + (math.random() - 0.5) * 8
            walletWorld.y = y
            walletWorld.kind = (typ == "gold" or walletWorld.kind == "gold") and "gold" or "silver"
            walletWorld.lastAddTime = now
            walletWorld.t = 0
            walletWorld.life = 0.85
            walletWorld.vy = -32 - math.random() * 14
            walletWorld.vx = (math.random() - 0.5) * 18
        else
            walletWorld = {
                total = amt,
                text = "+" .. tostring(amt),
                x = x + (math.random() - 0.5) * 10,
                y = y,
                kind = typ,
                t = 0,
                life = 0.85,
                vy = -32 - math.random() * 14,
                vx = (math.random() - 0.5) * 18,
                lastAddTime = now,
            }
        end
        return
    end
    local text
    local kind
    if typ == "weapon" then
        text = tostring(amount)  -- amount is the weapon name string
        kind = "weapon"
    else
        if amount <= 0 then return end
        text = "+" .. tostring(math.floor(amount))
        if typ == "health" then
            text = text .. " HP"
        end
        kind = (typ == "health" and "health" or "xp")
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
    for i = #hudXpItems, 1, -1 do
        local p = hudXpItems[i]
        p.t = p.t + dt
        p.y = p.y + p.vy * dt
        p.x = p.x + p.vx * dt
        p.vy = p.vy + 40 * dt
        if p.t >= p.life then
            table.remove(hudXpItems, i)
        end
    end
    for i = #hudGoldItems, 1, -1 do
        local p = hudGoldItems[i]
        p.t = p.t + dt
        if p.t >= p.life then
            table.remove(hudGoldItems, i)
        end
    end
    if walletWorld then
        local p = walletWorld
        p.t = p.t + dt
        p.y = p.y + p.vy * dt
        p.x = p.x + p.vx * dt
        p.vy = p.vy + 40 * dt
        if p.t >= p.life then
            walletWorld = nil
        end
    end
end

local function drawWorldFloater(p, vfx)
    local fade = math.max(0, 1 - (p.t / p.life) ^ 1.15) * vfx
    local r, g, b = 1, 0.92, 0.38
    if p.kind == "in" then
        r, g, b = 1, 0.42, 0.38
    elseif p.kind == "xp" then
        r, g, b = 0.4, 0.82, 1.0
    elseif p.kind == "gold" then
        r, g, b = 1, 0.88, 0.28
    elseif p.kind == "silver" then
        r, g, b = 0.82, 0.88, 0.95
    elseif p.kind == "health" then
        r, g, b = 0.4, 0.95, 0.45
    elseif p.kind == "weapon" then
        r, g, b = 1.0, 0.6, 0.1
    end
    local w = (p.kind == "xp" or p.kind == "gold" or p.kind == "silver" or p.kind == "health" or p.kind == "weapon") and 96 or 72
    local tx = p.x - w * 0.5
    love.graphics.setColor(r * 0.15, g * 0.15, b * 0.15, fade * 0.95)
    love.graphics.printf(p.text, tx, p.y + 1, w, "center")
    love.graphics.setColor(r, g, b, fade)
    love.graphics.printf(p.text, tx, p.y, w, "center")
end

function DamageNumbers.draw()
    if #items == 0 and not walletWorld then return end
    local vfx = Settings.getVfxMul()
    if vfx <= 0.001 then return end

    local f = getFont()
    local prev = love.graphics.getFont()
    love.graphics.setFont(f)

    for _, p in ipairs(items) do
        drawWorldFloater(p, vfx)
    end
    if walletWorld then
        drawWorldFloater(walletWorld, vfx)
    end

    love.graphics.setFont(prev)
    love.graphics.setColor(1, 1, 1)
end

--- Screen-space; call after HUD.draw while origin is screen space.
function DamageNumbers.drawHudXp()
    if #hudXpItems == 0 then return end
    local vfx = Settings.getVfxMul()
    if vfx <= 0.001 then return end

    local cx, baseY, w = HUD.getXpBarPopupAnchor()
    local f = getFont()
    local prev = love.graphics.getFont()
    love.graphics.setFont(f)

    local r, g, b = 0.4, 0.82, 1.0
    for _, p in ipairs(hudXpItems) do
        local fade = math.max(0, 1 - (p.t / p.life) ^ 1.15) * vfx
        local tx = cx + (p.x or 0) + (p.ix or 0)
        local ty = baseY + (p.y or 0)
        local tw = 96
        local left = tx - tw * 0.5
        love.graphics.setColor(r * 0.15, g * 0.15, b * 0.15, fade * 0.95)
        love.graphics.printf(p.text, left, ty + 1, tw, "center")
        love.graphics.setColor(r, g, b, fade)
        love.graphics.printf(p.text, left, ty, tw, "center")
    end

    love.graphics.setFont(prev)
    love.graphics.setColor(1, 1, 1)
end

--- Screen-space; call after HUD.draw while origin is screen space.
--- `camera` converts world pickup origin into screen space; coin sprites fly to the wallet (not text).
function DamageNumbers.drawHudGold(player, camera)
    if #hudGoldItems == 0 then return end
    local vfx = Settings.getVfxMul()
    if vfx <= 0.001 then return end

    local cx, baseY = HUD.getGoldCounterPopupAnchor(player)
    local sw = GAME_WIDTH
    local sh = GAME_HEIGHT
    local coinH = 30

    for _, p in ipairs(hudGoldItems) do
        local u = math.min(1, (p.t or 0) / (p.life or 0.62))
        local e = 1 - (1 - u) * (1 - u) * (1 - u)
        local sx0, sy0
        if camera and p.wx and p.wy then
            sx0, sy0 = camera:cameraCoords(p.wx, p.wy, 0, 0, sw, sh)
            sx0 = sx0 + (p.ix or 0) * (1 - e)
        else
            sx0, sy0 = cx, baseY + 80
        end
        local tx = sx0 + (cx - sx0) * e
        local ty = sy0 + (baseY - sy0) * e - 38 * math.sin(math.pi * u)
        local fade = vfx
        if u < 0.05 then
            fade = fade * (u / 0.05)
        elseif u > 0.82 then
            fade = fade * math.max(0, 1 - (u - 0.82) / 0.18)
        end

        local variant = p.kind == "silver" and "silver" or "gold"
        local animT = (p.t or 0) * 1.35
        if not GoldCoin.drawAnimatedCentered(tx, ty, coinH, animT, {
            variant = variant,
            alpha = fade,
            fps = 14,
        }) then
            GoldCoin.drawIdleFaceCentered(tx, ty, coinH, { variant = variant, alpha = fade })
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return DamageNumbers
