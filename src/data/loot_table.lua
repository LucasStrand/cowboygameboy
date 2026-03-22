--- Chest loot table. Returns a list of {type, value, vx, vy} drop specs.
--- Types match Pickup.new() types: "gold", "health", "xp".

local LootTable = {}

local function randBetween(a, b)
    return a + math.random() * (b - a)
end

--- Spawn a scattered burst of pickups from a chest position.
--- tier: "normal" | "rich" | "cursed"
function LootTable.rollChest(tier)
    local drops = {}
    tier = tier or "normal"

    if tier == "normal" then
        -- 4-8 gold coins, each worth 3-7
        local n = math.random(4, 8)
        for _ = 1, n do
            table.insert(drops, {
                type = "gold",
                value = math.random(3, 7),
                vx = randBetween(-140, 140),
                vy = randBetween(-260, -120),
            })
        end
        -- 40% health pickup
        if math.random() < 0.40 then
            table.insert(drops, {
                type = "health",
                value = 20,
                vx = randBetween(-60, 60),
                vy = randBetween(-220, -100),
            })
        end
        -- 20% XP gem
        if math.random() < 0.20 then
            table.insert(drops, {
                type = "xp",
                value = math.random(15, 30),
                vx = randBetween(-80, 80),
                vy = randBetween(-240, -100),
            })
        end

    elseif tier == "rich" then
        -- 10-18 gold, higher values
        local n = math.random(10, 18)
        for _ = 1, n do
            table.insert(drops, {
                type = "gold",
                value = math.random(6, 14),
                vx = randBetween(-180, 180),
                vy = randBetween(-300, -130),
            })
        end
        -- Guaranteed health
        table.insert(drops, {
            type = "health",
            value = 35,
            vx = randBetween(-50, 50),
            vy = randBetween(-200, -100),
        })
        -- 50% XP gem
        if math.random() < 0.50 then
            table.insert(drops, {
                type = "xp",
                value = math.random(30, 55),
                vx = randBetween(-80, 80),
                vy = randBetween(-240, -100),
            })
        end

    elseif tier == "cursed" then
        -- Cursed: tempting gold, but risky.  Caller applies damage separately.
        local n = math.random(6, 12)
        for _ = 1, n do
            table.insert(drops, {
                type = "gold",
                value = math.random(5, 10),
                vx = randBetween(-160, 160),
                vy = randBetween(-280, -120),
            })
        end
        -- Always XP
        table.insert(drops, {
            type = "xp",
            value = math.random(25, 45),
            vx = randBetween(-80, 80),
            vy = randBetween(-220, -100),
        })
    end

    return drops
end

return LootTable
