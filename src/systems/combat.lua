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
            b.hitEnemy:takeDamage(b.damage)
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

    table.insert(drops, {
        x = enemy.x,
        y = enemy.y,
        type = "xp",
        value = enemy.xpValue,
    })

    if enemy.goldValue > 0 and math.random() < 0.7 then
        table.insert(drops, {
            x = enemy.x + 10,
            y = enemy.y,
            type = "gold",
            value = enemy.goldValue,
        })
    end

    if math.random() < 0.1 then
        table.insert(drops, {
            x = enemy.x - 5,
            y = enemy.y,
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
        if enemy.alive then
            local ex = enemy.x + enemy.w / 2
            local ey = enemy.y + enemy.h / 2
            local px = player.x + player.w / 2
            local py = player.y + player.h / 2
            local dist = math.sqrt((ex - px)^2 + (ey - py)^2)
            if dist < (enemy.w + player.w) / 2 then
                if (enemy.behavior == "melee" or enemy.behavior == "flying") then
                    if player:takeDamage(enemy.damage) then
                        enemy:onContactDamage()
                    end
                end
            end
        end
    end
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
