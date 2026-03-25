local Guns = require("src.data.guns")

local Weapons = {}

-- Default gun at game start (`Player.new`); melee slot starts empty (fists / unarmed stats).
-- Gear with slot "melee" or "shield" follows the same stat-table pattern as
-- hat/vest/boots: values are added on top of the player's base stats in
-- getEffectiveStats().
Weapons.defaults = {
    gun = Guns.default,
    --- Bare fists when no melee gear (knife dropped). StatRuntime merges as `unarmed_melee`.
    unarmed = {
        id   = "fists",
        name = "Fists",
        slot = "melee",
        description = "Bare knuckles. Equip a knife from the ground or the saloon to stab harder.",
        stats = {
            meleeDamage    = 9,
            meleeRange     = 26,
            meleeCooldown  = 0.42,
            meleeKnockback = 72,
        },
    },
    melee = {
        id      = "knife",
        name    = "Knife",
        slot    = "melee",
        tier    = 0,
        -- Items.png: 176×112 → 11×7 tiles @ 16×16; knife = row1 col2 (0-based col 1, row 0)
        icon    = {
            sheet = "assets/weapons/Items.png",
            tile  = 16,
            col   = 1,
            row   = 0,
        },
        stats   = {
            meleeDamage   = 20,
            meleeRange    = 36,
            meleeCooldown = 0.5,
            meleeKnockback = 130,
        },
    },
    -- Shield slot starts empty; equip via rewards / shop when offered.
}

return Weapons
