--- Weapon Altar entity: displays 3 weapon choices on pedestals.
--- Player picks one with E, the others disappear.

local Guns = require("src.data.guns")
local WorldInteractLabel = require("src.ui.world_interact_label")

local WeaponAltar = {}
WeaponAltar.__index = WeaponAltar

local PEDESTAL_W = 28
local PEDESTAL_H = 20
local PEDESTAL_GAP = 16
local INTERACT_RADIUS = 60
local TOTAL_W = PEDESTAL_W * 3 + PEDESTAL_GAP * 2

-- World Y for "Choose a weapon" anchor: must sit clearly above "[E] Take" (anchored at weaponTopY).
local CHOOSE_HEADER_ANCHOR_Y = -44

local RARITY_COLORS = {
    common   = {0.85, 0.85, 0.85},
    uncommon = {0.2, 0.8, 0.2},
    rare     = {1.0, 0.6, 0.1},
}

function WeaponAltar.new(x, y, luck)
    local self = setmetatable({}, WeaponAltar)
    -- x,y is the left foot of the altar group
    self.x = x
    self.y = y
    self.w = TOTAL_W
    self.h = PEDESTAL_H + 24  -- pedestal + weapon float space
    -- Roll 3 weapons
    self.choices = {}
    local usedIds = {}
    for i = 1, 3 do
        local gun = nil
        for attempt = 1, 20 do
            gun = Guns.rollDrop(luck or 0)
            if gun and not usedIds[gun.id] then
                usedIds[gun.id] = true
                break
            end
        end
        if gun then
            self.choices[i] = gun
        end
    end
    -- State: "choosing" | "chosen"
    self.state = "choosing"
    self.selectedIndex = 0  -- 0 = none highlighted
    self.chosenIndex = 0
    self.glowTimer = math.random() * 6.28
    -- Vanish animation for unchosen weapons
    self.vanishTimer = 0
    -- Callback: set by game.lua, called with (gunDef) when player picks
    self.onChoose = nil
    return self
end

function WeaponAltar:update(dt)
    self.glowTimer = self.glowTimer + dt
    if self.state == "chosen" then
        self.vanishTimer = self.vanishTimer + dt
    end
end

--- Get the center X of the i-th pedestal.
function WeaponAltar:pedestalCenterX(i)
    return self.x + (i - 1) * (PEDESTAL_W + PEDESTAL_GAP) + PEDESTAL_W / 2
end

--- Determine which pedestal the player is closest to (1-3), or 0.
function WeaponAltar:nearestPedestal(px, py)
    local best, bestDist = 0, math.huge
    for i = 1, 3 do
        if self.choices[i] then
            local pcx = self:pedestalCenterX(i)
            local pcy = self.y + PEDESTAL_H / 2
            local dx = px - pcx
            local dy = py - pcy
            local d = dx * dx + dy * dy
            if d < bestDist then
                bestDist = d
                best = i
            end
        end
    end
    return best
end

function WeaponAltar:isNearPlayer(px, py)
    local cx = self.x + self.w / 2
    local cy = self.y + self.h / 2
    local dx = px - cx
    local dy = py - cy
    return dx * dx + dy * dy < INTERACT_RADIUS * INTERACT_RADIUS
end

--- Called each frame the player is nearby to highlight the closest pedestal.
function WeaponAltar:updateSelection(px, py)
    if self.state ~= "choosing" then
        self.selectedIndex = 0
        return
    end
    self.selectedIndex = self:nearestPedestal(px, py)
end

--- Called by game.lua when E is pressed near the altar.
function WeaponAltar:tryChoose(player)
    if self.state ~= "choosing" then return false end
    if self.selectedIndex < 1 or self.selectedIndex > 3 then return false end
    local gun = self.choices[self.selectedIndex]
    if not gun then return false end

    self.state = "chosen"
    self.chosenIndex = self.selectedIndex
    self.vanishTimer = 0
    if self.onChoose then
        self.onChoose(gun)
    end
    return true
end

function WeaponAltar:draw(showHint)
    local pulse = 0.5 + 0.5 * math.sin(self.glowTimer * 3)

    for i = 1, 3 do
        local gun = self.choices[i]
        if not gun then goto continue end

        local pcx = self:pedestalCenterX(i)
        local pLeft = pcx - PEDESTAL_W / 2

        -- Skip vanished weapons
        if self.state == "chosen" and i ~= self.chosenIndex then
            if self.vanishTimer > 0.5 then goto continue end
            -- Fade out
            local alpha = 1 - self.vanishTimer / 0.5
            love.graphics.setColor(1, 1, 1, alpha)
        end

        local rc = RARITY_COLORS[gun.rarity] or RARITY_COLORS.common

        -- Pedestal base
        love.graphics.setColor(0.40, 0.36, 0.30)
        love.graphics.rectangle("fill", pLeft, self.y + self.h - PEDESTAL_H, PEDESTAL_W, PEDESTAL_H, 2)
        love.graphics.setColor(0.50, 0.46, 0.38)
        love.graphics.rectangle("fill", pLeft, self.y + self.h - PEDESTAL_H, PEDESTAL_W, 4, 1)

        -- Selection glow
        local selected = self.state == "choosing" and i == self.selectedIndex
        if selected then
            love.graphics.setColor(rc[1], rc[2], rc[3], 0.25 + 0.15 * pulse)
            love.graphics.rectangle("fill", pLeft - 2, self.y - 4, PEDESTAL_W + 4, self.h + 8, 4)
        end

        -- Weapon sprite floating above pedestal
        local weaponY = self.y + self.h - PEDESTAL_H - 18 + math.sin(self.glowTimer * 2 + i) * 3
        local sprite = Guns.getSprite(gun)
        local scale = 0.6
        local spriteHalfH = 10
        if sprite then
            local sw, sh = sprite:getDimensions()
            spriteHalfH = sh * scale * 0.5
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(sprite, pcx, weaponY, 0, scale, scale, sw / 2, sh / 2)
        else
            -- Fallback colored block
            love.graphics.setColor(rc[1], rc[2], rc[3], 0.9)
            love.graphics.rectangle("fill", pcx - 8, weaponY - 4, 16, 8, 2)
            spriteHalfH = 6
        end

        -- Rarity glow under weapon
        love.graphics.setColor(rc[1], rc[2], rc[3], 0.18 * pulse)
        love.graphics.circle("fill", pcx, weaponY, 12)

        local weaponTopY = weaponY - spriteHalfH
        local nameAlpha = (self.state == "chosen" and i ~= self.chosenIndex) and (1 - self.vanishTimer / 0.5) or 1

        -- Interaction hint above the weapon (no per-gun name labels — guns are readable from sprites)
        if selected and showHint then
            WorldInteractLabel.drawAboveAnchor(pcx, weaponTopY, "[E] Take", {
                bobAmp = 1,
                bobTime = love.timer.getTime(),
                alpha = nameAlpha,
            })
        end

        ::continue::
    end

    -- Draw last so the header stays on top of pedestals, glows, and [E] prompts.
    if self.state == "choosing" and showHint then
        local headerAnchorY = self.y + CHOOSE_HEADER_ANCHOR_Y
        WorldInteractLabel.drawAboveAnchor(self.x + self.w * 0.5, headerAnchorY, "Choose a weapon", {
            gap = 8,
            bobAmp = 0.6,
            bobTime = love.timer.getTime(),
            fg = { 0.95, 0.88, 0.65 },
        })
    end

    love.graphics.setColor(1, 1, 1)
end

return WeaponAltar
