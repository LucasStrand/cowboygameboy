local TooltipTemplates = {}

TooltipTemplates.lines = {
    perk_damage_up = {
        "Deal {bonus_pct}% more damage.",
    },
    perk_speed_up = {
        "Move {bonus_pct}% faster.",
    },
    perk_hp_up = {
        "Increase max HP by {bonus_pct}%.",
    },
    perk_armor_up = {
        "Gain {armor} armor.",
    },
    perk_fast_reload = {
        "Reload {bonus_pct}% faster.",
    },
    perk_extra_bullet = {
        "Increase cylinder capacity by {amount}.",
    },
    perk_lifesteal = {
        "Heal {amount} HP on kill.",
    },
    perk_luck_up = {
        "Gain {bonus_pct}% luck.",
    },
    perk_scattershot = {
        "Fire {projectiles} bullets in a spread.",
        "Spread angle widens to {spread_angle} radians.",
    },
    perk_explosive_rounds = {
        "Bullets explode on hit for splash damage.",
        "Explosive rounds lock ricochet to 0.",
    },
    perk_ricochet = {
        "Bullets bounce off walls {ricochet_count} time.",
    },
    perk_akimbo = {
        "Fire both weapon slots at once.",
    },
    perk_phantom_third = {
        "Every {every_n}rd direct hit on the same target",
        "triggers a delayed true-damage ping.",
    },
    gun_revolver = {
        "Balanced sidearm with a {cylinder_size}-shot cylinder.",
        "Fires {bullet_count} projectile per shot for {bullet_damage} base damage.",
        "Fire rate {rate_of_fire}/s (~{shoot_cooldown}s between shots); reloads in {reload_speed}s.",
        "{crit_chance_pct}% crit chance; {crit_damage_mult}x damage on crit.",
    },
    gun_blunderbuss = {
        "Double-barrel scattergun with {cylinder_size} loaded shots.",
        "Fires {bullet_count} pellets per blast with {spread_angle} radians of spread.",
        "Fire rate {rate_of_fire}/s (~{shoot_cooldown}s between shots).",
        "Aiming downward kicks you upward after firing.",
        "{crit_chance_pct}% crit chance; {crit_damage_mult}x damage on crit.",
    },
    gun_ak47 = {
        "Rapid-fire rifle with a {cylinder_size}-round magazine.",
        "Fires {bullet_count} projectile per shot for {bullet_damage} base damage.",
        "Fire rate {rate_of_fire}/s (~{shoot_cooldown}s between shots); reloads in {reload_speed}s.",
        "{crit_chance_pct}% crit chance; {crit_damage_mult}x damage on crit.",
    },
    gear_cowboy_hat = {
        "Gain {luck_pct}% luck.",
    },
    gear_ten_gallon = {
        "Gain {luck_pct}% luck and {max_hp} max HP.",
    },
    gear_sheriffs_hat = {
        "Gain {luck_pct}% luck and {armor} armor.",
    },
    gear_leather_vest = {
        "Gain {max_hp} max HP and {armor} armor.",
    },
    gear_reinforced_vest = {
        "Gain {max_hp} max HP and {armor} armor.",
    },
    gear_bandolier = {
        "Gain {armor} armor and {damage_pct}% damage.",
    },
    gear_riding_boots = {
        "Gain {move_speed} move speed.",
    },
    gear_spurred_boots = {
        "Gain {move_speed} move speed and {damage_flat} flat damage.",
    },
    gear_snake_boots = {
        "Gain {move_speed} move speed and {luck_pct}% luck.",
    },
    status_speed_boost = {
        "Gain move speed for {duration}s.",
        "Stacks up to {max_stacks} times.",
    },
    status_jitter = {
        "Distorts movement for {duration}s.",
        "Stacks up to {max_stacks} times.",
    },
    status_regen = {
        "Heal over time for {duration}s.",
    },
    status_attack_boost = {
        "Gain bonus damage for {duration}s.",
        "Stacks up to {max_stacks} times.",
    },
    status_defense_boost = {
        "Gain armor for {duration}s.",
        "Stacks up to {max_stacks} times.",
    },
    status_lucky = {
        "Gain critical strike chance for {duration}s.",
    },
    status_slow = {
        "Reduce move speed for {duration}s.",
        "Counts as soft crowd control.",
    },
    status_bleed = {
        "Deals physical damage every {tick_interval}s for {duration}s.",
        "Stacks up to {max_stacks} times.",
    },
    status_burn = {
        "Deals fire damage every {tick_interval}s for {duration}s.",
        "Stacks up to {max_stacks} times.",
    },
    status_shock = {
        "Builds shock for {duration}s.",
        "Stacks up to {max_stacks} times.",
    },
    status_wet = {
        "Marks the target as Wet for {duration}s.",
    },
    status_stun = {
        "Hard crowd control for {duration}s.",
    },
    status_attack_down = {
        "Reduce damage dealt for {duration}s.",
        "Stacks up to {max_stacks} times.",
    },
    status_exp_boost = {
        "Gain bonus experience for {duration}s.",
    },
    shop_heal = {
        "Restore 50% of max HP.",
    },
    shop_ammo_upgrade = {
        "Increase cylinder capacity by 2 for this run.",
    },
    attack_enemy_contact_physical = {
        "Enemy melee contact: {base_min}–{base_max} {family} damage.",
    },
    attack_enemy_projectile_physical = {
        "Enemy projectile: {base_min}–{base_max} {family} damage.",
    },
    attack_enemy_projectile_magical = {
        "Enemy projectile: {base_min}–{base_max} {family} damage.",
    },
}

function TooltipTemplates.has(key)
    return TooltipTemplates.lines[key] ~= nil
end

function TooltipTemplates.get(key)
    return TooltipTemplates.lines[key]
end

return TooltipTemplates
