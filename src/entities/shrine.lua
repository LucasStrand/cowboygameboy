--- Shrine entity: an interactive world prop that grants a random blessing (buff) when activated.
--- One-use per shrine. Shows buff icon above the shrine after activation.

local Buffs = require("src.systems.buffs")

local Shrine = {}
Shrine.__index = Shrine

-- Visual constants
local SHRINE_W = 32
local SHRINE_H = 48
local INTERACT_RADIUS = 56

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

    -- Base pedestal (stone slab)
    love.graphics.setColor(0.45, 0.42, 0.38)
    love.graphics.rectangle("fill", self.x - 2, self.y + self.h - 12, self.w + 4, 12, 2)
    love.graphics.setColor(0.55, 0.52, 0.46)
    love.graphics.rectangle("fill", self.x, self.y + self.h - 14, self.w, 4, 1)

    -- Pillar
    love.graphics.setColor(0.50, 0.47, 0.42)
    love.graphics.rectangle("fill", self.x + 6, self.y + 8, self.w - 12, self.h - 20, 2)
    -- Pillar highlight edge
    love.graphics.setColor(0.58, 0.55, 0.48)
    love.graphics.rectangle("fill", self.x + 6, self.y + 8, 3, self.h - 20, 1)

    -- Capstone
    love.graphics.setColor(0.48, 0.45, 0.40)
    love.graphics.rectangle("fill", self.x + 2, self.y + 4, self.w - 4, 8, 2)

    if self.state == "dormant" then
        -- Glowing rune on pillar face
        local runeAlpha = 0.5 + 0.4 * pulse
        love.graphics.setColor(bc[1], bc[2], bc[3], runeAlpha)
        -- Diamond rune shape
        local rx, ry = cx, self.y + self.h / 2 - 2
        love.graphics.polygon("fill",
            rx, ry - 8,
            rx + 5, ry,
            rx, ry + 8,
            rx - 5, ry
        )
        -- Outer glow
        love.graphics.setColor(bc[1], bc[2], bc[3], 0.15 * pulse)
        love.graphics.circle("fill", cx, self.y + self.h / 2, 18)

        -- Interaction hint
        if showHint then
            love.graphics.setColor(1, 0.92, 0.3, 0.9)
            love.graphics.printf("[E] Pray", cx - 32, self.y - 16, 64, "center")
        end
    else
        -- Activated: show blessing name briefly, then buff icon
        -- Faded rune (spent)
        love.graphics.setColor(bc[1], bc[2], bc[3], 0.15)
        local rx, ry = cx, self.y + self.h / 2 - 2
        love.graphics.polygon("fill",
            rx, ry - 8,
            rx + 5, ry,
            rx, ry + 8,
            rx - 5, ry
        )

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
