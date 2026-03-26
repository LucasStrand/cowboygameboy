--- Weapon Altar entity: displays 3 weapon choices on pedestals.
--- Player picks one with E, the others disappear.
--- Choices are guns (Guns.rollDrop pool) and/or one knife — same weighted mix as rare enemy weapon drops.

local Guns = require("src.data.guns")
local Combat = require("src.systems.combat")
local GearIcons = require("src.ui.gear_icons")
local WorldInteractLabel = require("src.ui.world_interact_label")

local WeaponAltar = {}
WeaponAltar.__index = WeaponAltar

local PEDESTAL_W = 28
local PEDESTAL_H = 20

-- Sprite (lazy-loaded)
local _pedestalSprite
local function getPedestalSprite()
    if not _pedestalSprite then
        _pedestalSprite = love.graphics.newImage("assets/sprites/props/weapon_altar.png")
        _pedestalSprite:setFilter("nearest", "nearest")
    end
    return _pedestalSprite
end
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
    -- Roll 3 offerings: guns + at most one knife (same pool as Combat.rollWeaponOrMeleeDrop).
    self.choices = {}
    local usedGunIds = {}
    local knifeFree = true
    local lk = luck or 0
    for i = 1, 3 do
        local chosen = nil
        for _ = 1, 40 do
            local pick = Combat.rollWeaponOrMeleeDrop(lk)
            if pick.kind == "melee" and pick.gear and knifeFree then
                knifeFree = false
                chosen = { kind = "melee", def = pick.gear }
                break
            elseif pick.kind == "gun" and pick.gun and not usedGunIds[pick.gun.id] then
                usedGunIds[pick.gun.id] = true
                chosen = { kind = "gun", def = pick.gun }
                break
            end
        end
        if not chosen then
            for _ = 1, 25 do
                local gun = Guns.rollDrop(lk)
                if gun and not usedGunIds[gun.id] then
                    usedGunIds[gun.id] = true
                    chosen = { kind = "gun", def = gun }
                    break
                end
            end
        end
        if not chosen then
            -- Last resort: any droppable gun (allow duplicate id so pedestals never stay empty).
            for _, gun in ipairs(Guns.pool) do
                if gun.dropWeight and gun.dropWeight > 0 then
                    chosen = { kind = "gun", def = gun }
                    break
                end
            end
        end
        self.choices[i] = chosen
    end
    -- State: "choosing" | "chosen"
    self.state = "choosing"
    self.selectedIndex = 0  -- 0 = none highlighted
    self.chosenIndex = 0
    self.glowTimer = math.random() * 6.28
    -- Vanish animation for unchosen weapons
    self.vanishTimer = 0
    -- Callback: set by game.lua, called with ({ kind = "gun"|"melee", def = ... }) when player picks
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
    local choice = self.choices[self.selectedIndex]
    if not choice then return false end

    self.state = "chosen"
    self.chosenIndex = self.selectedIndex
    self.vanishTimer = 0
    if self.onChoose then
        self.onChoose(choice)
    end
    return true
end

function WeaponAltar:draw(showHint)
    local pulse = 0.5 + 0.5 * math.sin(self.glowTimer * 3)

    for i = 1, 3 do
        local ch = self.choices[i]
        if not ch then goto continue end

        local pcx = self:pedestalCenterX(i)
        local pLeft = pcx - PEDESTAL_W / 2

        -- Skip vanished weapons
        if self.state == "chosen" and i ~= self.chosenIndex then
            if self.vanishTimer > 0.5 then goto continue end
            -- Fade out
            local alpha = 1 - self.vanishTimer / 0.5
            love.graphics.setColor(1, 1, 1, alpha)
        end

        local rc = RARITY_COLORS.common
        if ch.kind == "gun" then
            rc = RARITY_COLORS[ch.def.rarity] or RARITY_COLORS.common
        elseif ch.kind == "melee" then
            rc = RARITY_COLORS.uncommon
        end

        -- Pedestal sprite (uniform scale, bottom-aligned)
        local pedSpr = getPedestalSprite()
        local psw, psh = pedSpr:getDimensions()
        local pedScale = math.min(PEDESTAL_W / psw, PEDESTAL_H / psh)
        local pedDrawX = pLeft + (PEDESTAL_W - psw * pedScale) / 2
        local pedDrawY = self.y + self.h - psh * pedScale
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(pedSpr, pedDrawX, pedDrawY, 0, pedScale, pedScale)

        -- Selection glow
        local selected = self.state == "choosing" and i == self.selectedIndex
        if selected then
            love.graphics.setColor(rc[1], rc[2], rc[3], 0.25 + 0.15 * pulse)
            love.graphics.rectangle("fill", pLeft - 2, self.y - 4, PEDESTAL_W + 4, self.h + 8, 4)
        end

        -- Gun sprite or knife tile above pedestal
        local weaponY = self.y + self.h - PEDESTAL_H - 18 + math.sin(self.glowTimer * 2 + i) * 3
        local spriteHalfH = 10
        if ch.kind == "gun" then
            local sprite = Guns.getSprite(ch.def)
            local scale = 0.6
            if sprite then
                local sw, sh = sprite:getDimensions()
                spriteHalfH = sh * scale * 0.5
                love.graphics.setColor(1, 1, 1)
                love.graphics.draw(sprite, pcx, weaponY, 0, scale, scale, sw / 2, sh / 2)
            else
                love.graphics.setColor(rc[1], rc[2], rc[3], 0.9)
                love.graphics.rectangle("fill", pcx - 8, weaponY - 4, 16, 8, 2)
                spriteHalfH = 6
            end
        else
            local icon = ch.def and ch.def.icon
            local drawn = icon and GearIcons.draw(icon, pLeft, weaponY - 14, PEDESTAL_W, 28, 2, 1)
            if drawn then
                spriteHalfH = 14
            else
                love.graphics.setColor(rc[1], rc[2], rc[3], 0.9)
                love.graphics.rectangle("fill", pcx - 8, weaponY - 4, 16, 8, 2)
                spriteHalfH = 6
            end
        end

        -- Rarity glow under weapon
        love.graphics.setColor(rc[1], rc[2], rc[3], 0.18 * pulse)
        love.graphics.circle("fill", pcx, weaponY, 12)

        local weaponTopY = weaponY - spriteHalfH
        local nameAlpha = (self.state == "chosen" and i ~= self.chosenIndex) and (1 - self.vanishTimer / 0.5) or 1

        local hintText = (ch.kind == "melee" and ch.def and ch.def.name) and ("[E] Take — " .. ch.def.name) or "[E] Take"
        if selected and showHint then
            WorldInteractLabel.drawAboveAnchor(pcx, weaponTopY, hintText, {
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
