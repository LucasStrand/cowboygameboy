local Weapons = require("src.data.weapons")
local Guns    = require("src.data.guns")
local PlatformCollision = require("src.systems.platform_collision")
local Animator = require("src.systems.animation")
local Keybinds = require("src.systems.keybinds")
local Sfx = require("src.systems.sfx")
local DropShadow = require("src.ui.drop_shadow")

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

-- Original player base gun stats — used to compute perk deltas when a
-- non-default weapon is equipped.  These MUST match the values in Player.new().
local PLAYER_BASE_GUN_STATS = {
    cylinderSize  = 6,
    reloadSpeed   = 1.2,
    bulletSpeed   = 500,
    bulletDamage  = 10,
    bulletCount   = 1,
    spreadAngle   = 0,
}

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
        akimbo = false,
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

    -- Weapon slots: [1] = primary (always ranged), [2] = secondary (ranged or nil for melee)
    self.weapons = {
        [1] = { gun = Guns.default, ammo = Guns.default.baseStats.cylinderSize,
                reloading = false, reloadTimer = 0, shootCooldown = 0 },
        [2] = nil,  -- nil = melee/shield mode (legacy)
    }
    self.activeWeaponSlot = 1

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

--- Returns the gun definition for the active weapon slot, or nil if melee.
function Player:getActiveGun()
    local slot = self.weapons[self.activeWeaponSlot]
    return slot and slot.gun or nil
end

--- Returns the gun definition for the off-hand weapon slot, or nil.
function Player:getOffhandGun()
    local otherSlot = self.activeWeaponSlot == 1 and 2 or 1
    local slot = self.weapons[otherSlot]
    return slot and slot.gun or nil
end

--- True when akimbo perk is active AND both slots have ranged weapons.
function Player:isAkimbo()
    return self.stats.akimbo and self.weapons[1] and self.weapons[1].gun
           and self.weapons[2] and self.weapons[2].gun
end

function Player:getEffectiveStats()
    return self:getEffectiveStatsForGun(self:getActiveGun())
end

--- Combat stats for a specific gun (perk deltas applied to that weapon's base), like melee coexisting with gun.
function Player:getEffectiveStatsForGun(gun)
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

    if gun then
        for stat, baseDefault in pairs(PLAYER_BASE_GUN_STATS) do
            local perkDelta = self.stats[stat] - baseDefault
            s[stat] = gun.baseStats[stat] + perkDelta
        end
        s.shootCooldown = gun.baseStats.shootCooldown
        s.inaccuracy    = gun.baseStats.inaccuracy or 0
    else
        s.shootCooldown = 0.38
        s.inaccuracy    = 0
    end

    return s
end

--- True if any ranged slot can fire (for akimbo auto-fire; each gun has its own cadence).
function Player:canAnyAkimboGunFire()
    for i = 1, 2 do
        local w = self.weapons[i]
        if w and w.gun and w.ammo > 0 and not w.reloading and (w.shootCooldown or 0) <= 0 then
            return true
        end
    end
    return false
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

    -- Shoot cooldown + reload: akimbo = each slot independent (like melee + gun); else mirror active slot on self
    if self:isAkimbo() then
        for i = 1, 2 do
            local w = self.weapons[i]
            if w and w.gun then
                if (w.shootCooldown or 0) > 0 then
                    w.shootCooldown = w.shootCooldown - dt
                end
                if w.reloading then
                    w.reloadTimer = w.reloadTimer - dt
                    if w.reloadTimer <= 0 then
                        w.reloading = false
                        local gunBase = w.gun.baseStats.cylinderSize
                        local perkDelta = self.stats.cylinderSize - PLAYER_BASE_GUN_STATS.cylinderSize
                        w.ammo = gunBase + perkDelta
                        w.reloadTimer = 0
                        if i == self.activeWeaponSlot and self.stats.deadEye then
                            self.deadEyeTimer = 3.0
                        end
                    end
                end
            end
        end
        local a = self.weapons[self.activeWeaponSlot]
        if a then
            self.ammo = a.ammo
            self.reloading = a.reloading
            self.reloadTimer = a.reloadTimer
            self.shootCooldown = a.shootCooldown or 0
        end
    else
        if self.shootCooldown > 0 then
            self.shootCooldown = self.shootCooldown - dt
        end
        local slot = self.weapons[self.activeWeaponSlot]
        if slot then slot.shootCooldown = self.shootCooldown end
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

    -- Reload (active slot only; akimbo slots tick above)
    if not self:isAkimbo() and self.reloading then
        self.reloadTimer = self.reloadTimer - dt
        if self.reloadTimer <= 0 then
            self.reloading = false
            self.ammo = effectiveStats.cylinderSize
            Sfx.play("reload")
            if self.stats.deadEye then
                self.deadEyeTimer = 3.0
            end
            local slot = self.weapons[self.activeWeaponSlot]
            if slot then
                slot.ammo = self.ammo
                slot.reloading = false
                slot.reloadTimer = 0
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

--- Fire one weapon slot (each gun has its own cooldown, damage, and reload — akimbo works like gun + melee coexistence).
function Player:shootFromSlot(slotIndex, mx, my)
    local slot = self.weapons[slotIndex]
    if not slot or not slot.gun then return nil end
    if slot.reloading or (slot.shootCooldown or 0) > 0 then return nil end
    if slot.ammo <= 0 then
        self:startReloadSlot(slotIndex)
        return nil
    end

    local gun = slot.gun
    local effectiveStats = self:getEffectiveStatsForGun(gun)

    slot.ammo = slot.ammo - 1
    slot.shootCooldown = gun.baseStats.shootCooldown

    if slotIndex == self.activeWeaponSlot then
        self.ammo = slot.ammo
        self.shootCooldown = slot.shootCooldown
    end

    if not self:isAkimbo() then
        self.anim:play("shoot", true)
    end

    local cx = self.x + self.w / 2
    local cy = self.y + self.h / 2
    local angle = math.atan2(my - cy, mx - cx)

    local inacc = effectiveStats.inaccuracy or 0
    if inacc > 0 then
        angle = angle + (math.random() - 0.5) * 2 * inacc
    end

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

    if gun.onShoot then
        gun.onShoot(self, angle)
    end

    if slot.ammo <= 0 then
        self:startReloadSlot(slotIndex)
    end

    if slotIndex == self.activeWeaponSlot then
        self.ammo = slot.ammo
        self.reloading = slot.reloading
        self.reloadTimer = slot.reloadTimer
        self.shootCooldown = slot.shootCooldown
    end

    return bullets
end

function Player:shoot(mx, my)
    if self:isAkimbo() then
        local allBullets = {}
        local any = false
        for i = 1, 2 do
            local b = self:shootFromSlot(i, mx, my)
            if b then
                any = true
                for _, b2 in ipairs(b) do
                    table.insert(allBullets, b2)
                end
            end
        end
        if any then
            self.anim:play("shoot", true)
        end
        return #allBullets > 0 and allBullets or nil
    end
    return self:shootFromSlot(self.activeWeaponSlot, mx, my)
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

--- Start reload for one weapon slot (akimbo: each gun reloads on its own timeline).
function Player:startReloadSlot(slotIndex)
    local slot = self.weapons[slotIndex]
    if not slot or not slot.gun then return end
    if slot.reloading then return end
    local perkDelta = self.stats.cylinderSize - PLAYER_BASE_GUN_STATS.cylinderSize
    local cap = slot.gun.baseStats.cylinderSize + perkDelta
    if slot.ammo >= cap then return end
    local reloadDelta = self.stats.reloadSpeed - PLAYER_BASE_GUN_STATS.reloadSpeed
    slot.reloading = true
    slot.reloadTimer = slot.gun.baseStats.reloadSpeed + reloadDelta
    if slotIndex == self.activeWeaponSlot then
        self.reloading = true
        self.reloadTimer = slot.reloadTimer
        self.anim:play("holster_spin", true)
    end
end

function Player:reload()
    if self.reloading then return end
    if not self:getActiveGun() then return end
    if self.ammo >= self:getEffectiveStats().cylinderSize then return end
    self:startReloadSlot(self.activeWeaponSlot)
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

--- Save active slot state from live fields, then restore the target slot.
function Player:switchWeapon()
    -- Save current slot state
    local cur = self.weapons[self.activeWeaponSlot]
    if cur then
        cur.ammo         = self.ammo
        cur.reloading    = self.reloading
        cur.reloadTimer  = self.reloadTimer
        cur.shootCooldown = self.shootCooldown
    end

    -- Toggle between slot 1 and 2
    local newSlot = self.activeWeaponSlot == 1 and 2 or 1
    local target = self.weapons[newSlot]
    if not target then return end  -- slot 2 has no ranged weapon

    -- Cancel any active reload on old weapon
    if self.reloading then
        -- Keep reload progress saved in the slot (resume later)
    end

    self.activeWeaponSlot = newSlot

    -- Restore new slot state
    self.ammo          = target.ammo
    self.reloading     = target.reloading
    self.reloadTimer   = target.reloadTimer
    self.shootCooldown = target.shootCooldown

    -- Visual feedback
    self.anim:play("holster", true)
end

--- Equip a gun definition into a weapon slot (1 or 2). Resets ammo to full.
--- Auto-switches to the new weapon slot for immediate feedback.
function Player:equipWeapon(gunDef, slotIndex)
    slotIndex = slotIndex or 2

    -- Save current active slot state before switching
    local curSlot = self.weapons[self.activeWeaponSlot]
    if curSlot then
        curSlot.ammo         = self.ammo
        curSlot.reloading    = self.reloading
        curSlot.reloadTimer  = self.reloadTimer
        curSlot.shootCooldown = self.shootCooldown
    end

    self.weapons[slotIndex] = {
        gun          = gunDef,
        ammo         = gunDef.baseStats.cylinderSize,
        reloading    = false,
        reloadTimer  = 0,
        shootCooldown = 0,
    }

    -- Auto-switch to the newly equipped weapon
    self.activeWeaponSlot = slotIndex
    self.ammo         = gunDef.baseStats.cylinderSize
    self.reloading    = false
    self.reloadTimer  = 0
    self.shootCooldown = 0

    -- If equipping a ranged weapon to any slot that previously held melee, remove melee gear
    self.gear.melee = nil
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
    local function drawReloadBar(bx, by, bw, bh, pct, r, g, b)
        love.graphics.setColor(0, 0, 0, 0.28)
        love.graphics.rectangle("fill", bx - 1, by - 1, bw + 2, bh + 2)
        love.graphics.setColor(0.2, 0.18, 0.16, 0.45)
        love.graphics.rectangle("fill", bx, by, bw, bh)
        love.graphics.setColor(r or 0.42, g or 0.36, b or 0.26, 0.55)
        love.graphics.rectangle("fill", bx, by, bw * pct, bh)
        love.graphics.setColor(0.65, 0.58, 0.42, 0.35)
        love.graphics.rectangle("line", bx, by, bw, bh)
        love.graphics.setColor(1, 1, 1)
    end

    if not self.dying then
        local bw, bh = 48, 3
        local barX = self.x + self.w * 0.5 - bw * 0.5
        local barY = self.y - 16

        if self:isAkimbo() then
            local offY = barY
            for i = 1, 2 do
                local w = self.weapons[i]
                if w and w.gun and w.reloading then
                    local reloadDelta = self.stats.reloadSpeed - PLAYER_BASE_GUN_STATS.reloadSpeed
                    local total = w.gun.baseStats.reloadSpeed + reloadDelta
                    local pct = (total > 0) and (1 - w.reloadTimer / total) or 1
                    pct = math.max(0, math.min(1, pct))
                    local r, g, b = 0.42, 0.36, 0.26
                    if i == 2 then r, g, b = 0.35, 0.45, 0.55 end
                    drawReloadBar(barX, offY, bw, bh, pct, r, g, b)
                    offY = offY - 6
                end
            end
        elseif self.reloading then
            local es = self:getEffectiveStats()
            local total = es.reloadSpeed
            local pct = (total > 0) and (1 - self.reloadTimer / total) or 1
            pct = math.max(0, math.min(1, pct))
            drawReloadBar(barX, barY, bw, bh, pct)
        end
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

    -- Ground shadow (same visibility as sprite)
    do
        local scx = self.x + self.w / 2
        local footY = self.y + self.h
        local sRx, sRy, sA = self.w * 0.42, 5, 0.3
        if self.dying then
            local u = math.min(1, self.deathTimer / Player.DEATH_DURATION)
            local ease = 1 - math.cos(u * math.pi * 0.5)
            sA = sA * (1 - u * 0.5)
            sRx = sRx * (1 - ease * 0.25)
            sRy = sRy * (1 - ease * 0.2)
        end
        DropShadow.drawEllipse(scx, footY, sRx, sRy, sA)
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

    -- Weapon sprite overlay (draw equipped gun on top of cowboy)
    if not self.dying then
        local aimAngle = self:getAimAngle()
        local handX = cx + (self.facingRight and 2 or -2)
        local baseHandY = self.y + self.h * 0.42

        local function drawGunSprite(gun, yOff)
            if gun.id == "revolver" then return end  -- cowboy animation already has a revolver
            local sprite = Guns.getSprite(gun)
            if not sprite then return end
            local scale = gun.spriteScale or 0.7
            local origin = gun.spriteOrigin or { x = 0.25, y = 0.5 }
            local sw, sh = sprite:getDimensions()
            local ox = sw * origin.x
            local oy = sh * origin.y
            local sy = scale
            if not self.facingRight then sy = -scale end
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(sprite, handX, baseHandY + yOff, aimAngle, scale, sy, ox, oy)
        end

        if self:isAkimbo() then
            -- Draw both weapons offset vertically
            local gun1 = self.weapons[1] and self.weapons[1].gun
            local gun2 = self.weapons[2] and self.weapons[2].gun
            if gun1 then drawGunSprite(gun1, -4) end
            if gun2 then drawGunSprite(gun2, 4) end
        else
            local gun = self:getActiveGun()
            if gun then drawGunSprite(gun, 0) end
        end
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
