local Guns = {}
local GameRng = require("src.systems.game_rng")

-- All gun definitions.  Each weapon's baseStats REPLACE the player's default
-- gun stats when the weapon is active.  Perk bonuses are applied on top via
-- the delta approach in player:getEffectiveStats().

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
        name        = "Revolver",
        rarity      = "common",
        dropWeight  = 0,            -- 0 = starter only
        ammoType    = "cylinder",   -- HUD render style
        attack_profile_id = "projectile_basic",
        tags = { "attack:projectile", "weapon:revolver" },
        capabilities = {},
        rules = {},
        status_applications = {},
        sprite      = "ColtSingleActionArmy.png",
        -- Sprite origin: fraction of 32x32 where the grip is (for rotation pivot)
        spriteOrigin = { x = 0.25, y = 0.55 },
        spriteScale  = 0.65,
        baseStats   = {
            cylinderSize  = 6,
            reloadSpeed   = 1.2,
            bulletSpeed   = 720,
            bulletDamage  = 10,
            bulletCount   = 1,
            spreadAngle   = 0,
            shootCooldown = 0.38,
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
        tags = { "attack:projectile", "weapon:shotgun", "attack:recoil_mobility" },
        capabilities = {},
        rules = {
            recoil_only_when_aiming_down = true,
        },
        status_applications = {
            {
                id = "bleed",
                chance = 0.28,
                stacks = 1,
                duration = 6,
                bleed_scalar = 0.18,
            },
        },
        sprite      = "Blunderbuss.png",
        spriteOrigin = { x = 0.3, y = 0.55 },
        spriteScale  = 0.75,
        baseStats   = {
            cylinderSize  = 2,
            reloadSpeed   = 1.8,
            bulletSpeed   = 580,
            bulletDamage  = 6,
            bulletCount   = 5,
            spreadAngle   = 0.45,
            shootCooldown = 0.70,
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
        tags = { "attack:projectile", "weapon:rifle" },
        capabilities = {},
        rules = {},
        status_applications = {
            {
                id = "shock",
                chance = 0.18,
                stacks = 1,
                duration = 5,
                overload_damage_scale = 0.75,
                overload_stun_duration = 0.6,
            },
        },
        sprite      = "AK47.png",
        spriteOrigin = { x = 0.22, y = 0.50 },
        spriteScale  = 0.72,
        baseStats   = {
            cylinderSize  = 30,
            reloadSpeed   = 2.0,
            bulletSpeed   = 780,
            bulletDamage  = 5,
            bulletCount   = 1,
            spreadAngle   = 0,
            shootCooldown = 0.10,
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
