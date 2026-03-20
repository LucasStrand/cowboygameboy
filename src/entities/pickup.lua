local Pickup = {}
Pickup.__index = Pickup

local GRAVITY = 600

function Pickup.new(x, y, pickupType, value)
    local self = setmetatable({}, Pickup)
    self.x = x
    self.y = y
    self.w = 10
    self.h = 10
    self.vy = 0
    self.pickupType = pickupType
    self.value = value or 1
    self.isPickup = true
    self.alive = true
    self.lifetime = 15
    self.grounded = false
    self.bobTimer = math.random() * math.pi * 2
    self.bobOffset = 0
    return self
end

function Pickup.filter(item, other)
    if other.isPlatform or other.isWall then
        return "slide"
    end
    return nil
end

function Pickup:update(dt, world)
    self.lifetime = self.lifetime - dt
    if self.lifetime <= 0 then
        self.alive = false
        return
    end

    if not self.grounded then
        self.vy = self.vy + GRAVITY * dt
        if self.vy > 400 then self.vy = 400 end

        local goalY = self.y + self.vy * dt
        local actualX, actualY, cols, len = world:move(self, self.x, goalY, self.filter)
        self.x = actualX
        self.y = actualY

        for i = 1, len do
            if cols[i].normal.y == -1 then
                self.grounded = true
                self.vy = 0
            end
        end
    else
        self.bobTimer = self.bobTimer + dt * 3
        self.bobOffset = math.sin(self.bobTimer) * 2
    end
end

function Pickup:draw()
    local dy = self.bobOffset or 0
    if self.pickupType == "xp" then
        love.graphics.setColor(0.3, 0.7, 1.0)
        love.graphics.circle("fill", self.x + self.w/2, self.y + self.h/2 + dy, 5)
    elseif self.pickupType == "gold" then
        love.graphics.setColor(1.0, 0.85, 0.2)
        love.graphics.circle("fill", self.x + self.w/2, self.y + self.h/2 + dy, 5)
        love.graphics.setColor(0.8, 0.65, 0.1)
        love.graphics.circle("line", self.x + self.w/2, self.y + self.h/2 + dy, 5)
    elseif self.pickupType == "health" then
        love.graphics.setColor(0.9, 0.2, 0.2)
        love.graphics.rectangle("fill", self.x + 2, self.y + dy, 6, self.h)
        love.graphics.rectangle("fill", self.x, self.y + 2 + dy, self.w, 6)
    end

    -- Flash when about to expire
    if self.lifetime < 3 and math.floor(self.lifetime * 4) % 2 == 0 then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.circle("fill", self.x + self.w/2, self.y + self.h/2 + dy, 6)
    end

    love.graphics.setColor(1, 1, 1)
end

return Pickup
