local DamagePacket = require("src.systems.damage_packet")
local GameRng = require("src.systems.game_rng")
local SourceRef = require("src.systems.source_ref")

local EnemyAI = {}

local GRAVITY = 900
local MAX_FALL_SPEED = 600
local PLAYER_FEET_OFFSET = 14
local BOB_HEIGHT = 20
local BOB_SPEED = 2.1

local STATE_PRIORITY = {
    dead = 100,
    attack = 80,
    chase = 70,
    reposition = 64,
    search = 58,
    investigate = 48,
    suspicious = 38,
    patrol = 22,
    idle = 10,
}

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = cloneValue(v)
    end
    return copy
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function sign(v)
    if v > 0 then return 1 end
    if v < 0 then return -1 end
    return 0
end

local function randRange(lo, hi)
    if hi <= lo then
        return lo
    end
    return GameRng.randomFloat("enemy_ai.range", lo, hi)
end

local function randSigned(amount)
    if not amount or amount == 0 then
        return 0
    end
    return (GameRng.randomFloat("enemy_ai.signed", 0, 1) * 2 - 1) * amount
end

local function enemyCenter(enemy)
    return enemy.x + enemy.w * 0.5, enemy.y + enemy.h * 0.5
end

local function playerCenter(player)
    return player.x + player.w * 0.5, player.y + player.h * 0.5
end

local function distanceBetween(ax, ay, bx, by)
    local dx = bx - ax
    local dy = by - ay
    return dx, dy, math.sqrt(dx * dx + dy * dy)
end

local function enemyCanAttack(enemy)
    return enemy and enemy.alive and not enemy.peaceful and not enemy.unarmed
end

local function blankSenses(enemy)
    local ex, ey = enemyCenter(enemy)
    return {
        ex = ex,
        ey = ey,
        px = ex,
        py = ey,
        dx = 0,
        dy = 0,
        dist = math.huge,
        horizDist = math.huge,
        los = false,
        visible = false,
        noise = nil,
        heard = false,
        shared = nil,
        playerBelow = false,
        canShoot = false,
        crowdCount = 0,
    }
end

local function groundFilter(item)
    return item.isPlatform or item.isWall
end

local function losFilter(item)
    return item.isPlatform or item.isWall
end

local function platformSurfaceFilter(item)
    return item.isPlatform
end

local function hasLineOfSight(world, x1, y1, x2, y2)
    local items, len = world:querySegment(x1, y1, x2, y2, losFilter)
    return len == 0
end

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

local function isRecent(age, maxAge)
    return age and age <= maxAge
end

local function setState(enemy, nextState)
    if enemy.state == nextState then
        return
    end

    enemy.state = nextState
    enemy.stateTimer = 0
    enemy.decisionTimer = enemy.ai.decisionInterval

    if nextState == "search" then
        enemy.searchTimer = enemy.ai.searchTime
        enemy.searchTarget = nil
    elseif nextState == "investigate" then
        enemy.investigateTimer = enemy.ai.investigateTime
    elseif nextState == "reposition" then
        enemy.repositionTimer = enemy.ai.repositionTime
    elseif nextState == "idle" then
        enemy.vx = 0
    elseif nextState == "attack" then
        enemy.searchTarget = nil
    end
end

local function maybeChangeState(enemy, desiredState, urgent)
    if desiredState == enemy.state then
        return
    end

    local currentPriority = STATE_PRIORITY[enemy.state] or 0
    local desiredPriority = STATE_PRIORITY[desiredState] or 0
    if urgent or desiredPriority > currentPriority or enemy.decisionTimer <= 0 then
        setState(enemy, desiredState)
    end
end

local function choosePatrolTarget(enemy, world, preferDir)
    local left, right = getPlatformSurfaceExtents(world, enemy.x, enemy.y, enemy.w, enemy.h)
    local radius = enemy.ai.patrolRadius
    local minX = enemy.homeX - radius
    local maxX = enemy.homeX + radius

    if left and right then
        minX = math.max(minX, left + 6)
        maxX = math.min(maxX, right - enemy.w - 6)
    end

    if maxX <= minX + 8 then
        enemy.patrolTargetX = enemy.x
        return enemy.patrolTargetX
    end

    local dir = preferDir or enemy.patrolDir or enemy.flankBias or 1
    enemy.patrolDir = dir
    enemy.patrolTargetX = dir > 0 and maxX or minX
    return enemy.patrolTargetX
end

local function moveGround(enemy, dt, world, desiredVX, allowEdgeDrop)
    local wasGrounded = enemy.grounded
    enemy.vx = desiredVX or 0

    if enemy.vx > 1 then
        enemy.facingRight = true
    elseif enemy.vx < -1 then
        enemy.facingRight = false
    end

    if wasGrounded and enemy.vx ~= 0 and not allowEdgeDrop and not enemy:hasGroundAhead(world, sign(enemy.vx)) then
        enemy.vx = 0
    end

    enemy.vy = clamp((enemy.vy or 0) + GRAVITY * dt, -999, MAX_FALL_SPEED)

    enemy.grounded = false
    local goalX = enemy.x + enemy.vx * dt
    local goalY = enemy.y + enemy.vy * dt
    local actualX, actualY, cols, len = world:move(enemy, goalX, goalY, enemy.filter)
    enemy.x = actualX
    enemy.y = actualY

    local blockedX = false
    for i = 1, len do
        local col = cols[i]
        if col.normal.y == -1 then
            enemy.grounded = true
            enemy.vy = 0
        elseif col.normal.x ~= 0 then
            blockedX = true
        end
    end

    return blockedX
end

local function moveFlying(enemy, dt, world, desiredVX, desiredVY)
    enemy.vx = desiredVX or 0
    enemy.vy = desiredVY or 0

    if enemy.vx > 1 then
        enemy.facingRight = true
    elseif enemy.vx < -1 then
        enemy.facingRight = false
    end

    local goalX = enemy.x + enemy.vx * dt
    local goalY = enemy.y + enemy.vy * dt
    local actualX, actualY = world:move(enemy, goalX, goalY, enemy.filter)
    enemy.x = actualX
    enemy.y = actualY
end

local function startPatrolPause(enemy)
    enemy.patrolPauseTimer = randRange(enemy.ai.patrolPauseMin, enemy.ai.patrolPauseMax)
    enemy.patrolTargetX = nil
end

local function buildNoiseSense(enemy, noiseEvents)
    if not noiseEvents or #noiseEvents == 0 then
        return nil
    end

    local ex, ey = enemyCenter(enemy)
    local bestEvent = nil
    local bestScore = -math.huge
    for _, event in ipairs(noiseEvents) do
        if event.age <= enemy.ai.hearingMemory then
            local dx, dy, dist = distanceBetween(ex, ey, event.x, event.y)
            if dist <= event.radius then
                local score = (event.radius - dist) - event.age * 60
                if score > bestScore then
                    bestScore = score
                    bestEvent = {
                        x = event.x,
                        y = event.y,
                        dx = dx,
                        dy = dy,
                        dist = dist,
                        kind = event.kind or "noise",
                    }
                end
            end
        end
    end

    return bestEvent
end

local function buildSharedAlert(enemy, enemies)
    if not enemies then
        return nil
    end

    local ex, ey = enemyCenter(enemy)
    local bestAlert = nil
    local bestAge = math.huge
    for _, other in ipairs(enemies) do
        if other ~= enemy and other.alive and other.lastKnownTarget and other.alertMeter and other.alertMeter >= 0.65 then
            local _, _, dist = distanceBetween(ex, ey, other.x + other.w * 0.5, other.y + other.h * 0.5)
            if dist <= enemy.ai.groupAlertRange and isRecent(other.lastKnownAge, enemy.ai.groupAlertMemory) then
                if other.lastKnownAge < bestAge then
                    bestAge = other.lastKnownAge
                    bestAlert = {
                        x = other.lastKnownTarget.x,
                        y = other.lastKnownTarget.y,
                        kind = "ally",
                    }
                end
            end
        end
    end

    return bestAlert
end

local function countAlliesNearPlayer(enemy, enemies, px, py, radius)
    if not enemies then
        return 0
    end

    local count = 0
    local radius2 = radius * radius
    for _, other in ipairs(enemies) do
        if other ~= enemy and other.alive then
            local ox, oy = enemyCenter(other)
            local dx = ox - px
            local dy = oy - py
            if dx * dx + dy * dy <= radius2 then
                count = count + 1
            end
        end
    end
    return count
end

local function buildSenses(enemy, world, context)
    local player = context.player
    local ex, ey = enemyCenter(enemy)
    local px, py = playerCenter(player)
    local dx, dy, dist = distanceBetween(ex, ey, px, py)
    local visualRange = math.max(enemy.ai.sightRange, enemy.aggroRange or 0)
    local closeSight = dist <= enemy.ai.closeSightRange
    local los = dist <= visualRange and hasLineOfSight(world, ex, ey, px, py)
    local facingDir = enemy.facingRight and 1 or -1
    local dot = dist > 0 and (dx / dist) * facingDir or 1
    local fovLimit = math.cos((enemy.ai.fieldOfView or math.pi) * 0.5)
    local relaxedFov = enemy.alertMeter >= 0.7 or enemy.state == "search" or enemy.state == "chase"
    local visible = dist <= visualRange and los and (closeSight or relaxedFov or dot >= fovLimit)

    local playerFeetY = py + PLAYER_FEET_OFFSET
    local enemyFeetY = enemy.y + enemy.h
    local playerBelow = playerFeetY > enemyFeetY + 10
    local horizDist = math.abs(dx)
    local canShoot = enemy.behavior == "ranged"
        and enemyCanAttack(enemy)
        and dist <= enemy.attackRange * 1.1
        and los
        and horizDist <= enemy.attackRange * 1.05
        and math.abs(dy) <= (enemy.ai.attackHeightTolerance or enemy.attackRange * 1.45)

    local noise = buildNoiseSense(enemy, context.noiseEvents)
    local shared = buildSharedAlert(enemy, context.enemies)

    return {
        ex = ex,
        ey = ey,
        px = px,
        py = py,
        dx = dx,
        dy = dy,
        dist = dist,
        horizDist = horizDist,
        los = los,
        visible = visible,
        noise = noise,
        heard = noise ~= nil,
        shared = shared,
        playerBelow = playerBelow,
        canShoot = canShoot,
        crowdCount = countAlliesNearPlayer(enemy, context.enemies, px, py, enemy.ai.allyCrowdRadius),
    }
end

local function updateAlertMeter(enemy, dt, senses)
    local gain
    if senses.visible then
        gain = dt / enemy.ai.reactionTime
    elseif senses.heard then
        gain = dt / (enemy.ai.reactionTime * 1.8)
    elseif senses.shared then
        gain = dt / (enemy.ai.reactionTime * 2.2)
    else
        gain = -dt / enemy.ai.calmDownTime
    end

    enemy.alertMeter = clamp(enemy.alertMeter + gain * enemy.aggressionScale, 0, 1.25)
end

local function rememberTarget(enemy, x, y, source)
    enemy.lastKnownTarget = { x = x, y = y, source = source }
    enemy.lastKnownAge = 0
    if source == "visual" then
        enemy.lastSeenAge = 0
    elseif source == "noise" then
        enemy.lastHeardAge = 0
    end
end

local function updateTargetMemory(enemy, senses)
    if senses.visible then
        rememberTarget(enemy, senses.px, senses.py, "visual")
    elseif senses.heard then
        rememberTarget(enemy, senses.noise.x, senses.noise.y, "noise")
    elseif senses.shared then
        if not enemy.lastKnownTarget or enemy.lastKnownAge > 0.15 then
            rememberTarget(enemy, senses.shared.x, senses.shared.y, "ally")
            enemy.lastKnownAge = 0.15
        end
    end
end

local function pickGroundPursuit(enemy, world, targetX, targetY, speed)
    local targetBelow = targetY and targetY > enemy.y + enemy.h + 10
    if targetBelow then
        local left, right = getPlatformSurfaceExtents(world, enemy.x, enemy.y, enemy.w, enemy.h)
        if left and right then
            local mid = (left + right) * 0.5
            local edgeDir = (targetX < mid) and -1 or 1
            return edgeDir * speed, true
        end
    end

    local ex = enemy.x + enemy.w * 0.5
    local dx = targetX - ex
    if math.abs(dx) <= 6 then
        return 0, false
    end

    return sign(dx) * speed, false
end

local function nextSearchTarget(enemy, world)
    local anchor = enemy.lastKnownTarget or { x = enemy.homeX, y = enemy.homeY }
    enemy.searchSweepDir = -(enemy.searchSweepDir or enemy.flankBias or 1)
    local targetX = anchor.x + enemy.searchSweepDir * enemy.ai.searchSweepDistance

    local left, right = getPlatformSurfaceExtents(world, enemy.x, enemy.y, enemy.w, enemy.h)
    if left and right then
        targetX = clamp(targetX, left + 6, right - enemy.w - 6)
    end

    enemy.searchTarget = {
        x = targetX,
        y = anchor.y,
    }

    return enemy.searchTarget
end

local function shouldFrontlineReposition(enemy, senses)
    if senses.dist > enemy.ai.preferredMaxDistance + 14 then
        return false
    end
    return senses.crowdCount >= enemy.ai.maxFrontlineAllies
end

local function decideGroundState(enemy, senses)
    local confirmed = enemy.alertMeter >= 1
    local hasTargetMemory = enemy.lastKnownTarget and isRecent(enemy.lastKnownAge, enemy.ai.sightMemory)
    local withinAttack = senses.dist <= enemy.attackRange + 4
    local canAttack = enemyCanAttack(enemy)

    if confirmed then
        if enemy.behavior == "ranged" then
            if canAttack and senses.visible and senses.dist < enemy.ai.retreatDistance then
                return "reposition"
            end
            if canAttack
                and senses.canShoot
                and senses.dist >= enemy.ai.preferredMinDistance - 10
                and senses.dist <= enemy.ai.preferredMaxDistance + 36 then
                return "attack"
            end
            if hasTargetMemory then
                return senses.visible and "chase" or "search"
            end
        else
            if canAttack and senses.visible and withinAttack and not shouldFrontlineReposition(enemy, senses) then
                return "attack"
            end
            if senses.visible and shouldFrontlineReposition(enemy, senses) then
                return "reposition"
            end
            if hasTargetMemory then
                return senses.visible and "chase" or "search"
            end
        end
    end

    if senses.visible or senses.heard or senses.shared then
        if enemy.alertMeter >= 0.45 then
            return "investigate"
        end
        return "suspicious"
    end

    if enemy.patrolPauseTimer > 0 then
        return "idle"
    end
    return "patrol"
end

local function decideFlyingState(enemy, senses)
    local confirmed = enemy.alertMeter >= 1
    local hasTargetMemory = enemy.lastKnownTarget and isRecent(enemy.lastKnownAge, enemy.ai.sightMemory)
    local canAttack = enemyCanAttack(enemy)

    if confirmed then
        if canAttack and senses.visible and enemy.attackTimer <= 0 and senses.dist <= enemy.attackRange * 1.1 then
            return "attack"
        end
        if canAttack and senses.visible and senses.dist < enemy.ai.retreatDistance then
            return "reposition"
        end
        if hasTargetMemory then
            return senses.visible and "chase" or "search"
        end
    end

    if senses.visible or senses.heard or senses.shared then
        if enemy.alertMeter >= 0.45 then
            return "investigate"
        end
        return "suspicious"
    end

    if enemy.patrolPauseTimer > 0 then
        return "idle"
    end
    return "patrol"
end

local function decideState(enemy, senses)
    if not enemy.alive then
        return "dead"
    end

    if enemy.behavior == "flying" then
        return decideFlyingState(enemy, senses)
    end
    return decideGroundState(enemy, senses)
end

local function meleeChaseSpeed(enemy, senses)
    local ai = enemy.ai
    local speedMult = ai.chaseSpeedMultiplier
    if senses.dist > enemy.attackRange + (ai.rushDistance or 56) then
        speedMult = (ai.rushSpeedMultiplier or speedMult)
            + math.min(
                (ai.rushSpeedCap or speedMult) - (ai.rushSpeedMultiplier or speedMult),
                (senses.dist - enemy.attackRange - (ai.rushDistance or 56)) * 0.0018
            )
    end
    speedMult = math.min(ai.rushSpeedCap or speedMult, speedMult)
    return enemy.speed * speedMult * enemy.aggressionScale
end

local function updateGroundState(enemy, dt, world, senses)
    local desiredVX = 0
    local allowDrop = false
    local blockedX = false

    if enemy.state == "idle" then
        desiredVX = 0
    elseif enemy.state == "patrol" then
        if not enemy.patrolTargetX then
            choosePatrolTarget(enemy, world)
        end
        local targetX = enemy.patrolTargetX or enemy.x
        if math.abs((enemy.x + enemy.w * 0.5) - targetX) <= 8 then
            startPatrolPause(enemy)
            desiredVX = 0
        else
            desiredVX = sign(targetX - (enemy.x + enemy.w * 0.5)) * enemy.speed * enemy.ai.patrolSpeedMultiplier
        end
    elseif enemy.state == "suspicious" then
        desiredVX = 0
        if enemy.lastKnownTarget then
            enemy.facingRight = enemy.lastKnownTarget.x >= (enemy.x + enemy.w * 0.5)
        end
    elseif enemy.state == "investigate" then
        local target = enemy.lastKnownTarget or { x = enemy.homeX, y = enemy.homeY }
        desiredVX, allowDrop = pickGroundPursuit(enemy, world, target.x, target.y, enemy.speed * enemy.ai.investigateSpeedMultiplier)
    elseif enemy.state == "search" then
        local target = enemy.searchTarget or nextSearchTarget(enemy, world)
        if math.abs((enemy.x + enemy.w * 0.5) - target.x) <= 10 then
            nextSearchTarget(enemy, world)
            target = enemy.searchTarget
        end
        desiredVX, allowDrop = pickGroundPursuit(enemy, world, target.x, target.y, enemy.speed * 0.7)
    elseif enemy.state == "chase" then
        local target = enemy.lastKnownTarget or { x = senses.px, y = senses.py }
        local chaseSpeed = enemy.behavior == "melee"
            and meleeChaseSpeed(enemy, senses)
            or (enemy.speed * enemy.ai.chaseSpeedMultiplier)
        desiredVX, allowDrop = pickGroundPursuit(enemy, world, target.x, target.y, chaseSpeed)
    elseif enemy.state == "reposition" then
        local dir = enemy.repositionDir or enemy.flankBias or 1
        desiredVX = dir * enemy.speed * 0.78
    elseif enemy.state == "attack" then
        desiredVX = 0
        if enemy.behavior == "ranged" and enemy.attackTimer > enemy.attackCooldown * 0.42 then
            desiredVX = (enemy.repositionDir or enemy.flankBias or 1) * enemy.speed * 0.35
        end
    end

    blockedX = moveGround(enemy, dt, world, desiredVX, allowDrop)
    if blockedX then
        enemy.repositionDir = -(enemy.repositionDir or enemy.flankBias or 1)
        if enemy.state == "patrol" then
            choosePatrolTarget(enemy, world, enemy.repositionDir)
        end
    end
end

local function updateFlyingState(enemy, dt, world, senses)
    local desiredVX = 0
    local desiredVY = 0
    local bobTarget = enemy.homeY + math.sin(love.timer.getTime() * BOB_SPEED + enemy.aiBobOffset) * BOB_HEIGHT

    if enemy.state == "idle" then
        desiredVX = 0
        desiredVY = (bobTarget - enemy.y) * 2
        enemy.swoopTarget = nil
    elseif enemy.state == "patrol" then
        if not enemy.patrolTargetX then
            enemy.patrolTargetX = enemy.homeX + enemy.ai.patrolRadius * (enemy.patrolDir or enemy.flankBias or 1)
        end
        local dx = enemy.patrolTargetX - enemy.x
        if math.abs(dx) <= 16 then
            startPatrolPause(enemy)
            enemy.patrolDir = -(enemy.patrolDir or enemy.flankBias or 1)
            enemy.patrolTargetX = nil
        else
            desiredVX = sign(dx) * enemy.speed * enemy.ai.patrolSpeedMultiplier
        end
        desiredVY = (bobTarget - enemy.y) * 2
        enemy.swoopTarget = nil
    elseif enemy.state == "suspicious" then
        local target = enemy.lastKnownTarget or { x = enemy.homeX, y = enemy.homeY }
        desiredVX = (target.x - enemy.x) * 0.45
        desiredVY = ((target.y - 36) - enemy.y) * 0.45
    elseif enemy.state == "investigate" or enemy.state == "search" or enemy.state == "chase" or enemy.state == "reposition" then
        local target = enemy.lastKnownTarget or { x = senses.px, y = senses.py }
        if enemy.state == "search" then
            target = enemy.searchTarget or nextSearchTarget(enemy, world)
            if math.abs(enemy.x - target.x) <= 14 then
                nextSearchTarget(enemy, world)
                target = enemy.searchTarget
            end
        end

        local orbitDir = enemy.state == "reposition" and -(enemy.repositionDir or enemy.flankBias or 1)
            or (enemy.repositionDir or enemy.flankBias or 1)
        local desiredX = target.x - orbitDir * enemy.ai.preferredMinDistance
        local desiredY = target.y - 46
        local mx = desiredX - enemy.x
        local my = desiredY - enemy.y
        local md = math.max(1, math.sqrt(mx * mx + my * my))
        local speed = enemy.speed * (enemy.state == "investigate" and enemy.ai.investigateSpeedMultiplier or enemy.ai.chaseSpeedMultiplier)
        desiredVX = (mx / md) * speed
        desiredVY = (my / md) * speed
        enemy.swoopTarget = nil
    elseif enemy.state == "attack" then
        if not enemy.swoopTarget then
            enemy.swoopTarget = { x = senses.px, y = senses.py }
            enemy.swoopTimer = 0.75
            if enemy.swoopAnimTimer then
                enemy.swoopAnimTimer = 0.4
            end
        end

        enemy.swoopTimer = math.max(0, (enemy.swoopTimer or 0) - dt)
        local target = enemy.swoopTarget or { x = senses.px, y = senses.py }
        local sx = target.x - enemy.x
        local sy = target.y - enemy.y
        local sd = math.max(1, math.sqrt(sx * sx + sy * sy))
        desiredVX = (sx / sd) * (enemy.swoopSpeed or 280)
        desiredVY = (sy / sd) * (enemy.swoopSpeed or 280)
        if sd < 20 or enemy.swoopTimer <= 0 then
            enemy.swoopTarget = nil
            enemy.attackTimer = enemy.attackCooldown
            maybeChangeState(enemy, "reposition", true)
        end
    end

    moveFlying(enemy, dt, world, desiredVX, desiredVY)
end

local function tryRangedAttack(enemy, senses)
    if not enemyCanAttack(enemy) or enemy.state ~= "attack" or enemy.attackTimer > 0 or not senses.canShoot then
        return nil
    end

    enemy.attackTimer = enemy.attackCooldown
    enemy.repositionDir = -sign(senses.dx ~= 0 and senses.dx or enemy.repositionDir or enemy.flankBias or 1)

    if enemy.gsAnim then
        enemy.gsAnim = "shoot"
        enemy.spriteFrame = 1
        enemy.spriteTimer = 0
        enemy.gsShootAnimDone = false
    end
    if enemy.attackAnimDuration then
        enemy.attackAnimTimer = enemy.attackAnimDuration
    end

    local angle = math.atan2(senses.dy, senses.dx)
    local spread = math.max(0.01, enemy.ai.attackInaccuracy / enemy.accuracyScale)
    angle = angle + randSigned(spread)
    local source_ref = SourceRef.new({
        owner_actor_id = enemy.actorId or enemy.typeId or "enemy",
        owner_source_type = "enemy_attack",
        owner_source_id = enemy.typeId or enemy.name or "enemy",
    })
    local packet = DamagePacket.new({
        kind = "direct_hit",
        family = "physical",
        base_min = enemy.damage,
        base_max = enemy.damage,
        can_crit = true,
        counts_as_hit = true,
        can_trigger_on_hit = true,
        can_trigger_proc = true,
        can_lifesteal = false,
        source = source_ref,
        tags = { "projectile", "enemy" },
        snapshot_data = {
            source_context = {
                base_min = enemy.damage,
                base_max = enemy.damage,
                damage = 1,
                physical_damage = 0,
                magical_damage = 0,
                true_damage = 0,
                crit_chance = 0,
                crit_damage = 1.5,
                armor_pen = 0,
                magic_pen = 0,
            },
        },
        metadata = {
            source_context_kind = "enemy_projectile",
            source_attack_id = source_ref.owner_source_id,
        },
    })

    return {
        x = enemy.x + enemy.w * 0.5,
        y = enemy.y + enemy.h * 0.5,
        angle = angle,
        speed = enemy.bulletSpeed or 250,
        packet = packet,
        source_actor = enemy,
        damage = enemy.damage,
        fromEnemy = true,
        damage_family = "physical",
        packet_kind = "direct_hit",
        damage_tags = { "projectile", "enemy" },
    }
end

local function updateStuckState(enemy, dt, senses)
    if enemy.behavior == "flying" then
        enemy.stuckTimer = 0
        enemy.progressSampleX = enemy.x
        enemy.progressSampleY = enemy.y
        return
    end

    local movedX = math.abs(enemy.x - (enemy.progressSampleX or enemy.x))
    local movedY = math.abs(enemy.y - (enemy.progressSampleY or enemy.y))
    local activeMove = math.abs(enemy.vx or 0) > 12
    local shouldCare = activeMove and (enemy.state == "chase" or enemy.state == "investigate" or enemy.state == "reposition" or enemy.state == "search")

    if shouldCare and movedX + movedY < 1.5 then
        enemy.stuckTimer = enemy.stuckTimer + dt
        if enemy.stuckTimer >= enemy.ai.stuckTimeout then
            enemy.stuckTimer = 0
            enemy.repositionDir = -(enemy.repositionDir or enemy.flankBias or 1)
            maybeChangeState(enemy, "reposition", true)
        end
    else
        enemy.stuckTimer = math.max(0, enemy.stuckTimer - dt * 2)
    end

    enemy.progressSampleX = enemy.x
    enemy.progressSampleY = enemy.y
end

local function refreshTimers(enemy, dt)
    enemy.stateTimer = (enemy.stateTimer or 0) + dt
    enemy.decisionTimer = math.max(-dt, (enemy.decisionTimer or 0) - dt)
    enemy.lastKnownAge = (enemy.lastKnownAge or math.huge) + dt
    enemy.lastSeenAge = (enemy.lastSeenAge or math.huge) + dt
    enemy.lastHeardAge = (enemy.lastHeardAge or math.huge) + dt
    enemy.patrolPauseTimer = math.max(0, (enemy.patrolPauseTimer or 0) - dt)
    enemy.searchTimer = math.max(0, (enemy.searchTimer or 0) - dt)
    enemy.investigateTimer = math.max(0, (enemy.investigateTimer or 0) - dt)
    enemy.repositionTimer = math.max(0, (enemy.repositionTimer or 0) - dt)
end

local function keepStateSane(enemy)
    if enemy.state == "investigate" and enemy.investigateTimer <= 0 and enemy.alertMeter < 1 then
        maybeChangeState(enemy, "search", true)
    elseif enemy.state == "search" and enemy.searchTimer <= 0 and enemy.alertMeter < 0.55 then
        if enemy.patrolPauseTimer > 0 then
            maybeChangeState(enemy, "idle", true)
        else
            maybeChangeState(enemy, "patrol", true)
        end
    elseif enemy.state == "reposition" and enemy.repositionTimer <= 0 then
        maybeChangeState(enemy, enemy.alertMeter >= 1 and "chase" or "investigate", true)
    elseif enemy.state == "patrol" and enemy.patrolPauseTimer > 0 then
        maybeChangeState(enemy, "idle", true)
    end
end

local function updatePeacefulBehavior(enemy, dt, world)
    local senses = blankSenses(enemy)
    enemy.alertMeter = 0
    enemy.lastKnownTarget = nil
    enemy.lastKnownAge = math.huge
    enemy.lastSeenAge = math.huge
    enemy.lastHeardAge = math.huge

    local desiredState = enemy.patrolPauseTimer > 0 and "idle" or "patrol"
    maybeChangeState(enemy, desiredState, true)

    if enemy.behavior == "flying" then
        updateFlyingState(enemy, dt, world, senses)
    else
        updateGroundState(enemy, dt, world, senses)
    end

    updateStuckState(enemy, dt, senses)
    return senses
end

local function buildDebugInfo(enemy, senses)
    enemy.debugAI = {
        state = enemy.state,
        visible = senses.visible,
        heard = senses.heard,
        shared = senses.shared ~= nil,
        alert = enemy.alertMeter,
        memory = enemy.lastKnownAge,
        attack = math.max(0, enemy.attackTimer),
        target = enemy.lastKnownTarget and enemy.lastKnownTarget.source or "-",
        mode = enemy.peaceful and "peaceful" or (enemy.unarmed and "unarmed" or nil),
    }
end

function EnemyAI.init(enemy, data)
    enemy.ai = cloneValue(data.ai or {})
    enemy.ai.reactionTime = math.max(0.08, (enemy.ai.reactionTime or 0.25) + randSigned(enemy.ai.reactionJitter or 0))
    enemy.ai.decisionInterval = math.max(0.06, (enemy.ai.decisionInterval or 0.18) + randSigned(enemy.ai.decisionJitter or 0))

    local preferredOffset = randSigned(enemy.ai.preferredDistanceJitter or 0)
    enemy.ai.preferredMinDistance = math.max(0, (enemy.ai.preferredMinDistance or 16) + preferredOffset)
    enemy.ai.preferredMaxDistance = math.max(
        enemy.ai.preferredMinDistance + 8,
        (enemy.ai.preferredMaxDistance or 32) + preferredOffset
    )
    enemy.ai.attackInaccuracy = math.max(0, (enemy.ai.attackInaccuracy or 0) + randSigned(enemy.ai.attackInaccuracyJitter or 0))

    enemy.aggressionScale = 0.9 + GameRng.randomFloat("enemy_ai.aggression_scale", 0, 0.25)
    enemy.accuracyScale = 0.88 + GameRng.randomFloat("enemy_ai.accuracy_scale", 0, 0.3)
    enemy.flankBias = GameRng.randomChance("enemy_ai.flank_bias", 0.5) and -1 or 1
    enemy.aiBobOffset = GameRng.randomFloat("enemy_ai.bob_offset", 0, math.pi * 2)

    enemy.homeX = enemy.x
    enemy.homeY = enemy.homeY or enemy.y
    enemy.state = "idle"
    enemy.stateTimer = 0
    enemy.decisionTimer = randRange(0.02, enemy.ai.decisionInterval)
    enemy.alertMeter = 0
    enemy.lastKnownTarget = nil
    enemy.lastKnownAge = math.huge
    enemy.lastSeenAge = math.huge
    enemy.lastHeardAge = math.huge
    enemy.searchTimer = 0
    enemy.investigateTimer = 0
    enemy.repositionTimer = 0
    enemy.patrolPauseTimer = randRange(enemy.ai.patrolPauseMin, enemy.ai.patrolPauseMax)
    enemy.patrolDir = enemy.flankBias
    enemy.repositionDir = enemy.flankBias
    enemy.patrolTargetX = nil
    enemy.searchTarget = nil
    enemy.swoopTimer = 0
    enemy.progressSampleX = enemy.x
    enemy.progressSampleY = enemy.y
    enemy.stuckTimer = 0
    enemy.debugAI = nil
end

function EnemyAI.onDamaged(enemy)
    if enemy.peaceful then
        return
    end
    enemy.alertMeter = math.max(enemy.alertMeter or 0, 0.8)
    enemy.decisionTimer = 0
    if enemy.state == "idle" or enemy.state == "patrol" then
        setState(enemy, "suspicious")
    end
end

function EnemyAI.update(enemy, dt, world, context)
    if not enemy.alive then
        enemy.state = "dead"
        return nil
    end

    local player = context and context.player
    if not player or player.dying then
        enemy.debugAI = {
            state = enemy.state,
            visible = false,
            heard = false,
            shared = false,
            alert = enemy.alertMeter or 0,
            memory = enemy.lastKnownAge or math.huge,
            attack = math.max(0, enemy.attackTimer or 0),
            target = "-",
        }
        if enemy.behavior == "flying" then
            moveFlying(enemy, dt, world, 0, (enemy.homeY - enemy.y) * 2)
        else
            moveGround(enemy, dt, world, 0, false)
        end
        return nil
    end

    refreshTimers(enemy, dt)

    if enemy.peaceful then
        local senses = updatePeacefulBehavior(enemy, dt, world)
        buildDebugInfo(enemy, senses)
        return nil
    end

    local senses = buildSenses(enemy, world, context)
    updateAlertMeter(enemy, dt, senses)
    updateTargetMemory(enemy, senses)

    local desiredState = decideState(enemy, senses)
    local urgent = desiredState == "attack"
        or enemy.state == "attack"
        or senses.visible
        or enemy.stuckTimer > enemy.ai.stuckTimeout * 0.5
    maybeChangeState(enemy, desiredState, urgent)
    keepStateSane(enemy)

    if enemy.behavior == "flying" then
        updateFlyingState(enemy, dt, world, senses)
    else
        updateGroundState(enemy, dt, world, senses)
    end

    updateStuckState(enemy, dt, senses)
    buildDebugInfo(enemy, senses)

    if enemy.behavior == "ranged" then
        return tryRangedAttack(enemy, senses)
    end

    return nil
end

return EnemyAI
