local ContentTooltips = require("src.systems.content_tooltips")
local RewardRuntime = require("src.systems.reward_runtime")
local RunMetadata = require("src.systems.run_metadata")
local Sfx = require("src.systems.sfx")

local Shop = {}
Shop.__index = Shop

Shop.offer_templates = {
    heal = {
        id = "heal",
        name = "Whiskey - Heal 50%",
        tooltip_key = "shop_heal",
        tooltip_tokens = {},
        type = "heal",
        tags = { "theme:sustain", "reward:neutral", "role:sustain" },
    },
    ammo_upgrade = {
        id = "ammo_upgrade",
        name = "Extended Cylinder (+2)",
        tooltip_key = "shop_ammo_upgrade",
        tooltip_tokens = {
            amount = 2,
        },
        type = "ammo",
        tags = { "attack:projectile", "theme:ammo", "reward:support", "role:utility" },
    },
}

function Shop.new(difficulty, player, context)
    local self = setmetatable({}, Shop)
    self.difficulty = difficulty or 1
    self.player = player
    self.context = context or {}
    self.items = {}
    self:generateItems()
    return self
end

function Shop:generateItems()
    local build_snapshot = nil
    if self.player then
        local profile = RewardRuntime.buildProfile(self.player, { source = self.context.source or "shop" })
        build_snapshot = RunMetadata.snapshotBuild(self.player, profile)
        self.context.build_snapshot = build_snapshot
    end
    self.items = RewardRuntime.rollShopOffers(self.player, {
        difficulty = self.difficulty,
        run_metadata = self.context.run_metadata,
        source = self.context.source or "shop",
        room_manager = self.context.room_manager,
        build_snapshot = build_snapshot,
    })

    for _, item in ipairs(self.items or {}) do
        if item.type == "gear" and item.gearData then
            item.description = ContentTooltips.getJoinedText("gear", item.gearData)
        elseif item.type == "weapon" and item.gunData then
            item.description = ContentTooltips.getJoinedText("gun", item.gunData)
        elseif item.tooltip_key or item.tooltip_override then
            item.description = ContentTooltips.getJoinedText("offer", item)
        end
    end
end

function Shop:getRerollCost()
    return RewardRuntime.getRerollCost("shop", self.context and self.context.run_metadata or nil, {
        difficulty = self.difficulty,
    })
end

function Shop:reroll(player)
    player = player or self.player
    local offers, cost, err, profile = RewardRuntime.reroll("shop", player, {
        difficulty = self.difficulty,
        run_metadata = self.context.run_metadata,
        source = self.context.source or "shop",
        room_manager = self.context.room_manager,
        current_offers = self.items,
    })
    if not offers then
        return false, err or "Reroll failed", cost
    end
    self.items = offers
    self.context.build_snapshot = RunMetadata.snapshotBuild(player, profile)
    for _, item in ipairs(self.items or {}) do
        if item.type == "gear" and item.gearData then
            item.description = ContentTooltips.getJoinedText("gear", item.gearData)
        elseif item.type == "weapon" and item.gunData then
            item.description = ContentTooltips.getJoinedText("gun", item.gunData)
        elseif item.tooltip_key or item.tooltip_override then
            item.description = ContentTooltips.getJoinedText("offer", item)
        end
    end
    return true, "Rerolled!", cost
end

function Shop.applyOfferItem(item, player)
    if not item or not player then
        return false
    end

    if item.type == "heal" then
        local healAmount = math.floor(player:getEffectiveStats().maxHP * 0.5)
        player:heal(healAmount)
    elseif item.type == "gear" then
        player:equipGear(item.gearData)
    elseif item.type == "weapon" and item.gunData then
        player:equipWeapon(item.gunData)
    elseif item.type == "ammo" then
        player.stats.cylinderSize = player.stats.cylinderSize + 2
        player:addAmmoToActiveSlot(2, "shop:ammo_upgrade")
    else
        return false
    end

    return true
end

function Shop.validateOfferSpecs()
    for _, item in pairs(Shop.offer_templates) do
        if type(item.name) ~= "string" or item.name == "" then
            error(string.format("[shop] offer '%s' missing name", tostring(item.id)), 0)
        end
        if type(item.tooltip_key) ~= "string" or item.tooltip_key == "" then
            error(string.format("[shop] offer '%s' missing tooltip_key", tostring(item.id)), 0)
        end
    end
    return true
end

function Shop:buyItem(index, player)
    local item = self.items[index]
    if not item or item.sold then return false, "Already sold" end
    if player.gold < item.price then return false, "Not enough gold" end

    local success = player:spendGold(item.price, self.context.source or "shop_purchase")
    if not success then return false, "Not enough gold" end
    item.sold = true
    Sfx.play("shop_buy")

    Shop.applyOfferItem(item, player)
    if self.context and self.context.run_metadata then
        local build_snapshot = self.context.build_snapshot
        if not build_snapshot and player then
            local profile = RewardRuntime.buildProfile(player, { source = self.context.source or "shop_purchase" })
            build_snapshot = RunMetadata.snapshotBuild(player, profile)
        end
        RewardRuntime.recordChoice(self.context.run_metadata, {
            kind = "shop_purchase",
            source = self.context.source or "shop_purchase",
            item = item,
            price = item.price,
            build_snapshot = build_snapshot,
        })
    end
    return true, "Purchased!"
end

return Shop
