-- Canonical enemy attack definitions (Phase 11). Runtime damage numbers use instance enemy.damage
-- (difficulty + elite); base_min/base_max here match enemies.lua at difficulty 1 for validation.

local AttackProfiles = {}

local by_id = {}

local function register(profile)
    by_id[profile.id] = profile
end

AttackProfiles.pool = {
    {
        id = "atk_bandit_melee",
        kind = "direct_hit",
        family = "physical",
        delivery = "contact",
        base_min = 8,
        base_max = 8,
        can_crit = false,
        counts_as_hit = true,
        can_trigger_on_hit = true,
        can_trigger_proc = true,
        can_lifesteal = false,
        tags = { "enemy", "contact", "melee" },
        tooltip_key = "attack_enemy_contact_physical",
        tooltip_tokens = {},
    },
    {
        id = "atk_nightborne_melee",
        kind = "direct_hit",
        family = "physical",
        delivery = "contact",
        base_min = 10,
        base_max = 10,
        can_crit = false,
        counts_as_hit = true,
        can_trigger_on_hit = true,
        can_trigger_proc = true,
        can_lifesteal = false,
        tags = { "enemy", "contact", "melee" },
        tooltip_key = "attack_enemy_contact_physical",
        tooltip_tokens = {},
    },
    {
        id = "atk_ogreboss_melee",
        kind = "direct_hit",
        family = "physical",
        delivery = "contact",
        base_min = 18,
        base_max = 18,
        can_crit = false,
        counts_as_hit = true,
        can_trigger_on_hit = true,
        can_trigger_proc = true,
        can_lifesteal = false,
        tags = { "enemy", "contact", "melee" },
        tooltip_key = "attack_enemy_contact_physical",
        tooltip_tokens = {},
    },
    {
        id = "atk_blackkid_melee",
        kind = "direct_hit",
        family = "physical",
        delivery = "contact",
        base_min = 14,
        base_max = 14,
        can_crit = false,
        counts_as_hit = true,
        can_trigger_on_hit = true,
        can_trigger_proc = true,
        can_lifesteal = false,
        tags = { "enemy", "contact", "melee" },
        tooltip_key = "attack_enemy_contact_physical",
        tooltip_tokens = {},
    },
    {
        id = "atk_buzzard_contact",
        kind = "direct_hit",
        family = "physical",
        delivery = "contact",
        base_min = 8,
        base_max = 8,
        can_crit = false,
        counts_as_hit = true,
        can_trigger_on_hit = true,
        can_trigger_proc = true,
        can_lifesteal = false,
        tags = { "enemy", "contact", "melee" },
        tooltip_key = "attack_enemy_contact_physical",
        tooltip_tokens = {},
    },
    {
        id = "atk_gunslinger_shot",
        kind = "direct_hit",
        family = "physical",
        delivery = "projectile",
        base_min = 8,
        base_max = 8,
        can_crit = true,
        counts_as_hit = true,
        can_trigger_on_hit = true,
        can_trigger_proc = true,
        can_lifesteal = false,
        tags = { "projectile", "enemy" },
        tooltip_key = "attack_enemy_projectile_physical",
        tooltip_tokens = {},
    },
    {
        id = "atk_necromancer_shot",
        kind = "direct_hit",
        family = "magical",
        delivery = "projectile",
        base_min = 10,
        base_max = 10,
        can_crit = true,
        counts_as_hit = true,
        can_trigger_on_hit = true,
        can_trigger_proc = true,
        can_lifesteal = false,
        tags = { "projectile", "enemy", "damage:fire" },
        tooltip_key = "attack_enemy_projectile_magical",
        tooltip_tokens = {},
    },
    {
        id = "atk_phase11_proc_ping",
        kind = "direct_hit",
        family = "physical",
        delivery = "contact",
        base_min = 5,
        base_max = 5,
        can_crit = false,
        counts_as_hit = true,
        can_trigger_on_hit = true,
        can_trigger_proc = true,
        can_lifesteal = false,
        tags = { "enemy", "contact" },
        tooltip_key = "attack_enemy_contact_physical",
        tooltip_tokens = {},
        proc_rules = {
            {
                id = "phase11_test_proc",
                trigger = "OnHit",
                source_owner_type = "enemy_contact",
                source_actor_kind = "enemy",
                packet_kind = "direct_hit",
                counter = {
                    mode = "source_target_hits",
                    every_n = 1,
                },
                effect = {
                    type = "delayed_damage",
                    delay = 0,
                    family = "true",
                    damage_scale = 0,
                    min_damage = 2,
                    can_crit = false,
                    counts_as_hit = false,
                    can_trigger_on_hit = false,
                    can_trigger_proc = false,
                    can_lifesteal = false,
                },
            },
        },
    },
}

for _, profile in ipairs(AttackProfiles.pool) do
    register(profile)
end

function AttackProfiles.get(id)
    return by_id[id]
end

function AttackProfiles.has(id)
    return by_id[id] ~= nil
end

return AttackProfiles
