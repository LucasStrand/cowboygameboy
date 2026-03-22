--- Merchant entity: a travelling merchant NPC that sells items in the field.
--- Appears on a platform, player interacts with E to browse wares.
--- Sells gear, health potions, and ammo at a premium.

local GearData = require("src.data.gear")
local Sfx = require("src.systems.sfx")

local Merchant = {}
Merchant.__index = Merchant

local MERCHANT_W = 24
local MERCHANT_H = 36
local INTERACT_RADIUS = 60

-- Colors for the merchant character
local HAT_COLOR   = {0.55, 0.25, 0.12}
local COAT_COLOR  = {0.30, 0.18, 0.10}
local SKIN_COLOR  = {0.85, 0.72, 0.55}
local PANTS_COLOR = {0.25, 0.22, 0.18}
local PACK_COLOR  = {0.50, 0.38, 0.22}

function Merchant.new(x, y, difficulty)
    local self = setmetatable({}, Merchant)
    self.x = x
    self.y = y
    self.w = MERCHANT_W
    self.h = MERCHANT_H
    self.difficulty = difficulty or 1
    -- State: "idle" | "browsing"
    self.state = "idle"
    self.bobTimer = math.random() * 6.28
    -- Generate shop items
    self.items = {}
    self:generateItems()
    -- Selected item index (for browsing UI)
    self.selectedIndex = 1
    -- Message to show briefly after purchase
    self.message = nil
    self.messageTimer = 0
    -- Callback: set by game.lua
    self.onBuy = nil
    return self
end

function Merchant:generateItems()
    local maxTier = math.min(3, math.floor(self.difficulty / 2) + 1)
    local priceMul = 1.3 + (self.difficulty - 1) * 0.2  -- premium over saloon

    -- Health potion
    table.insert(self.items, {
        id = "heal",
        name = "Snake Oil - Heal 35%",
        description = "Restore 35% of max HP",
        price = math.floor(25 * priceMul),
        type = "heal",
        healPercent = 0.35,
        sold = false,
    })

    -- Random gear piece
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
            price = math.floor((25 + gear.tier * 18) * priceMul),
            type = "gear",
            gearData = gear,
            sold = false,
        })
    end

    -- Ammo
    table.insert(self.items, {
        id = "ammo",
        name = "Extra Rounds (+2)",
        description = "+2 cylinder capacity",
        price = math.floor(45 * priceMul),
        type = "ammo",
        sold = false,
    })
end

function Merchant:update(dt)
    self.bobTimer = self.bobTimer + dt
    if self.messageTimer > 0 then
        self.messageTimer = self.messageTimer - dt
        if self.messageTimer <= 0 then
            self.message = nil
        end
    end
end

function Merchant:tryInteract()
    if self.state == "idle" then
        self.state = "browsing"
        self.selectedIndex = 1
        return true
    end
    return false
end

function Merchant:closeBrowse()
    self.state = "idle"
end

function Merchant:buySelected(player)
    local item = self.items[self.selectedIndex]
    if not item or item.sold then
        self.message = "Sold out"
        self.messageTimer = 1.5
        return false
    end
    if player.gold < item.price then
        self.message = "Not enough gold"
        self.messageTimer = 1.5
        return false
    end

    player.gold = player.gold - item.price
    item.sold = true
    Sfx.play("shop_buy")

    if item.type == "heal" then
        local healAmount = math.floor(player:getEffectiveStats().maxHP * item.healPercent)
        player:heal(healAmount)
    elseif item.type == "gear" then
        player:equipGear(item.gearData)
    elseif item.type == "ammo" then
        player.stats.cylinderSize = player.stats.cylinderSize + 2
        player.ammo = player.ammo + 2
    end

    self.message = "Sold!"
    self.messageTimer = 1.5
    if self.onBuy then self.onBuy(item) end
    return true
end

function Merchant:selectNext()
    self.selectedIndex = self.selectedIndex + 1
    if self.selectedIndex > #self.items then self.selectedIndex = 1 end
end

function Merchant:selectPrev()
    self.selectedIndex = self.selectedIndex - 1
    if self.selectedIndex < 1 then self.selectedIndex = #self.items end
end

function Merchant:isNearPlayer(px, py)
    local cx = self.x + self.w / 2
    local cy = self.y + self.h / 2
    local dx = px - cx
    local dy = py - cy
    return dx * dx + dy * dy < INTERACT_RADIUS * INTERACT_RADIUS
end

function Merchant:draw(showHint, playerGold)
    local cx = self.x + self.w / 2
    local bob = math.sin(self.bobTimer * 1.5) * 1.5

    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.2)
    love.graphics.ellipse("fill", cx, self.y + self.h, 14, 4)

    local dy = bob

    -- Boots
    love.graphics.setColor(PANTS_COLOR[1], PANTS_COLOR[2], PANTS_COLOR[3])
    love.graphics.rectangle("fill", self.x + 4, self.y + self.h - 8 + dy, 6, 8, 1)
    love.graphics.rectangle("fill", self.x + self.w - 10, self.y + self.h - 8 + dy, 6, 8, 1)

    -- Body / coat
    love.graphics.setColor(COAT_COLOR[1], COAT_COLOR[2], COAT_COLOR[3])
    love.graphics.rectangle("fill", self.x + 2, self.y + 14 + dy, self.w - 4, self.h - 22, 3)

    -- Backpack
    love.graphics.setColor(PACK_COLOR[1], PACK_COLOR[2], PACK_COLOR[3])
    love.graphics.rectangle("fill", self.x + self.w - 4, self.y + 16 + dy, 8, 14, 2)
    -- Pack straps
    love.graphics.setColor(PACK_COLOR[1] * 0.7, PACK_COLOR[2] * 0.7, PACK_COLOR[3] * 0.7)
    love.graphics.line(self.x + self.w - 2, self.y + 14 + dy, self.x + self.w + 2, self.y + 16 + dy)

    -- Head
    love.graphics.setColor(SKIN_COLOR[1], SKIN_COLOR[2], SKIN_COLOR[3])
    love.graphics.circle("fill", cx, self.y + 10 + dy, 7)

    -- Hat (wide brim)
    love.graphics.setColor(HAT_COLOR[1], HAT_COLOR[2], HAT_COLOR[3])
    love.graphics.rectangle("fill", self.x - 2, self.y + 3 + dy, self.w + 4, 5, 2)
    love.graphics.rectangle("fill", self.x + 4, self.y - 2 + dy, self.w - 8, 7, 2)

    -- Eyes
    love.graphics.setColor(0.15, 0.12, 0.08)
    love.graphics.circle("fill", cx - 3, self.y + 9 + dy, 1.5)
    love.graphics.circle("fill", cx + 3, self.y + 9 + dy, 1.5)

    -- "$" sign on coat (merchant indicator)
    love.graphics.setColor(0.85, 0.75, 0.2, 0.9)
    love.graphics.printf("$", self.x, self.y + 22 + dy, self.w, "center")

    -- Interaction hint
    if showHint and self.state == "idle" then
        love.graphics.setColor(1, 0.92, 0.3, 0.9)
        love.graphics.printf("[E] Trade", cx - 36, self.y - 18, 72, "center")
    end

    -- Message popup
    if self.message and self.messageTimer > 0 then
        local alpha = math.min(1, self.messageTimer)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.printf(self.message, cx - 40, self.y - 30, 80, "center")
    end

    love.graphics.setColor(1, 1, 1)
end

--- Draw the browsing UI overlay (called in screen space, not world space).
function Merchant:drawShopUI(screenX, screenY, playerGold)
    if self.state ~= "browsing" then return end

    local panelW = 220
    local panelH = 30 + #self.items * 42
    local px = screenX - panelW / 2
    local py = screenY - panelH - 20

    -- Panel background
    love.graphics.setColor(0.08, 0.06, 0.04, 0.92)
    love.graphics.rectangle("fill", px, py, panelW, panelH, 6)
    love.graphics.setColor(0.6, 0.45, 0.2, 0.8)
    love.graphics.rectangle("line", px, py, panelW, panelH, 6)

    -- Title
    love.graphics.setColor(0.9, 0.8, 0.4)
    love.graphics.printf("Trader", px, py + 4, panelW, "center")

    -- Items
    for i, item in ipairs(self.items) do
        local iy = py + 22 + (i - 1) * 42
        local selected = i == self.selectedIndex

        -- Selection highlight
        if selected then
            love.graphics.setColor(0.6, 0.45, 0.2, 0.3)
            love.graphics.rectangle("fill", px + 4, iy, panelW - 8, 38, 3)
        end

        if item.sold then
            love.graphics.setColor(0.4, 0.4, 0.4, 0.5)
            love.graphics.printf(item.name .. " (SOLD)", px + 8, iy + 4, panelW - 16, "left")
        else
            -- Name
            local canAfford = playerGold >= item.price
            if canAfford then
                love.graphics.setColor(1, 1, 1, 0.95)
            else
                love.graphics.setColor(0.7, 0.4, 0.4, 0.8)
            end
            love.graphics.printf(item.name, px + 8, iy + 4, panelW - 16, "left")
            -- Price
            love.graphics.setColor(0.9, 0.8, 0.2)
            love.graphics.printf(item.price .. "g", px + 8, iy + 4, panelW - 16, "right")
            -- Description
            love.graphics.setColor(0.7, 0.7, 0.6, 0.7)
            love.graphics.printf(item.description, px + 8, iy + 20, panelW - 16, "left")
        end
    end

    -- Controls hint
    love.graphics.setColor(0.6, 0.6, 0.5, 0.6)
    love.graphics.printf("W/S: select  E: buy  Q: close", px, py + panelH + 2, panelW, "center")

    love.graphics.setColor(1, 1, 1)
end

return Merchant
