local Weapons = require("src.data.weapons")
local PlatformCollision = require("src.systems.platform_collision")

local Player = {}
Player.__index = Player

local GRAVITY = 900

-- Melee swipe: same aim idea as bullets — segment from body toward cursor (AABB bounds the rotated stroke).
local MELEE_HIT_THICKNESS = 14
local MELEE_INNER_DIST = 6
local JUMP_FORCE = -380
local COYOTE_TIME = 0.1
local JUMP_BUFFER = 0.12
local DOUBLE_JUMP_MULT = 0.9
local JUMP_RELEASE_GRAVITY_MULT = 0.95 -- extra gravity while rising if jump not held (short hop)

local DASH_SPEED = 520
local DASH_DURATION = 0.12
local DASH_COOLDOWN = 0.52

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
    self.jumpCount = 0 -- 0 = can ground/coyote jump, 1 = can double jump, 2 = spent

    self.dashTimer = 0
    self.dashCooldown = 0
    self.dashDir = 1

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
        bulletDamage = 10,
        bulletCount = 1,
        spreadAngle = 0,
        lifestealOnKill = 0,
        ricochetCount = 0,
        explosiveRounds = false,
        deadEye = false,
        -- Melee
        meleeDamage    = 0,
        meleeRange     = 0,
        meleeCooldown  = 0,
        meleeKnockback = 0,
        -- Shield / blocking
        blockReduction = 0,
        -- >0 = can move / jump / dash while blocking (upgrades); 0 = Smash-style rooted shield
        blockMobility = 0,
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
        hat    = nil,
        vest   = nil,
        boots  = nil,
        melee  = Weapons.defaults.melee,
        shield = Weapons.defaults.shield,
    }

    -- Crouch / platform-drop
    self.crouching        = false
    self.dropThroughTimer = 0   -- > 0 → ignore one-way platforms until timer expires

    -- Melee / block state
    self.blocking         = false
    self.meleeCooldown    = 0        -- time until next swing is allowed
    self.meleeSwingTimer  = 0        -- > 0 while the hit-window is active
    self.meleeHitEnemies  = {}       -- enemies already hit in the current swing
    self.meleeHitFlashTimer = 0      -- HUD / strike feedback after a connecting hit
    self.meleeAimAngle = 0           -- radians, set when a swing starts (same basis as :shoot)

    -- Updated each frame in game state — world position under cursor (like shooting).
    self.aimWorldX = 0
    self.aimWorldY = 0

    -- Loadout automation (toggled via HUD right-click). Gun + melee on by default.
    -- Shield auto-block only applies when equipped shield has stats.allowAutoBlock.
    self.autoGun   = true
    self.autoMelee = true
    self.autoBlock = false

    self.perks = {}

    return self
end

--- True only when the equipped shield explicitly enables auto-block (never on default gear).
function Player:shieldAllowsAutoBlock()
    local st = self.gear.shield and self.gear.shield.stats
    return st and st.allowAutoBlock and true or false
end

function Player:getEffectiveStats()
    local s = {}
    for k, v in pairs(self.stats) do
        s[k] = v
    end

    for _, gear in pairs(self.gear) do
        if gear then
            for stat, val in pairs(gear.stats) do
                if s[stat] ~= nil then
                    s[stat] = s[stat] + val
                end
            end
        end
    end

    return s
end

local AUTO_BLOCK_RANGE_SQ = 70 * 70

function Player:update(dt, world, enemies)
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

    -- Melee cooldown + swing window
    if self.meleeCooldown > 0 then
        self.meleeCooldown = math.max(0, self.meleeCooldown - dt)
    end
    if self.meleeSwingTimer > 0 then
        self.meleeSwingTimer = math.max(0, self.meleeSwingTimer - dt)
        if self.meleeSwingTimer <= 0 then
            self.meleeHitEnemies = {}
        end
    end

    if self.meleeHitFlashTimer > 0 then
        self.meleeHitFlashTimer = math.max(0, self.meleeHitFlashTimer - dt)
    end

    -- Blocking: CTRL always. Auto-block only if this shield supports it (gear stat) and HUD toggle is on.
    local keysBlock = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    local autoBlockActive = false
    if self:shieldAllowsAutoBlock() and self.autoBlock and enemies then
        local px = self.x + self.w / 2
        local py = self.y + self.h / 2
        for _, e in ipairs(enemies) do
            if e.alive then
                local ex = e.x + e.w / 2
                local ey = e.y + e.h / 2
                local dx, dy = ex - px, ey - py
                if dx * dx + dy * dy <= AUTO_BLOCK_RANGE_SQ then
                    autoBlockActive = true
                    break
                end
            end
        end
    end
    self.blocking  = keysBlock or autoBlockActive
    self.crouching = love.keyboard.isDown("s") or love.keyboard.isDown("down")

    -- Drop-through timer (set by tryDropThrough on keypressed, not polled)
    if self.dropThroughTimer > 0 then
        self.dropThroughTimer = math.max(0, self.dropThroughTimer - dt)
    end

    local blockRooted = self.blocking and effectiveStats.blockMobility <= 0

    -- Dash timers
    if self.dashTimer > 0 then
        local prev = self.dashTimer
        self.dashTimer = self.dashTimer - dt
        if prev > 0 and self.dashTimer <= 0 then
            self.dashCooldown = DASH_COOLDOWN
        end
    elseif self.dashCooldown > 0 then
        self.dashCooldown = math.max(0, self.dashCooldown - dt)
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

    if blockRooted then
        self.dashTimer = 0
    end

    -- Horizontal movement (dash overrides walk; rooted block = no move)
    if self.dashTimer > 0 and not blockRooted then
        self.vx = self.dashDir * DASH_SPEED
    elseif blockRooted then
        self.vx = 0
    else
        self.vx = 0
        if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
            self.vx = -effectiveStats.moveSpeed
            self.facingRight = false
        end
        if love.keyboard.isDown("d") or love.keyboard.isDown("right") then
            self.vx = effectiveStats.moveSpeed
            self.facingRight = true
        end
    end

    -- Coyote time + jump chain reset while supported
    if self.grounded then
        self.coyoteTimer = COYOTE_TIME
        self.jumpCount = 0
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

    -- Short hop: stronger fall when jump released while still moving up
    if self.vy < 0 then
        local jHeld = love.keyboard.isDown("space") or love.keyboard.isDown("w") or love.keyboard.isDown("up")
        if not jHeld then
            self.vy = self.vy + GRAVITY * JUMP_RELEASE_GRAVITY_MULT * dt
        end
    end

    -- Buffered jump: ground/coyote first, then one mid-air jump (double jump)
    if self.jumpBufferTimer > 0 and not blockRooted then
        if self.jumpCount == 0 and self.coyoteTimer > 0 then
            self.vy = effectiveStats.jumpForce
            self.grounded = false
            self.coyoteTimer = 0
            self.jumpBufferTimer = 0
            self.jumpCount = 1
        elseif self.jumpCount == 1 then
            self.vy = effectiveStats.jumpForce * DOUBLE_JUMP_MULT
            self.jumpBufferTimer = 0
            self.jumpCount = 2
        end
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
            self.jumpCount = 0
        elseif col.normal.y == 1 then
            self.vy = 0
        end
    end
end

function Player:jump()
    local s = self:getEffectiveStats()
    if self.blocking and s.blockMobility <= 0 then
        return
    end
    self.jumpBufferTimer = JUMP_BUFFER
end

function Player:tryDropThrough()
    if self.grounded then
        self.dropThroughTimer = 0.25
        -- Nudge downward so bump sees movement on this same frame
        if self.vy <= 0 then self.vy = 60 end
    end
end

function Player:tryDash()
    local s = self:getEffectiveStats()
    if self.blocking and s.blockMobility <= 0 then
        return
    end
    if self.dashCooldown > 0 or self.dashTimer > 0 then
        return
    end
    local dir = 0
    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then dir = -1 end
    if love.keyboard.isDown("d") or love.keyboard.isDown("right") then dir = 1 end
    if dir == 0 then
        dir = self.facingRight and 1 or -1
    end
    self.dashDir = dir
    self.dashTimer = DASH_DURATION
    self.iframes = math.max(self.iframes, 0.2)

    -- Dash strike: active melee hitbox for the full dash, aimed in dash direction
    local s = self:getEffectiveStats()
    if s.meleeDamage > 0 then
        self.meleeAimAngle  = dir == 1 and 0 or math.pi
        self.meleeSwingTimer = DASH_DURATION
        self.meleeCooldown   = 0           -- dash resets cooldown so it always fires
        self.meleeHitEnemies = {}
    end
end

function Player:shoot(mx, my)
    if self.reloading or self.shootCooldown > 0 then return nil end
    if self.ammo <= 0 then
        self:reload()
        return nil
    end

    self.ammo = self.ammo - 1
    self.shootCooldown = 0.38

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

--- Aim direction for melee when not locked into a swing (mouse world aim, else facing).
function Player:getMeleeAimAngleLive()
    local cx = self.x + self.w * 0.5
    local cy = self.y + self.h * 0.5
    if self.aimWorldX and self.aimWorldY then
        return math.atan2(self.aimWorldY - cy, self.aimWorldX - cx)
    end
    return self.facingRight and 0 or math.pi
end

-- Axis-aligned bounds of the oriented melee stroke at `angle` (radians).
function Player:getMeleeHitboxAABB(angle)
    local s = self:getEffectiveStats()
    local range = s.meleeRange
    if range <= 0 then
        return 0, 0, 0, 0
    end
    local thick = MELEE_HIT_THICKNESS
    local cx, cy = self.x + self.w * 0.5, self.y + self.h * 0.5
    local cosa, sina = math.cos(angle), math.sin(angle)
    local ux, uy = cosa, sina
    local vx, vy = -sina, cosa
    local inner = MELEE_INNER_DIST
    local outer = inner + range
    local midx = cx + ux * (inner + outer) * 0.5
    local midy = cy + uy * (inner + outer) * 0.5
    local hl = range * 0.5
    local ht = thick * 0.5
    local minx, maxx = math.huge, -math.huge
    local miny, maxy = math.huge, -math.huge
    for _, sgnl in ipairs({ -1, 1 }) do
        for _, sgnh in ipairs({ -1, 1 }) do
            local px = midx + ux * hl * sgnl + vx * ht * sgnh
            local py = midy + uy * hl * sgnl + vy * ht * sgnh
            minx = math.min(minx, px)
            maxx = math.max(maxx, px)
            miny = math.min(miny, py)
            maxy = math.max(maxy, py)
        end
    end
    return minx, miny, maxx - minx, maxy - miny
end

function Player:meleeAttack(aimX, aimY)
    local s = self:getEffectiveStats()
    if self.meleeCooldown > 0 or s.meleeDamage <= 0 then return false end
    local cx = self.x + self.w * 0.5
    local cy = self.y + self.h * 0.5
    if aimX ~= nil and aimY ~= nil then
        self.meleeAimAngle = math.atan2(aimY - cy, aimX - cx)
    else
        self.meleeAimAngle = self:getMeleeAimAngleLive()
    end
    self.meleeCooldown   = s.meleeCooldown
    self.meleeSwingTimer = 0.15
    self.meleeHitEnemies = {}
    return true
end

-- Hit / preview AABB: locked aim while swinging, otherwise live aim (cursor / facing).
function Player:getMeleeHitbox()
    local ang = self.meleeSwingTimer > 0 and self.meleeAimAngle or self:getMeleeAimAngleLive()
    return self:getMeleeHitboxAABB(ang)
end

-- Center, rotation, size for drawing the swipe (world space).
function Player:getMeleeSwingDrawParams()
    local s = self:getEffectiveStats()
    local range = s.meleeRange
    local thick = MELEE_HIT_THICKNESS
    local angle = self.meleeSwingTimer > 0 and self.meleeAimAngle or self:getMeleeAimAngleLive()
    local cx, cy = self.x + self.w * 0.5, self.y + self.h * 0.5
    local inner = MELEE_INNER_DIST
    local midAlong = inner + range * 0.5
    local midx = cx + math.cos(angle) * midAlong
    local midy = cy + math.sin(angle) * midAlong
    return midx, midy, angle, range, thick
end

function Player:reload()
    if self.reloading then return end
    if self.ammo >= self:getEffectiveStats().cylinderSize then return end
    self.reloading = true
    self.reloadTimer = self:getEffectiveStats().reloadSpeed
end

function Player:takeDamage(amount)
    if self.iframes > 0 then return false end

    local es = self:getEffectiveStats()

    -- Blocking absorbs a fraction of incoming damage (default shield has blockReduction from gear)
    if self.blocking and (es.blockReduction or 0) > 0 then
        amount = math.max(1, math.floor(amount * (1 - es.blockReduction)))
    end

    local finalDamage = math.max(1, amount - es.armor)
    self.hp = self.hp - finalDamage
    self.iframes = 0.5

    if debugLog then
        local suffix = self.blocking and " [blocked]" or ""
        debugLog(string.format("Took %d dmg  HP %d→%d%s", finalDamage, self.hp + finalDamage, self.hp, suffix))
    end

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
    -- Pickups use distance collection only; resolving them in bump causes snagging when
    -- loot spawns on the player or they jump through the drop point.
    if other.isPickup then
        return nil
    end
    if other.isEnemy or other.isBullet or other.isDoor then
        return nil
    end
    if other.isWall then
        return "slide"
    end
    if other.isPlatform then
        if other.oneWay and item.dropThroughTimer > 0 then
            return nil
        end
        if PlatformCollision.shouldPassThroughOneWay(item, other) then
            return nil
        end
        return "slide"
    end
    return "slide"
end

function Player:draw()
    local t = love.timer.getTime()
    -- Smash-style energy bubble while blocking (drawn behind the fighter)
    if self.blocking and self.gear.shield then
        local cx = self.x + self.w / 2
        local cy = self.y + self.h / 2
        local pulse = 0.65 + 0.35 * math.sin(t * 10)
        local rx, ry = 24, 30
        love.graphics.setColor(0.45, 0.7, 1.0, 0.22 * pulse)
        love.graphics.ellipse("fill", cx, cy, rx, ry)
        love.graphics.setColor(0.65, 0.88, 1.0, 0.55 * pulse)
        love.graphics.setLineWidth(2)
        love.graphics.ellipse("line", cx, cy, rx, ry)
        love.graphics.setLineWidth(1)
        -- Hex-ish highlight (second thin ring)
        love.graphics.setColor(0.85, 0.95, 1.0, 0.25 * pulse)
        love.graphics.ellipse("line", cx, cy, rx * 0.88, ry * 0.88)
    end

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

    -- Gun (right hand side)
    love.graphics.setColor(0.3, 0.3, 0.3)
    if self.facingRight then
        love.graphics.rectangle("fill", self.x + self.w, self.y + 10, 8, 3)
    else
        love.graphics.rectangle("fill", self.x - 8, self.y + 10, 8, 3)
    end

    -- Shield (off-hand, opposite to gun) — drawn as a small coloured square
    if self.gear.shield then
        if self.blocking then
            love.graphics.setColor(0.4, 0.6, 1.0)  -- bright blue when active
        else
            love.graphics.setColor(0.5, 0.4, 0.2)  -- wood brown at rest
        end
        if self.facingRight then
            love.graphics.rectangle("fill", self.x - 6, self.y + 8, 6, 14)
        else
            love.graphics.rectangle("fill", self.x + self.w, self.y + 8, 6, 14)
        end
    end

    -- Dagger (idle; during swing the swipe rect reads as the blade)
    if self.gear.melee and self.meleeSwingTimer <= 0 then
        love.graphics.setColor(0.7, 0.7, 0.8)
        if self.facingRight then
            love.graphics.rectangle("fill", self.x + self.w, self.y + 16, 10, 2)
        else
            love.graphics.rectangle("fill", self.x - 10, self.y + 16, 10, 2)
        end
    end

    -- Melee swipe (oriented like gun fire direction)
    if self.meleeSwingTimer > 0 then
        local midx, midy, angle, range, thick = self:getMeleeSwingDrawParams()
        local alpha = self.meleeSwingTimer / 0.15
        love.graphics.push()
        love.graphics.translate(midx, midy)
        love.graphics.rotate(angle)
        love.graphics.setColor(1, 0.9, 0.3, alpha * 0.5)
        love.graphics.rectangle("fill", -range * 0.5, -thick * 0.5, range, thick)
        love.graphics.setColor(1, 0.9, 0.3, alpha)
        love.graphics.rectangle("line", -range * 0.5, -thick * 0.5, range, thick)
        love.graphics.setLineWidth(2)
        love.graphics.setColor(1, 1, 0.85, alpha * 0.9)
        love.graphics.line(-range * 0.5, 0, range * 0.5, 0)
        love.graphics.line(-range * 0.5 + 4, -thick * 0.45, range * 0.5 - 4, thick * 0.45)
        love.graphics.setLineWidth(1)
        love.graphics.pop()
    end
    if self.meleeHitFlashTimer > 0 then
        local f = self.meleeHitFlashTimer / 0.2
        love.graphics.setColor(1, 0.35, 0.15, 0.45 * f)
        love.graphics.rectangle("fill", self.x - 4, self.y - 4, self.w + 8, self.h + 8)
    end

    love.graphics.setColor(1, 1, 1)
end

return Player
