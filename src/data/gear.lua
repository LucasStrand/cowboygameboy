local GearData = {}
local GameRng = require("src.systems.game_rng")

GearData.slots = {"hat", "vest", "boots"}

GearData.pool = {
    -- Hats
    {
        id = "cowboy_hat",
        name = "Cowboy Hat",
        slot = "hat",
        tooltip_key = "gear_cowboy_hat",
        tooltip_tokens = { luck_pct = 5 },
        tags = { "theme:luck", "reward:neutral", "role:power" },
        stats = {luck = 0.05},
        tier = 1,
    },
    {
        id = "ten_gallon",
        name = "Ten Gallon Hat",
        slot = "hat",
        tooltip_key = "gear_ten_gallon",
        tooltip_tokens = { luck_pct = 10, max_hp = 10 },
        tags = { "theme:luck", "theme:defense", "reward:neutral", "role:power" },
        stats = {luck = 0.10, maxHP = 10},
        tier = 2,
    },
    {
        id = "sheriffs_hat",
        name = "Sheriff's Hat",
        slot = "hat",
        tooltip_key = "gear_sheriffs_hat",
        tooltip_tokens = { luck_pct = 15, armor = 1 },
        tags = { "theme:luck", "theme:defense", "reward:neutral", "role:power" },
        stats = {luck = 0.15, armor = 1},
        tier = 3,
    },

    -- Vests
    {
        id = "leather_vest",
        name = "Leather Vest",
        slot = "vest",
        tooltip_key = "gear_leather_vest",
        tooltip_tokens = { max_hp = 15, armor = 1 },
        tags = { "theme:defense", "reward:neutral", "role:power" },
        stats = {maxHP = 15, armor = 1},
        tier = 1,
    },
    {
        id = "reinforced_vest",
        name = "Reinforced Vest",
        slot = "vest",
        tooltip_key = "gear_reinforced_vest",
        tooltip_tokens = { max_hp = 25, armor = 2 },
        tags = { "theme:defense", "reward:neutral", "role:power" },
        stats = {maxHP = 25, armor = 2},
        tier = 2,
    },
    {
        id = "bandolier",
        name = "Bandolier",
        slot = "vest",
        tooltip_key = "gear_bandolier",
        tooltip_tokens = { armor = 1, damage_pct = 10 },
        tags = { "attack:projectile", "theme:damage", "reward:support", "role:power" },
        stats = {armor = 1, damageMultiplier = 0.1},
        tier = 3,
    },

    -- Boots
    {
        id = "riding_boots",
        name = "Riding Boots",
        slot = "boots",
        tooltip_key = "gear_riding_boots",
        tooltip_tokens = { move_speed = 15 },
        tags = { "theme:mobility", "reward:neutral", "role:power" },
        stats = {moveSpeed = 15},
        tier = 1,
    },
    {
        id = "spurred_boots",
        name = "Spurred Boots",
        slot = "boots",
        tooltip_key = "gear_spurred_boots",
        tooltip_tokens = { move_speed = 25, damage_flat = 3 },
        tags = { "theme:mobility", "theme:damage", "reward:neutral", "role:power" },
        stats = {moveSpeed = 25, damage = 3},
        tier = 2,
    },
    {
        id = "snake_boots",
        name = "Snakeskin Boots",
        slot = "boots",
        tooltip_key = "gear_snake_boots",
        tooltip_tokens = { move_speed = 35, luck_pct = 5 },
        tags = { "theme:mobility", "theme:luck", "reward:neutral", "role:power" },
        stats = {moveSpeed = 35, luck = 0.05},
        tier = 3,
    },
}

local _byId = {}
for _, gear in ipairs(GearData.pool) do
    _byId[gear.id] = gear
end

function GearData.getById(id)
    return _byId[id]
end

function GearData.getRandomForSlot(slot, maxTier)
    maxTier = maxTier or 3
    local candidates = {}
    for _, gear in ipairs(GearData.pool) do
        if gear.slot == slot and gear.tier <= maxTier then
            table.insert(candidates, gear)
        end
    end
    if #candidates == 0 then return nil end
    return candidates[GameRng.random("gear.random_for_slot." .. tostring(slot), #candidates)]
end

function GearData.getRandom(maxTier)
    local slot = GearData.slots[GameRng.random("gear.random_slot", #GearData.slots)]
    return GearData.getRandomForSlot(slot, maxTier)
end

return GearData
