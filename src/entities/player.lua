local Weapons = require("src.data.weapons")
local Guns    = require("src.data.guns")
local PlatformCollision = require("src.systems.platform_collision")
local Animator = require("src.systems.animation")
local Keybinds = require("src.systems.keybinds")
local Sfx = require("src.systems.sfx")
local ImpactFX = require("src.systems.impact_fx")
local GearIcons = require("src.ui.gear_icons")
local Font = require("src.ui.font")
local Buffs = require("src.systems.buffs")
local DamagePacket = require("src.systems.damage_packet")
local DamageResolver = require("src.systems.damage_resolver")
local GameRng = require("src.systems.game_rng")
local RunMetadata = require("src.systems.run_metadata")
local SourceRef = require("src.systems.source_ref")
local StatRuntime = require("src.systems.stat_runtime")
local WeaponRuntime = require("src.systems.weapon_runtime")
local Perks = require("src.data.perks")

-- Monster Energy (saloon): each drink heals to full; walk-speed bonus stacks with diminishing returns.
local MONSTER_MOVE_FIRST = 44
local MONSTER_MOVE_DECAY = 0.71
-- Jitter never rolls on the 1st drink; from the 2nd on, chance and shake ramp up.
local MONSTER_JITTER_BASE_CHANCE = 0.06
local MONSTER_JITTER_PER_DRINK = 0.11
local MONSTER_JITTER_CAP = 0.78
local MONSTER_SPEECH_CHANCE = 0.42
local MONSTER_SPEECH_DURATION = 3.0

local MONSTER_SPEECH_LINES = {
    "Woo.",
    "That ain't bourbon.",
    "I can see next week.",
    "My spurs won't stop.",
    "Tastes like a stampede.",
    "Ride the lightning.",
    "The saloon's spinni'.",
    "Heart's drummin' double-time.",
    "Yee— never mind.",
    "One more ridge to climb.",
    "Liquid outlaw.",
    "My hat shrunk.",
}

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
-- Melee swing: hit window + held dagger overlay (longer than melee anim tail so knife stays visible)
local MELEE_SWING_DURATION = 0.30
local DASH_MELEE_SWING_DURATION = 0.26  -- dash strike: linger past dash motion so dagger doesn’t vanish instantly

-- Original player base gun stats — used to compute perk deltas when a
-- non-default weapon is equipped.  These MUST match the values in Player.new().
local PLAYER_BASE_GUN_STATS = {
    cylinderSize  = 6,
    reloadSpeed   = 1.2,
    bulletSpeed   = 720,
    bulletDamage  = 10,
    bulletCount   = 1,
    spreadAngle   = 0,
}

-- Face sprite toward horizontal aim; small deadzone only when aim is ~through torso
local AIM_FACE_DEADZONE = 3

-- Head/gun draw: turn relative to body forward so we never flip the cowboy upside down
local MAX_HEAD_TURN = 1.32 -- ~75° each way from facing

local STAT_RUNTIME_COMPARE_KEYS = {
    "maxHP",
    "moveSpeed",
    "damageMultiplier",
    "armor",
    "luck",
    "pickupRadius",
    "reloadSpeed",
    "cylinderSize",
    "bulletSpeed",
    "bulletDamage",
    "bulletCount",
    "spreadAngle",
    "lifestealOnKill",
    "ricochetCount",
    "meleeDamage",
    "meleeRange",
    "meleeCooldown",
    "meleeKnockback",
    "blockReduction",
    "blockMobility",
    "shootCooldown",
    "inaccuracy",
}

local function angleWrapPi(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

local function angleDiff(a, b)
    return angleWrapPi(a - b)
end

local function weaponSourceRef(player, slotIndex, gun, parent_source_id)
    return SourceRef.new({
        owner_actor_id = player.actorId or "player",
        owner_source_type = slotIndex and "weapon_slot" or "player",
        owner_source_id = gun and gun.id or ("slot_" .. tostring(slotIndex or player.activeWeaponSlot or 1)),
        parent_source_id = parent_source_id,
    })
end

local function compareStatRuntime(player, gun, live_stats)
    if not DEBUG or not debugLog then
        return
    end

    local ctx = StatRuntime.build_player_context(player, gun, PLAYER_BASE_GUN_STATS)
    local computed = StatRuntime.compute_actor_stats(ctx)
    local exported = StatRuntime.export_legacy_stats(computed)
    player._statRuntimeMismatchCache = player._statRuntimeMismatchCache or {}
    local cacheKey = gun and gun.id or "melee"
    player._statRuntimeMismatchCache[cacheKey] = player._statRuntimeMismatchCache[cacheKey] or {}

    for _, key in ipairs(STAT_RUNTIME_COMPARE_KEYS) do
        local live = live_stats[key]
        local next_value = exported[key]
        if live ~= nil and next_value ~= nil then
            local mismatch = tostring(live) .. "!=" .. tostring(next_value)
            if live ~= next_value and player._statRuntimeMismatchCache[cacheKey][key] ~= mismatch then
                player._statRuntimeMismatchCache[cacheKey][key] = mismatch
                debugLog(string.format("[stat_runtime] %s mismatch for %s: live=%s runtime=%s", cacheKey, key, tostring(live), tostring(next_value)))
            end
        end
    end
end

function Player.new(x, y)
    local self = setmetatable({}, Player)
    self.actorId = "player"
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
    self.combatDisabled = false

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
        bulletSpeed = 720,
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

    self.baseGunStats = PLAYER_BASE_GUN_STATS
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

    -- Ultimate: Dead Man's Hand
    self.ultCharge = 0           -- 0..1, fills by killing enemies
    self.ultChargePerKill = 0.1  -- 10 kills = full charge
    self.ultActive = false       -- true during barrage
    self.ultPhase = "none"       -- "none", "barrage", "cooldown"
    self.ultTimer = 0
    self.ultTargets = {}         -- enemies marked for barrage
    self.ultShotIndex = 0        -- which target we're firing at next
    self.ultShotTimer = 0        -- delay between barrage shots

    self.gear = {
        hat    = nil,
        vest   = nil,
        boots  = nil,
        melee  = Weapons.defaults.melee,
        shield = Weapons.defaults.shield,
    }

    self.weapons = {}
    self.activeWeaponSlot = 1
    WeaponRuntime.initPlayerLoadout(self, Guns.default, nil)

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

    -- Shared status runtime for player buffs/debuffs and control-state.
    self.statuses = Buffs.newTracker({
        owner_actor_id = self.actorId,
    }, {
        owner_actor = self,
        owner_actor_id = self.actorId,
        owner_kind = "player",
        cc_profile = "normal",
    })

    -- Monster Energy (saloon): cumulative drinks this run — move bonus + rare speech / visual jitter
    self.monsterDrinks = 0
    self.monsterMoveBonus = 0
    self.monsterJitteryTimer = 0
    self.monsterJitterShakeMul = 0
    self.monsterSpeechText = nil
    self.monsterSpeechLife = 0
    self._monsterSpeechFont = nil

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

function Player:getWeaponRuntime(slotIndex)
    return WeaponRuntime.getSlot(self, slotIndex)
end

function Player:getActiveWeaponRuntime()
    return WeaponRuntime.getActiveSlot(self)
end

function Player:getResolvedWeaponStats(slotIndex)
    return WeaponRuntime.getResolvedStats(self, slotIndex)
end

function Player:getActiveSlotMode()
    local slot = self:getActiveWeaponRuntime()
    return slot and slot.mode or "melee"
end

function Player:addAmmoToSlot(slotIndex, amount, reason)
    return WeaponRuntime.addAmmo(self, slotIndex, amount, reason)
end

function Player:addAmmoToActiveSlot(amount, reason)
    return self:addAmmoToSlot(self.activeWeaponSlot, amount, reason)
end

function Player:syncLegacyWeaponViews()
    WeaponRuntime.syncLegacyViews(self)
end

function Player:debugDumpWeaponRuntime(reason)
    WeaponRuntime.debugDump(self, reason)
end

--- Returns the gun definition for the active weapon slot, or nil if melee.
function Player:getActiveGun()
    local slot = self:getActiveWeaponRuntime()
    return slot and slot.weapon_def or nil
end

--- Returns the gun definition for the off-hand weapon slot, or nil.
function Player:getOffhandGun()
    local otherSlot = self.activeWeaponSlot == 1 and 2 or 1
    local slot = self:getWeaponRuntime(otherSlot)
    return slot and slot.weapon_def or nil
end

--- Slot index for automatic gunfire: active slot when a gun is in hand; in melee stance, primary (1) then secondary.
function Player:getWeaponSlotForAutoFire()
    if self:getActiveSlotMode() == "weapon" then
        return self.activeWeaponSlot
    end
    local slot1 = self:getWeaponRuntime(1)
    local slot2 = self:getWeaponRuntime(2)
    if slot1 and slot1.mode == "weapon" then return 1 end
    if slot2 and slot2.mode == "weapon" then return 2 end
    return nil
end

--- True when akimbo perk is active AND both slots have ranged weapons.
function Player:isAkimbo()
    local slot1 = self:getWeaponRuntime(1)
    local slot2 = self:getWeaponRuntime(2)
    return self.stats.akimbo
        and slot1 and slot1.mode == "weapon"
        and slot2 and slot2.mode == "weapon"
end

function Player:getEffectiveStats()
    if self:getActiveSlotMode() == "weapon" then
        return self:getResolvedWeaponStats(self.activeWeaponSlot) or self:getEffectiveStatsForGun(self:getActiveGun())
    end
    return self:getEffectiveStatsForGun(nil)
end

--- Combat stats for a specific gun (perk deltas applied to that weapon's base), like melee coexisting with gun.
function Player:getEffectiveStatsForGun(gun)
    local resolved
    if gun then
        resolved = WeaponRuntime.getResolvedStatsForGun(self, gun)
    else
        local ctx = StatRuntime.build_player_context(self, nil, self.baseGunStats)
        local computed = StatRuntime.compute_actor_stats(ctx)
        resolved = StatRuntime.export_legacy_stats(computed)
    end

    compareStatRuntime(self, gun, resolved)
    return resolved
end

--- True if any ranged slot can fire (for akimbo auto-fire; each gun has its own cadence).
function Player:canAnyAkimboGunFire()
    for i = 1, 2 do
        local w = self:getWeaponRuntime(i)
        if w and w.mode == "weapon" and (w.ammo or 0) > 0 and (w.reload_timer or 0) <= 0 and (w.cooldown_timer or 0) <= 0 then
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

    -- I-frames
    if self.iframes > 0 then
        self.iframes = self.iframes - dt
    end

    -- Dead eye timer
    if self.deadEyeTimer > 0 then
        self.deadEyeTimer = self.deadEyeTimer - dt
    end

    if (self.monsterJitteryTimer or 0) > 0 then
        self.monsterJitteryTimer = math.max(0, self.monsterJitteryTimer - dt)
        if self.monsterJitteryTimer <= 0 then
            self.monsterJitterShakeMul = 0
        end
    end

    -- Update shared status runtime before movement/combat gates.
    Buffs.update(self.statuses, dt, {
        owner_actor = self,
        target_kind = "player",
        world = world,
    })
    if self.dying then
        self.deathTimer = self.deathTimer + dt
        self.anim:update(dt)
        return
    end
    local effectiveStats = self:getEffectiveStats()
    local control = Buffs.getControlState(self.statuses)

    if self.monsterSpeechText then
        self.monsterSpeechLife = (self.monsterSpeechLife or 0) + dt
        if self.monsterSpeechLife >= MONSTER_SPEECH_DURATION then
            self.monsterSpeechText = nil
            self.monsterSpeechLife = 0
        end
    end

    WeaponRuntime.tick(self, dt)

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

    local hardLocked = control.stunned
    local blockRooted = hardLocked or (self.blocking and effectiveStats.blockMobility <= 0)

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

    if blockRooted then
        self.dashTimer = 0
    end

    -- Horizontal movement (dash overrides walk; rooted block = no move)
    local moveLeft = love.keyboard.isDown("a") or love.keyboard.isDown("left")
    local moveRight = love.keyboard.isDown("d") or love.keyboard.isDown("right")
    if hardLocked then
        self.vx = 0
    elseif self.dashTimer > 0 and not blockRooted then
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
    if Buffs.getControlState(self.statuses).stunned then
        return
    end
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
    if self.combatDisabled then return end
    if Buffs.getControlState(self.statuses).stunned then return end
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
    if s.meleeDamage > 0 then
        self.meleeAimAngle  = dir == 1 and 0 or math.pi
        self.meleeSwingTimer = DASH_MELEE_SWING_DURATION
        self.meleeCooldown   = 0           -- dash resets cooldown so it always fires
        self.meleeHitEnemies = {}
        local cx = self.x + self.w * 0.5
        local cy = self.y + self.h * 0.5
        local a = self.meleeAimAngle
        local tip = 20
        ImpactFX.spawn(cx + math.cos(a) * tip, cy + math.sin(a) * tip, "melee", nil, a)
    end
end

--- Fire one weapon slot (each gun has its own cooldown, damage, and reload — akimbo works like gun + melee coexistence).
function Player:shootFromSlot(slotIndex, mx, my)
    if Buffs.getControlState(self.statuses).stunned then
        return nil
    end
    local fired = WeaponRuntime.fireSlot(self, slotIndex, mx, my)
    if not fired then return nil end

    if not self:isAkimbo() then
        self.anim:play("shoot", true)
    end
    Sfx.play("shoot")
    if fired.muzzle_fx_id then
        local cx = self.x + self.w * 0.5
        local cy = self.y + self.h * 0.5
        local tip = fired.weapon_def and fired.weapon_def.id == "blunderbuss" and 24 or 18
        ImpactFX.spawn(
            cx + math.cos(fired.angle) * tip,
            cy + math.sin(fired.angle) * tip,
            fired.muzzle_fx_id,
            {
                angle = fired.angle,
                scale_mul = fired.explosion_tier == "large" and 1.15 or 1.0,
            }
        )
    end
    self:syncLegacyWeaponViews()
    return fired.bullets
end

function Player:shoot(mx, my)
    if self.combatDisabled then return nil end
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
    if self.combatDisabled then return false end
    if Buffs.getControlState(self.statuses).stunned then return false end
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
    self.meleeSwingTimer = MELEE_SWING_DURATION
    self.meleeHitEnemies = {}
    self.anim:play("melee", true)
    Sfx.play("melee_swing")
-- Row 1 of RetroImpactEffectPack1A (see impact_fx.lua ANIM.melee)
    do
        local tip = 22
        local a = self.meleeAimAngle
        ImpactFX.spawn(cx + math.cos(a) * tip, cy + math.sin(a) * tip, "melee", nil, a)
    end
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
    if WeaponRuntime.startReload(self, slotIndex) then
        if slotIndex == self.activeWeaponSlot then
            self:syncLegacyWeaponViews()
        end
        self.anim:play("holster_spin", true)
    end
end

function Player:reload()
    if Buffs.getControlState(self.statuses).stunned then return end
    local slot = self:getActiveWeaponRuntime()
    if not slot or slot.mode ~= "weapon" then return end
    if (slot.reload_timer or 0) > 0 then return end
    if (slot.ammo or 0) >= WeaponRuntime.getAmmoCapacity(self, self.activeWeaponSlot) then return end
    self:startReloadSlot(self.activeWeaponSlot)
end

--- Dead Man's Hand ultimate: mark all enemies and fire explosive barrage.
--- Returns true if activation succeeded.
function Player:tryActivateUlt()
    if self.dying then return false, 0 end
    if self.ultActive then return false end
    if self.ultCharge < 1 then return false end
    self.ultCharge = 0
    self.ultActive = true
    self.ultPhase = "barrage"
    self.ultTimer = 0
    self.ultTargets = {}
    self.ultShotIndex = 1
    self.ultShotTimer = 0.1      -- brief pause before first shot
    self.iframes = 6.0           -- invincible throughout
    return true
end

--- Call when player kills an enemy to build ult charge.
function Player:addUltCharge(amount)
    if self.ultActive then return end
    local wasFull = self.ultCharge >= 1
    self.ultCharge = math.min(1, self.ultCharge + (amount or self.ultChargePerKill))
    if not wasFull and self.ultCharge >= 1 then
        Sfx.play("ult_ready")
    end
end

function Player:get_defense_state(packet)
    local stats = self:getEffectiveStats()
    local allow_block = not (packet and packet.metadata and packet.metadata.ignore_block)
    return {
        armor = stats.armor or 0,
        magic_resist = stats.magicResist or 0,
        armor_shred = self.armorShred or 0,
        magic_shred = self.magicShred or 0,
        incoming_damage_mul = self.incomingDamageMul or 1,
        incoming_physical_mul = self.incomingPhysicalMul or 1,
        incoming_magical_mul = self.incomingMagicalMul or 1,
        block_damage_mul = (allow_block and self.blocking and (stats.blockReduction or 0) > 0)
            and (1 - stats.blockReduction)
            or 1,
    }
end

function Player:getProcRules()
    local out = {}
    for _, perk_id in ipairs(self.perks or {}) do
        local perk = Perks.getById and Perks.getById(perk_id) or nil
        for _, rule in ipairs((perk and perk.proc_rules) or {}) do
            out[#out + 1] = {
                rule = rule,
                meta = { kind = "perk", perk = perk },
            }
        end
    end
    return out
end

function Player:getEquipmentState()
    return nil
end

function Player:takeDamage(amount, packet)
    packet = packet or DamagePacket.new({
        kind = "direct_hit",
        family = "physical",
        amount = amount,
        source = SourceRef.new({ owner_actor_id = "unknown_actor", owner_source_type = "unknown_source", owner_source_id = "unknown_source" }),
        tags = { "incoming" },
        target_id = self.actorId,
        metadata = {
            source_context_kind = "snapshot_only",
        },
    })

    local result = DamageResolver.resolve_direct_hit({
        packet = packet,
        source_actor = nil,
        target_actor = self,
        target_kind = "player",
    })

    return result.applied, result.final_damage

end

function Player:applyResolvedDamage(result, _, packet)
    local packet_kind = packet and packet.kind or "direct_hit"
    local bypass_iframes = packet_kind == "status_tick" or packet_kind == "status_payoff_hit"
    if self.dying or self.devGodMode or ((not bypass_iframes) and self.iframes > 0) then
        return false, 0, false
    end

    local before = self.hp
    self.hp = self.hp - (result.final_damage or 0)
    if not bypass_iframes then
        self.iframes = 0.5
        Sfx.play("hurt")
    end

    if debugLog then
        local suffix = self.blocking and " [blocked]" or ""
        debugLog(string.format(
            "Took %d dmg  HP %d -> %d%s [%s]",
            result.final_damage or 0,
            before,
            self.hp,
            suffix,
            tostring(packet and packet.family or "physical")
        ))
    end

    local killed = self.hp <= 0
    if killed then
        self:beginDeath()
    end

    return true, result.final_damage or 0, killed
end

function Player:heal(amount)
    local maxHP = self:getEffectiveStats().maxHP
    self.hp = math.min(maxHP, self.hp + amount)
end

--- Saloon Monster Energy: full heal, stacking move speed (diminishing per drink), roll for jitter (visual only) + maybe a voice line.
function Player:consumeMonsterEnergy()
    self.monsterDrinks = (self.monsterDrinks or 0) + 1
    local n = self.monsterDrinks
    local increment = MONSTER_MOVE_FIRST * (MONSTER_MOVE_DECAY ^ (n - 1))
    self.monsterMoveBonus = (self.monsterMoveBonus or 0) + increment

    local jitterChance = 0
    if n >= 2 then
        jitterChance = math.min(
            MONSTER_JITTER_CAP,
            MONSTER_JITTER_BASE_CHANCE + (n - 2) * MONSTER_JITTER_PER_DRINK
        )
    end
    if GameRng.randomChance("player.monster_energy.jitter", jitterChance) then
        -- Longer / shakier as drinks mount (still mild on 2nd drink)
        local intensity = math.min(1.15, 0.35 + (n - 2) * 0.18)
        self.monsterJitteryTimer = (6.0 + intensity * 5.0) + GameRng.randomFloat("player.monster_energy.jitter_duration", 0, 3.0 + intensity * 2.0)
        self.monsterJitterShakeMul = intensity
        Buffs.apply(self.statuses, "jitter")
    end

    -- Apply speed buff through buff system
    Buffs.apply(self.statuses, "speed_boost")

    self.monsterSpeechText = nil
    if GameRng.randomChance("player.monster_energy.speech", MONSTER_SPEECH_CHANCE) then
        self.monsterSpeechText = MONSTER_SPEECH_LINES[GameRng.random("player.monster_energy.speech_line", #MONSTER_SPEECH_LINES)]
        self.monsterSpeechLife = 0
    end

    local maxHP = self:getEffectiveStats().maxHP
    self:heal(maxHP)
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

function Player:addGold(amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then
        return 0
    end
    self.gold = self.gold + amount
    if self.runMetadata then
        RunMetadata.recordEconomy(self.runMetadata, "earned", amount, reason or "gold_gain")
    end
    return amount
end

function Player:spendGold(amount, reason)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then
        return true, 0
    end
    if self.gold < amount then
        return false, amount
    end
    self.gold = self.gold - amount
    if self.runMetadata then
        RunMetadata.recordEconomy(self.runMetadata, "spent", amount, reason or "gold_spend")
    end
    return true, amount
end

function Player:equipGear(gear)
    self.gear[gear.slot] = gear
    if gear.stats.maxHP then
        self.hp = math.min(self:getEffectiveStats().maxHP, self.hp + gear.stats.maxHP)
    end
    self:syncLegacyWeaponViews()
end

function Player:applyPerk(perk)
    table.insert(self.perks, perk.id)
    perk.apply(self)
    self:syncLegacyWeaponViews()
end

--- Save active slot state from live fields, then restore the target slot.
--- Always toggles 1 <-> 2 so Tab can highlight which slot a ground weapon will replace
--- (including when slot 2 is empty / melee).
function Player:switchWeapon()
    if Buffs.getControlState(self.statuses).stunned then
        return
    end
    WeaponRuntime.switchActiveSlot(self)
    self:syncLegacyWeaponViews()
    self.anim:play("holster", true)
end

--- Equip a gun definition into a weapon slot (1 or 2). Resets ammo to full.
--- Auto-switches to the new weapon slot for immediate feedback.
function Player:equipWeapon(gunDef, slotIndex)
    if Buffs.getControlState(self.statuses).stunned then
        return
    end
    slotIndex = slotIndex or 2
    WeaponRuntime.equipWeapon(self, gunDef, slotIndex)
    self:syncLegacyWeaponViews()

    if slotIndex == 2 then
        self.gear.melee = nil
    end
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
        local jx, jy = 0, 0
        if (self.monsterJitteryTimer or 0) > 0 then
            local mul = self.monsterJitterShakeMul or 0.35
            jx = (math.sin(t * 22.7) + math.sin(t * 16.2)) * 1.25 * mul
            jy = (math.cos(t * 19.1) + math.sin(t * 14.4)) * 0.95 * mul
        end
        -- Buff system jitter (stacks with monster jitter)
        local statusTracker = self.statuses or self.buffs
        if statusTracker then
            local vis = Buffs.getVisuals(statusTracker)
            if vis.jitterAmp > 0 then
                local f = vis.jitterFreq
                jx = jx + math.sin(t * f * 1.13) * vis.jitterAmp
                jy = jy + math.cos(t * f * 0.97) * vis.jitterAmp * 0.75
            end
        end
        love.graphics.push()
        love.graphics.translate(jx, jy)

        -- Smash-style energy bubble while blocking (drawn behind the fighter)
        if self.blocking and self.gear.shield then
            local scx = self.x + self.w / 2
            local scy = self.y + self.h / 2
            local pulse = 0.65 + 0.35 * math.sin(t * 10)
            local rx, ry = 24, 30
            love.graphics.setColor(0.45, 0.7, 1.0, 0.22 * pulse)
            love.graphics.ellipse("fill", scx, scy, rx, ry)
            love.graphics.setColor(0.65, 0.88, 1.0, 0.55 * pulse)
            love.graphics.setLineWidth(2)
            love.graphics.ellipse("line", scx, scy, rx, ry)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(0.85, 0.95, 1.0, 0.25 * pulse)
            love.graphics.ellipse("line", scx, scy, rx * 0.88, ry * 0.88)
        end

        self.anim:drawCentered(cx, footY, self.facingRight)

        -- Weapon sprite overlay (gun — hidden during melee swing so equipped dagger reads clearly)
        if self.meleeSwingTimer <= 0 then
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
                local gun1 = self.weapons[1] and self.weapons[1].gun
                local gun2 = self.weapons[2] and self.weapons[2].gun
                if gun1 then drawGunSprite(gun1, -4) end
                if gun2 then drawGunSprite(gun2, 4) end
            else
                local gun = self:getActiveGun()
                if gun then drawGunSprite(gun, 0) end
            end
        end

        -- Equipped melee weapon (same icon as HUD / gear.icon) during swing or dash strike
        if self.meleeSwingTimer > 0 then
            local s = self:getEffectiveStats()
            if s.meleeDamage > 0 then
                local gear = self.gear.melee or Weapons.defaults.melee
                if gear and gear.icon then
                    local ang = self.meleeAimAngle
                    local pcx = self.x + self.w * 0.5
                    local pcy = self.y + self.h * 0.5
                    local grip = 10
                    local hx = pcx + math.cos(ang) * grip
                    local hy = pcy + math.sin(ang) * grip
                    if self.facingRight then
                        hy = hy - 10  -- nudge up vs left-facing (screen Y+ is down)
                    end
                    -- Facing-right body is not mirrored like the left-facing sprite; flip the tile on X so the grip/blade match the good left-facing read.
                    GearIcons.drawHeld(gear.icon, hx, hy, ang, {
                        scale       = 1.45,  -- 16px tile → ~23px; reads as a knife vs 16×28 body
                        originX     = 0.42,
                        originY     = 0.58,
                        angleOffset = math.pi * 0.5,
                        flipX       = self.facingRight,
                    })
                end
            end
        end

        if self.monsterSpeechText then
            if not self._monsterSpeechFont then
                self._monsterSpeechFont = Font.new(14)
            end
            local font = self._monsterSpeechFont
            local prevFont = love.graphics.getFont()
            love.graphics.setFont(font)
            local alpha = 1
            local life = self.monsterSpeechLife or 0
            if life < 0.4 then
                alpha = life / 0.4
            elseif life > MONSTER_SPEECH_DURATION - 0.8 then
                alpha = (MONSTER_SPEECH_DURATION - life) / 0.8
            end
            local py = self.y - 38 - life * 2
            local tw = font:getWidth(self.monsterSpeechText)
            love.graphics.setColor(0, 0, 0, 0.45 * alpha)
            love.graphics.print(self.monsterSpeechText, math.floor(cx - tw / 2) + 1, math.floor(py) + 1)
            love.graphics.setColor(0.72, 0.68, 0.58, 0.85 * alpha)
            love.graphics.print(self.monsterSpeechText, math.floor(cx - tw / 2), math.floor(py))
            love.graphics.setFont(prevFont)
        end

        love.graphics.pop()
    end

    love.graphics.setColor(1, 1, 1)
end

return Player
