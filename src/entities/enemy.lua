local EnemyData = require("src.data.enemies")
local PlatformCollision = require("src.systems.platform_collision")

local Enemy = {}
Enemy.__index = Enemy

-- Bandit sprite constants
local BANDIT_FRAME_H = 48
local BANDIT_SPRITE_SCALE = 0.85
local _banditSheet = nil
local _banditQuads = nil
local BANDIT_WALK_FRAMES = 8
local BANDIT_WALK_FPS   = 10

local function loadBanditSprite()
    if _banditSheet then return end
    _banditSheet = love.graphics.newImage("assets/sprites/bandit/walk.png")
    _banditSheet:setFilter("nearest", "nearest")
    local sw, sh = _banditSheet:getDimensions()
    _banditQuads = {}
    for i = 0, BANDIT_WALK_FRAMES - 1 do
        _banditQuads[i + 1] = love.graphics.newQuad(
            i * BANDIT_FRAME_H, 0, BANDIT_FRAME_H, BANDIT_FRAME_H, sw, sh
        )
    end
end

local ELITE_HP = 1.9
local ELITE_DMG = 1.15
local ELITE_LOOT = 1.75
local ELITE_ATK_SPEED = 0.88

function Enemy.new(typeId, x, y, difficulty, opts)
    opts = opts or {}
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
    self.aggroRange = data.aggroRange or 260
    self.contactRange = data.contactRange
    self.name = data.name or typeId
    self.elite = false

    if opts.elite then
        self.elite = true
        self.hp = math.max(1, math.floor(self.hp * ELITE_HP + 0.5))
        self.maxHP = self.hp
        self.damage = math.max(1, math.floor(self.damage * ELITE_DMG + 0.5))
        self.xpValue = math.max(1, math.floor(self.xpValue * ELITE_LOOT + 0.5))
        self.goldValue = math.max(1, math.floor(self.goldValue * ELITE_LOOT + 0.5))
        self.attackCooldown = self.attackCooldown * ELITE_ATK_SPEED
        self.name = "Elite " .. self.name
        self.color = {
            math.min(1, data.color[1] * 1.08 + 0.12),
            math.min(1, data.color[2] * 1.05 + 0.1),
            math.min(1, data.color[3] * 0.95 + 0.08),
        }
    end

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

    -- Bandit sprite animation
    if typeId == "bandit" then
        loadBanditSprite()
        self.spriteFrame = 1
        self.spriteTimer = 0
        self.attackAnimTimer = 0  -- counts down during slash visual
    end

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

    -- Update bandit attack animation timer
    if self.attackAnimTimer and self.attackAnimTimer > 0 then
        self.attackAnimTimer = self.attackAnimTimer - dt
    end

    -- Update bandit walk animation
    if self.spriteTimer then
        if math.abs(self.vx) > 10 then
            self.spriteTimer = self.spriteTimer + dt
            local interval = 1 / BANDIT_WALK_FPS
            if self.spriteTimer >= interval then
                self.spriteTimer = self.spriteTimer - interval
                self.spriteFrame = (self.spriteFrame % BANDIT_WALK_FRAMES) + 1
            end
        else
            self.spriteFrame = 1
            self.spriteTimer = 0
        end
    end

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

local function groundFilter(item)
    return item.isPlatform or item.isWall
end

local function losFilter(item)
    return item.isPlatform or item.isWall
end

local function hasLineOfSight(world, x1, y1, x2, y2)
    local items, len = world:querySegment(x1, y1, x2, y2, losFilter)
    return len == 0
end

local function platformSurfaceFilter(item)
    return item.isPlatform
end

--- Left/right extent of the platform surface under this enemy's feet (world space).
local function getPlatformSurfaceExtents(world, ex, ey, ew, eh)
    local feetY = ey + eh
    local items, len = world:queryRect(ex - 120, feetY - 6, ew + 240, 10, platformSurfaceFilter)
    local left, right = nil, nil
    for i = 1, len do
        local p = items[i]
        if math.abs(p.y - feetY) <= 6 then
            if not left or p.x < left then left = p.x end
            if not right or p.x + p.w > right then right = p.x + p.w end
        end
    end
    return left, right
end

function Enemy:hasGroundAhead(world)
    -- Check for ground support at the leading foot (one step ahead, one tile down)
    local probeX
    if self.vx > 0 then
        probeX = self.x + self.w + 2
    elseif self.vx < 0 then
        probeX = self.x - 4
    else
        return true
    end
    local probeY = self.y + self.h + 2
    local items, len = world:queryRect(probeX, probeY, 2, 32, groundFilter)
    return len > 0
end

function Enemy:updateMelee(dt, world, dx, dy, dist, playerX, playerY)
    -- playerY = player center (game passes center); approximate feet for vertical checks
    local playerFeetY = playerY + 14
    local enemyFeetY = self.y + self.h
    local playerBelow = playerFeetY > enemyFeetY + 10

    if dist > self.aggroRange then
        self.state = "idle"
        self.vx = 0
    else
        local rush = 1.0
        if dist > self.attackRange + 28 then
            rush = 1.38 + math.min(0.48, (dist - self.attackRange - 28) * 0.0018)
        end
        if rush > 1.9 then rush = 1.9 end

        if dist <= self.attackRange then
            self.state = "attack"
            self.vx = 0
        elseif playerBelow then
            -- Don't track player X on the ledge — walk toward the nearest side to drop down
            self.state = "chase_drop"
            local left, right = getPlatformSurfaceExtents(world, self.x, self.y, self.w, self.h)
            if left and right then
                local mid = (left + right) * 0.5
                local edgeDir = (playerX < mid) and -1 or 1
                self.vx = edgeDir * self.speed * rush
            else
                self.state = "chase"
                self.vx = ((dx > 0) and self.speed or -self.speed) * rush
            end
        else
            self.state = "chase"
            self.vx = ((dx > 0) and self.speed or -self.speed) * rush
        end

        if self.grounded and self.vx ~= 0 and not self:hasGroundAhead(world) and not playerBelow then
            self.vx = 0
        end
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
    local ecx, ecy = self.x + self.w / 2, self.y + self.h / 2
    local playerFeetY = playerY + 14
    local enemyFeetY = self.y + self.h
    local playerBelow = playerFeetY > enemyFeetY + 10
    local horizDist = math.abs(dx)
    local los = hasLineOfSight(world, ecx, ecy, playerX, playerY)
    -- Allow shooting when mostly separated vertically but still lined up horizontally (no more 2D-dist mirroring chase)
    local canShoot = dist <= self.aggroRange
        and los and horizDist <= self.attackRange * 1.05 and math.abs(dy) <= self.attackRange * 1.45

    if dist > self.aggroRange then
        self.state = "idle"
        self.vx = 0
    elseif canShoot then
        self.state = "attack"
        self.vx = 0
    elseif playerBelow and not canShoot then
        if not los then
            -- Blocked: head for a ledge instead of mirroring X under the player
            self.state = "chase_drop"
            local left, right = getPlatformSurfaceExtents(world, self.x, self.y, self.w, self.h)
            if left and right then
                local mid = (left + right) * 0.5
                local edgeDir = (playerX < mid) and -1 or 1
                self.vx = edgeDir * self.speed
            else
                self.state = "chase"
                self.vx = (dx > 0) and self.speed or -self.speed
            end
        elseif horizDist > self.attackRange * 1.05 then
            -- Clear shot exists vertically but need to strafe in horizontally
            self.state = "chase"
            self.vx = (dx > 0) and self.speed or -self.speed
        else
            -- Too steep: drop to the player
            self.state = "chase_drop"
            local left, right = getPlatformSurfaceExtents(world, self.x, self.y, self.w, self.h)
            if left and right then
                local mid = (left + right) * 0.5
                local edgeDir = (playerX < mid) and -1 or 1
                self.vx = edgeDir * self.speed
            else
                self.state = "chase"
                self.vx = (dx > 0) and self.speed or -self.speed
            end
        end
    elseif dist > self.attackRange * 1.5 then
        self.state = "chase"
        self.vx = (dx > 0) and (self.speed) or (-self.speed)
    else
        self.state = "attack"
        self.vx = 0
    end

    if self.grounded and self.vx ~= 0 and not self:hasGroundAhead(world) and not playerBelow then
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

    if self.state == "attack" and self.attackTimer <= 0 and canShoot then
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
    -- Bob up and down around homeY, swoop toward player only inside aggro radius
    if dist > self.aggroRange then
        self.swoopTarget = nil
        self.vx = 0
        local bobTarget = self.homeY + math.sin(love.timer.getTime() * 2) * 20
        self.vy = (bobTarget - self.y) * 2
    elseif self.swoopTarget then
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

function Enemy:takeDamage(amount, world)
    self.hp = self.hp - amount
    self.hurtTimer = 0.1
    if self.hp <= 0 then
        self.alive = false
        self.isEnemy = false
        if world and world:hasItem(self) then
            world:remove(self)
        end
    end
end

function Enemy:canDamagePlayer(playerX, playerY, playerW, playerH)
    if self.behavior == "melee" or self.behavior == "flying" then
        local cx = self.x + self.w / 2
        local cy = self.y + self.h / 2
        local px = playerX + playerW / 2
        local py = playerY + playerH / 2
        local dist = math.sqrt((cx - px)^2 + (cy - py)^2)
        local hitR = self.contactRange or self.attackRange
        return dist <= hitR and self.attackTimer <= 0
    end
    return false
end

function Enemy:onContactDamage()
    if self.behavior == "melee" or self.behavior == "flying" then
        self.attackTimer = self.attackCooldown
    end
    if self.attackAnimTimer then
        self.attackAnimTimer = 0.3
    end
end

function Enemy.filter(item, other)
    if other.isEnemy or other.isPickup or other.isBullet or other.isDoor then
        return nil
    end
    if other.isPlayer then
        return "cross"
    end
    if other.isWall then
        return "slide"
    end
    if other.isPlatform then
        if PlatformCollision.shouldPassThroughOneWay(item, other) then
            return nil
        end
        return "slide"
    end
    return "slide"
end

function Enemy:draw()
    if not self.alive then return end
    local c = self.color

    if self.elite and self.typeId ~= "bandit" then
        love.graphics.setColor(0.92, 0.72, 0.15)
        love.graphics.rectangle("line", self.x - 2, self.y - 2, self.w + 4, self.h + 4)
    end

    -- Bandit: draw sprite instead of rectangle
    if self.typeId == "bandit" and _banditSheet then
        local quad = _banditQuads[self.spriteFrame]
        if quad then
            if self.hurtTimer > 0 then
                love.graphics.setColor(1, 0.4, 0.4)
            else
                love.graphics.setColor(1, 1, 1)
            end
            local scaledW = BANDIT_FRAME_H * BANDIT_SPRITE_SCALE
            local scaledH = BANDIT_FRAME_H * BANDIT_SPRITE_SCALE
            local cx = self.x + self.w / 2
            local footY = self.y + self.h

            -- Lunge forward during attack
            local attacking = self.attackAnimTimer and self.attackAnimTimer > 0
            local lungeOffset = 0
            if attacking then
                local t = self.attackAnimTimer / 0.3  -- 1→0
                lungeOffset = math.sin(t * math.pi) * 6
                if not self.facingRight then lungeOffset = -lungeOffset end
            end

            local drawX = cx - scaledW / 2 + lungeOffset
            local drawY = footY - scaledH
            local sx = self.facingRight and BANDIT_SPRITE_SCALE or -BANDIT_SPRITE_SCALE
            local flipShift = self.facingRight and 0 or scaledW
            love.graphics.draw(_banditSheet, quad, drawX + flipShift, drawY, 0, sx, BANDIT_SPRITE_SCALE)

            -- Slash arc during attack
            if attacking then
                local t = self.attackAnimTimer / 0.3
                local alpha = t  -- fades out
                local dir = self.facingRight and 1 or -1
                local arcCx = cx + dir * 16
                local arcCy = self.y + self.h * 0.4
                local radius = 12
                local startAngle = self.facingRight and -math.pi * 0.6 or math.pi * 0.4
                local sweep = math.pi * 0.8 * (1 - t)  -- grows as timer counts down
                love.graphics.setColor(1, 0.95, 0.7, alpha * 0.9)
                love.graphics.setLineWidth(2)
                love.graphics.arc("line", "open", arcCx, arcCy, radius, startAngle, startAngle + sweep * dir, 8)
                love.graphics.setLineWidth(1)
            end
        end
    else
        if self.hurtTimer > 0 then
            love.graphics.setColor(1, 1, 1)
        else
            love.graphics.setColor(c[1], c[2], c[3])
        end
        love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
        -- Simple hat for non-sprite enemies
        love.graphics.setColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6)
        love.graphics.rectangle("fill", self.x - 2, self.y - 4, self.w + 4, 4)
    end

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
