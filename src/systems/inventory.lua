local GearData = require("src.data.gear")

local Inventory = {}

function Inventory.equipGear(player, gear)
    player:equipGear(gear)
end

function Inventory.getGearInSlot(player, slot)
    return player.gear[slot]
end

function Inventory.getAllGear(player)
    local gear = {}
    for _, slot in ipairs(GearData.slots) do
        if player.gear[slot] then
            table.insert(gear, player.gear[slot])
        end
    end
    return gear
end

return Inventory
