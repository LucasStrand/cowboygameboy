local Perks = {}

Perks.pool = {
    -- Common (60% weight)
    {
        id = "damage_up",
        name = "Steady Hand",
        description = "+15% damage",
        rarity = "common",
        weight = 15,
        apply = function(player)
            player.stats.damageMultiplier = player.stats.damageMultiplier + 0.15
        end
    },
    {
        id = "speed_up",
        name = "Quick Draw Boots",
        description = "+12% move speed",
        rarity = "common",
        weight = 15,
        apply = function(player)
            player.stats.moveSpeed = player.stats.moveSpeed * 1.12
        end
    },
    {
        id = "hp_up",
        name = "Tough Hide",
        description = "+20% max HP",
        rarity = "common",
        weight = 15,
        apply = function(player)
            local bonus = math.floor(player.stats.maxHP * 0.20)
            player.stats.maxHP = player.stats.maxHP + bonus
            player.hp = player.hp + bonus
        end
    },
    {
        id = "armor_up",
        name = "Iron Gut",
        description = "+1 armor",
        rarity = "common",
        weight = 15,
        apply = function(player)
            player.stats.armor = player.stats.armor + 1
        end
    },

    -- Uncommon (30% weight)
    {
        id = "fast_reload",
        name = "Sleight of Hand",
        description = "30% faster reload",
        rarity = "uncommon",
        weight = 8,
        apply = function(player)
            player.stats.reloadSpeed = player.stats.reloadSpeed * 0.7
        end
    },
    {
        id = "extra_bullet",
        name = "Extended Cylinder",
        description = "+1 bullet in cylinder",
        rarity = "uncommon",
        weight = 8,
        apply = function(player)
            player.stats.cylinderSize = player.stats.cylinderSize + 1
            player.ammo = player.ammo + 1
        end
    },
    {
        id = "lifesteal",
        name = "Blood Thirst",
        description = "Heal 5 HP on kill",
        rarity = "uncommon",
        weight = 7,
        apply = function(player)
            player.stats.lifestealOnKill = player.stats.lifestealOnKill + 5
        end
    },
    {
        id = "luck_up",
        name = "Lucky Charm",
        description = "+15% luck",
        rarity = "uncommon",
        weight = 7,
        apply = function(player)
            player.stats.luck = player.stats.luck + 0.15
        end
    },

    -- Rare (10% weight)
    {
        id = "scattershot",
        name = "Scattershot",
        description = "Fire 3 bullets in a spread",
        rarity = "rare",
        weight = 3,
        apply = function(player)
            player.stats.bulletCount = player.stats.bulletCount + 2
            player.stats.spreadAngle = 0.25
        end
    },
    {
        id = "explosive_rounds",
        name = "Explosive Rounds",
        description = "Bullets explode on hit (AOE)",
        rarity = "rare",
        weight = 3,
        apply = function(player)
            player.stats.explosiveRounds = true
        end
    },
    {
        id = "ricochet",
        name = "Ricochet",
        description = "Bullets bounce once off walls",
        rarity = "rare",
        weight = 2,
        apply = function(player)
            player.stats.ricochetCount = player.stats.ricochetCount + 1
        end
    },
    {
        id = "akimbo",
        name = "Akimbo",
        description = "Dual-wield: fire both guns at once",
        rarity = "rare",
        weight = 2,
        apply = function(player)
            player.stats.akimbo = true
        end
    },
}

function Perks.rollPerks(count, luck)
    local luck = luck or 0
    local available = {}
    for _, perk in ipairs(Perks.pool) do
        table.insert(available, perk)
    end

    local selected = {}
    local usedIds = {}

    for i = 1, count do
        local totalWeight = 0
        for _, perk in ipairs(available) do
            if not usedIds[perk.id] then
                local w = perk.weight
                if perk.rarity == "rare" then
                    w = w * (1 + luck)
                elseif perk.rarity == "uncommon" then
                    w = w * (1 + luck * 0.5)
                end
                totalWeight = totalWeight + w
            end
        end

        local roll = math.random() * totalWeight
        local cumulative = 0
        for _, perk in ipairs(available) do
            if not usedIds[perk.id] then
                local w = perk.weight
                if perk.rarity == "rare" then
                    w = w * (1 + luck)
                elseif perk.rarity == "uncommon" then
                    w = w * (1 + luck * 0.5)
                end
                cumulative = cumulative + w
                if roll <= cumulative then
                    table.insert(selected, perk)
                    usedIds[perk.id] = true
                    break
                end
            end
        end
    end

    return selected
end

Perks.rarityColors = {
    common = {0.7, 0.7, 0.7},
    uncommon = {0.2, 0.8, 0.2},
    rare = {0.9, 0.7, 0.1},
}

return Perks
