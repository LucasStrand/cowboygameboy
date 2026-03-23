local Guns = {}
local GameRng = require("src.systems.game_rng")

-- Overlay guns: heldHandOffset (pixels, x mirrors when facing left) + spriteOrigin tune the grip.
-- Held sprites rotate with body + getHeadGunTilt (see Player:getHeldGunDrawAngle), not raw cursor aim.
-- Cowboy strips still bake a small revolver; use drawHeldGunSprite only when you accept overlap until unarmed body art exists.
--
-- Gun definitions: baseStats feed StatRuntime with a revolver-anchored delta
-- merge for core weapon stats (damage, mag, reload, speed, spread, crit, ROF, …).
-- rateOfFire is shots per second (default player baseline 1). StatRuntime derives
-- shoot_cooldown as 1 / rate_of_fire. inaccuracy overrides when set on the gun.
-- See docs/player_weapon_stat_resolution.md.

-- Weapon sprite directory
local WEAPON_SPRITE_DIR = "assets/weapons/Weapons/"

-- Sprite cache (loaded lazily on first draw)
local _spriteCache = {}

--- Load (and cache) a weapon sprite image.
function Guns.getSprite(gun)
    if not gun or not gun.sprite then return nil end
    if not _spriteCache[gun.id] then
        local img = love.graphics.newImage(WEAPON_SPRITE_DIR .. gun.sprite)
        img:setFilter("nearest", "nearest")
        _spriteCache[gun.id] = img
    end
    return _spriteCache[gun.id]
end

Guns.pool = {
    ---------------------------------------------------------------------------
    -- Revolver (starter, never drops)
    ---------------------------------------------------------------------------
    {
        id          = "revolver",
        name        = "Colt .45",
        rarity      = "common",
        dropWeight  = 0,            -- 0 = starter only
        ammoType    = "cylinder",   -- HUD render style
        attack_profile_id = "projectile_basic",
        tooltip_key = "gun_revolver",
        tags = { "attack:projectile", "weapon:revolver" },
        capabilities = {},
        rules = {},
        -- Commission art: assets/weapons/guns/.../Revolver - Colt 45 [64x32].png → Weapons/Colt45.png
        sprite      = "Colt45.png",
        spriteOrigin = { x = 0.36, y = 0.52 },
        spriteScale  = 0.58,
        heldHandOffset = { x = 11, y = -1 },
        drawHeldGunSprite = true,
        muzzle_fx_id = "muzzle_colt45",
        muzzle_tip = 15,
        shoot_sfx_id = "shoot_revolver",
        shoot_sfx_opts = { volume = 1.2 },
        baseStats   = {
            cylinderSize  = 6,
            reloadSpeed   = 1.2,
            bulletSpeed   = 720,
            bulletDamage  = 10,
            bulletCount   = 1,
            spreadAngle   = 0,
            critChance    = 0,
            critDamage    = 1.5,
            rateOfFire    = 1 / 0.38,
            inaccuracy    = 0,
        },
    },

    ---------------------------------------------------------------------------
    -- Blunderbuss – double-barrel shotgun; recoils player upward when shooting
    -- downward, enabling rocket-jump style movement.
    ---------------------------------------------------------------------------
    {
        id          = "blunderbuss",
        name        = "Blunderbuss",
        rarity      = "uncommon",
        dropWeight  = 8,
        ammoType    = "double_barrel",
        attack_profile_id = "projectile_spread",
        tooltip_key = "gun_blunderbuss",
        tags = { "attack:projectile", "weapon:shotgun", "attack:recoil_mobility" },
        capabilities = {},
        rules = {
            recoil_only_when_aiming_down = true,
        },
        sprite      = "Blunderbuss.png",
        spriteOrigin = { x = 0.3, y = 0.55 },
        spriteScale  = 0.75,
        heldHandOffset = { x = 14, y = -2 },
        baseStats   = {
            cylinderSize  = 2,
            reloadSpeed   = 1.8,
            bulletSpeed   = 580,
            bulletDamage  = 6,
            bulletCount   = 5,
            spreadAngle   = 0.45,
            critChance    = 0.04,
            critDamage    = 1.48,
            rateOfFire    = 1 / 0.70,
            inaccuracy    = 0,
        },
        ---@param player table
        ---@param aimAngle number radians
        onShoot = function(player, aimAngle)
            -- If the player is aiming meaningfully downward, kick them upward.
            if math.sin(aimAngle) > 0.3 then
                player.vy = math.min(player.vy, -280)
                -- Allow a double-jump after the recoil hop
                if player.jumpCount > 1 then
                    player.jumpCount = 1
                end
            end
        end,
    },

    ---------------------------------------------------------------------------
    -- AK-47 (Kalashnikov) – magazine-fed, rapid fire, slight inaccuracy.
    ---------------------------------------------------------------------------
    {
        id          = "ak47",
        name        = "AK-47",
        rarity      = "rare",
        dropWeight  = 4,
        ammoType    = "magazine",
        attack_profile_id = "projectile_basic",
        tooltip_key = "gun_ak47",
        tags = { "attack:projectile", "weapon:rifle" },
        capabilities = {},
        rules = {},
        sprite      = "AK47.png",
        spriteOrigin = { x = 0.22, y = 0.50 },
        spriteScale  = 0.72,
        heldHandOffset = { x = 13, y = -1 },
        baseStats   = {
            cylinderSize  = 30,
            reloadSpeed   = 2.0,
            bulletSpeed   = 780,
            bulletDamage  = 5,
            bulletCount   = 1,
            spreadAngle   = 0,
            critChance    = 0.02,
            critDamage    = 1.45,
            rateOfFire    = 10,
            inaccuracy    = 0.08,
        },
    },
}

-- Quick lookup table (built once on require)
local _byId = {}
for _, gun in ipairs(Guns.pool) do
    _byId[gun.id] = gun
end

--- The default starting weapon.
Guns.default = _byId["revolver"]

--- Look up a weapon definition by its id string.
function Guns.getById(id)
    return _byId[id]
end

--- Weighted random pick from droppable weapons (dropWeight > 0).
--- Luck increases the weight of rarer weapons (same formula as perks).
function Guns.rollDrop(luck)
    luck = luck or 0
    local totalWeight = 0
    for _, gun in ipairs(Guns.pool) do
        if gun.dropWeight > 0 then
            local w = gun.dropWeight
            if gun.rarity == "rare" then
                w = w * (1 + luck)
            elseif gun.rarity == "uncommon" then
                w = w * (1 + luck * 0.5)
            end
            totalWeight = totalWeight + w
        end
    end
    if totalWeight <= 0 then return nil end

    local roll = GameRng.randomFloat("guns.roll_drop.weight", 0, totalWeight)
    local cumulative = 0
    for _, gun in ipairs(Guns.pool) do
        if gun.dropWeight > 0 then
            local w = gun.dropWeight
            if gun.rarity == "rare" then
                w = w * (1 + luck)
            elseif gun.rarity == "uncommon" then
                w = w * (1 + luck * 0.5)
            end
            cumulative = cumulative + w
            if roll <= cumulative then
                return gun
            end
        end
    end
    return nil
end

return Guns
