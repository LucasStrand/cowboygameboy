local PlatformCollision = require("src.systems.platform_collision")
local Font = require("src.ui.font")
local Guns = require("src.data.guns")
local GoldCoin = require("src.ui.gold_coin")
local Vision = require("src.data.vision")

local Pickup = {}
Pickup.__index = Pickup

local RARITY_COLORS = {
    common   = {0.85, 0.85, 0.85},
    uncommon = {0.2, 0.8, 0.2},
    rare     = {1.0, 0.6, 0.1},
}

local GRAVITY = 600

local ATTRACT_SPEED_MIN = 180
local ATTRACT_SPEED_MAX = 520
-- XP: brief pop-out, then homes from any distance (see xpMagnetDelay)
local XP_MAGNET_DELAY = 0.11
local XP_ATTRACT_SPEED_MIN = 260
local XP_ATTRACT_SPEED_MAX = 640

function Pickup.new(x, y, pickupType, value)
    local self = setmetatable({}, Pickup)
    self.x = x
    self.y = y
    self.w = 10
    self.h = 10
    self.vx = 0
    self.vy = 0
    self.pickupType = pickupType
    self.value = value or 1
    self.isPickup = true
    self.alive = true
    self.lifetime = 15
    self.grounded = false
    self.attracted = false
    self.attractSpeed = ATTRACT_SPEED_MIN
    self.bobTimer = math.random() * math.pi * 2
    self.bobOffset = 0
    if pickupType == "gold" or pickupType == "silver" then
        self.coinPhase = math.random() * 8.17
    end

    if pickupType == "silver" then
        self.value = 1
        self.w = 8
        self.h = 8
    end

    if pickupType == "xp" then
        self.xpMagnetDelay = XP_MAGNET_DELAY
        self.attracted = false
    end

    -- Weapon pickup extras
    if pickupType == "weapon" then
        self.gunDef = value        -- value holds the gun definition table
        self.w = 14
        self.h = 14
        self.lifetime = 30         -- weapons stay longer
    end

    return self
end

function Pickup.filter(item, other)
    if other.isWall then
        return "slide"
    end
    if other.isPlatform then
        if PlatformCollision.shouldPassThroughOneWay(item, other) then
            return nil
        end
        return "slide"
    end
    return nil
end

function Pickup:update(dt, world, playerX, playerY)
    self.lifetime = self.lifetime - dt
    if self.lifetime <= 0 then
        self.alive = false
        return
    end

    if self.pickupType == "xp" and self.xpMagnetDelay then
        self.xpMagnetDelay = self.xpMagnetDelay - dt
        if self.xpMagnetDelay <= 0 then
            self.xpMagnetDelay = nil
            self.attracted = true
            self.attractSpeed = XP_ATTRACT_SPEED_MIN
        end
    end

    if self.attracted and playerX then
        -- Accelerate toward player (XP pulls harder — infinite range via checkPickups)
        local vmax = self.pickupType == "xp" and XP_ATTRACT_SPEED_MAX or ATTRACT_SPEED_MAX
        local vmin = self.pickupType == "xp" and XP_ATTRACT_SPEED_MIN or ATTRACT_SPEED_MIN
        if self.attractSpeed < vmin then
            self.attractSpeed = vmin
        end
        self.attractSpeed = math.min(vmax, self.attractSpeed + 900 * dt)
        local cx = self.x + self.w / 2
        local cy = self.y + self.h / 2
        local dx = (playerX) - cx
        local dy = (playerY) - cy
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 1 then
            self.x = self.x + (dx / len) * self.attractSpeed * dt
            self.y = self.y + (dy / len) * self.attractSpeed * dt
            world:update(self, self.x, self.y)
        end
        self.bobOffset = 0
    elseif not self.grounded then
        self.vy = self.vy + GRAVITY * dt
        if self.vy > 400 then self.vy = 400 end

        local goalX = self.x + self.vx * dt
        local goalY = self.y + self.vy * dt
        local actualX, actualY, cols, len = world:move(self, goalX, goalY, self.filter)
        self.x = actualX
        self.y = actualY

        for i = 1, len do
            local ny = cols[i].normal.y
            if ny == -1 then
                self.grounded = true
                self.vy = 0
                self.vx = 0
            elseif math.abs(cols[i].normal.x) > 0.5 then
                self.vx = 0
            end
        end
    else
        self.bobTimer = self.bobTimer + dt * 3
        self.bobOffset = math.sin(self.bobTimer) * 2
    end
end

function Pickup:draw(player, camera, shakeX, shakeY, room)
    if player and camera then
        local cx = self.x + self.w * 0.5
        local cy = self.y + self.h * 0.5
        if not Vision.isEntityVisibleToPlayer(room, player, cx, cy, camera, shakeX, shakeY) then
            return
        end
    end
    local dy = self.bobOffset or 0
    -- XP reads full bright while homing; other pickups dim until grounded.
    local airMul = ((self.pickupType == "xp" and self.attracted) or self.grounded) and 1 or 0.55
    if self.pickupType == "xp" then
        local cx = self.x + self.w / 2
        local cy = self.y + self.h / 2 + dy
        local r1, r2 = 5, 2.2
        local rot = self.bobTimer * 0.9   -- slowly spinning
        -- Build 4-pointed star polygon
        local pts = {}
        for i = 0, 7 do
            local a = rot + i * math.pi * 0.25
            local r = (i % 2 == 0) and r1 or r2
            pts[#pts + 1] = cx + math.cos(a) * r
            pts[#pts + 1] = cy + math.sin(a) * r
        end
        -- Soft glow
        love.graphics.setColor(0.2, 0.55, 1.0, 0.32 * airMul)
        love.graphics.circle("fill", cx, cy, r1 + 4)
        -- Star body
        love.graphics.setColor(0.45, 0.78, 1.0, airMul)
        love.graphics.polygon("fill", pts)
        -- Bright centre sparkle
        love.graphics.setColor(0.9, 0.97, 1.0, 0.95 * airMul)
        love.graphics.circle("fill", cx, cy, 1.5)
    elseif self.pickupType == "gold" then
        local cx = self.x + self.w / 2
        local cy = self.y + self.h / 2 + dy
        local t = love.timer.getTime() + (self.coinPhase or 0)
        love.graphics.setColor(1, 1, 1, airMul)
        if not GoldCoin.drawAnimatedCentered(cx, cy, 14, t, { fps = 9 }) then
            love.graphics.setColor(1.0, 0.85, 0.2, airMul)
            love.graphics.circle("fill", cx, cy, 5)
        end
    elseif self.pickupType == "silver" then
        local cx = self.x + self.w / 2
        local cy = self.y + self.h / 2 + dy
        local t = love.timer.getTime() + (self.coinPhase or 0)
        local pulse = 0.85 + 0.15 * math.sin(t * 5)
        love.graphics.setColor(0.55, 0.62, 0.72, 0.35 * airMul * pulse)
        love.graphics.circle("fill", cx, cy, 6)
        love.graphics.setColor(0.78, 0.82, 0.9, airMul * pulse)
        love.graphics.circle("fill", cx, cy, 4.5)
        love.graphics.setColor(0.95, 0.97, 1.0, 0.5 * airMul)
        love.graphics.setLineWidth(1)
        love.graphics.circle("line", cx, cy, 4.5)
        love.graphics.setLineWidth(1)
    elseif self.pickupType == "health" then
        local cx = self.x + self.w / 2
        local cy = self.y + self.h / 2 + dy
        local pulse = 1 + 0.14 * math.sin(self.bobTimer * 5)
        local hw = 2.5 * pulse   -- cross arm half-width
        local hl = 5.0 * pulse   -- cross arm half-length
        -- Soft outer glow
        love.graphics.setColor(1.0, 0.1, 0.1, 0.28 * airMul)
        love.graphics.circle("fill", cx, cy, hl + 3)
        -- White border so cross pops on any background
        love.graphics.setColor(1, 1, 1, 0.55 * airMul)
        love.graphics.rectangle("fill", cx - hw - 1, cy - hl - 1, (hw + 1) * 2, (hl + 1) * 2)
        love.graphics.rectangle("fill", cx - hl - 1, cy - hw - 1, (hl + 1) * 2, (hw + 1) * 2)
        -- Red cross
        love.graphics.setColor(0.95, 0.18, 0.18, airMul)
        love.graphics.rectangle("fill", cx - hw, cy - hl, hw * 2, hl * 2)
        love.graphics.rectangle("fill", cx - hl, cy - hw, hl * 2, hw * 2)
        -- Bright centre highlight
        love.graphics.setColor(1, 0.6, 0.6, 0.7 * airMul)
        love.graphics.circle("fill", cx, cy, hw * 0.75)
    elseif self.pickupType == "weapon" and self.gunDef then
        local t = love.timer.getTime()
        local pulse = 0.7 + 0.3 * math.sin(t * 4)
        local rc = RARITY_COLORS[self.gunDef.rarity] or RARITY_COLORS.common
        local cx, cy = self.x + self.w / 2, self.y + self.h / 2 + dy
        -- Glow
        love.graphics.setColor(rc[1], rc[2], rc[3], 0.22 * pulse * airMul)
        love.graphics.circle("fill", cx, cy, 16)
        love.graphics.setColor(rc[1], rc[2], rc[3], 0.35 * pulse * airMul)
        love.graphics.circle("line", cx, cy, 16)

        -- Draw actual weapon sprite if available
        local sprite = Guns.getSprite(self.gunDef)
        if sprite then
            local sw, sh = sprite:getDimensions()
            local scale = 0.55
            love.graphics.setColor(1, 1, 1, airMul)
            love.graphics.draw(sprite, cx, cy, 0, scale, scale, sw / 2, sh / 2)
        else
            -- Fallback: colored rectangle
            love.graphics.setColor(rc[1], rc[2], rc[3], 0.9 * airMul)
            love.graphics.rectangle("fill", self.x + 1, self.y + 3 + dy, self.w - 2, self.h - 6)
        end

        -- Floating name label
        if not Pickup._weaponFont then
            Pickup._weaponFont = Font.new(8)
        end
        local prevFont = love.graphics.getFont()
        love.graphics.setFont(Pickup._weaponFont)
        local label = self.gunDef.name
        local tw = Pickup._weaponFont:getWidth(label)
        love.graphics.setColor(0, 0, 0, 0.7 * airMul)
        love.graphics.print(label, cx - tw / 2 + 1, self.y - 12 + dy + 1)
        love.graphics.setColor(rc[1], rc[2], rc[3], airMul)
        love.graphics.print(label, cx - tw / 2, self.y - 12 + dy)
        love.graphics.setFont(prevFont)
    end

    -- Flash when about to expire
    if self.lifetime < 3 and math.floor(self.lifetime * 4) % 2 == 0 then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.circle("fill", self.x + self.w/2, self.y + self.h/2 + dy, 6)
    end

    love.graphics.setColor(1, 1, 1)
end

return Pickup
