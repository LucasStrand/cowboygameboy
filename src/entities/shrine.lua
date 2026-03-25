--- Shrine entity: an interactive world prop that grants a random blessing (buff) when activated.
--- One-use per shrine. Shows buff icon above the shrine after activation.

local Buffs = require("src.systems.buffs")
local WorldInteractLabel = require("src.ui.world_interact_label")

local Shrine = {}
Shrine.__index = Shrine

-- Visual constants
local SHRINE_W = 32
local SHRINE_H = 48
local INTERACT_RADIUS = 56

-- Sprite (lazy-loaded)
local _sprite
local function getSprite()
    if not _sprite then
        _sprite = love.graphics.newImage("assets/sprites/props/shrine.png")
        _sprite:setFilter("nearest", "nearest")
    end
    return _sprite
end

-- Blessings the shrine can bestow (maps to buff ids)
local BLESSINGS = {
    { buffId = "regen",         name = "Regeneration",  color = {0.3, 0.9, 0.3} },
    { buffId = "attack_boost",  name = "Sharpshooter",  color = {0.9, 0.3, 0.2} },
    { buffId = "defense_boost", name = "Ironhide",      color = {0.4, 0.5, 0.9} },
    { buffId = "speed_boost",   name = "Swiftness",     color = {0.2, 0.8, 0.9} },
    { buffId = "lucky",         name = "Fortune",       color = {0.9, 0.8, 0.2} },
    { buffId = "exp_boost",     name = "Wisdom",        color = {0.6, 0.3, 0.9} },
}

--- Number of distinct blessing types (for dev / map placement)
Shrine.BLESSING_COUNT = #BLESSINGS

--- opts:
---   blessing   index into BLESSINGS (random if nil)
function Shrine.new(x, y, opts)
    opts = opts or {}
    local self = setmetatable({}, Shrine)
    self.x = x
    self.y = y
    self.w = SHRINE_W
    self.h = SHRINE_H
    -- Pick a random blessing
    local idx = opts.blessing or math.random(#BLESSINGS)
    self.blessing = BLESSINGS[idx]
    -- State: "dormant" | "activated"
    self.state = "dormant"
    -- Glow animation timer
    self.glowTimer = math.random() * 6.28
    -- Particles after activation
    self.particles = {}
    self.particleTimer = 0
    -- Callback set by game.lua: called with (buffId) when activated
    self.onActivate = nil
    -- Icon reference for drawing after activation
    self.buffIcon = nil
    self.iconShowTimer = 0
    return self
end

function Shrine:update(dt)
    self.glowTimer = self.glowTimer + dt

    if self.state == "activated" then
        self.iconShowTimer = self.iconShowTimer + dt
        -- Update shrine particles
        self.particleTimer = self.particleTimer + dt
        if self.particleTimer > 0.15 and #self.particles < 8 then
            self.particleTimer = 0
            table.insert(self.particles, {
                x = self.x + self.w / 2 + (math.random() - 0.5) * 20,
                y = self.y + self.h * 0.3,
                vy = -20 - math.random() * 30,
                life = 1.0,
            })
        end
        local i = 1
        while i <= #self.particles do
            local p = self.particles[i]
            p.y = p.y + p.vy * dt
            p.life = p.life - dt * 0.8
            if p.life <= 0 then
                table.remove(self.particles, i)
            else
                i = i + 1
            end
        end
    end
end

--- Called by game.lua when the player presses E near this shrine.
function Shrine:tryActivate(player)
    if self.state ~= "dormant" then return false end
    self.state = "activated"
    if self.onActivate then
        self.onActivate(self.blessing.buffId)
    end
    return true
end

--- Returns true when the player is close enough to interact.
function Shrine:isNearPlayer(px, py)
    local cx = self.x + self.w / 2
    local cy = self.y + self.h / 2
    local dx = px - cx
    local dy = py - cy
    return dx * dx + dy * dy < INTERACT_RADIUS * INTERACT_RADIUS
end

function Shrine:draw(showHint)
    local cx = self.x + self.w / 2
    local bc = self.blessing.color
    local pulse = 0.5 + 0.5 * math.sin(self.glowTimer * 2.5)

    -- Draw sprite (uniform scale, anchored at bottom-center)
    local spr = getSprite()
    local sw, sh = spr:getDimensions()
    local scale = math.min(self.w / sw, self.h / sh)
    local drawX = self.x + (self.w - sw * scale) / 2
    local drawY = self.y + self.h - sh * scale
    if self.state == "dormant" then
        love.graphics.setColor(1, 1, 1)
    else
        love.graphics.setColor(0.55, 0.55, 0.55)
    end
    love.graphics.draw(spr, drawX, drawY, 0, scale, scale)

    if self.state == "dormant" then
        -- Soft blessing-colored glow underneath (not on the sprite itself)
        love.graphics.setColor(bc[1], bc[2], bc[3], 0.18 * pulse)
        love.graphics.circle("fill", cx, self.y + self.h * 0.65, 16)

        -- Interaction hint
        if showHint then
            WorldInteractLabel.drawAboveAnchor(cx, self.y + 4, "[E] Pray", {
                bobAmp = 1,
                bobTime = love.timer.getTime(),
            })
        end
    else
        -- Blessing name float-up
        if self.iconShowTimer < 2.5 then
            local fadeIn = math.min(1, self.iconShowTimer * 3)
            local rise = self.iconShowTimer * 12
            love.graphics.setColor(bc[1], bc[2], bc[3], fadeIn * (1 - self.iconShowTimer / 2.5))
            love.graphics.printf(self.blessing.name, cx - 48, self.y - 20 - rise, 96, "center")
        end

        -- Rising particles
        for _, p in ipairs(self.particles) do
            love.graphics.setColor(bc[1], bc[2], bc[3], p.life * 0.6)
            love.graphics.circle("fill", p.x, p.y, 2 * p.life)
        end
    end

    love.graphics.setColor(1, 1, 1)
end

return Shrine
