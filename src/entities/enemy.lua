local EnemyData = require("src.data.enemies")
local Vision = require("src.data.vision")
local DamagePacket = require("src.systems.damage_packet")
local DamageResolver = require("src.systems.damage_resolver")
local EnemyAI = require("src.systems.enemy_ai")
local PlatformCollision = require("src.systems.platform_collision")
local GameRng = require("src.systems.game_rng")
local SourceRef = require("src.systems.source_ref")

local Enemy = {}
Enemy.__index = Enemy
local NEXT_ENEMY_ID = 1

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

-- Buzzard sprite constants (Pirots asset: 1536×192, 8 frames of 192×192)
local BUZZARD_FRAME_SIZE = 192
local BUZZARD_SPRITE_SCALE = 0.22  -- 192 * 0.22 ≈ 42px drawn (fits 22×16 hitbox)
local _buzzardSheet = nil
local _buzzardQuads = nil
local BUZZARD_FLY_FRAMES = 8
local BUZZARD_FLY_FPS    = 10

local function loadBuzzardSprite()
    if _buzzardSheet then return end
    _buzzardSheet = love.graphics.newImage("assets/sprites/buzzard/BuzzardFlying_Pirots.png")
    _buzzardSheet:setFilter("nearest", "nearest")
    local sw, sh = _buzzardSheet:getDimensions()
    _buzzardQuads = {}
    for i = 0, BUZZARD_FLY_FRAMES - 1 do
        _buzzardQuads[i + 1] = love.graphics.newQuad(
            i * BUZZARD_FRAME_SIZE, 0, BUZZARD_FRAME_SIZE, BUZZARD_FRAME_SIZE, sw, sh
        )
    end
end

-- Gunslinger sprite constants
local GS_FRAME_H = 48
local GS_SPRITE_SCALE = 0.85
local _gsWalkSheet = nil
local _gsWalkQuads = nil
local GS_WALK_FRAMES = 8
local GS_WALK_FPS    = 10
local _gsShootSheet = nil
local _gsShootQuads = nil
local GS_SHOOT_FRAMES = 5
local GS_SHOOT_FPS    = 14

local function loadGunslingerSprites()
    if _gsWalkSheet then return end
    _gsWalkSheet = love.graphics.newImage("assets/sprites/gunslinger/walk.png")
    _gsWalkSheet:setFilter("nearest", "nearest")
    local sw, sh = _gsWalkSheet:getDimensions()
    _gsWalkQuads = {}
    for i = 0, GS_WALK_FRAMES - 1 do
        _gsWalkQuads[i + 1] = love.graphics.newQuad(
            i * GS_FRAME_H, 0, GS_FRAME_H, GS_FRAME_H, sw, sh
        )
    end
    _gsShootSheet = love.graphics.newImage("assets/sprites/gunslinger/shoot.png")
    _gsShootSheet:setFilter("nearest", "nearest")
    sw, sh = _gsShootSheet:getDimensions()
    _gsShootQuads = {}
    for i = 0, GS_SHOOT_FRAMES - 1 do
        _gsShootQuads[i + 1] = love.graphics.newQuad(
            i * GS_FRAME_H, 0, GS_FRAME_H, GS_FRAME_H, sw, sh
        )
    end
end

-- Blackkid boss: single full-frame PNG, scaled to ~bandit on-screen height
local _blackkidSheet = nil
local BLACKKID_TARGET_DRAW_H = BANDIT_FRAME_H * BANDIT_SPRITE_SCALE

local function loadBlackkidSprite()
    if _blackkidSheet then return end
    _blackkidSheet = love.graphics.newImage("assets/sprites/blackkid/blackkid.png")
    _blackkidSheet:setFilter("nearest", "nearest")
end

local OGRE_BOSS_FRAME_SIZE = 64
local OGRE_BOSS_TARGET_DRAW_H = 68
local OGRE_BOSS_ANIMS = {
    idle = { file = "assets/sprites/ogreboss/idle.png", frames = 4, fps = 5, loop = true },
    walk = { file = "assets/sprites/ogreboss/walk.png", frames = 6, fps = 9, loop = true },
    attack = { file = "assets/sprites/ogreboss/attack.png", frames = 5, fps = 14, loop = false },
    hurt = { file = "assets/sprites/ogreboss/hurt.png", frames = 2, fps = 12, loop = false },
}
local _ogreBossSheets = nil
local _ogreBossQuads = nil

local function loadOgreBossSprite()
    if _ogreBossSheets then return end
    _ogreBossSheets = {}
    _ogreBossQuads = {}
    for name, anim in pairs(OGRE_BOSS_ANIMS) do
        local sheet = love.graphics.newImage(anim.file)
        sheet:setFilter("nearest", "nearest")
        local sw, sh = sheet:getDimensions()
        _ogreBossSheets[name] = sheet
        _ogreBossQuads[name] = {}
        for i = 0, anim.frames - 1 do
            _ogreBossQuads[name][i + 1] = love.graphics.newQuad(
                i * OGRE_BOSS_FRAME_SIZE, 0, OGRE_BOSS_FRAME_SIZE, OGRE_BOSS_FRAME_SIZE, sw, sh
            )
        end
    end
end

local function loadSheetAnimations(path, frameW, frameH, anims)
    local sheet = love.graphics.newImage(path)
    sheet:setFilter("nearest", "nearest")
    local sw, sh = sheet:getDimensions()
    local quads = {}
    for name, anim in pairs(anims) do
        quads[name] = {}
        for i = 0, anim.frames - 1 do
            quads[name][i + 1] = love.graphics.newQuad(
                i * frameW, anim.row * frameH, frameW, frameH, sw, sh
            )
        end
    end
    return sheet, quads
end

local NECRO_FRAME_W = 160
local NECRO_FRAME_H = 128
local NECRO_TARGET_DRAW_H = 116
local NECRO_FOOT_TRIM = 26
local NECRO_HOVER_LIFT = 18
local NECRO_ANIMS = {
    idle = { row = 0, frames = 8, fps = 8, loop = true },
    walk = { row = 1, frames = 8, fps = 10, loop = true },
    attack = { row = 2, frames = 13, fps = 16, loop = false },
    hurt = { row = 5, frames = 5, fps = 14, loop = false },
}
local _necroSheet = nil
local _necroQuads = nil

local function loadNecromancerSprite()
    if _necroSheet then return end
    _necroSheet, _necroQuads = loadSheetAnimations(
        "assets/sprites/necromancer/Necromancer_creativekind-Sheet.png",
        NECRO_FRAME_W,
        NECRO_FRAME_H,
        NECRO_ANIMS
    )
end

local NIGHTBORNE_FRAME = 80
local NIGHTBORNE_TARGET_DRAW_H = 96
local NIGHTBORNE_FOOT_TRIM = 14
local NIGHTBORNE_ANIMS = {
    idle = { row = 0, frames = 9, fps = 9, loop = true },
    walk = { row = 1, frames = 6, fps = 12, loop = true },
    attack = { row = 2, frames = 12, fps = 18, loop = false },
    hurt = { row = 3, frames = 5, fps = 14, loop = false },
}
local _nightborneSheet = nil
local _nightborneQuads = nil

local function loadNightborneSprite()
    if _nightborneSheet then return end
    _nightborneSheet, _nightborneQuads = loadSheetAnimations(
        "assets/sprites/nightborne/NightBorne.png",
        NIGHTBORNE_FRAME,
        NIGHTBORNE_FRAME,
        NIGHTBORNE_ANIMS
    )
end

local ELITE_HP = 1.9
local ELITE_DMG = 1.15
local ELITE_LOOT = 1.75
local ELITE_ATK_SPEED = 0.88

local function sign(v)
    if v > 0 then return 1 end
    if v < 0 then return -1 end
    return 0
end

local function updateSheetRowAnimation(enemy, dt, animField, animDefs)
    local nextAnim = "idle"
    if enemy.hurtTimer > 0 then
        nextAnim = "hurt"
    elseif enemy.attackAnimTimer and enemy.attackAnimTimer > 0 then
        nextAnim = "attack"
    elseif math.abs(enemy.vx) > 8 then
        nextAnim = "walk"
    end

    if enemy[animField] ~= nextAnim then
        enemy[animField] = nextAnim
        enemy.spriteFrame = 1
        enemy.spriteTimer = 0
    end

    local anim = animDefs[enemy[animField]]
    enemy.spriteTimer = enemy.spriteTimer + dt
    local interval = 1 / anim.fps
    while enemy.spriteTimer >= interval do
        enemy.spriteTimer = enemy.spriteTimer - interval
        if anim.loop then
            enemy.spriteFrame = (enemy.spriteFrame % anim.frames) + 1
        else
            enemy.spriteFrame = math.min(anim.frames, enemy.spriteFrame + 1)
        end
    end
end

function Enemy.new(typeId, x, y, difficulty, opts)
    opts = opts or {}
    local data = EnemyData.getScaled(typeId, difficulty or 1)
    if not data then return nil end

    local self = setmetatable({}, Enemy)
    self.actorId = "enemy_" .. NEXT_ENEMY_ID
    NEXT_ENEMY_ID = NEXT_ENEMY_ID + 1
    self.typeId = typeId
    self.x = x
    self.y = y
    self.w = data.width
    self.h = data.height
    self.hp = data.hp
    self.maxHP = data.hp
    self.damage = data.damage
    self.armor = 0
    self.magic_resist = 0
    self.armor_shred = 0
    self.magic_shred = 0
    self.incoming_damage_mul = 1
    self.incoming_physical_mul = 1
    self.incoming_magical_mul = 1
    self.speed = data.speed
    self.xpValue = data.xpValue
    self.goldValue = data.goldValue
    self.color = data.color
    self.behavior = data.behavior
    self.attackRange = data.attackRange
    self.attackCooldown = data.attackCooldown
    self.attackAnimDuration = data.attackAnimDuration
    self.bulletSpeed = data.bulletSpeed
    self.swoopSpeed = data.swoopSpeed
    self.aggroRange = data.aggroRange or 260
    self.contactRange = data.contactRange
    self.name = data.name or typeId
    self.elite = false
    self.peaceful = opts.peaceful == true
    self.unarmed = opts.unarmed == true

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

    -- Sprite animation
    if typeId == "bandit" then
        loadBanditSprite()
        self.spriteFrame = 1
        self.spriteTimer = 0
        self.attackAnimTimer = 0
    elseif typeId == "buzzard" then
        loadBuzzardSprite()
        self.spriteFrame = 1
        self.spriteTimer = 0
        self.swoopAnimTimer = 0
    elseif typeId == "gunslinger" then
        loadGunslingerSprites()
        self.spriteFrame = 1
        self.spriteTimer = 0
        self.gsAnim = "walk"       -- "walk" or "shoot"
        self.gsShootAnimDone = true
    elseif typeId == "necromancer" then
        loadNecromancerSprite()
        self.spriteFrame = 1
        self.spriteTimer = 0
        self.necroAnim = "idle"
        self.attackAnimTimer = 0
    elseif typeId == "nightborne" then
        loadNightborneSprite()
        self.spriteFrame = 1
        self.spriteTimer = 0
        self.nightborneAnim = "idle"
        self.attackAnimTimer = 0
    elseif typeId == "blackkid" then
        loadBlackkidSprite()
        self.attackAnimTimer = 0
    elseif typeId == "ogreboss" then
        loadOgreBossSprite()
        self.ogreAnim = "idle"
        self.spriteFrame = 1
        self.spriteTimer = 0
        self.attackAnimTimer = 0
    end

    EnemyAI.init(self, data)
    return self
end

function Enemy:update(dt, world, context)
    self.attackTimer = self.attackTimer - dt
    if self.hurtTimer > 0 then
        self.hurtTimer = self.hurtTimer - dt
    end

    local dx = 0
    local player = context and context.player
    if player then
        local playerX = player.x + player.w * 0.5
        dx = playerX - (self.x + self.w * 0.5)
        if math.abs(dx) > 1 then
            self.facingRight = dx > 0
        end
    end

    -- Update attack/swoop animation timers
    if self.attackAnimTimer and self.attackAnimTimer > 0 then
        self.attackAnimTimer = self.attackAnimTimer - dt
    end
    if self.swoopAnimTimer and self.swoopAnimTimer > 0 then
        self.swoopAnimTimer = self.swoopAnimTimer - dt
    end

    -- Update sprite animation
    if self.typeId == "bandit" and self.spriteTimer then
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
    elseif self.typeId == "buzzard" and self.spriteTimer then
        -- Buzzard always animates; speed up during swoop
        local fps = self.swoopTarget and (BUZZARD_FLY_FPS * 2) or BUZZARD_FLY_FPS
        self.spriteTimer = self.spriteTimer + dt
        local interval = 1 / fps
        if self.spriteTimer >= interval then
            self.spriteTimer = self.spriteTimer - interval
            self.spriteFrame = (self.spriteFrame % BUZZARD_FLY_FRAMES) + 1
        end
    elseif self.typeId == "gunslinger" and self.spriteTimer then
        if self.gsAnim == "shoot" and not self.gsShootAnimDone then
            -- Play shoot animation once then return to walk
            self.spriteTimer = self.spriteTimer + dt
            local interval = 1 / GS_SHOOT_FPS
            if self.spriteTimer >= interval then
                self.spriteTimer = self.spriteTimer - interval
                if self.spriteFrame < GS_SHOOT_FRAMES then
                    self.spriteFrame = self.spriteFrame + 1
                else
                    self.gsShootAnimDone = true
                    self.gsAnim = "walk"
                    self.spriteFrame = 1
                    self.spriteTimer = 0
                end
            end
        else
            -- Walk animation (or idle at frame 1)
            self.gsAnim = "walk"
            if math.abs(self.vx) > 10 then
                self.spriteTimer = self.spriteTimer + dt
                local interval = 1 / GS_WALK_FPS
                if self.spriteTimer >= interval then
                    self.spriteTimer = self.spriteTimer - interval
                    self.spriteFrame = (self.spriteFrame % GS_WALK_FRAMES) + 1
                end
            else
                self.spriteFrame = 1
                self.spriteTimer = 0
            end
        end
    elseif self.typeId == "necromancer" and self.spriteTimer then
        updateSheetRowAnimation(self, dt, "necroAnim", NECRO_ANIMS)
    elseif self.typeId == "nightborne" and self.spriteTimer then
        updateSheetRowAnimation(self, dt, "nightborneAnim", NIGHTBORNE_ANIMS)
    elseif self.typeId == "ogreboss" and self.spriteTimer then
        local nextAnim = "idle"
        if self.hurtTimer > 0 then
            nextAnim = "hurt"
        elseif self.attackAnimTimer and self.attackAnimTimer > 0 then
            nextAnim = "attack"
        elseif math.abs(self.vx) > 8 then
            nextAnim = "walk"
        end

        if self.ogreAnim ~= nextAnim then
            self.ogreAnim = nextAnim
            self.spriteFrame = 1
            self.spriteTimer = 0
        end

        local anim = OGRE_BOSS_ANIMS[self.ogreAnim]
        self.spriteTimer = self.spriteTimer + dt
        local interval = 1 / anim.fps
        while self.spriteTimer >= interval do
            self.spriteTimer = self.spriteTimer - interval
            if anim.loop then
                self.spriteFrame = (self.spriteFrame % anim.frames) + 1
            else
                self.spriteFrame = math.min(anim.frames, self.spriteFrame + 1)
            end
        end
    end

    return EnemyAI.update(self, dt, world, context or {})
end

local function groundFilter(item)
    return item.isPlatform or item.isWall
end

function Enemy:hasGroundAhead(world, dir)
    -- Check for ground support at the leading foot (one step ahead, one tile down)
    local probeX
    dir = dir or sign(self.vx or 0)
    if dir > 0 then
        probeX = self.x + self.w + 2
    elseif dir < 0 then
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
        -- Trigger shoot animation
        if self.gsAnim then
            self.gsAnim = "shoot"
            self.spriteFrame = 1
            self.spriteTimer = 0
            self.gsShootAnimDone = false
        end
        local angle = math.atan2(dy, dx)
        -- Slight inaccuracy
            angle = angle + (GameRng.randomFloat("enemy.projectile_inaccuracy", 0, 1) - 0.5) * 0.15
        return {
            x = self.x + self.w / 2,
            y = self.y + self.h / 2,
            angle = angle,
            speed = self.bulletSpeed or 380,
            damage = self.damage,
            fromEnemy = true,
            damage_family = "physical",
            packet_kind = "direct_hit",
            damage_tags = { "projectile", "enemy" },
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
            if self.swoopAnimTimer then
                self.swoopAnimTimer = 0.4
            end
        end
    end

    local goalX = self.x + self.vx * dt
    local goalY = self.y + self.vy * dt
    local actualX, actualY = world:move(self, goalX, goalY, self.filter)
    self.x = actualX
    self.y = actualY

    return nil
end

function Enemy:takeDamage(amount, world, packet)
    packet = packet or DamagePacket.new({
        kind = "direct_hit",
        family = "physical",
        amount = amount,
        source = SourceRef.new({ owner_actor_id = "unknown_actor", owner_source_type = "unknown_source", owner_source_id = "unknown_source" }),
        target_id = self.actorId,
        metadata = {
            source_context_kind = "snapshot_only",
        },
    })
    local result = DamageResolver.resolve_direct_hit({
        packet = packet,
        source_actor = nil,
        target_actor = self,
        target_kind = "enemy",
        world = world,
    })
    return result.target_killed
end

function Enemy:applyResolvedDamage(result, world, packet)
    if not self.alive then
        return false, 0, false
    end

    self.hp = self.hp - (result.final_damage or 0)
    self.hurtTimer = 0.18
    self.lastDamagePacket = packet
    if self.hp <= 0 then
        self.alive = false
        self.state = "dead"
        self.isEnemy = false
        if world and world:hasItem(self) then
            world:remove(self)
        end
        return true, result.final_damage or 0, true
    end

    EnemyAI.onDamaged(self)
    return true, result.final_damage or 0, false
end

function Enemy:canDamagePlayer(playerX, playerY, playerW, playerH)
    if self.peaceful or self.unarmed then
        return false
    end
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
    if self.peaceful or self.unarmed then
        return
    end
    if self.behavior == "melee" or self.behavior == "flying" then
        self.attackTimer = self.attackCooldown
    end
    if self.attackAnimTimer then
        self.attackAnimTimer = self.attackAnimDuration or 0.36
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

function Enemy:draw(player, camera, shakeX, shakeY, room)
    if not self.alive then return end
    if player and camera then
        local ex = self.x + self.w * 0.5
        local ey = self.y + self.h * 0.5
        if not Vision.isEntityVisibleToPlayer(room, player, ex, ey, camera, shakeX, shakeY) then
            return
        end
    end
    local c = self.color

    if self.elite and self.typeId ~= "bandit" and self.typeId ~= "buzzard" and self.typeId ~= "gunslinger"
        and self.typeId ~= "necromancer" and self.typeId ~= "nightborne"
        and self.typeId ~= "blackkid" and self.typeId ~= "ogreboss" then
        love.graphics.setColor(0.92, 0.72, 0.15)
        love.graphics.rectangle("line", self.x - 2, self.y - 2, self.w + 4, self.h + 4)
    end

    -- Buzzard: draw sprite
    if self.typeId == "buzzard" and _buzzardSheet then
        local quad = _buzzardQuads[self.spriteFrame]
        if quad then
            if self.hurtTimer > 0 then
                love.graphics.setColor(1, 0.4, 0.4)
            else
                love.graphics.setColor(1, 1, 1)
            end
            local scaledW = BUZZARD_FRAME_SIZE * BUZZARD_SPRITE_SCALE
            local scaledH = BUZZARD_FRAME_SIZE * BUZZARD_SPRITE_SCALE
            local cx = self.x + self.w / 2
            local cy = self.y + self.h / 2

            -- Tilt during swoop
            local angle = 0
            if self.swoopTarget then
                local sdx = self.swoopTarget.x - self.x
                local sdy = self.swoopTarget.y - self.y
                angle = math.atan2(sdy, sdx) * 0.3  -- subtle tilt toward target
            end

            local drawX = cx - scaledW / 2
            local drawY = cy - scaledH / 2
            local sx = self.facingRight and BUZZARD_SPRITE_SCALE or -BUZZARD_SPRITE_SCALE
            local flipShift = self.facingRight and 0 or scaledW

            love.graphics.push()
            love.graphics.translate(cx, cy)
            love.graphics.rotate(angle)
            love.graphics.translate(-cx, -cy)
            love.graphics.draw(_buzzardSheet, quad, drawX + flipShift, drawY, 0, sx, BUZZARD_SPRITE_SCALE)
            love.graphics.pop()

            -- Swoop indicator: speed lines behind the buzzard during attack
            if self.swoopAnimTimer and self.swoopAnimTimer > 0 then
                local alpha = self.swoopAnimTimer / 0.4
                local dir = self.facingRight and -1 or 1
                love.graphics.setColor(1, 0.85, 0.5, alpha * 0.7)
                love.graphics.setLineWidth(2)
                for i = 1, 3 do
                    local offsetY = (i - 2) * 5
                    local len = 8 + i * 3
                    local startX = cx + dir * (scaledW * 0.4)
                    love.graphics.line(startX, cy + offsetY, startX + dir * len, cy + offsetY)
                end
                love.graphics.setLineWidth(1)
            end
        end

    -- Bandit: draw sprite instead of rectangle
    elseif self.typeId == "bandit" and _banditSheet then
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

    -- Gunslinger: draw sprite (walk or shoot)
    elseif self.typeId == "gunslinger" and _gsWalkSheet then
        local sheet, quads, maxFrames
        if self.gsAnim == "shoot" and not self.gsShootAnimDone then
            sheet = _gsShootSheet
            quads = _gsShootQuads
            maxFrames = GS_SHOOT_FRAMES
        else
            sheet = _gsWalkSheet
            quads = _gsWalkQuads
            maxFrames = GS_WALK_FRAMES
        end
        local frame = math.min(self.spriteFrame, maxFrames)
        local quad = quads[frame]
        if quad then
            if self.hurtTimer > 0 then
                love.graphics.setColor(1, 0.4, 0.4)
            else
                love.graphics.setColor(1, 1, 1)
            end
            local scaledW = GS_FRAME_H * GS_SPRITE_SCALE
            local scaledH = GS_FRAME_H * GS_SPRITE_SCALE
            local cx = self.x + self.w / 2
            local footY = self.y + self.h
            local drawX = cx - scaledW / 2
            local drawY = footY - scaledH
            local sx = self.facingRight and GS_SPRITE_SCALE or -GS_SPRITE_SCALE
            local flipShift = self.facingRight and 0 or scaledW
            love.graphics.draw(sheet, quad, drawX + flipShift, drawY, 0, sx, GS_SPRITE_SCALE)
        end

    elseif self.typeId == "necromancer" and _necroSheet then
        local animName = self.necroAnim or "idle"
        local quadList = _necroQuads[animName]
        local quad = quadList and quadList[self.spriteFrame]
        if quad then
            local scale = NECRO_TARGET_DRAW_H / NECRO_FRAME_H
            local scaledW = NECRO_FRAME_W * scale
            local scaledH = NECRO_FRAME_H * scale
            local footTrim = NECRO_FOOT_TRIM * scale
            local hoverLift = NECRO_HOVER_LIFT * scale
            local cx = self.x + self.w / 2
            local footY = self.y + self.h
            local casting = self.attackAnimTimer and self.attackAnimTimer > 0
            local castOffset = 0
            if casting then
                local t = self.attackAnimDuration and (self.attackAnimTimer / self.attackAnimDuration) or 0
                castOffset = math.sin((1 - t) * math.pi) * 3
            end
            local drawX = cx - scaledW / 2
            local drawY = footY - scaledH + footTrim - hoverLift - castOffset
            local sx = self.facingRight and scale or -scale
            local flipShift = self.facingRight and 0 or scaledW

            if self.hurtTimer > 0 then
                love.graphics.setColor(1, 0.4, 0.4)
            else
                love.graphics.setColor(1, 1, 1)
            end
            love.graphics.draw(_necroSheet, quad, drawX + flipShift, drawY, 0, sx, scale)

            if casting then
                local pulse = 0.35 + 0.65 * math.sin(love.timer.getTime() * 22) ^ 2
                local orbX = cx + (self.facingRight and 10 or -10)
                local orbY = self.y + self.h * 0.28
                love.graphics.setColor(0.95, 0.2, 0.2, 0.35 * pulse)
                love.graphics.circle("fill", orbX, orbY, 8)
                love.graphics.setColor(1, 0.45, 0.45, 0.9 * pulse)
                love.graphics.circle("fill", orbX, orbY, 4)
            end
        end

    elseif self.typeId == "nightborne" and _nightborneSheet then
        local animName = self.nightborneAnim or "idle"
        local quadList = _nightborneQuads[animName]
        local quad = quadList and quadList[self.spriteFrame]
        if quad then
            local scale = NIGHTBORNE_TARGET_DRAW_H / NIGHTBORNE_FRAME
            local scaledW = NIGHTBORNE_FRAME * scale
            local scaledH = NIGHTBORNE_FRAME * scale
            local footTrim = NIGHTBORNE_FOOT_TRIM * scale
            local cx = self.x + self.w / 2
            local footY = self.y + self.h
            local attacking = self.attackAnimTimer and self.attackAnimTimer > 0
            local lungeOffset = 0
            if attacking then
                local t = self.attackAnimDuration and (self.attackAnimTimer / self.attackAnimDuration) or 0
                lungeOffset = math.sin((1 - t) * math.pi) * 7
                if not self.facingRight then
                    lungeOffset = -lungeOffset
                end
            end
            local drawX = cx - scaledW / 2 + lungeOffset
            local drawY = footY - scaledH + footTrim
            local sx = self.facingRight and scale or -scale
            local flipShift = self.facingRight and 0 or scaledW

            if self.hurtTimer > 0 then
                love.graphics.setColor(1, 0.4, 0.4)
            else
                love.graphics.setColor(1, 1, 1)
            end
            love.graphics.draw(_nightborneSheet, quad, drawX + flipShift, drawY, 0, sx, scale)

            if attacking then
                local t = self.attackAnimDuration and (self.attackAnimTimer / self.attackAnimDuration) or 0
                local alpha = 1 - t
                local dir = self.facingRight and 1 or -1
                love.graphics.setColor(0.85, 0.55, 1.0, alpha * 0.55)
                love.graphics.setLineWidth(2)
                love.graphics.arc("line", "open", cx + dir * 14, self.y + self.h * 0.36, 14,
                    self.facingRight and -math.pi * 0.45 or math.pi * 0.35,
                    self.facingRight and math.pi * 0.12 or math.pi * 1.15,
                    8
                )
                love.graphics.setLineWidth(1)
            end
        end

    elseif self.typeId == "blackkid" and _blackkidSheet then
        local iw, ih = _blackkidSheet:getDimensions()
        local scale = BLACKKID_TARGET_DRAW_H / ih
        local scaledW = iw * scale
        local scaledH = ih * scale
        local cx = self.x + self.w / 2
        local footY = self.y + self.h

        local attacking = self.attackAnimTimer and self.attackAnimTimer > 0
        local lungeOffset = 0
        if attacking then
            local t = self.attackAnimTimer / 0.3
            lungeOffset = math.sin(t * math.pi) * 8
            if not self.facingRight then lungeOffset = -lungeOffset end
        end

        local drawX = cx - scaledW / 2 + lungeOffset
        local drawY = footY - scaledH
        local sx = self.facingRight and scale or -scale
        local flipShift = self.facingRight and 0 or scaledW

        if self.hurtTimer > 0 then
            love.graphics.setColor(1, 0.4, 0.4)
        else
            love.graphics.setColor(1, 1, 1)
        end
        love.graphics.draw(_blackkidSheet, drawX + flipShift, drawY, 0, sx, scale)

        if attacking then
            local t = self.attackAnimTimer / 0.3
            local alpha = t
            local dir = self.facingRight and 1 or -1
            local arcCx = cx + dir * 20
            local arcCy = self.y + self.h * 0.4
            local radius = 16
            local startAngle = self.facingRight and -math.pi * 0.6 or math.pi * 0.4
            local sweep = math.pi * 0.8 * (1 - t)
            love.graphics.setColor(1, 0.85, 0.55, alpha * 0.85)
            love.graphics.setLineWidth(2)
            love.graphics.arc("line", "open", arcCx, arcCy, radius, startAngle, startAngle + sweep * dir, 10)
            love.graphics.setLineWidth(1)
        end

    elseif self.typeId == "ogreboss" and _ogreBossSheets then
        local animName = self.ogreAnim or "idle"
        local sheet = _ogreBossSheets[animName]
        local quadList = _ogreBossQuads[animName]
        local quad = quadList and quadList[self.spriteFrame]
        if quad then
            local scale = OGRE_BOSS_TARGET_DRAW_H / OGRE_BOSS_FRAME_SIZE
            local scaledW = OGRE_BOSS_FRAME_SIZE * scale
            local scaledH = OGRE_BOSS_FRAME_SIZE * scale
            local cx = self.x + self.w / 2
            local footY = self.y + self.h
            local attacking = self.attackAnimTimer and self.attackAnimTimer > 0
            local lungeOffset = 0
            if attacking then
                local t = self.attackAnimTimer / 0.36
                lungeOffset = math.sin(t * math.pi) * 10
                if not self.facingRight then lungeOffset = -lungeOffset end
            end

            if animName == "walk" then
                lungeOffset = lungeOffset + math.sin((self.spriteFrame / 6) * math.pi * 2) * 1.5
            elseif animName == "hurt" then
                lungeOffset = lungeOffset - (self.facingRight and 3 or -3)
            end

            local drawX = cx - scaledW / 2 + lungeOffset
            local drawY = footY - scaledH
            local sx = self.facingRight and scale or -scale
            local flipShift = self.facingRight and 0 or scaledW

            if self.hurtTimer > 0 then
                love.graphics.setColor(1, 0.4, 0.4)
            else
                love.graphics.setColor(1, 1, 1)
            end
            love.graphics.draw(sheet, quad, drawX + flipShift, drawY, 0, sx, scale)

            if attacking then
                local t = self.attackAnimTimer / 0.36
                local alpha = t
                local dir = self.facingRight and 1 or -1
                local arcCx = cx + dir * 22
                local arcCy = self.y + self.h * 0.36
                local radius = 20
                local startAngle = self.facingRight and -math.pi * 0.6 or math.pi * 0.35
                local sweep = math.pi * 0.9 * (1 - t)
                love.graphics.setColor(1, 0.86, 0.45, alpha * 0.9)
                love.graphics.setLineWidth(3)
                love.graphics.arc("line", "open", arcCx, arcCy, radius, startAngle, startAngle + sweep * dir, 10)
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

    if DEBUG and self.debugAI then
        local stateLabel = self.debugAI.state or self.state
        if self.debugAI.mode == "peaceful" then
            stateLabel = stateLabel .. " P"
        elseif self.debugAI.mode == "unarmed" then
            stateLabel = stateLabel .. " U"
        end
        local debugState = string.format(
            "%s  a%.2f  cd%.1f",
            stateLabel,
            self.debugAI.alert or 0,
            self.debugAI.attack or 0
        )
        local debugSense = string.format(
            "%s%s%s  mem:%s  tgt:%s",
            self.debugAI.visible and "V" or "-",
            self.debugAI.heard and "H" or "-",
            self.debugAI.shared and "G" or "-",
            self.debugAI.memory < 9 and string.format("%.1f", self.debugAI.memory) or "-",
            self.debugAI.target or "-"
        )
        local panelW = math.max(self.w + 8, 128)
        love.graphics.setColor(0, 0, 0, 0.72)
        love.graphics.rectangle("fill", self.x - 6, self.y - 30, panelW, 18)
        love.graphics.rectangle("fill", self.x - 6, self.y - 12, panelW, 16)
        love.graphics.setColor(0.9, 0.95, 0.9)
        love.graphics.print(debugState, self.x - 4, self.y - 29)
        love.graphics.setColor(0.78, 0.84, 1.0)
        love.graphics.print(debugSense, self.x - 4, self.y - 11)
    end

    love.graphics.setColor(1, 1, 1)
end

return Enemy
