local PresentationHooks = {}

PresentationHooks.definitions = {
    phantom_third_payoff = {
        event = "proc_damage_taken",
        effect_id = "hit_enemy",
        scale_mul = 0.95,
        tint = { 0.62, 0.95, 1.0, 1.0 },
        sfx_id = "hit_enemy",
    },
    status_bleed_apply = {
        event = "status_applied",
        effect_id = "hit_enemy",
        scale_mul = 0.72,
        tint = { 0.92, 0.24, 0.2, 0.95 },
        sfx_id = "hit_enemy",
        volume = 0.75,
    },
    status_burn_apply = {
        event = "status_applied",
        effect_id = "explosion_small",
        scale_mul = 0.52,
        tint = { 1.0, 0.42, 0.12, 0.65 },
        sfx_id = "explosion",
        volume = 0.4,
    },
    status_shock_apply = {
        event = "status_applied",
        effect_id = "hit_enemy",
        scale_mul = 0.8,
        tint = { 1.0, 0.9, 0.3, 1.0 },
        sfx_id = "hit_enemy",
        volume = 0.7,
    },
    status_stun_apply = {
        event = "status_applied",
        effect_id = "melee",
        scale_mul = 0.72,
        tint = { 1.0, 0.96, 0.64, 0.9 },
        sfx_id = "hit_wall",
        volume = 0.7,
    },
    status_cleanse = {
        event = "status_cleanse",
        effect_id = "hit_wall",
        scale_mul = 0.65,
        tint = { 0.45, 0.92, 0.7, 0.9 },
        sfx_id = "pickup_health",
        volume = 0.65,
    },
    status_purge = {
        event = "status_purge",
        effect_id = "hit_wall",
        scale_mul = 0.7,
        tint = { 0.82, 0.56, 1.0, 0.85 },
        sfx_id = "hit_wall",
        volume = 0.7,
    },
}

function PresentationHooks.has(id)
    return PresentationHooks.definitions[id] ~= nil
end

function PresentationHooks.get(id)
    return PresentationHooks.definitions[id]
end

return PresentationHooks
