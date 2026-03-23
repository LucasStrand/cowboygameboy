--[[
  Run-time perks: canonical schema, tags, reward buckets, and proc wiring are documented in
  docs/perks_and_skills_system.md

  Quick checklist for a new perk:
  - id (unique), name, description, weight, apply(player)
  - tooltip_key (+ tooltip_tokens) or tooltip_override
  - tags: include reward:support | reward:neutral | reward:pivot when you care about level-up buckets
  - If reward_runtime should infer extra themes: add FEATURE_HINTS[id] in src/systems/reward_runtime.lua
  - Stat changes: prefer fields that getEffectiveStats / weapon resolution actually read; see stat_registry.lua
  - Combat logic: prefer proc_rules (+ presentation_hooks.on_proc) over scattered combat branches
]]
local Perks = {}
local GameRng = require("src.systems.game_rng")

Perks.pool = {
    -- Common (60% weight)
    {
        id = "damage_up",
        name = "Steady Hand",
        description = "+15% damage",
        tooltip_key = "perk_damage_up",
        tooltip_tokens = {
            bonus_pct = 15,
        },
        tags = { "theme:damage", "reward:neutral", "role:power" },
        rarity = "common",
        weight = 15,
        apply = function(player)
            player.stats.damageMultiplier = player.stats.damageMultiplier + 0.15
        end
    },
    {
        id = "speed_up",
        name = "Quick Draw Boots",
        description = "+12% move speed",
        tooltip_key = "perk_speed_up",
        tooltip_tokens = {
            bonus_pct = 12,
        },
        tags = { "theme:mobility", "reward:neutral", "role:power" },
        rarity = "common",
        weight = 15,
        apply = function(player)
            player.stats.moveSpeed = player.stats.moveSpeed * 1.12
        end
    },
    {
        id = "hp_up",
        name = "Tough Hide",
        description = "+20% max HP",
        tooltip_key = "perk_hp_up",
        tooltip_tokens = {
            bonus_pct = 20,
        },
        tags = { "theme:defense", "reward:neutral", "role:power" },
        rarity = "common",
        weight = 15,
        apply = function(player)
            local bonus = math.floor(player.stats.maxHP * 0.20)
            player.stats.maxHP = player.stats.maxHP + bonus
            player.hp = player.hp + bonus
        end
    },
    {
        id = "armor_up",
        name = "Iron Gut",
        description = "+1 armor",
        tooltip_key = "perk_armor_up",
        tooltip_tokens = {
            armor = 1,
        },
        tags = { "theme:defense", "reward:neutral", "role:power" },
        rarity = "common",
        weight = 15,
        apply = function(player)
            player.stats.armor = player.stats.armor + 1
        end
    },

    -- Uncommon (30% weight)
    {
        id = "fast_reload",
        name = "Sleight of Hand",
        description = "30% faster reload",
        tooltip_key = "perk_fast_reload",
        tooltip_tokens = {
            bonus_pct = 30,
        },
        tags = { "attack:projectile", "theme:reload", "reward:support", "role:power" },
        rarity = "uncommon",
        weight = 8,
        apply = function(player)
            player.stats.reloadSpeed = player.stats.reloadSpeed * 0.7
        end
    },
    {
        id = "extra_bullet",
        name = "Extended Cylinder",
        description = "+1 bullet in cylinder",
        tooltip_key = "perk_extra_bullet",
        tooltip_tokens = {
            amount = 1,
        },
        tags = { "attack:projectile", "theme:ammo", "reward:support", "role:power" },
        rarity = "uncommon",
        weight = 8,
        apply = function(player)
            player.stats.cylinderSize = player.stats.cylinderSize + 1
            player:addAmmoToActiveSlot(1, "perk:extra_bullet")
        end
    },
    {
        id = "lifesteal",
        name = "Blood Thirst",
        description = "Heal 5 HP on kill",
        tooltip_key = "perk_lifesteal",
        tooltip_tokens = {
            amount = 5,
        },
        tags = { "theme:sustain", "reward:neutral", "role:power" },
        rarity = "uncommon",
        weight = 7,
        apply = function(player)
            player.stats.lifestealOnKill = player.stats.lifestealOnKill + 5
        end
    },
    {
        id = "luck_up",
        name = "Lucky Charm",
        description = "+15% luck",
        tooltip_key = "perk_luck_up",
        tooltip_tokens = {
            bonus_pct = 15,
        },
        tags = { "theme:luck", "reward:neutral", "role:power" },
        rarity = "uncommon",
        weight = 7,
        apply = function(player)
            player.stats.luck = player.stats.luck + 0.15
        end
    },

    -- Rare (10% weight)
    {
        id = "scattershot",
        name = "Scattershot",
        description = "Fire 3 bullets in a spread",
        tooltip_key = "perk_scattershot",
        tooltip_tokens = {
            projectiles = 3,
            spread_angle = 0.25,
        },
        tags = { "attack:projectile", "theme:multishot", "reward:support", "role:power" },
        rarity = "rare",
        weight = 3,
        apply = function(player)
            player.stats.bulletCount = player.stats.bulletCount + 2
            player.stats.spreadAngle = 0.25
        end
    },
    {
        id = "explosive_rounds",
        name = "Explosive Rounds",
        description = "Bullets explode on hit (AOE)",
        tooltip_key = "perk_explosive_rounds",
        tags = { "attack:projectile", "damage:aoe", "theme:explosive", "reward:pivot", "role:power" },
        rarity = "rare",
        weight = 3,
        apply = function(player)
            player.stats.explosiveRounds = true
        end
    },
    {
        id = "ricochet",
        name = "Ricochet",
        description = "Bullets bounce once off walls",
        tooltip_key = "perk_ricochet",
        tooltip_tokens = {
            ricochet_count = 1,
        },
        tags = { "attack:projectile", "theme:ricochet", "reward:pivot", "role:power" },
        rarity = "rare",
        weight = 2,
        apply = function(player)
            player.stats.ricochetCount = player.stats.ricochetCount + 1
        end
    },
    {
        id = "akimbo",
        name = "Akimbo",
        description = "Dual-wield: fire both guns at once",
        tooltip_key = "perk_akimbo",
        tags = { "attack:projectile", "theme:multishot", "reward:pivot", "role:power" },
        rarity = "rare",
        weight = 2,
        apply = function(player)
            player.stats.akimbo = true
        end
    },
    {
        id = "phantom_third",
        name = "Phantom Third",
        description = "Every 3rd hit on the same target triggers a delayed true-damage ping",
        tooltip_key = "perk_phantom_third",
        presentation_hooks = {
            on_proc = "phantom_third_payoff",
        },
        rarity = "rare",
        weight = 2,
        tags = { "damage:true", "setup:proc", "theme:proc", "reward:pivot", "role:power" },
        proc_rules = {
            {
                id = "third_hit_true_ping",
                trigger = "OnHit",
                source_owner_type = "weapon_slot",
                source_actor_kind = "player",
                packet_kind = "direct_hit",
                counter = {
                    mode = "source_target_hits",
                    every_n = 3,
                },
                effect = {
                    type = "delayed_damage",
                    delay = 0.08,
                    family = "true",
                    damage_scale = 0.35,
                    min_damage = 4,
                    can_crit = false,
                    counts_as_hit = false,
                    can_trigger_on_hit = false,
                    can_trigger_proc = false,
                    can_lifesteal = false,
                },
            },
        },
        apply = function(player)
            local _ = player
        end
    },
}

function Perks.rollPerks(count, luck)
    local luck = luck or 0
    local available = {}
    for _, perk in ipairs(Perks.pool) do
        table.insert(available, perk)
    end

    local selected = {}
    local usedIds = {}

    for i = 1, count do
        local totalWeight = 0
        for _, perk in ipairs(available) do
            if not usedIds[perk.id] then
                local w = perk.weight
                if perk.rarity == "rare" then
                    w = w * (1 + luck)
                elseif perk.rarity == "uncommon" then
                    w = w * (1 + luck * 0.5)
                end
                totalWeight = totalWeight + w
            end
        end

        local roll = GameRng.randomFloat("perks.roll.weight." .. i, 0, totalWeight)
        local cumulative = 0
        for _, perk in ipairs(available) do
            if not usedIds[perk.id] then
                local w = perk.weight
                if perk.rarity == "rare" then
                    w = w * (1 + luck)
                elseif perk.rarity == "uncommon" then
                    w = w * (1 + luck * 0.5)
                end
                cumulative = cumulative + w
                if roll <= cumulative then
                    table.insert(selected, perk)
                    usedIds[perk.id] = true
                    break
                end
            end
        end
    end

    return selected
end

Perks.rarityColors = {
    common = {0.7, 0.7, 0.7},
    uncommon = {0.2, 0.8, 0.2},
    rare = {0.9, 0.7, 0.1},
}

Perks.byId = {}
for _, perk in ipairs(Perks.pool) do
    Perks.byId[perk.id] = perk
end

function Perks.getById(id)
    return Perks.byId[id]
end

return Perks
