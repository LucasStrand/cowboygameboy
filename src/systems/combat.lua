local Bullet = require("src.entities.bullet")
local Pickup = require("src.entities.pickup")
local Guns   = require("src.data.guns")
local Vision = require("src.data.vision")
local DamageNumbers = require("src.ui.damage_numbers")
local ImpactFX = require("src.systems.impact_fx")
local RoomProps = require("src.systems.room_props")
local Sfx = require("src.systems.sfx")
local DamagePacket = require("src.systems.damage_packet")
local DamageResolver = require("src.systems.damage_resolver")
local Buffs = require("src.systems.buffs")
local GameRng = require("src.systems.game_rng")
local SourceRef = require("src.systems.source_ref")
local AttackPacketBuilder = require("src.systems.attack_packet_builder")

local Combat = {}

local explosiveShakeHook = nil

--- Optional callback(duration, intensity) from gameplay (e.g. game.lua camera shake) for player explosive hits.
function Combat.setExplosiveShakeHook(cb)
    explosiveShakeHook = cb
end

local function tryExplosiveShake(effect_id)
    if not explosiveShakeHook then
        return
    end
    local def = ImpactFX.getDefinition(effect_id)
    local sh = def and def.recommended_shake
    local dur = sh and tonumber(sh.duration) or nil
    local intens = sh and tonumber(sh.intensity) or nil
    if dur and dur > 0 and intens and intens > 0 then
        explosiveShakeHook(dur, intens)
    end
end

-- Must be this close to the player (after attraction) to collect
local PICKUP_COLLECT_RADIUS = 26

local function statusApplyChannel(packet, result, status_id)
    return table.concat({
        "combat.status_apply",
        tostring(status_id),
        tostring(packet.kind or "direct_hit"),
        tostring(packet.source and packet.source.owner_source_id or "unknown"),
        tostring(result and result.target_id or "unknown"),
    }, ".")
end

local function applyStatusApplications(packet, result, source_actor, target_actor, target_kind, world)
    if not packet or not result or not result.applied or not target_actor or not target_actor.statuses then
        return
    end

    for _, app in ipairs(packet.status_applications or {}) do
        local chance = app.chance or 1
        if chance >= 1 or GameRng.randomChance(statusApplyChannel(packet, result, app.id), chance) then
            local snapshot_data = nil
            if app.id == "bleed" then
                local tick_damage = math.max(1, math.floor((result.pre_defense_damage or result.final_damage or 0) * (app.bleed_scalar or 0.18)))
                snapshot_data = {
                    tick_damage = tick_damage,
                    tick_damage_per_stack = true,
                    family = "physical",
                    source_context = {
                        damage = 1,
                        physical_damage = 0,
                        magical_damage = 0,
                        true_damage = 0,
                        crit_chance = 0,
                        crit_damage = 1.5,
                        armor_pen = 0,
                        magic_pen = 0,
                    },
                }
            elseif app.id == "burn" then
                local source_level = source_actor and source_actor.level or 1
                local base_damage = app.base_damage or 2
                local level_scale = app.level_scale or 0
                local tick_damage = math.max(1, math.floor(base_damage * (1 + level_scale * source_level)))
                snapshot_data = {
                    tick_damage = tick_damage,
                    tick_damage_per_stack = true,
                    family = "magical",
                    source_context = {
                        damage = 1,
                        physical_damage = 0,
                        magical_damage = 0,
                        true_damage = 0,
                        crit_chance = 0,
                        crit_damage = 1.5,
                        armor_pen = 0,
                        magic_pen = 0,
                    },
                }
            elseif app.id == "shock" then
                snapshot_data = {
                    overload_damage = math.max(1, math.floor((result.pre_defense_damage or result.final_damage or 0) * (app.overload_damage_scale or 0.75))),
                    overload_stun_duration = app.overload_stun_duration or 0.6,
                    source_context = {
                        damage = 1,
                        physical_damage = 0,
                        magical_damage = 0,
                        true_damage = 0,
                        crit_chance = 0,
                        crit_damage = 1.5,
                        armor_pen = 0,
                        magic_pen = 0,
                    },
                }
            end

            Buffs.applyStatus(target_actor.statuses, {
                id = app.id,
                stacks = app.stacks or 1,
                duration = app.duration,
                source = packet.source,
                source_actor = source_actor,
                target_actor = target_actor,
                family = app.family,
                snapshot_data = snapshot_data,
                runtime_ctx = {
                    owner_actor = target_actor,
                    target_kind = target_kind,
                    world = world,
                },
                metadata = {
                    from_packet_kind = packet.kind,
                    from_family = packet.family,
                    source_tag = app.source_tag,
                },
            })
        end
    end
end

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
            local packet = b.packet or DamagePacket.new({
                kind = b.packet_kind or "direct_hit",
                family = b.damage_family or "physical",
                amount = b.damage,
                source = b.source_ref,
                tags = b.damage_tags,
                target_id = b.hitEnemy.actorId or b.hitEnemy.typeId or b.hitEnemy.name,
            })
            local result = DamageResolver.resolve_direct_hit({
                packet = packet,
                source_actor = b.source_actor,
                target_actor = b.hitEnemy,
                target_kind = "enemy",
                world = world,
            })
            if result.applied then
                applyStatusApplications(packet, result, b.source_actor, b.hitEnemy, "enemy", world)
                DamageNumbers.spawn(hitX, hitY, result.final_damage, "out")
                local fxScale = b.ultBullet and 2.0 or nil
                local metadata = packet.metadata or {}
                local explosiveHit = b.explosive or metadata.explosion_radius ~= nil
                if explosiveHit then
                    local fxId = b.impact_fx_id or metadata.impact_fx_id or "explosion_medium"
                    ImpactFX.spawn(hitX, hitY, fxId)
                    if not b.fromEnemy then
                        tryExplosiveShake(fxId)
                    end
                else
                    ImpactFX.spawn(hitX, hitY, "hit_enemy", { scale_mul = fxScale })
                end
                if b.ultBullet then
                    ImpactFX.spawn(hitX, hitY - 8, "melee", { scale_mul = fxScale })
                end
                if not b.fromEnemy then
                    Sfx.play(explosiveHit and (b.explosion_sfx_id or metadata.explosion_sfx_id or "explosion") or "hit_enemy")
                end
            end
        end

        if b.hitPlayer then
            local packet = b.packet or DamagePacket.new({
                kind = b.packet_kind or "direct_hit",
                family = b.damage_family or "physical",
                amount = b.damage,
                source = b.source_ref or SourceRef.new({
                    owner_actor_id = "enemy",
                    owner_source_type = "projectile",
                    owner_source_id = "enemy_projectile",
                }),
                tags = b.damage_tags or { "projectile", "enemy" },
                target_id = player.actorId or "player",
            })
            local result = DamageResolver.resolve_direct_hit({
                packet = packet,
                source_actor = b.source_actor,
                target_actor = player,
                target_kind = "player",
                world = world,
            })
            if result.applied then
                applyStatusApplications(packet, result, b.source_actor, player, "player", world)
                DamageNumbers.spawn(b.x + b.w / 2, b.y + b.h / 2, result.final_damage, "in")
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

    local secondary_results = DamageResolver.processSecondaryJobs({
        dt = dt,
        world = world,
        enemies = enemies,
        player = player,
    })
    for _, entry in ipairs(secondary_results) do
        DamageNumbers.spawn(entry.x, entry.y - 4, entry.result.final_damage, "out")
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

    if enemy.goldValue > 0 and GameRng.randomChance("combat.enemy_drop.gold", 0.7) then
        table.insert(drops, {
            x = baseX + 12,
            y = baseY,
            type = "gold",
            value = enemy.goldValue,
        })
    end

    if GameRng.randomChance("combat.enemy_drop.health", 0.1) then
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
    if GameRng.randomChance("combat.enemy_drop.weapon", weaponDropChance) then
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
            local packet = AttackPacketBuilder.build_enemy_hit(enemy, "contact")
            packet.target_id = player.actorId or "player"
            local result = DamageResolver.resolve_direct_hit({
                packet = packet,
                source_actor = enemy,
                target_actor = player,
                target_kind = "player",
            })
            if result.applied then
                applyStatusApplications(packet, result, enemy, player, "player", nil)
                local mx = (enemy.x + enemy.w * 0.5 + player.x + player.w * 0.5) * 0.5
                local my = (enemy.y + enemy.h * 0.5 + player.y + player.h * 0.5) * 0.5
                DamageNumbers.spawn(mx, my, result.final_damage, "in")
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
                    local packet = AttackPacketBuilder.build_enemy_hit(enemy, "contact")
                    packet.target_id = player.actorId or "player"
                    local result = DamageResolver.resolve_direct_hit({
                        packet = packet,
                        source_actor = enemy,
                        target_actor = player,
                        target_kind = "player",
                    })
                    if result.applied then
                        applyStatusApplications(packet, result, enemy, player, "player", nil)
                        local mx = (ex + px) * 0.5
                        local my = (ey + py) * 0.5
                        DamageNumbers.spawn(mx, my, result.final_damage, "in")
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
    local base_dmg = math.floor(s.meleeDamage)
    local hx, hy, hw, hh = player:getMeleeHitbox()

    for _, e in ipairs(enemies) do
        if e.alive and not player.meleeHitEnemies[e] then
            -- AABB overlap
            if hx < e.x + e.w and hx + hw > e.x and
               hy < e.y + e.h and hy + hh > e.y then
                local packet = DamagePacket.new({
                    kind = "direct_hit",
                    family = "physical",
                    base_min = base_dmg,
                    base_max = base_dmg,
                    source = SourceRef.new({
                        owner_actor_id = player.actorId or "player",
                        owner_source_type = "melee",
                        owner_source_id = "melee_swing",
                    }),
                    tags = { "melee" },
                    target_id = e.actorId or e.typeId or e.name,
                    snapshot_data = {
                        source_context = {
                            base_min = base_dmg,
                            base_max = base_dmg,
                            damage = s.damageMultiplier or 1,
                            physical_damage = 0,
                            magical_damage = 0,
                            true_damage = 0,
                            crit_chance = s.critChance or 0,
                            crit_damage = s.critDamage or 1.5,
                            armor_pen = s.armorPen or 0,
                            magic_pen = s.magicPen or 0,
                        },
                    },
                    metadata = {
                        source_context_kind = "player_melee",
                    },
                })
                local result = DamageResolver.resolve_direct_hit({
                    packet = packet,
                    source_actor = player,
                    target_actor = e,
                    target_kind = "enemy",
                })
                if result.applied then
                    applyStatusApplications(packet, result, player, e, "enemy", nil)
                    DamageNumbers.spawn(e.x + e.w / 2, e.y + e.h / 2 - 4, result.final_damage, "out")
                    ImpactFX.spawn(e.x + e.w / 2, e.y + e.h / 2, "melee", nil, player.meleeAimAngle)
                    Sfx.play("melee_hit")
                    player.meleeHitEnemies[e] = true
                    player.meleeHitFlashTimer = 0.2
                    local a = player.meleeAimAngle
                    e.vx = (e.vx or 0) + math.cos(a) * s.meleeKnockback
                    e.vy = (e.vy or 0) + math.sin(a) * s.meleeKnockback
                    if debugLog then
                        debugLog("Melee hit " .. (e.name or "enemy") .. " for " .. tostring(result.final_damage))
                    end
                end
            end
        end
    end
end

--- Melee cuts vegetation decor (see `WorldProps.pathLooksVegetation` / `vegetation` on decor entries).
function Combat.checkPlayerMeleeVegetation(player, decorProps)
    if not decorProps or player.meleeSwingTimer <= 0 then return end

    local hx, hy, hw, hh = player:getMeleeHitbox()

    for _, prop in ipairs(decorProps) do
        if prop.vegetation and not prop.cut and not player.meleeHitDecor[prop] then
            local left, top, w, h = RoomProps.getDecorBounds(prop)
            if left and hx < left + w and hx + hw > left and hy < top + h and hy + hh > top then
                prop.cut = true
                local sc = prop.scale or 1
                local sign = (prop.flip and -1 or 1)
                prop.cutFallDx = sign * (26 + math.random() * 22) * sc
                prop.cutFallAngle = (0.2 + math.random() * 0.45) * (prop.cutFallDx >= 0 and 1 or -1)
                player.meleeHitDecor[prop] = true
                player.meleeHitFlashTimer = 0.12
                Sfx.play("melee_hit", { volume = 0.22 })
                local cx = prop.x
                local cy = (prop.footY or 0) + (prop.sink or 0) - 40 * sc
                ImpactFX.spawn(cx, cy, "melee", nil, player.meleeAimAngle)
            end
        end
    end
end

function Combat.checkPickups(pickups, player, world)
    local leveledUp = false
    local baseAttractR = pickupAttractRadius(player)
    local i = 1
    while i <= #pickups do
        local p = pickups[i]
        local px = player.x + player.w / 2
        local py = player.y + player.h / 2
        local dx = (p.x + p.w / 2) - px
        local dy = (p.y + p.h / 2) - py
        local dist = math.sqrt(dx * dx + dy * dy)

        local attractR = p.casinoPayout and math.min(baseAttractR, 46) or baseAttractR

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
                player:addGold(p.value, p.casinoPayout and "casino_payout_pickup" or "combat_gold_pickup")
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
