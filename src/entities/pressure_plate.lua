--- Pressure plate: triggers linked spike traps when the player steps on it.
--- Not a bump physics body — detected via AABB overlap in the game update loop.

local PressurePlate = {}
PressurePlate.__index = PressurePlate

local PLATE_W  = 28
local PLATE_H  = 5
local COOLDOWN = 5.0  -- seconds before the plate can retrigger

function PressurePlate.new(x, y, traps)
    local self  = setmetatable({}, PressurePlate)
    self.x      = x
    self.y      = y
    self.w      = PLATE_W
    self.h      = PLATE_H
    self.traps  = traps or {}
    self.pressed  = false
    self.cooldown = 0
    return self
end

function PressurePlate:update(dt, player)
    if self.cooldown > 0 then
        self.cooldown = self.cooldown - dt
        if self.cooldown <= 0 then
            self.pressed = false
        end
        return
    end

    -- AABB overlap: fire when any part of the player touches the plate
    local px, py, pw, ph = player.x, player.y, player.w, player.h
    local overlaps = px < self.x + self.w and px + pw > self.x
                 and py < self.y + self.h and py + ph > self.y
    if overlaps then
        self:trigger()
    end
end

function PressurePlate:trigger()
    if self.pressed then return end
    self.pressed  = true
    self.cooldown = COOLDOWN
    for _, trap in ipairs(self.traps) do
        trap:trigger()
    end
end

function PressurePlate:draw()
    local r, g, b = 0.65, 0.52, 0.28
    if self.pressed then r, g, b = 0.50, 0.28, 0.18 end
    -- Base plate
    love.graphics.setColor(r, g, b)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 1)
    -- Outline
    love.graphics.setColor(0.35, 0.28, 0.14)
    love.graphics.rectangle("line", self.x, self.y, self.w, self.h, 1)
    -- Rivets
    love.graphics.setColor(0.48, 0.38, 0.18)
    love.graphics.circle("fill", self.x + 5,          self.y + 2.5, 1.5)
    love.graphics.circle("fill", self.x + self.w - 5, self.y + 2.5, 1.5)
end

return PressurePlate
