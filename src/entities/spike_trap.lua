--- Spike trap: rises from the floor and damages the player while extended.
--- Triggered by a linked PressurePlate.

local DamageNumbers = require("src.ui.damage_numbers")

local SpikeTrap = {}
SpikeTrap.__index = SpikeTrap

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

    -- Base strip embedded in the floor
    love.graphics.setColor(0.28, 0.26, 0.30)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)

    if spikeH > 0.5 then
        -- Red glow when extended
        if self.state == "extended" then
            local glow = 0.14 + 0.08 * math.sin(love.timer.getTime() * 8)
            love.graphics.setColor(1, 0.15, 0.1, glow)
            love.graphics.rectangle("fill",
                self.x - 2, self.y - spikeH - 2,
                self.w + 4, spikeH + 6, 2)
        end

        -- Spike triangles
        local count   = math.max(2, math.floor(self.w / 11))
        local spacing = self.w / count
        for i = 0, count - 1 do
            local cx       = self.x + i * spacing + spacing * 0.5
            local baseHalf = spacing * 0.38
            love.graphics.setColor(0.72, 0.72, 0.80)
            love.graphics.polygon("fill",
                cx - baseHalf, self.y,
                cx + baseHalf, self.y,
                cx,            self.y - spikeH)
            -- Dark center ridge
            love.graphics.setColor(0.42, 0.42, 0.50)
            love.graphics.line(cx, self.y - spikeH * 0.2, cx, self.y - spikeH * 0.88)
        end
    end
end

return SpikeTrap
