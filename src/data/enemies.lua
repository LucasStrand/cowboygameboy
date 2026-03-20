local EnemyData = {}

EnemyData.types = {
    bandit = {
        name = "Bandit",
        hp = 30,
        damage = 10,
        speed = 120,
        xpValue = 15,
        goldValue = 5,
        width = 20,
        height = 28,
        color = {0.8, 0.3, 0.2},
        behavior = "melee",
        attackRange = 24,
        attackCooldown = 0.8,
    },
    gunslinger = {
        name = "Gunslinger",
        hp = 50,
        damage = 8,
        speed = 40,
        xpValue = 25,
        goldValue = 15,
        width = 20,
        height = 28,
        color = {0.6, 0.2, 0.6},
        behavior = "ranged",
        attackRange = 300,
        attackCooldown = 1.5,
        bulletSpeed = 250,
    },
    buzzard = {
        name = "Buzzard",
        hp = 20,
        damage = 8,
        speed = 150,
        xpValue = 10,
        goldValue = 3,
        width = 22,
        height = 16,
        color = {0.5, 0.4, 0.2},
        behavior = "flying",
        attackRange = 200,
        attackCooldown = 2.0,
        swoopSpeed = 280,
    },
}

function EnemyData.getScaled(typeId, difficulty)
    local base = EnemyData.types[typeId]
    if not base then return nil end

    local scaled = {}
    for k, v in pairs(base) do
        scaled[k] = v
    end

    local mult = 1 + (difficulty - 1) * 0.15
    scaled.hp = math.floor(base.hp * mult)
    scaled.damage = math.floor(base.damage * mult)
    scaled.xpValue = math.floor(base.xpValue * mult)
    scaled.goldValue = math.floor(base.goldValue * mult)

    return scaled
end

return EnemyData
