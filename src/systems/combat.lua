local Bullet = require("src.entities.bullet")
local Pickup = require("src.entities.pickup")

local Combat = {}

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
            b.hitEnemy:takeDamage(b.damage, world)

            -- Explosive rounds: AOE damage to nearby enemies
            if b.explosive and not b.fromEnemy then
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
            player:takeDamage(b.damage)
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

    return drops
end

function Combat.checkMeleeEnemies(enemies, player)
    for _, enemy in ipairs(enemies) do
        if enemy.alive and enemy:canDamagePlayer(player.x, player.y, player.w, player.h) then
            if player:takeDamage(enemy.damage) then
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
                if dist <= enemy.attackRange then
                    if player:takeDamage(enemy.damage) then
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

function Combat.findAutoTarget(enemies, player, world, viewL, viewT, viewR, viewB)
    local px = player.x + player.w / 2
    local py = player.y + player.h / 2

    local bestEnemy = nil
    local bestDist = math.huge

    for _, e in ipairs(enemies) do
        if e.alive then
            local ex = e.x + e.w / 2
            local ey = e.y + e.h / 2
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

    if bestEnemy then
        return bestEnemy.x + bestEnemy.w / 2, bestEnemy.y + bestEnemy.h / 2
    end

    return nil, nil
end

function Combat.checkPickups(pickups, player)
    local leveledUp = false
    local i = 1
    while i <= #pickups do
        local p = pickups[i]
        local px = player.x + player.w / 2
        local py = player.y + player.h / 2
        local dx = (p.x + p.w / 2) - px
        local dy = (p.y + p.h / 2) - py
        local dist = math.sqrt(dx * dx + dy * dy)

        if dist < 30 then
            if p.pickupType == "xp" then
                leveledUp = player:addXP(p.value) or leveledUp
            elseif p.pickupType == "gold" then
                player:addGold(p.value)
            elseif p.pickupType == "health" then
                player:heal(p.value)
            end
            p.alive = false
        end

        if not p.alive then
            table.remove(pickups, i)
        else
            i = i + 1
        end
    end

    return leveledUp
end

return Combat
