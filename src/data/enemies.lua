local EnemyData = {}

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = cloneValue(v)
    end
    return copy
end

local function mergeInto(target, source)
    for k, v in pairs(source) do
        target[k] = cloneValue(v)
    end
    return target
end

local function buildAI(base, overrides)
    local ai = cloneValue(base)
    if overrides then
        mergeInto(ai, overrides)
    end
    return ai
end

local DEFAULT_AI = {
    sightRange = 240,
    closeSightRange = 72,
    fieldOfView = math.rad(135),
    hearingRange = 280,
    hearingMemory = 1.2,
    sightMemory = 1.8,
    calmDownTime = 2.7,
    reactionTime = 0.25,
    reactionJitter = 0.08,
    decisionInterval = 0.18,
    decisionJitter = 0.08,
    patrolRadius = 80,
    patrolPauseMin = 0.55,
    patrolPauseMax = 1.15,
    patrolSpeedMultiplier = 0.42,
    investigateTime = 1.1,
    investigateSpeedMultiplier = 0.72,
    searchTime = 2.2,
    searchSweepDistance = 60,
    chaseSpeedMultiplier = 1.0,
    preferredMinDistance = 16,
    preferredMaxDistance = 32,
    preferredDistanceJitter = 8,
    retreatDistance = 0,
    repositionTime = 0.65,
    repositionCooldown = 1.15,
    stuckTimeout = 0.55,
    groupAlertRange = 220,
    groupAlertMemory = 1.5,
    allyCrowdRadius = 64,
    maxFrontlineAllies = 1,
    attackInaccuracy = 0,
    attackInaccuracyJitter = 0,
}

local MELEE_AI = buildAI(DEFAULT_AI, {
    chaseSpeedMultiplier = 1.05,
    rushDistance = 56,
    rushSpeedMultiplier = 1.32,
    rushSpeedCap = 1.88,
    preferredMinDistance = 12,
    preferredMaxDistance = 26,
    preferredDistanceJitter = 10,
    investigateSpeedMultiplier = 0.82,
    searchTime = 2.5,
    searchSweepDistance = 72,
})

local RANGED_AI = buildAI(DEFAULT_AI, {
    fieldOfView = math.rad(140),
    patrolSpeedMultiplier = 0.32,
    investigateSpeedMultiplier = 0.62,
    chaseSpeedMultiplier = 0.82,
    preferredMinDistance = 165,
    preferredMaxDistance = 255,
    preferredDistanceJitter = 26,
    retreatDistance = 120,
    repositionTime = 0.85,
    repositionCooldown = 1.35,
    allyCrowdRadius = 112,
    maxFrontlineAllies = 2,
    attackInaccuracy = 0.09,
    attackInaccuracyJitter = 0.07,
    attackHeightTolerance = 180,
})

local FLYING_AI = buildAI(DEFAULT_AI, {
    fieldOfView = math.rad(170),
    patrolRadius = 96,
    patrolSpeedMultiplier = 0.36,
    investigateSpeedMultiplier = 0.9,
    chaseSpeedMultiplier = 1.0,
    preferredMinDistance = 105,
    preferredMaxDistance = 175,
    preferredDistanceJitter = 22,
    retreatDistance = 72,
    repositionTime = 0.45,
    repositionCooldown = 0.9,
    searchTime = 1.8,
    searchSweepDistance = 84,
    calmDownTime = 2.1,
    maxFrontlineAllies = 2,
})

EnemyData.types = {
    bandit = {
        name = "Bandit",
        hp = 22,
        damage = 8,
        speed = 168,
        xpValue = 12,
        goldValue = 5,
        width = 20,
        height = 28,
        color = {0.8, 0.3, 0.2},
        behavior = "melee",
        attackRange = 24,
        attackCooldown = 0.8,
        -- Short leash keeps melee threats local until they actually sense the player.
        aggroRange = 210,
        ai = buildAI(MELEE_AI, {
            sightRange = 225,
            hearingRange = 285,
            reactionTime = 0.24,
            patrolRadius = 88,
            preferredMinDistance = 12,
            preferredMaxDistance = 24,
        }),
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
        bulletSpeed = 380,
        aggroRange = 300,
        ai = buildAI(RANGED_AI, {
            sightRange = 300,
            hearingRange = 340,
            reactionTime = 0.3,
            searchTime = 2.8,
            preferredMinDistance = 175,
            preferredMaxDistance = 270,
        }),
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
        -- Actual body contact must stay small; swoop intent is handled by AI state.
        contactRange = 26,
        attackCooldown = 2.0,
        swoopSpeed = 280,
        aggroRange = 230,
        ai = buildAI(FLYING_AI, {
            sightRange = 260,
            hearingRange = 320,
            reactionTime = 0.18,
            calmDownTime = 1.8,
            preferredMinDistance = 115,
            preferredMaxDistance = 185,
        }),
    },
    necromancer = {
        name = "Necromancer",
        hp = 44,
        damage = 10,
        speed = 34,
        xpValue = 30,
        goldValue = 18,
        width = 22,
        height = 34,
        color = {0.42, 0.18, 0.22},
        behavior = "ranged",
        attackRange = 320,
        attackCooldown = 1.9,
        attackAnimDuration = 0.62,
        bulletSpeed = 220,
        aggroRange = 340,
        ai = buildAI(RANGED_AI, {
            sightRange = 330,
            hearingRange = 360,
            reactionTime = 0.36,
            searchTime = 3.1,
            preferredMinDistance = 200,
            preferredMaxDistance = 300,
            retreatDistance = 135,
            attackInaccuracy = 0.06,
            attackHeightTolerance = 210,
        }),
    },
    nightborne = {
        name = "Nightborne",
        hp = 28,
        damage = 10,
        speed = 190,
        xpValue = 16,
        goldValue = 8,
        width = 22,
        height = 30,
        color = {0.42, 0.18, 0.62},
        behavior = "melee",
        attackRange = 28,
        attackCooldown = 0.72,
        attackAnimDuration = 0.44,
        aggroRange = 235,
        ai = buildAI(MELEE_AI, {
            sightRange = 248,
            hearingRange = 305,
            reactionTime = 0.2,
            patrolRadius = 104,
            rushSpeedMultiplier = 1.45,
            rushSpeedCap = 2.05,
            preferredMinDistance = 10,
            preferredMaxDistance = 22,
            searchTime = 2.9,
        }),
    },
    ogreboss = {
        name = "Ogre Boss",
        hp = 280,
        damage = 18,
        speed = 116,
        xpValue = 110,
        goldValue = 70,
        width = 38,
        height = 44,
        color = {0.22, 0.42, 0.18},
        behavior = "melee",
        attackRange = 40,
        attackCooldown = 1.0,
        aggroRange = 280,
        ai = buildAI(MELEE_AI, {
            sightRange = 300,
            hearingRange = 360,
            reactionTime = 0.2,
            patrolRadius = 96,
            preferredMinDistance = 20,
            preferredMaxDistance = 42,
            repositionTime = 0.8,
        }),
    },
    blackkid = {
        name = "Blackkid",
        hp = 220,
        damage = 14,
        speed = 140,
        xpValue = 80,
        goldValue = 45,
        width = 32,
        height = 40,
        color = {0.15, 0.12, 0.18},
        behavior = "melee",
        attackRange = 32,
        attackCooldown = 0.85,
        aggroRange = 240,
        ai = buildAI(MELEE_AI, {
            sightRange = 255,
            hearingRange = 320,
            reactionTime = 0.2,
            patrolRadius = 92,
            preferredMinDistance = 14,
            preferredMaxDistance = 30,
        }),
    },
}

function EnemyData.getScaled(typeId, difficulty)
    local base = EnemyData.types[typeId]
    if not base then return nil end

    local scaled = cloneValue(base)
    local mult = 1 + (difficulty - 1) * 0.15

    scaled.hp = math.floor(base.hp * mult)
    scaled.damage = math.floor(base.damage * mult)
    scaled.xpValue = math.floor(base.xpValue * mult)
    scaled.goldValue = math.floor(base.goldValue * mult)

    return scaled
end

return EnemyData
