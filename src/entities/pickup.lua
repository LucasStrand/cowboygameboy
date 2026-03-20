local Pickup = {}
Pickup.__index = Pickup

function Pickup.new(x, y, pickupType, value)
    local self = setmetatable({}, Pickup)
    self.x = x
    self.y = y
    self.w = 10
    self.h = 10
    self.pickupType = pickupType
    self.value = value or 1
    self.isPickup = true
    self.alive = true
    self.lifetime = 15
    self.bobTimer = math.random() * math.pi * 2
    self.baseY = y
    return self
end

function Pickup:update(dt)
    self.lifetime = self.lifetime - dt
    if self.lifetime <= 0 then
        self.alive = false
    end
    self.bobTimer = self.bobTimer + dt * 3
    self.y = self.baseY + math.sin(self.bobTimer) * 3
end

function Pickup:draw()
    if self.pickupType == "xp" then
        love.graphics.setColor(0.3, 0.7, 1.0)
        love.graphics.circle("fill", self.x + self.w/2, self.y + self.h/2, 5)
    elseif self.pickupType == "gold" then
        love.graphics.setColor(1.0, 0.85, 0.2)
        love.graphics.circle("fill", self.x + self.w/2, self.y + self.h/2, 5)
        love.graphics.setColor(0.8, 0.65, 0.1)
        love.graphics.circle("line", self.x + self.w/2, self.y + self.h/2, 5)
    elseif self.pickupType == "health" then
        love.graphics.setColor(0.9, 0.2, 0.2)
        love.graphics.rectangle("fill", self.x + 2, self.y, 6, self.h)
        love.graphics.rectangle("fill", self.x, self.y + 2, self.w, 6)
    end

    -- Flash when about to expire
    if self.lifetime < 3 and math.floor(self.lifetime * 4) % 2 == 0 then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.circle("fill", self.x + self.w/2, self.y + self.h/2, 6)
    end

    love.graphics.setColor(1, 1, 1)
end

return Pickup
