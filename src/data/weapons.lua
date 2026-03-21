local Guns = require("src.data.guns")

local Weapons = {}

-- Default weapons equipped at game start.
-- Gear with slot "melee" or "shield" follows the same stat-table pattern as
-- hat/vest/boots: values are added on top of the player's base stats in
-- getEffectiveStats().
Weapons.defaults = {
    gun = Guns.default,
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
    shield = {
        id      = "wooden_shield",
        name    = "Wooden Shield",
        slot    = "shield",
        tier    = 0,
        -- Plain round wooden shield: row2 col8 → 0-based col 7, row 1
        icon    = {
            sheet = "assets/weapons/Items.png",
            tile  = 16,
            col   = 7,
            row   = 1,
        },
        stats   = {
            -- Fraction of incoming damage absorbed while blocking (0–1).
            blockReduction = 0.6,
            -- Add blockMobility = 1 on upgraded shields to move/jump/dash while blocking.
            -- allowAutoBlock = true  → HUD can toggle shield auto-block (never default).
        },
    },
}

return Weapons
