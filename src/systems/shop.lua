local GearData = require("src.data.gear")
local Sfx = require("src.systems.sfx")

local Shop = {}
Shop.__index = Shop

function Shop.new(difficulty)
    local self = setmetatable({}, Shop)
    self.difficulty = difficulty or 1
    self.items = {}
    self:generateItems()
    return self
end

function Shop:generateItems()
    self.items = {}

    local maxTier = math.min(3, math.floor(self.difficulty / 2) + 1)
    local priceMultiplier = 1 + (self.difficulty - 1) * 0.2

    -- Heal option
    table.insert(self.items, {
        id = "heal",
        name = "Whiskey - Heal 50%",
        description = "Restore 50% of max HP",
        price = math.floor(30 * priceMultiplier),
        type = "heal",
        sold = false,
    })

    -- Random gear
    local gear = GearData.getRandom(maxTier)
    if gear then
        local statDesc = ""
        for stat, val in pairs(gear.stats) do
            if statDesc ~= "" then statDesc = statDesc .. ", " end
            statDesc = statDesc .. stat .. " +" .. val
        end
        table.insert(self.items, {
            id = "gear_" .. gear.id,
            name = gear.name,
            description = statDesc,
            price = math.floor((20 + gear.tier * 15) * priceMultiplier),
            type = "gear",
            gearData = gear,
            sold = false,
        })
    end

    -- Ammo upgrade
    table.insert(self.items, {
        id = "ammo_upgrade",
        name = "Extended Cylinder (+2)",
        description = "+2 cylinder capacity this run",
        price = math.floor(50 * priceMultiplier),
        type = "ammo",
        sold = false,
    })
end

function Shop:buyItem(index, player)
    local item = self.items[index]
    if not item or item.sold then return false, "Already sold" end
    if player.gold < item.price then return false, "Not enough gold" end

    player.gold = player.gold - item.price
    item.sold = true
    Sfx.play("shop_buy")

    if item.type == "heal" then
        local healAmount = math.floor(player:getEffectiveStats().maxHP * 0.5)
        player:heal(healAmount)
    elseif item.type == "gear" then
        player:equipGear(item.gearData)
    elseif item.type == "ammo" then
        player.stats.cylinderSize = player.stats.cylinderSize + 2
        player:addAmmoToActiveSlot(2, "shop:ammo_upgrade")
    end

    return true, "Purchased!"
end

return Shop
