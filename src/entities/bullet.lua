local ImpactFX = require("src.systems.impact_fx")
local Sfx = require("src.systems.sfx")

local Bullet = {}
Bullet.__index = Bullet

function Bullet.new(data)
    local self = setmetatable({}, Bullet)
    self.x = data.x
    self.y = data.y
    -- Small axis-aligned hitbox (visual is drawn along travel direction below).
    self.w = data.w or 3
    self.h = data.h or 2
    self.angle = data.angle
    self.speed = data.speed or 500
    self.damage = data.damage or 10
    self.ricochet = data.ricochet or 0
    self.explosive = data.explosive or false
    self.fromEnemy = data.fromEnemy or false
    self.ultBullet = data.ultBullet or false
    self.isBullet = true
    self.alive = true
    self.lifetime = 3
    self.age = 0
    return self
end

function Bullet:update(dt, world)
    self.age = self.age + dt
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
                if not self.fromEnemy then
                    Sfx.play("ricochet")
                end
                if debugLog then debugLog("Ricochet bounce (" .. self.ricochet .. " left)") end
                return
            else
                if not self.fromEnemy then
                    Sfx.play("hit_wall")
                end
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

--- Procedural pistol slug: elongated capsule along +x after rotation (no bullet sprites in assets).
function Bullet:draw()
    local cx = self.x + self.w * 0.5
    local cy = self.y + self.h * 0.5
    local len = self.ultBullet and 8.5 or 5.5
    local halfW = self.ultBullet and 1.15 or 0.95
    local trailLen = self.ultBullet and 22 or 14
    local glowR, glowG, glowB = 1, 0.92, 0.72
    local trailAlpha = self.ultBullet and 0.34 or 0.22

    if self.explosive then
        trailLen = trailLen + 4
    end

    if self.ultBullet then
        glowR, glowG, glowB = 1.0, 0.72, 0.2
    elseif self.fromEnemy then
        glowR, glowG, glowB = 1.0, 0.45, 0.38
        trailAlpha = 0.18
    else
        glowR, glowG, glowB = 1.0, 0.88, 0.62
    end

    local prevBlendMode, prevAlphaMode = love.graphics.getBlendMode()
    local prevLineWidth = love.graphics.getLineWidth()
    love.graphics.setBlendMode("add", "alphamultiply")
    love.graphics.setLineWidth(self.ultBullet and 3.2 or 2.2)
    love.graphics.setColor(glowR, glowG, glowB, trailAlpha)
    love.graphics.line(
        cx - math.cos(self.angle) * trailLen,
        cy - math.sin(self.angle) * trailLen,
        cx,
        cy
    )
    love.graphics.setColor(1, 1, 1, trailAlpha * 0.72)
    love.graphics.line(
        cx - math.cos(self.angle) * trailLen * 0.45,
        cy - math.sin(self.angle) * trailLen * 0.45,
        cx,
        cy
    )
    love.graphics.setColor(glowR, glowG, glowB, trailAlpha * 0.8)
    love.graphics.circle("fill", cx, cy, self.ultBullet and 2.6 or 1.8)
    love.graphics.setLineWidth(prevLineWidth)
    love.graphics.setBlendMode(prevBlendMode, prevAlphaMode)

    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(self.angle)

    if self.ultBullet then
        love.graphics.setColor(0.95, 0.72, 0.2)
        love.graphics.rectangle("fill", -len * 0.5 + 0.4, -halfW, len - 1.2, halfW * 2, 0.45, 0.45)
        love.graphics.setColor(1, 0.95, 0.55)
        love.graphics.rectangle("fill", len * 0.5 - 1.6, -halfW * 0.7, 1.6, halfW * 1.4, 0.35, 0.35)
    elseif self.fromEnemy then
        love.graphics.setColor(0.55, 0.14, 0.12)
        love.graphics.rectangle("fill", -len * 0.5 + 0.4, -halfW, len - 1.2, halfW * 2, 0.45, 0.45)
        love.graphics.setColor(1, 0.45, 0.38)
        love.graphics.rectangle("fill", len * 0.5 - 1.35, -halfW * 0.72, 1.35, halfW * 1.44, 0.3, 0.3)
    else
        love.graphics.setColor(0.5, 0.38, 0.14)
        love.graphics.rectangle("fill", -len * 0.5 + 0.4, -halfW, len - 1.2, halfW * 2, 0.45, 0.45)
        love.graphics.setColor(0.92, 0.88, 0.78)
        love.graphics.rectangle("fill", len * 0.5 - 1.35, -halfW * 0.72, 1.35, halfW * 1.44, 0.3, 0.3)
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

return Bullet
