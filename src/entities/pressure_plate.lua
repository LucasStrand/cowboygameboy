--- Pressure plate: triggers linked spike traps when the player steps on it.
--- Not a bump physics body — detected via AABB overlap in the game update loop.

local PressurePlate = {}
PressurePlate.__index = PressurePlate

local PLATE_W  = 28
local PLATE_H  = 5

-- Sprite (lazy-loaded)
local _sprite
local function getSprite()
    if not _sprite then
        _sprite = love.graphics.newImage("assets/sprites/props/pressure_plate.png")
        _sprite:setFilter("nearest", "nearest")
    end
    return _sprite
end
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
    local spr = getSprite()
    local sw, sh = spr:getDimensions()
    -- Draw sprite centered on the plate, scaled to match plate width.
    -- The sprite is taller than the hitbox (transparent padding) so anchor at bottom.
    local scale = self.w / sw
    local drawX = self.x
    local drawY = self.y + self.h - sh * scale  -- align sprite bottom to plate bottom
    if self.pressed then
        love.graphics.setColor(0.7, 0.5, 0.4)
    else
        love.graphics.setColor(1, 1, 1)
    end
    love.graphics.draw(spr, drawX, drawY, 0, scale, scale)
    love.graphics.setColor(1, 1, 1)
end

return PressurePlate
