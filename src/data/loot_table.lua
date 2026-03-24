--- Chest loot table. Returns a list of {type, value, vx, vy} drop specs.
--- Gold chest coins are all gold pieces (5 wallet gold each); silver is used elsewhere for exact totals.
--- Types match Pickup.new() types: "gold", "health", "xp".

local GoldCoin = require("src.data.gold_coin")

local LootTable = {}

LootTable.GOLD_COIN_VALUE = GoldCoin.GOLD_VALUE

local function randBetween(a, b)
    return a + math.random() * (b - a)
end

local V = GoldCoin.GOLD_VALUE

--- Spawn a scattered burst of pickups from a chest position.
--- tier: "normal" | "rich" | "cursed"
function LootTable.rollChest(tier)
    local drops = {}
    tier = tier or "normal"

    if tier == "normal" then
        -- 4–9 coins × V → e.g. 20–45 gold total, always same per-coin value
        local n = math.random(4, 9)
        for _ = 1, n do
            table.insert(drops, {
                type = "gold",
                value = V,
                vx = randBetween(-105, 105),
                vy = randBetween(-380, -200),
            })
        end
        if math.random() < 0.40 then
            table.insert(drops, {
                type = "health",
                value = 20,
                vx = randBetween(-90, 90),
                vy = randBetween(-280, -140),
            })
        end
        if math.random() < 0.20 then
            table.insert(drops, {
                type = "xp",
                value = math.random(15, 30),
                vx = randBetween(-120, 120),
                vy = randBetween(-320, -180),
            })
        end

    elseif tier == "rich" then
        local n = math.random(14, 24)
        for _ = 1, n do
            table.insert(drops, {
                type = "gold",
                value = V,
                vx = randBetween(-260, 260),
                vy = randBetween(-440, -240),
            })
        end
        table.insert(drops, {
            type = "health",
            value = 35,
            vx = randBetween(-70, 70),
            vy = randBetween(-260, -150),
        })
        if math.random() < 0.50 then
            table.insert(drops, {
                type = "xp",
                value = math.random(30, 55),
                vx = randBetween(-130, 130),
                vy = randBetween(-340, -200),
            })
        end

    elseif tier == "cursed" then
        local n = math.random(8, 16)
        for _ = 1, n do
            table.insert(drops, {
                type = "gold",
                value = V,
                vx = randBetween(-115, 115),
                vy = randBetween(-400, -220),
            })
        end
        table.insert(drops, {
            type = "xp",
            value = math.random(25, 45),
            vx = randBetween(-120, 120),
            vy = randBetween(-320, -180),
        })
    end

    return drops
end

return LootTable
