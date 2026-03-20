local Player = {}
Player.__index = Player

local GRAVITY = 900
local JUMP_FORCE = -380
local COYOTE_TIME = 0.08
local JUMP_BUFFER = 0.1

function Player.new(x, y)
    local self = setmetatable({}, Player)
    self.x = x
    self.y = y
    self.w = 16
    self.h = 28
    self.vx = 0
    self.vy = 0

    self.facingRight = true
    self.grounded = false
    self.coyoteTimer = 0
    self.jumpBufferTimer = 0

    self.stats = {
        maxHP = 100,
        moveSpeed = 200,
        jumpForce = JUMP_FORCE,
        damageMultiplier = 1.0,
        armor = 0,
        luck = 0,
        reloadSpeed = 1.2,
        cylinderSize = 6,
        bulletSpeed = 500,
        bulletDamage = 15,
        bulletCount = 1,
        spreadAngle = 0,
        lifestealOnKill = 0,
        ricochetCount = 0,
        explosiveRounds = false,
        deadEye = false,
    }

    self.hp = self.stats.maxHP
    self.ammo = self.stats.cylinderSize
    self.reloading = false
    self.reloadTimer = 0
    self.shootCooldown = 0

    self.xp = 0
    self.level = 1
    self.xpToNext = 50
    self.gold = 0

    self.iframes = 0
    self.deadEyeTimer = 0

    self.gear = {
        hat = nil,
        vest = nil,
        boots = nil,
    }

    self.perks = {}

    return self
end

function Player:getEffectiveStats()
    local s = {}
    for k, v in pairs(self.stats) do
        s[k] = v
    end

    for _, slot in ipairs({"hat", "vest", "boots"}) do
        local gear = self.gear[slot]
        if gear then
            for stat, val in pairs(gear.stats) do
                if s[stat] then
                    if stat == "damageMultiplier" or stat == "luck" then
                        s[stat] = s[stat] + val
                    else
                        s[stat] = s[stat] + val
                    end
                end
            end
        end
    end

    return s
end

function Player:update(dt, world)
    local effectiveStats = self:getEffectiveStats()

    -- I-frames
    if self.iframes > 0 then
        self.iframes = self.iframes - dt
    end

    -- Dead eye timer
    if self.deadEyeTimer > 0 then
        self.deadEyeTimer = self.deadEyeTimer - dt
    end

    -- Shoot cooldown
    if self.shootCooldown > 0 then
        self.shootCooldown = self.shootCooldown - dt
    end

    -- Reload
    if self.reloading then
        self.reloadTimer = self.reloadTimer - dt
        if self.reloadTimer <= 0 then
            self.reloading = false
            self.ammo = effectiveStats.cylinderSize
            if self.stats.deadEye then
                self.deadEyeTimer = 3.0
            end
        end
    end

    -- Horizontal movement
    self.vx = 0
    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
        self.vx = -effectiveStats.moveSpeed
        self.facingRight = false
    end
    if love.keyboard.isDown("d") or love.keyboard.isDown("right") then
        self.vx = effectiveStats.moveSpeed
        self.facingRight = true
    end

    -- Coyote time tracking
    if self.grounded then
        self.coyoteTimer = COYOTE_TIME
    else
        self.coyoteTimer = self.coyoteTimer - dt
    end

    -- Jump buffer
    if self.jumpBufferTimer > 0 then
        self.jumpBufferTimer = self.jumpBufferTimer - dt
    end

    -- Apply gravity
    self.vy = self.vy + GRAVITY * dt
    if self.vy > 600 then self.vy = 600 end

    -- Execute buffered jump
    if self.jumpBufferTimer > 0 and self.coyoteTimer > 0 then
        self.vy = effectiveStats.jumpForce
        self.grounded = false
        self.coyoteTimer = 0
        self.jumpBufferTimer = 0
    end

    -- Move with collision
    local goalX = self.x + self.vx * dt
    local goalY = self.y + self.vy * dt

    self.grounded = false
    local actualX, actualY, cols, len = world:move(self, goalX, goalY, self.filter)
    self.x = actualX
    self.y = actualY

    for i = 1, len do
        local col = cols[i]
        if col.normal.y == -1 then
            self.grounded = true
            self.vy = 0
        elseif col.normal.y == 1 then
            self.vy = 0
        end
    end
end

function Player:jump()
    self.jumpBufferTimer = JUMP_BUFFER
end

function Player:shoot(mx, my)
    if self.reloading or self.shootCooldown > 0 then return nil end
    if self.ammo <= 0 then
        self:reload()
        return nil
    end

    self.ammo = self.ammo - 1
    self.shootCooldown = 0.15

    local cx = self.x + self.w / 2
    local cy = self.y + self.h / 2
    local angle = math.atan2(my - cy, mx - cx)

    local effectiveStats = self:getEffectiveStats()
    local bullets = {}
    local count = effectiveStats.bulletCount

    for i = 1, count do
        local a = angle
        if count > 1 then
            local spread = effectiveStats.spreadAngle
            a = angle - spread / 2 + spread * ((i - 1) / (count - 1))
        end
        table.insert(bullets, {
            x = cx,
            y = cy,
            angle = a,
            speed = effectiveStats.bulletSpeed,
            damage = math.floor(effectiveStats.bulletDamage * effectiveStats.damageMultiplier),
            ricochet = effectiveStats.ricochetCount,
            explosive = effectiveStats.explosiveRounds,
        })
    end

    if self.ammo <= 0 then
        self:reload()
    end

    return bullets
end

function Player:reload()
    if self.reloading then return end
    if self.ammo >= self:getEffectiveStats().cylinderSize then return end
    self.reloading = true
    self.reloadTimer = self:getEffectiveStats().reloadSpeed
end

function Player:takeDamage(amount)
    if self.iframes > 0 then return false end

    local effectiveArmor = self:getEffectiveStats().armor
    local finalDamage = math.max(1, amount - effectiveArmor)
    self.hp = self.hp - finalDamage
    self.iframes = 0.5

    return true
end

function Player:heal(amount)
    local maxHP = self:getEffectiveStats().maxHP
    self.hp = math.min(maxHP, self.hp + amount)
end

function Player:addXP(amount)
    self.xp = self.xp + amount
    if self.xp >= self.xpToNext then
        self.xp = self.xp - self.xpToNext
        self.level = self.level + 1
        self.xpToNext = math.floor(self.xpToNext * 1.4)
        return true
    end
    return false
end

function Player:addGold(amount)
    self.gold = self.gold + amount
end

function Player:equipGear(gear)
    self.gear[gear.slot] = gear
    if gear.stats.maxHP then
        self.hp = math.min(self:getEffectiveStats().maxHP, self.hp + gear.stats.maxHP)
    end
end

function Player:applyPerk(perk)
    table.insert(self.perks, perk.id)
    perk.apply(self)
end

function Player.filter(item, other)
    if other.isEnemy or other.isPickup or other.isBullet or other.isDoor then
        return "cross"
    end
    return "slide"
end

function Player:draw()
    -- Flash when invulnerable
    if self.iframes > 0 and math.floor(self.iframes * 10) % 2 == 0 then
        return
    end

    -- Body
    love.graphics.setColor(0.85, 0.65, 0.4)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)

    -- Hat
    love.graphics.setColor(0.5, 0.3, 0.1)
    love.graphics.rectangle("fill", self.x - 3, self.y - 6, self.w + 6, 6)
    love.graphics.rectangle("fill", self.x + 2, self.y - 12, self.w - 4, 8)

    -- Eyes
    love.graphics.setColor(0, 0, 0)
    if self.facingRight then
        love.graphics.rectangle("fill", self.x + 10, self.y + 6, 3, 3)
    else
        love.graphics.rectangle("fill", self.x + 3, self.y + 6, 3, 3)
    end

    -- Gun
    love.graphics.setColor(0.3, 0.3, 0.3)
    if self.facingRight then
        love.graphics.rectangle("fill", self.x + self.w, self.y + 10, 8, 3)
    else
        love.graphics.rectangle("fill", self.x - 8, self.y + 10, 8, 3)
    end

    love.graphics.setColor(1, 1, 1)
end

return Player
