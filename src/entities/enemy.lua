local EnemyData = require("src.data.enemies")

local Enemy = {}
Enemy.__index = Enemy

function Enemy.new(typeId, x, y, difficulty)
    local data = EnemyData.getScaled(typeId, difficulty or 1)
    if not data then return nil end

    local self = setmetatable({}, Enemy)
    self.typeId = typeId
    self.x = x
    self.y = y
    self.w = data.width
    self.h = data.height
    self.hp = data.hp
    self.maxHP = data.hp
    self.damage = data.damage
    self.speed = data.speed
    self.xpValue = data.xpValue
    self.goldValue = data.goldValue
    self.color = data.color
    self.behavior = data.behavior
    self.attackRange = data.attackRange
    self.attackCooldown = data.attackCooldown
    self.bulletSpeed = data.bulletSpeed
    self.swoopSpeed = data.swoopSpeed

    self.isEnemy = true
    self.alive = true
    self.state = "idle"
    self.attackTimer = data.attackCooldown
    self.facingRight = true
    self.vx = 0
    self.vy = 0
    self.grounded = false
    self.hurtTimer = 0

    -- Flying enemies hover
    self.flying = (data.behavior == "flying")
    self.swoopTarget = nil
    self.homeY = y

    return self
end

function Enemy:update(dt, world, playerX, playerY)
    self.attackTimer = self.attackTimer - dt
    if self.hurtTimer > 0 then
        self.hurtTimer = self.hurtTimer - dt
    end

    local dx = playerX - (self.x + self.w / 2)
    local dy = playerY - (self.y + self.h / 2)
    local dist = math.sqrt(dx * dx + dy * dy)

    self.facingRight = dx > 0

    local bulletsToSpawn = nil

    if self.behavior == "melee" then
        bulletsToSpawn = self:updateMelee(dt, world, dx, dy, dist, playerX, playerY)
    elseif self.behavior == "ranged" then
        bulletsToSpawn = self:updateRanged(dt, world, dx, dy, dist, playerX, playerY)
    elseif self.behavior == "flying" then
        bulletsToSpawn = self:updateFlying(dt, world, dx, dy, dist, playerX, playerY)
    end

    return bulletsToSpawn
end

function Enemy:updateMelee(dt, world, dx, dy, dist, playerX, playerY)
    if dist > self.attackRange then
        self.state = "chase"
        self.vx = (dx > 0) and self.speed or -self.speed
    else
        self.state = "attack"
        self.vx = 0
    end

    if not self.flying then
        self.vy = (self.vy or 0) + 900 * dt
        if self.vy > 600 then self.vy = 600 end
    end

    local goalX = self.x + self.vx * dt
    local goalY = self.y + self.vy * dt
    local actualX, actualY, cols, len = world:move(self, goalX, goalY, self.filter)
    self.x = actualX
    self.y = actualY

    for i = 1, len do
        if cols[i].normal.y == -1 then
            self.grounded = true
            self.vy = 0
        end
    end

    return nil
end

function Enemy:updateRanged(dt, world, dx, dy, dist, playerX, playerY)
    if dist > self.attackRange * 1.5 then
        self.state = "chase"
        self.vx = (dx > 0) and (self.speed) or (-self.speed)
    else
        self.state = "attack"
        self.vx = 0
    end

    if not self.flying then
        self.vy = (self.vy or 0) + 900 * dt
        if self.vy > 600 then self.vy = 600 end
    end

    local goalX = self.x + self.vx * dt
    local goalY = self.y + self.vy * dt
    local actualX, actualY, cols, len = world:move(self, goalX, goalY, self.filter)
    self.x = actualX
    self.y = actualY

    for i = 1, len do
        if cols[i].normal.y == -1 then
            self.grounded = true
            self.vy = 0
        end
    end

    if self.state == "attack" and self.attackTimer <= 0 and dist <= self.attackRange then
        self.attackTimer = self.attackCooldown
        local angle = math.atan2(dy, dx)
        -- Slight inaccuracy
        angle = angle + (math.random() - 0.5) * 0.15
        return {
            x = self.x + self.w / 2,
            y = self.y + self.h / 2,
            angle = angle,
            speed = self.bulletSpeed or 250,
            damage = self.damage,
            fromEnemy = true,
        }
    end

    return nil
end

function Enemy:updateFlying(dt, world, dx, dy, dist, playerX, playerY)
    -- Bob up and down around homeY, swoop toward player
    if self.swoopTarget then
        local sx = self.swoopTarget.x - self.x
        local sy = self.swoopTarget.y - self.y
        local sd = math.sqrt(sx * sx + sy * sy)
        if sd < 20 or self.attackTimer <= -1 then
            self.swoopTarget = nil
            self.attackTimer = self.attackCooldown
        else
            local spd = self.swoopSpeed or 280
            self.vx = (sx / sd) * spd
            self.vy = (sy / sd) * spd
        end
    else
        self.vx = (dx > 0) and 30 or -30
        local bobTarget = self.homeY + math.sin(love.timer.getTime() * 2) * 20
        self.vy = (bobTarget - self.y) * 2

        if self.attackTimer <= 0 and dist < self.attackRange then
            self.swoopTarget = {x = playerX, y = playerY}
            self.attackTimer = 0
        end
    end

    local goalX = self.x + self.vx * dt
    local goalY = self.y + self.vy * dt
    local actualX, actualY = world:move(self, goalX, goalY, self.filter)
    self.x = actualX
    self.y = actualY

    return nil
end

function Enemy:takeDamage(amount)
    self.hp = self.hp - amount
    self.hurtTimer = 0.1
    if self.hp <= 0 then
        self.alive = false
    end
end

function Enemy:canDamagePlayer(playerX, playerY, playerW, playerH)
    if self.behavior == "melee" or self.behavior == "flying" then
        local cx = self.x + self.w / 2
        local cy = self.y + self.h / 2
        local px = playerX + playerW / 2
        local py = playerY + playerH / 2
        local dist = math.sqrt((cx - px)^2 + (cy - py)^2)
        return dist < self.attackRange and self.attackTimer <= 0
    end
    return false
end

function Enemy:onContactDamage()
    if self.behavior == "melee" then
        self.attackTimer = self.attackCooldown
    end
end

function Enemy.filter(item, other)
    if other.isEnemy or other.isPickup or other.isBullet or other.isDoor then
        return nil
    end
    if other.isPlayer then
        return "cross"
    end
    return "slide"
end

function Enemy:draw()
    local c = self.color
    if self.hurtTimer > 0 then
        love.graphics.setColor(1, 1, 1)
    else
        love.graphics.setColor(c[1], c[2], c[3])
    end

    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)

    -- Simple hat for all enemies
    love.graphics.setColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6)
    love.graphics.rectangle("fill", self.x - 2, self.y - 4, self.w + 4, 4)

    -- HP bar
    if self.hp < self.maxHP then
        local barW = self.w + 4
        local barH = 3
        local barX = self.x - 2
        local barY = self.y - 10
        love.graphics.setColor(0.3, 0.0, 0.0)
        love.graphics.rectangle("fill", barX, barY, barW, barH)
        love.graphics.setColor(0.8, 0.1, 0.1)
        love.graphics.rectangle("fill", barX, barY, barW * (self.hp / self.maxHP), barH)
    end

    love.graphics.setColor(1, 1, 1)
end

return Enemy
