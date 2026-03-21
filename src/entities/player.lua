local Weapons = require("src.data.weapons")
local PlatformCollision = require("src.systems.platform_collision")
local Animator = require("src.systems.animation")
local Keybinds = require("src.systems.keybinds")
local Sfx = require("src.systems.sfx")

local Player = {}
Player.__index = Player

-- Seconds of collapse animation before game over
Player.DEATH_DURATION = 0.95

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

-- Face sprite toward horizontal aim; small deadzone only when aim is ~through torso
local AIM_FACE_DEADZONE = 3

-- Head/gun draw: turn relative to body forward so we never flip the cowboy upside down
local MAX_HEAD_TURN = 1.32 -- ~75° each way from facing

local function angleWrapPi(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

local function angleDiff(a, b)
    return angleWrapPi(a - b)
end

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
        -- Distance at which pickups on the ground start moving toward the player
        pickupRadius = 20,
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

    -- Set in game state: cursor aim, auto-target, or cursor fallback — drives gun/head angle + crosshair.
    self.effectiveAimX = nil
    self.effectiveAimY = nil
    -- While > love.timer.getTime(), shooting uses mouse aim instead of findAutoTarget.
    self.mouseAimOverrideUntil = 0
    -- Set each frame in game: true = ignore cursor for aim/facing (WASD + auto after mouse idle)
    self.keyboardAimMode = true

    -- Loadout automation (toggled via HUD right-click). Auto gun + mouse overrides aim while active.
    -- Shield auto-block only applies when equipped shield has stats.allowAutoBlock.
    self.autoGun   = true
    self.autoMelee = true
    self.autoBlock = false

    self.perks = {}

    -- Sprite animation
    self.anim = Animator.new()
    self.idleTimer = 0          -- seconds standing still, triggers smoking idle

    self.dying = false
    self.deathTimer = 0

    -- Dev panel (game.lua): when true, :takeDamage ignores hits
    self.devGodMode = false

    return self
end

function Player:beginDeath()
    if self.dying then return end
    self.hp = 0
    self.dying = true
    self.deathTimer = 0
    self.vx = 0
    self.vy = 0
    self.blocking = false
    self.meleeSwingTimer = 0
    self.anim:play("fall", true)
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
    if self.dying then
        self.deathTimer = self.deathTimer + dt
        self.anim:update(dt)
        return
    end

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

    -- Blocking: bound key (default Ctrl). Auto-block only if this shield supports it (gear stat) and HUD toggle is on.
    local keysBlock = Keybinds.isBlockDown()
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
    self.crouching = love.keyboard.isDown("down") or Keybinds.isDown("drop")

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
            Sfx.play("reload")
            if self.stats.deadEye then
                self.deadEyeTimer = 3.0
            end
        end
    end

    if blockRooted then
        self.dashTimer = 0
    end

    -- Horizontal movement (dash overrides walk; rooted block = no move)
    local moveLeft = love.keyboard.isDown("a") or love.keyboard.isDown("left")
    local moveRight = love.keyboard.isDown("d") or love.keyboard.isDown("right")
    if self.dashTimer > 0 and not blockRooted then
        self.vx = self.dashDir * DASH_SPEED
    elseif blockRooted then
        self.vx = 0
    else
        self.vx = 0
        if moveLeft then
            self.vx = self.vx - effectiveStats.moveSpeed
        end
        if moveRight then
            self.vx = self.vx + effectiveStats.moveSpeed
        end
    end

    -- Facing: mouse-aim mode uses horizontal aim; keyboard mode uses WASD / move / dash only
    do
        if self.keyboardAimMode then
            if moveRight and not moveLeft then
                self.facingRight = true
            elseif moveLeft and not moveRight then
                self.facingRight = false
            elseif self.dashTimer > 0 and not blockRooted then
                self.facingRight = self.dashDir > 0
            elseif self.vx ~= 0 then
                self.facingRight = self.vx > 0
            end
        else
            local cx = self.x + self.w * 0.5
            local ax = self.effectiveAimX or self.aimWorldX or cx
            local aimDx = ax - cx
            if math.abs(aimDx) > AIM_FACE_DEADZONE then
                self.facingRight = aimDx > 0
            elseif self.dashTimer > 0 and not blockRooted then
                self.facingRight = self.dashDir > 0
            elseif self.vx ~= 0 then
                self.facingRight = self.vx > 0
            elseif moveRight and not moveLeft then
                self.facingRight = true
            elseif moveLeft and not moveRight then
                self.facingRight = false
            end
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
        local jHeld = Keybinds.isDown("jump") or love.keyboard.isDown("w") or love.keyboard.isDown("up")
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
            Sfx.play("jump")
        elseif self.jumpCount == 1 then
            self.vy = effectiveStats.jumpForce * DOUBLE_JUMP_MULT
            self.jumpBufferTimer = 0
            self.jumpCount = 2
            Sfx.play("jump")
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

    -- Animation state machine (priority: one-shots > air > ground movement)
    local anim = self.anim
    anim:update(dt)
    -- Chain: shoot → holster before returning to idle
    if anim.current == "shoot" and anim.done then
        anim:play("holster", true)
    end
    local oneShotPlaying = (anim.current == "shoot" or anim.current == "melee"
                            or anim.current == "holster" or anim.current == "holster_spin") and not anim.done
    if not oneShotPlaying then
        if self.dashTimer > 0 then
            anim:play("dash")
            self.idleTimer = 0
        elseif not self.grounded then
            if self.vy < 0 then anim:play("jump") else anim:play("fall") end
            self.idleTimer = 0
        elseif math.abs(self.vx) > 10 then
            anim:play("run")
            self.idleTimer = 0
        else
            -- Idle: after 3 seconds of standing still, transition to smoking
            self.idleTimer = self.idleTimer + dt
            if self.idleTimer >= 3 then
                anim:play("smoking")
            else
                anim:play("idle")
            end
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
    Sfx.play("dash")

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
    self.anim:play("shoot", true)

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
    Sfx.play("shoot")

    if self.ammo <= 0 then
        self:reload()
    end

    return bullets
end

--- World angle (radians) from body center toward effective aim (auto target or cursor).
function Player:getAimAngle()
    local cx = self.x + self.w * 0.5
    local cy = self.y + self.h * 0.5
    local ax = self.effectiveAimX
    local ay = self.effectiveAimY
    if ax == nil or ay == nil then
        ax = self.aimWorldX
        ay = self.aimWorldY
    end
    if ax and ay then
        return math.atan2(ay - cy, ax - cx)
    end
    return self.facingRight and 0 or math.pi
end

--- Tilt (radians) for head + gun vs body forward. Use with translate + optional scale(-1,1) — never rotate(π) or hat flips under the body.
function Player:getHeadGunTilt()
    local worldAim = self:getAimAngle()
    local bodyAng = self.facingRight and 0 or math.pi
    local rel = angleDiff(worldAim, bodyAng)
    return math.max(-MAX_HEAD_TURN, math.min(MAX_HEAD_TURN, rel))
end

--- Aim direction for melee when not locked into a swing (mouse world aim, else facing).
function Player:getMeleeAimAngleLive()
    return self:getAimAngle()
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

function Player:spinHolster()
    local anim = self.anim
    -- Only play if no one-shot animation is active
    local busy = (anim.current == "shoot" or anim.current == "melee"
                  or anim.current == "holster" or anim.current == "holster_spin") and not anim.done
    if busy then return end
    anim:play("holster_spin", true)
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
    self.anim:play("melee", true)
    Sfx.play("melee_swing")
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
    self.anim:play("holster_spin", true)
end

--- Dead Eye ult (same duration as post-reload proc); only if Dead Eye perk is active.
function Player:tryActivateUlt()
    if self.dying then return end
    if not self:getEffectiveStats().deadEye then return end
    self.deadEyeTimer = 3.0
end

function Player:takeDamage(amount)
    if self.dying then return false end
    if self.devGodMode then return false end
    if self.iframes > 0 then return false end

    local es = self:getEffectiveStats()

    -- Blocking absorbs a fraction of incoming damage (default shield has blockReduction from gear)
    if self.blocking and (es.blockReduction or 0) > 0 then
        amount = math.max(1, math.floor(amount * (1 - es.blockReduction)))
    end

    local finalDamage = math.max(1, amount - es.armor)
    self.hp = self.hp - finalDamage
    self.iframes = 0.5
    Sfx.play("hurt")

    if debugLog then
        local suffix = self.blocking and " [blocked]" or ""
        debugLog(string.format("Took %d dmg  HP %d→%d%s", finalDamage, self.hp + finalDamage, self.hp, suffix))
    end

    if self.hp <= 0 then
        self:beginDeath()
    end

    return true, finalDamage
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
    -- Reload progress: thin bar above the cowboy (world space)
    if not self.dying and self.reloading then
        local es = self:getEffectiveStats()
        local total = es.reloadSpeed
        local pct = (total > 0) and (1 - self.reloadTimer / total) or 1
        pct = math.max(0, math.min(1, pct))
        local bw, bh = 48, 3
        local bx = self.x + self.w * 0.5 - bw * 0.5
        local by = self.y - 16
        love.graphics.setColor(0, 0, 0, 0.28)
        love.graphics.rectangle("fill", bx - 1, by - 1, bw + 2, bh + 2)
        love.graphics.setColor(0.2, 0.18, 0.16, 0.45)
        love.graphics.rectangle("fill", bx, by, bw, bh)
        love.graphics.setColor(0.42, 0.36, 0.26, 0.55)
        love.graphics.rectangle("fill", bx, by, bw * pct, bh)
        love.graphics.setColor(0.65, 0.58, 0.42, 0.35)
        love.graphics.rectangle("line", bx, by, bw, bh)
        love.graphics.setColor(1, 1, 1)
    end

    local t = love.timer.getTime()
    -- Smash-style energy bubble while blocking (drawn behind the fighter)
    if not self.dying and self.blocking and self.gear.shield then
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
    if not self.dying and self.iframes > 0 and math.floor(self.iframes * 10) % 2 == 0 then
        return
    end

    -- Sprite (replaces body, hat, eyes, gun placeholders)
    local cx = self.x + self.w / 2
    local footY = self.y + self.h
    if self.dying then
        local u = math.min(1, self.deathTimer / Player.DEATH_DURATION)
        local ease = 1 - math.cos(u * math.pi * 0.5)
        local ang = (self.facingRight and -1 or 1) * math.rad(82) * ease
        local sink = 3 * ease
        local alpha = 1 - u * 0.35
        love.graphics.push()
        love.graphics.translate(cx, footY + sink)
        love.graphics.rotate(ang)
        love.graphics.translate(-cx, -(footY + sink))
        self.anim:drawCentered(cx, footY, self.facingRight, 0, alpha)
        love.graphics.pop()
    else
        self.anim:drawCentered(cx, footY, self.facingRight)
    end


    -- Melee swipe (oriented like gun fire direction)
    if not self.dying and self.meleeSwingTimer > 0 then
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
