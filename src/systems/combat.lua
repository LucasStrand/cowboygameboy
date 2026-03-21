local Bullet = require("src.entities.bullet")
local Pickup = require("src.entities.pickup")
local Guns   = require("src.data.guns")
local Vision = require("src.data.vision")
local DamageNumbers = require("src.ui.damage_numbers")
local ImpactFX = require("src.systems.impact_fx")
local Sfx = require("src.systems.sfx")

local Combat = {}

-- Must be this close to the player (after attraction) to collect
local PICKUP_COLLECT_RADIUS = 26

local function pickupAttractRadius(player)
    local s = player:getEffectiveStats()
    return math.max(48, (s.pickupRadius or 180) + (s.luck or 0) * 3)
end

function Combat.spawnBullet(world, data)
    local b = Bullet.new(data)
    world:add(b, b.x, b.y, b.w, b.h)
    return b
end

function Combat.updateBullets(bullets, dt, world, enemies, player)
    local allDrops = {}
    local i = 1
    while i <= #bullets do
        local b = bullets[i]
        b:update(dt, world)

        if b.hitEnemy then
            local hitX = b.x + b.w / 2
            local hitY = b.y + b.h / 2
            b.hitEnemy:takeDamage(b.damage, world)
            DamageNumbers.spawn(hitX, hitY, b.damage, "out")
            -- Ult bullets get a massive explosion effect
            local fxScale = b.ultBullet and 2.0 or nil
            ImpactFX.spawn(hitX, hitY, "hit_enemy", fxScale)
            if b.ultBullet then
                ImpactFX.spawn(hitX, hitY - 8, "melee", fxScale)
            end
            if not b.fromEnemy then
                Sfx.play("hit_enemy")
            end

            -- Explosive rounds: AOE damage to nearby enemies
            if b.explosive and not b.fromEnemy then
                Sfx.play("explosion")
                local explosionRadius = 60
                local aoeDamage = math.floor(b.damage * 0.5)
                local bx = b.x + b.w / 2
                local by = b.y + b.h / 2
                local aoeHits = 0
                for _, e in ipairs(enemies) do
                    if e.alive and e ~= b.hitEnemy then
                        local ex = e.x + e.w / 2
                        local ey = e.y + e.h / 2
                        local dist = math.sqrt((ex - bx)^2 + (ey - by)^2)
                        if dist <= explosionRadius then
                            e:takeDamage(aoeDamage, world)
                            DamageNumbers.spawn(ex, ey - 4, aoeDamage, "out")
                            aoeHits = aoeHits + 1
                        end
                    end
                end
                if debugLog and aoeHits > 0 then
                    debugLog("Explosion hit " .. aoeHits .. " nearby")
                end
            end
        end

        if b.hitPlayer then
            local ok, dmg = player:takeDamage(b.damage)
            if ok then
                DamageNumbers.spawn(b.x + b.w / 2, b.y + b.h / 2, dmg, "in")
                ImpactFX.spawn(b.x + b.w / 2, b.y + b.h / 2, "hit_enemy")
            end
        end

        if not b.alive then
            if world:hasItem(b) then
                world:remove(b)
            end
            table.remove(bullets, i)
        else
            i = i + 1
        end
    end

    return #allDrops > 0 and allDrops or nil
end

function Combat.onEnemyKilled(enemy, player)
    local drops = {}

    -- Build ultimate charge
    player:addUltCharge()

    if player.stats.lifestealOnKill > 0 then
        player:heal(player.stats.lifestealOnKill)
    end

    -- Spawn at feet (pickup is 10×10) so loot sits on the floor, not inside the corpse AABB
    local pw = 10
    local baseX = enemy.x + enemy.w / 2 - pw / 2
    local baseY = enemy.y + enemy.h - pw

    table.insert(drops, {
        x = baseX,
        y = baseY,
        type = "xp",
        value = enemy.xpValue,
    })

    if enemy.goldValue > 0 and math.random() < 0.7 then
        table.insert(drops, {
            x = baseX + 12,
            y = baseY,
            type = "gold",
            value = enemy.goldValue,
        })
    end

    if math.random() < 0.1 then
        table.insert(drops, {
            x = baseX - 12,
            y = baseY,
            type = "health",
            value = 15,
        })
    end

    -- Weapon drop (rare)
    local luck = player:getEffectiveStats().luck or 0
    local weaponDropChance = 0.04 + luck * 0.02
    if math.random() < weaponDropChance then
        local gunDef = Guns.rollDrop(luck)
        if gunDef then
            table.insert(drops, {
                x = baseX,
                y = baseY - 8,
                type = "weapon",
                value = gunDef,
            })
        end
    end

    return drops
end

function Combat.checkMeleeEnemies(enemies, player)
    for _, enemy in ipairs(enemies) do
        if enemy.alive and enemy:canDamagePlayer(player.x, player.y, player.w, player.h) then
            local ok, dmg = player:takeDamage(enemy.damage)
            if ok then
                local mx = (enemy.x + enemy.w * 0.5 + player.x + player.w * 0.5) * 0.5
                local my = (enemy.y + enemy.h * 0.5 + player.y + player.h * 0.5) * 0.5
                DamageNumbers.spawn(mx, my, dmg, "in")
                enemy:onContactDamage()
            end
        end
    end
end

function Combat.checkContactDamage(enemies, player)
    for _, enemy in ipairs(enemies) do
        if enemy.alive and enemy.attackTimer <= 0 then
            if enemy.behavior == "melee" or enemy.behavior == "flying" then
                local ex = enemy.x + enemy.w / 2
                local ey = enemy.y + enemy.h / 2
                local px = player.x + player.w / 2
                local py = player.y + player.h / 2
                local dist = math.sqrt((ex - px)^2 + (ey - py)^2)
                local hitR = enemy.contactRange or enemy.attackRange
                if dist <= hitR then
                    local ok, dmg = player:takeDamage(enemy.damage)
                    if ok then
                        local mx = (ex + px) * 0.5
                        local my = (ey + py) * 0.5
                        DamageNumbers.spawn(mx, my, dmg, "in")
                        enemy:onContactDamage()
                    else
                        -- Player has iframes but enemy is in range; don't waste the cooldown
                    end
                end
            end
        end
    end
end

local function losFilter(item)
    return item.isPlatform or item.isWall
end

local function hasLineOfSight(world, x1, y1, x2, y2)
    local items, len = world:querySegment(x1, y1, x2, y2, losFilter)
    return len == 0
end

function Combat.findAutoTarget(enemies, player, world, viewL, viewT, viewR, viewB, camera, nightMode, shakeX, shakeY)
    local px = player.x + player.w / 2
    local py = player.y + player.h / 2
    shakeX = shakeX or 0
    shakeY = shakeY or 0

    local bestEnemy = nil
    local bestDist = math.huge

    for _, e in ipairs(enemies) do
        if e.alive then
            local ex = e.x + e.w / 2
            local ey = e.y + e.h / 2
            local inLamp = not nightMode or Vision.isInLightVision(player, ex, ey, camera, shakeX, shakeY)
            if inLamp then
                local onScreen = ex >= viewL and ex <= viewR and ey >= viewT and ey <= viewB
                if onScreen and hasLineOfSight(world, px, py, ex, ey) then
                    local dx = ex - px
                    local dist = dx * dx + (ey - py) * (ey - py)
                    if dist < bestDist then
                        bestDist = dist
                        bestEnemy = e
                    end
                end
            end
        end
    end

    if bestEnemy then
        return bestEnemy.x + bestEnemy.w / 2, bestEnemy.y + bestEnemy.h / 2
    end

    return nil, nil
end

local function enemyListOverlapsMeleeAABB(enemies, hx, hy, hw, hh)
    for _, e in ipairs(enemies) do
        if e.alive then
            if hx < e.x + e.w and hx + hw > e.x and
               hy < e.y + e.h and hy + hh > e.y then
                return true
            end
        end
    end
    return false
end

function Combat.tryAutoMelee(player, enemies, world, viewL, viewT, viewR, viewB, camera, nightMode, shakeX, shakeY)
    if not player.autoMelee or player.blocking then return end
    -- Only when the active slot has no gun (melee stance); gun slot uses auto-fire instead
    if player:getActiveGun() then return end
    local s = player:getEffectiveStats()
    if s.meleeDamage <= 0 then return end
    if player.meleeCooldown > 0 or player.meleeSwingTimer > 0 then return end
    local tx, ty = Combat.findAutoTarget(enemies, player, world, viewL, viewT, viewR, viewB, camera, nightMode, shakeX, shakeY)
    if not tx then
        return
    end
    local cx = player.x + player.w * 0.5
    local cy = player.y + player.h * 0.5
    local ang = math.atan2(ty - cy, tx - cx)
    local hx, hy, hw, hh = player:getMeleeHitboxAABB(ang)
    if not enemyListOverlapsMeleeAABB(enemies, hx, hy, hw, hh) then
        return
    end
    return player:meleeAttack(tx, ty)
end

-- Called every frame while a melee swing is active.  Hits each enemy at most
-- once per swing (player.meleeHitEnemies guards duplicate hits).
-- Uses hitbox overlap only — platforms do not block melee (unlike bullets / LOS).
function Combat.checkPlayerMelee(player, enemies)
    if player.meleeSwingTimer <= 0 then return end

    local s   = player:getEffectiveStats()
    local dmg = math.floor(s.meleeDamage * s.damageMultiplier)
    local hx, hy, hw, hh = player:getMeleeHitbox()

    for _, e in ipairs(enemies) do
        if e.alive and not player.meleeHitEnemies[e] then
            -- AABB overlap
            if hx < e.x + e.w and hx + hw > e.x and
               hy < e.y + e.h and hy + hh > e.y then
                e:takeDamage(dmg, nil)
                DamageNumbers.spawn(e.x + e.w / 2, e.y + e.h / 2 - 4, dmg, "out")
                ImpactFX.spawn(e.x + e.w / 2, e.y + e.h / 2, "melee", nil, player.meleeAimAngle)
                Sfx.play("melee_hit")
                player.meleeHitEnemies[e] = true
                player.meleeHitFlashTimer = 0.2
                -- Knockback along melee aim (same axis as the swing / shot)
                local a = player.meleeAimAngle
                e.vx = (e.vx or 0) + math.cos(a) * s.meleeKnockback
                e.vy = (e.vy or 0) + math.sin(a) * s.meleeKnockback
                if debugLog then
                    debugLog("Melee hit " .. (e.name or "enemy") .. " for " .. dmg)
                end
            end
        end
    end
end

function Combat.checkPickups(pickups, player, world)
    local leveledUp = false
    local attractR = pickupAttractRadius(player)
    local i = 1
    while i <= #pickups do
        local p = pickups[i]
        local px = player.x + player.w / 2
        local py = player.y + player.h / 2
        local dx = (p.x + p.w / 2) - px
        local dy = (p.y + p.h / 2) - py
        local dist = math.sqrt(dx * dx + dy * dy)

        -- Weapon pickups are NOT attracted — must walk over deliberately
        if dist < attractR and p.pickupType ~= "weapon" then
            p.attracted = true
        end

        local collected = false
        if p.pickupType == "weapon" and p.gunDef then
            -- Weapon: close contact only (no attraction)
            if dist < PICKUP_COLLECT_RADIUS then
                player:equipWeapon(p.gunDef, player.activeWeaponSlot)
                local cx = p.x + p.w / 2
                local cy = p.y + p.h / 2
                DamageNumbers.spawnPickup(cx, cy, p.gunDef.name, "weapon")
                collected = true
            end
        elseif p.attracted and dist < PICKUP_COLLECT_RADIUS then
            local cx = p.x + p.w / 2
            local cy = p.y + p.h / 2
            if p.pickupType == "xp" then
                leveledUp = player:addXP(p.value) or leveledUp
                DamageNumbers.spawnPickup(cx, cy, p.value, "xp")
                Sfx.play("pickup_xp")
            elseif p.pickupType == "gold" then
                player:addGold(p.value)
                DamageNumbers.spawnPickup(cx, cy, p.value, "gold")
                Sfx.play("pickup_gold")
            elseif p.pickupType == "health" then
                player:heal(p.value)
                DamageNumbers.spawnPickup(cx, cy, p.value, "health")
                Sfx.play("pickup_health")
            end
            collected = true
        end

        if collected then
            p.alive = false
        end

        if not p.alive then
            if world and world:hasItem(p) then
                world:remove(p)
            end
            table.remove(pickups, i)
        else
            i = i + 1
        end
    end

    return leveledUp
end

return Combat
