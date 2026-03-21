local ImpactFX = require("src.systems.impact_fx")

local Bullet = {}
Bullet.__index = Bullet

function Bullet.new(data)
    local self = setmetatable({}, Bullet)
    self.x = data.x
    self.y = data.y
    self.w = 6
    self.h = 4
    self.angle = data.angle
    self.speed = data.speed or 500
    self.damage = data.damage or 10
    self.ricochet = data.ricochet or 0
    self.explosive = data.explosive or false
    self.fromEnemy = data.fromEnemy or false
    self.isBullet = true
    self.alive = true
    self.lifetime = 3
    return self
end

function Bullet:update(dt, world)
    self.lifetime = self.lifetime - dt
    if self.lifetime <= 0 then
        self.alive = false
        return
    end

    local vx = math.cos(self.angle) * self.speed
    local vy = math.sin(self.angle) * self.speed

    local goalX = self.x + vx * dt
    local goalY = self.y + vy * dt

    local actualX, actualY, cols, len = world:move(self, goalX, goalY, self.filter)
    self.x = actualX
    self.y = actualY

    for i = 1, len do
        local col = cols[i]
        local other = col.other

        if other.isEnemy and not self.fromEnemy then
            self.hitEnemy = other
            self.alive = false
            return
        end

        if other.isPlayer and self.fromEnemy then
            self.hitPlayer = true
            self.alive = false
            return
        end

        if not other.isEnemy and not other.isPickup and not other.isBullet and not other.isDoor and not other.isPlayer then
            if self.ricochet > 0 then
                self.ricochet = self.ricochet - 1
                if col.normal.x ~= 0 then
                    self.angle = math.pi - self.angle
                elseif col.normal.y ~= 0 then
                    self.angle = -self.angle
                end
                self.x = self.x + col.normal.x * 2
                self.y = self.y + col.normal.y * 2
                world:update(self, self.x, self.y)
                if debugLog then debugLog("Ricochet bounce (" .. self.ricochet .. " left)") end
                return
            else
                ImpactFX.spawn(self.x + self.w / 2, self.y + self.h / 2, "hit_wall")
                self.alive = false
                return
            end
        end
    end
end

function Bullet.filter(item, other)
    if other.isBullet then return nil end
    if other.isPickup then return nil end
    if item.fromEnemy and other.isEnemy then return nil end
    if not item.fromEnemy and other.isPlayer then return nil end
    if other.isDoor then return nil end
    -- Solid geometry blocks shots and line-of-sight probes (isPlatform / isWall)
    if other.isPlatform or other.isWall then
        return "slide"
    end
    return "cross"
end

function Bullet:draw()
    if self.fromEnemy then
        love.graphics.setColor(1, 0.3, 0.3)
    else
        love.graphics.setColor(1, 0.9, 0.3)
    end
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
    love.graphics.setColor(1, 1, 1)
end

return Bullet
