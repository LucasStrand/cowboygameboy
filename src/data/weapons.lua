local Guns = require("src.data.guns")

local Weapons = {}

-- Default gun at game start (`Player.new`); knife is `Guns.getById("knife")` in a weapon slot.
-- Gear with slot "shield" follows the same stat-table pattern as hat/vest/boots.
Weapons.defaults = {
    gun = Guns.default,
    --- Bare fists when the active weapon is ranged. StatRuntime merges as `unarmed_melee`.
    unarmed = {
        id   = "fists",
        name = "Fists",
        slot = "melee",
        description = "Bare knuckles. Stab with a knife by equipping it in weapon slot 1 or 2.",
        stats = {
            meleeDamage    = 9,
            meleeRange     = 26,
            meleeCooldown  = 0.42,
            meleeKnockback = 72,
        },
    },
    -- Shield slot starts empty; equip via rewards / shop when offered.
}

return Weapons
