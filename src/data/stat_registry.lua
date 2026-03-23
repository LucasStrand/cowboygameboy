local StatRegistry = {}

StatRegistry.ops = {
    flat = true,
    add_pct = true,
    mul = true,
    override = true,
}

StatRegistry.defs = {
    max_hp = { default = 100, group = "survivability", accepted_ops = { "flat", "add_pct", "mul", "override" }, rounding = "floor", clamp = { min = 1 } },
    move_speed = { default = 200, group = "movement", accepted_ops = { "flat", "add_pct", "mul", "override" }, rounding = "floor", clamp = { min = 0 } },
    jump_force = { default = -380, group = "movement", accepted_ops = { "flat", "add_pct", "mul", "override" } },
    damage = { default = 1.0, group = "offense", accepted_ops = { "flat", "add_pct", "mul", "override" }, clamp = { min = 0 } },
    physical_damage = { default = 0, group = "offense", accepted_ops = { "flat", "add_pct", "mul", "override" } },
    magical_damage = { default = 0, group = "offense", accepted_ops = { "flat", "add_pct", "mul", "override" } },
    true_damage = { default = 0, group = "offense", accepted_ops = { "flat", "add_pct", "mul", "override" } },
    armor = { default = 0, group = "defense", accepted_ops = { "flat", "add_pct", "mul", "override" }, rounding = "floor", clamp = { min = 0 } },
    magic_resist = { default = 0, group = "defense", accepted_ops = { "flat", "add_pct", "mul", "override" }, rounding = "floor", clamp = { min = 0 } },
    armor_pen = { default = 0, group = "offense", accepted_ops = { "flat", "add_pct", "mul", "override" } },
    magic_pen = { default = 0, group = "offense", accepted_ops = { "flat", "add_pct", "mul", "override" } },
    armor_shred = { default = 0, group = "offense", accepted_ops = { "flat", "add_pct", "mul", "override" } },
    magic_shred = { default = 0, group = "offense", accepted_ops = { "flat", "add_pct", "mul", "override" } },
    luck = { default = 0, group = "utility", accepted_ops = { "flat", "add_pct", "mul", "override" } },
    pickup_radius = { default = 20, group = "utility", accepted_ops = { "flat", "add_pct", "mul", "override" }, rounding = "floor", clamp = { min = 0 } },
    reload_time = { default = 1.2, group = "weapon", accepted_ops = { "flat", "add_pct", "mul", "override" }, clamp = { min = 0.05 } },
    magazine_size = { default = 6, group = "weapon", accepted_ops = { "flat", "add_pct", "mul", "override" }, rounding = "floor", clamp = { min = 0 } },
    projectile_speed = { default = 720, group = "weapon", accepted_ops = { "flat", "add_pct", "mul", "override" }, rounding = "floor", clamp = { min = 0 } },
    projectile_damage = { default = 10, group = "weapon", accepted_ops = { "flat", "add_pct", "mul", "override" }, rounding = "floor", clamp = { min = 0 } },
    projectile_count = { default = 1, group = "weapon", accepted_ops = { "flat", "add_pct", "mul", "override" }, rounding = "floor", clamp = { min = 0 } },
    spread_angle = { default = 0, group = "weapon", accepted_ops = { "flat", "add_pct", "mul", "override" }, clamp = { min = 0 } },
    lifesteal_on_kill = { default = 0, group = "utility", accepted_ops = { "flat", "add_pct", "mul", "override" }, rounding = "floor", clamp = { min = 0 } },
    projectile_bounce = { default = 0, group = "projectile", accepted_ops = { "flat", "add_pct", "mul", "override" }, rounding = "floor", clamp = { min = 0 } },
    explosive_rounds = { default = false, group = "projectile", accepted_ops = { "override" } },
    dead_eye = { default = false, group = "legacy", accepted_ops = { "override" } },
    akimbo = { default = false, group = "weapon", accepted_ops = { "override" } },
    melee_damage = { default = 0, group = "melee", accepted_ops = { "flat", "add_pct", "mul", "override" }, rounding = "floor" },
    melee_range = { default = 0, group = "melee", accepted_ops = { "flat", "add_pct", "mul", "override" }, rounding = "floor", clamp = { min = 0 } },
    melee_cooldown = { default = 0, group = "melee", accepted_ops = { "flat", "add_pct", "mul", "override" }, clamp = { min = 0 } },
    melee_knockback = { default = 0, group = "melee", accepted_ops = { "flat", "add_pct", "mul", "override" } },
    block_reduction = { default = 0, group = "defense", accepted_ops = { "flat", "add_pct", "mul", "override" }, clamp = { min = 0, max = 1 } },
    block_mobility = { default = 0, group = "defense", accepted_ops = { "flat", "add_pct", "mul", "override" } },
    shoot_cooldown = { default = 0.38, group = "weapon", accepted_ops = { "flat", "add_pct", "mul", "override" }, clamp = { min = 0 } },
    inaccuracy = { default = 0, group = "weapon", accepted_ops = { "flat", "add_pct", "mul", "override" }, clamp = { min = 0 } },
    crit_chance = { default = 0, group = "crit", accepted_ops = { "flat", "add_pct", "mul", "override" }, clamp = { min = 0 } },
    crit_damage = { default = 1.5, group = "crit", accepted_ops = { "flat", "add_pct", "mul", "override" }, clamp = { min = 1 } },
    chain_targets = { default = 0, group = "projectile", accepted_ops = { "flat", "add_pct", "mul", "override" }, rounding = "floor", clamp = { min = 0 } },
    chain_range = { default = 0, group = "projectile", accepted_ops = { "flat", "add_pct", "mul", "override" }, clamp = { min = 0 } },
}

StatRegistry.legacy_aliases = {
    maxHP = "max_hp",
    moveSpeed = "move_speed",
    jumpForce = "jump_force",
    damageMultiplier = "damage",
    reloadSpeed = "reload_time",
    cylinderSize = "magazine_size",
    bulletSpeed = "projectile_speed",
    bulletDamage = "projectile_damage",
    bulletCount = "projectile_count",
    spreadAngle = "spread_angle",
    lifestealOnKill = "lifesteal_on_kill",
    ricochetCount = "projectile_bounce",
    explosiveRounds = "explosive_rounds",
    deadEye = "dead_eye",
    meleeDamage = "melee_damage",
    meleeRange = "melee_range",
    meleeCooldown = "melee_cooldown",
    meleeKnockback = "melee_knockback",
    blockReduction = "block_reduction",
    blockMobility = "block_mobility",
    shootCooldown = "shoot_cooldown",
    pickupRadius = "pickup_radius",
    critChance = "crit_chance",
    critDamage = "crit_damage",
    magicResist = "magic_resist",
    magicPen = "magic_pen",
    armorPen = "armor_pen",
    armorShred = "armor_shred",
    magicShred = "magic_shred",
    chainTargets = "chain_targets",
    chainRange = "chain_range",
    damage = "damage",
}

function StatRegistry.normalizeId(id)
    if not id then
        return nil
    end
    if StatRegistry.defs[id] then
        return id
    end
    return StatRegistry.legacy_aliases[id]
end

function StatRegistry.get(id)
    local normalized = StatRegistry.normalizeId(id)
    if not normalized then
        return nil
    end
    return StatRegistry.defs[normalized], normalized
end

return StatRegistry
