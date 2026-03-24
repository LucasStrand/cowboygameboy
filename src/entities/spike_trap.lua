--- Spike trap: rises from the floor and damages the player while extended.
--- Triggered by a linked PressurePlate.

local DamageNumbers = require("src.ui.damage_numbers")

local SpikeTrap = {}
SpikeTrap.__index = SpikeTrap

-- Sprite (lazy-loaded)
local _sprite
local function getSprite()
    if not _sprite then
        _sprite = love.graphics.newImage("assets/sprites/props/spike_trap.png")
        _sprite:setFilter("nearest", "nearest")
    end
    return _sprite
end

local RISE_TIME       = 0.12   -- seconds to fully extend
local EXTENDED_TIME   = 2.2    -- seconds spikes stay up
local RETRACT_TIME    = 0.35   -- seconds to fully retract
local SPIKE_HEIGHT    = 22     -- max spike height in pixels
local DAMAGE          = 20
local DAMAGE_INTERVAL = 0.6    -- min seconds between damage ticks

function SpikeTrap.new(x, y, w)
    local self      = setmetatable({}, SpikeTrap)
    self.x          = x
    self.y          = y    -- top of the base strip, flush with platform surface
    self.w          = w or 32
    self.h          = 4    -- thin base strip height
    self.state      = "idle"
    self.timer      = 0
    self.extension  = 0    -- 0 = flush with floor, 1 = fully extended
    self.damageCooldown = 0
    return self
end

function SpikeTrap:trigger()
    if self.state == "idle" then
        self.state = "rising"
        self.timer = 0
    end
end

function SpikeTrap:update(dt, player)
    self.damageCooldown = math.max(0, self.damageCooldown - dt)

    if self.state == "rising" then
        self.timer     = self.timer + dt
        self.extension = math.min(1, self.timer / RISE_TIME)
        if self.timer >= RISE_TIME then
            self.state     = "extended"
            self.timer     = 0
            self.extension = 1
        end

    elseif self.state == "extended" then
        self.timer = self.timer + dt

        if self.damageCooldown <= 0 then
            local spikeTop = self.y - SPIKE_HEIGHT * self.extension
            local px, py, pw, ph = player.x, player.y, player.w, player.h
            if px < self.x + self.w and px + pw > self.x
               and py < self.y + self.h and py + ph > spikeTop then
                local ok, dmg = player:takeDamage(DAMAGE)
                if ok then
                    DamageNumbers.spawn(player.x + player.w / 2, player.y, dmg, "in")
                    self.damageCooldown = DAMAGE_INTERVAL
                end
            end
        end

        if self.timer >= EXTENDED_TIME then
            self.state = "retracting"
            self.timer = 0
        end

    elseif self.state == "retracting" then
        self.timer     = self.timer + dt
        self.extension = math.max(0, 1 - self.timer / RETRACT_TIME)
        if self.timer >= RETRACT_TIME then
            self.state     = "idle"
            self.extension = 0
        end
    end
end

function SpikeTrap:draw()
    local spikeH = SPIKE_HEIGHT * self.extension
    local spr = getSprite()
    local sw, sh = spr:getDimensions()

    -- Base strip embedded in the floor
    love.graphics.setColor(0.35, 0.32, 0.30)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)

    if spikeH > 0.5 then
        -- Draw spike sprite scaled to match extension
        local scaleX = self.w / sw
        local scaleY = (spikeH / sh)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(spr, self.x, self.y - spikeH, 0, scaleX, scaleY)

        -- Subtle red tint when fully extended (on top of sprite, not a big rectangle)
        if self.state == "extended" then
            local glow = 0.06 + 0.04 * math.sin(love.timer.getTime() * 8)
            love.graphics.setColor(1, 0.15, 0.1, glow)
            love.graphics.draw(spr, self.x, self.y - spikeH, 0, scaleX, scaleY)
        end
    end
end

return SpikeTrap
