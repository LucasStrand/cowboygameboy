local GearData = {}
local GameRng = require("src.systems.game_rng")

GearData.slots = {"hat", "vest", "boots"}

GearData.pool = {
    -- Hats
    {
        id = "cowboy_hat",
        name = "Cowboy Hat",
        slot = "hat",
        stats = {luck = 0.05},
        tier = 1,
    },
    {
        id = "ten_gallon",
        name = "Ten Gallon Hat",
        slot = "hat",
        stats = {luck = 0.10, maxHP = 10},
        tier = 2,
    },
    {
        id = "sheriffs_hat",
        name = "Sheriff's Hat",
        slot = "hat",
        stats = {luck = 0.15, armor = 1},
        tier = 3,
    },

    -- Vests
    {
        id = "leather_vest",
        name = "Leather Vest",
        slot = "vest",
        stats = {maxHP = 15, armor = 1},
        tier = 1,
    },
    {
        id = "reinforced_vest",
        name = "Reinforced Vest",
        slot = "vest",
        stats = {maxHP = 25, armor = 2},
        tier = 2,
    },
    {
        id = "bandolier",
        name = "Bandolier",
        slot = "vest",
        stats = {armor = 1, damageMultiplier = 0.1},
        tier = 3,
    },

    -- Boots
    {
        id = "riding_boots",
        name = "Riding Boots",
        slot = "boots",
        stats = {moveSpeed = 15},
        tier = 1,
    },
    {
        id = "spurred_boots",
        name = "Spurred Boots",
        slot = "boots",
        stats = {moveSpeed = 25, damage = 3},
        tier = 2,
    },
    {
        id = "snake_boots",
        name = "Snakeskin Boots",
        slot = "boots",
        stats = {moveSpeed = 35, luck = 0.05},
        tier = 3,
    },
}

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
