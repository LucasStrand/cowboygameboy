local PROJECT_ROOT = [[C:\Users\9914k\Dev\Cowboygamejam\cowboygameboy]]
local OUTPUT_PATH = PROJECT_ROOT .. [[\tmp\damage_resolver_harness_output.txt]]

package.path = table.concat({
    PROJECT_ROOT .. [[\?.lua]],
    PROJECT_ROOT .. [[\?\init.lua]],
    package.path,
}, ";")

local lines = {}
local failures = {}

local function log(msg)
    lines[#lines + 1] = tostring(msg)
end

DEBUG = true
function debugLog(msg)
    log("[debug] " .. tostring(msg))
end

package.loaded["src.entities.bullet"] = {
    new = function(data)
        return data
    end,
}
package.loaded["src.entities.pickup"] = {}
package.loaded["src.data.guns"] = {
    pool = {},
    getById = function()
        return nil
    end,
    rollDrop = function()
        return nil
    end,
}
package.loaded["src.data.vision"] = {
    isInLightVision = function()
        return true
    end,
}
package.loaded["src.ui.damage_numbers"] = {
    spawn = function(_, _, value, direction)
        log(string.format("[damage_numbers] dir=%s value=%s", tostring(direction), tostring(value)))
    end,
    clear = function()
    end,
    spawnPickup = function()
    end,
}
package.loaded["src.systems.impact_fx"] = {
    spawn = function(_, _, fx_id)
        log(string.format("[impact_fx] %s", tostring(fx_id)))
    end,
    clear = function()
    end,
}
package.loaded["src.systems.sfx"] = {
    play = function(id)
        log(string.format("[sfx] %s", tostring(id)))
    end,
}
package.loaded["src.systems.buffs"] = {
    applyStatus = function()
        return false
    end,
    getStatMods = function()
        return {}
    end,
}

local CombatEvents = require("src.systems.combat_events")
local DamagePacket = require("src.systems.damage_packet")
local DamageResolver = require("src.systems.damage_resolver")
local GameRng = require("src.systems.game_rng")
local SourceRef = require("src.systems.source_ref")
local Combat = require("src.systems.combat")

CombatEvents.subscribe("OnDamageTaken", function(payload)
    log(string.format(
        "[event] OnDamageTaken kind=%s target=%s final=%s",
        tostring(payload.packet_kind),
        tostring(payload.target_id),
        tostring(payload.final_applied_damage)
    ))
end)
CombatEvents.subscribe("OnHit", function(payload)
    log(string.format(
        "[event] OnHit kind=%s target=%s final=%s",
        tostring(payload.packet_kind),
        tostring(payload.target_id),
        tostring(payload.final_applied_damage)
    ))
end)
CombatEvents.subscribe("OnKill", function(payload)
    log(string.format(
        "[event] OnKill kind=%s target=%s final=%s",
        tostring(payload.packet_kind),
        tostring(payload.target_id),
        tostring(payload.final_applied_damage)
    ))
end)

local function resetState(seed)
    DamageResolver._secondary_jobs = {}
    GameRng.setCurrent(GameRng.new(seed or 12345))
end

local function assertScenario(name, condition, detail)
    if condition then
        log("[assert] PASS " .. name)
    else
        local message = "[assert] FAIL " .. name .. (detail and (" :: " .. detail) or "")
        log(message)
        failures[#failures + 1] = message
    end
end

local function writeOutput()
    local fh = assert(io.open(OUTPUT_PATH, "w"))
    fh:write(table.concat(lines, "\n"))
    fh:write("\n")
    if #failures == 0 then
        fh:write("SUMMARY: PASS\n")
    else
        fh:write("SUMMARY: FAIL (" .. tostring(#failures) .. ")\n")
    end
    fh:close()
end

local function makeWorld()
    return {
        hasItem = function()
            return false
        end,
        remove = function()
        end,
        add = function()
        end,
    }
end

local function makeEnemy(id, x, y, armor, hp)
    local enemy = {
        actorId = id,
        typeId = id,
        name = id,
        isEnemy = true,
        alive = true,
        x = x or 0,
        y = y or 0,
        w = 20,
        h = 20,
        armor = armor or 0,
        hp = hp or 100,
        statuses = nil,
        attackTimer = 0,
        behavior = "melee",
        attackRange = 24,
        contactRange = 24,
        attackCooldown = 1,
        canDamagePlayer = function()
            return true
        end,
        onContactDamage = function(self)
            self.contact_calls = (self.contact_calls or 0) + 1
        end,
        applyResolvedDamage = function(self, result, _, packet)
            self.last_result = result
            self.last_packet = packet
            self.hp = self.hp - (result.final_damage or 0)
            if self.hp <= 0 then
                self.alive = false
            end
            return true, result.final_damage or 0, self.hp <= 0
        end,
    }
    return enemy
end

local function makePlayerTarget(armor)
    local player = {
        actorId = "player",
        hp = 100,
        iframes = 0,
        blocking = false,
        x = 0,
        y = 0,
        w = 20,
        h = 20,
        statuses = nil,
        getEffectiveStats = function()
            return {
                armor = armor or 0,
                magicResist = 0,
                blockReduction = 0,
            }
        end,
        applyResolvedDamage = function(self, result, _, packet)
            self.last_result = result
            self.last_packet = packet
            self.hp = self.hp - (result.final_damage or 0)
            return true, result.final_damage or 0, self.hp <= 0
        end,
    }
    return player
end

local function makePlayerSource()
    local base_gun_stats = {
        cylinderSize = 6,
        reloadSpeed = 1.2,
        bulletSpeed = 720,
        bulletDamage = 10,
        bulletCount = 1,
        spreadAngle = 0,
    }
    local gun_def = {
        id = "revolver",
        baseStats = {
            cylinderSize = 6,
            reloadSpeed = 1.2,
            bulletSpeed = 720,
            bulletDamage = 10,
            bulletCount = 1,
            spreadAngle = 0,
        },
    }
    local slot1 = {
        slot_index = 1,
        mode = "weapon",
        weapon_id = "revolver",
        weapon_def = gun_def,
    }
    local slot2 = {
        slot_index = 2,
        mode = "melee",
    }
    local player = {
        actorId = "player",
        stats = {
            maxHP = 100,
            damageMultiplier = 1,
            armor = 0,
            reloadSpeed = 1.2,
            cylinderSize = 6,
            bulletSpeed = 720,
            bulletDamage = 10,
            bulletCount = 1,
            spreadAngle = 0,
            meleeDamage = 0,
            meleeRange = 0,
            meleeCooldown = 0,
            meleeKnockback = 0,
            critChance = 0,
            critDamage = 1.5,
            armorPen = 0,
        },
        gear = {
            melee = {
                stats = {
                    meleeDamage = 20,
                    meleeRange = 40,
                    meleeCooldown = 0.5,
                    meleeKnockback = 24,
                },
            },
        },
        baseGunStats = base_gun_stats,
        meleeSwingTimer = 0.2,
        meleeAimAngle = 0,
        meleeHitEnemies = {},
        meleeHitFlashTimer = 0,
        getWeaponRuntime = function(_, index)
            if index == 1 then
                return slot1
            end
            if index == 2 then
                return slot2
            end
            return nil
        end,
        getEffectiveStats = function()
            return {
                damageMultiplier = 1,
                meleeDamage = 20,
                meleeRange = 40,
                meleeCooldown = 0.5,
                meleeKnockback = 24,
                armorPen = 0,
                critChance = 0,
                critDamage = 1.5,
            }
        end,
        getMeleeHitbox = function()
            return 0, 0, 40, 40
        end,
    }
    return player, gun_def
end

local function baseSourceContext(base_damage)
    return {
        base_min = base_damage,
        base_max = base_damage,
        damage = 1,
        physical_damage = 0,
        magical_damage = 0,
        true_damage = 0,
        crit_chance = 0,
        crit_damage = 1.5,
        armor_pen = 0,
        magic_pen = 0,
    }
end

local function scenarioPlayerProjectile()
    log("== scenario: player projectile -> enemy ==")
    resetState(101)
    local world = makeWorld()
    local source_player = makePlayerSource()
    local target_enemy = makeEnemy("enemy_projectile_target", 0, 0, 15, 100)
    local packet = DamagePacket.new({
        kind = "direct_hit",
        family = "physical",
        base_min = 10,
        base_max = 10,
        source = SourceRef.new({
            owner_actor_id = "player",
            owner_source_type = "weapon_slot",
            owner_source_id = "revolver",
        }),
        tags = { "projectile", "revolver" },
        target_id = target_enemy.actorId,
        snapshot_data = {
            source_context = baseSourceContext(10),
        },
        metadata = {
            source_context_kind = "player_weapon_projectile",
            source_slot_index = 1,
            source_weapon_id = "revolver",
            base_scale = 1,
        },
    })
    local bullet = {
        x = 0,
        y = 0,
        w = 4,
        h = 4,
        alive = true,
        explosive = false,
        ultBullet = false,
        fromEnemy = false,
        packet = packet,
        source_actor = source_player,
        update = function(self)
            self.hitEnemy = target_enemy
            self.alive = false
        end,
    }
    Combat.updateBullets({ bullet }, 0, world, { target_enemy }, makePlayerTarget(0))
    assertScenario(
        "player projectile routed through resolver",
        target_enemy.last_result and target_enemy.last_result.packet_kind == "direct_hit"
            and target_enemy.last_result.source_ref
            and target_enemy.last_result.source_ref.owner_source_id == "revolver"
    )
    assertScenario(
        "player projectile used resolver output",
        target_enemy.last_result and target_enemy.last_result.final_damage == 8,
        target_enemy.last_result and ("final=" .. tostring(target_enemy.last_result.final_damage) .. " defense=" .. tostring(target_enemy.last_result.effective_defense)) or "no result"
    )
end

local function scenarioEnemyProjectile()
    log("== scenario: enemy projectile -> player ==")
    resetState(202)
    local world = makeWorld()
    local source_enemy = {
        actorId = "gunslinger_1",
        typeId = "gunslinger",
        name = "gunslinger",
        damage = 12,
    }
    local target_player = makePlayerTarget(25)
    local packet = DamagePacket.new({
        kind = "direct_hit",
        family = "physical",
        base_min = 12,
        base_max = 12,
        source = SourceRef.new({
            owner_actor_id = "gunslinger_1",
            owner_source_type = "enemy_attack",
            owner_source_id = "gunslinger",
        }),
        tags = { "projectile", "enemy" },
        target_id = target_player.actorId,
        snapshot_data = {
            source_context = baseSourceContext(12),
        },
        metadata = {
            source_context_kind = "enemy_projectile",
            source_attack_id = "gunslinger",
        },
    })
    local bullet = {
        x = 0,
        y = 0,
        w = 4,
        h = 4,
        alive = true,
        explosive = false,
        ultBullet = false,
        fromEnemy = true,
        packet = packet,
        source_actor = source_enemy,
        update = function(self)
            self.hitPlayer = true
            self.alive = false
        end,
    }
    Combat.updateBullets({ bullet }, 0, world, {}, target_player)
    assertScenario(
        "enemy projectile routed through resolver",
        target_player.last_result and target_player.last_result.packet_kind == "direct_hit"
            and target_player.last_result.source_ref
            and target_player.last_result.source_ref.owner_source_id == "gunslinger"
    )
    assertScenario(
        "enemy projectile respected player defense in resolver",
        target_player.last_result and target_player.last_result.effective_defense == 25 and target_player.last_result.final_damage == 9,
        target_player.last_result and ("final=" .. tostring(target_player.last_result.final_damage) .. " defense=" .. tostring(target_player.last_result.effective_defense)) or "no result"
    )
end

local function scenarioPlayerMelee()
    log("== scenario: player melee -> enemy ==")
    resetState(303)
    local player = makePlayerSource()
    local target_enemy = makeEnemy("enemy_melee_target", 10, 10, 30, 100)
    Combat.checkPlayerMelee(player, { target_enemy })
    assertScenario("player melee routed through resolver", target_enemy.last_packet ~= nil and target_enemy.last_packet.metadata.source_context_kind == "player_melee")
    assertScenario(
        "player melee damage uses resolver final_damage",
        target_enemy.last_result and target_enemy.last_result.final_damage == 15,
        target_enemy.last_result and ("final=" .. tostring(target_enemy.last_result.final_damage) .. " defense=" .. tostring(target_enemy.last_result.effective_defense)) or "no result"
    )
end

local function scenarioEnemyContact()
    log("== scenario: enemy contact -> player ==")
    resetState(404)
    local contact_enemy = makeEnemy("bandit_contact", 0, 0, 0, 100)
    contact_enemy.damage = 20
    local target_player = makePlayerTarget(50)
    Combat.checkMeleeEnemies({ contact_enemy }, target_player)
    assertScenario("enemy contact routed through resolver", target_player.last_packet ~= nil and target_player.last_packet.metadata.source_context_kind == "enemy_contact")
    assertScenario(
        "enemy contact damage uses resolver defense output",
        target_player.last_result and target_player.last_result.effective_defense == 50 and target_player.last_result.final_damage == 13,
        target_player.last_result and ("final=" .. tostring(target_player.last_result.final_damage) .. " defense=" .. tostring(target_player.last_result.effective_defense)) or "no result"
    )
end

local function scenarioExplosiveSplash()
    log("== scenario: explosive splash secondary job ==")
    resetState(505)
    local world = makeWorld()
    local source_player = makePlayerSource()
    local primary_enemy = makeEnemy("explosion_primary", 40, 40, 0, 100)
    local splash_enemy = makeEnemy("explosion_secondary", 70, 40, 0, 100)
    local packet = DamagePacket.new({
        kind = "direct_hit",
        family = "physical",
        base_min = 10,
        base_max = 10,
        source = SourceRef.new({
            owner_actor_id = "player",
            owner_source_type = "ultimate",
            owner_source_id = "dead_mans_hand",
        }),
        tags = { "projectile", "ultimate" },
        target_id = primary_enemy.actorId,
        snapshot_data = {
            source_context = baseSourceContext(10),
        },
        metadata = {
            source_context_kind = "player_weapon_projectile",
            source_slot_index = 1,
            source_weapon_id = "revolver",
            base_scale = 1,
            explosion_radius = 80,
            explosion_damage_scale = 0.5,
        },
    })
    local bullet = {
        x = 0,
        y = 0,
        w = 4,
        h = 4,
        alive = true,
        explosive = true,
        ultBullet = true,
        fromEnemy = false,
        packet = packet,
        source_actor = source_player,
        update = function(self)
            self.hitEnemy = primary_enemy
            self.alive = false
        end,
    }
    Combat.updateBullets({ bullet }, 0, world, { primary_enemy, splash_enemy }, makePlayerTarget(0))
    assertScenario("explosive splash created delayed secondary packet", splash_enemy.last_packet ~= nil and splash_enemy.last_packet.kind == "delayed_secondary_hit")
    assertScenario(
        "explosive splash applied delayed secondary damage",
        splash_enemy.last_result and splash_enemy.last_result.final_damage == 5,
        splash_enemy.last_result and ("final=" .. tostring(splash_enemy.last_result.final_damage) .. " kind=" .. tostring(splash_enemy.last_result.packet_kind)) or "no result"
    )
end

function love.load()
    local ok, err = xpcall(function()
        scenarioPlayerProjectile()
        scenarioEnemyProjectile()
        scenarioPlayerMelee()
        scenarioEnemyContact()
        scenarioExplosiveSplash()
    end, debug.traceback)

    if not ok then
        log("[fatal] " .. tostring(err))
        failures[#failures + 1] = tostring(err)
    end

    writeOutput()
    love.event.quit(0)
end
