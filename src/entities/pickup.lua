local PlatformCollision = require("src.systems.platform_collision")
local Font = require("src.ui.font")
local Guns = require("src.data.guns")

-- Coin sprite (lazy-loaded from HUD sprite sheet)
local coinSheet, coinQuad

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

    if self.attracted and playerX then
        -- Accelerate toward player
        self.attractSpeed = math.min(ATTRACT_SPEED_MAX, self.attractSpeed + 900 * dt)
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

        local goalY = self.y + self.vy * dt
        local actualX, actualY, cols, len = world:move(self, self.x, goalY, self.filter)
        self.x = actualX
        self.y = actualY

        for i = 1, len do
            if cols[i].normal.y == -1 then
                self.grounded = true
                self.vy = 0
            end
        end
    else
        self.bobTimer = self.bobTimer + dt * 3
        self.bobOffset = math.sin(self.bobTimer) * 2
    end
end

function Pickup:draw()
    local dy = self.bobOffset or 0
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
        love.graphics.setColor(0.2, 0.55, 1.0, 0.32)
        love.graphics.circle("fill", cx, cy, r1 + 4)
        -- Star body
        love.graphics.setColor(0.45, 0.78, 1.0)
        love.graphics.polygon("fill", pts)
        -- Bright centre sparkle
        love.graphics.setColor(0.9, 0.97, 1.0, 0.95)
        love.graphics.circle("fill", cx, cy, 1.5)
    elseif self.pickupType == "gold" then
        if not coinSheet then
            local ok, img = pcall(love.graphics.newImage, "assets/ui/western_cowboy_roguelike_hud_sprite_sheet.png")
            if ok then
                img:setFilter("nearest", "nearest")
                coinSheet = img
                local sw, sh = coinSheet:getDimensions()
                coinQuad = love.graphics.newQuad(80, 508, 64, 64, sw, sh)
            end
        end
        local cx = self.x + self.w / 2
        local cy = self.y + self.h / 2 + dy
        if coinSheet and coinQuad then
            local scale = 0.22   -- 64 × 0.22 ≈ 14 px
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(coinSheet, coinQuad, cx, cy, 0, scale, scale, 32, 32)
        else
            love.graphics.setColor(1.0, 0.85, 0.2)
            love.graphics.circle("fill", cx, cy, 5)
        end
    elseif self.pickupType == "health" then
        local cx = self.x + self.w / 2
        local cy = self.y + self.h / 2 + dy
        local pulse = 1 + 0.14 * math.sin(self.bobTimer * 5)
        local hw = 2.5 * pulse   -- cross arm half-width
        local hl = 5.0 * pulse   -- cross arm half-length
        -- Soft outer glow
        love.graphics.setColor(1.0, 0.1, 0.1, 0.28)
        love.graphics.circle("fill", cx, cy, hl + 3)
        -- White border so cross pops on any background
        love.graphics.setColor(1, 1, 1, 0.55)
        love.graphics.rectangle("fill", cx - hw - 1, cy - hl - 1, (hw + 1) * 2, (hl + 1) * 2)
        love.graphics.rectangle("fill", cx - hl - 1, cy - hw - 1, (hl + 1) * 2, (hw + 1) * 2)
        -- Red cross
        love.graphics.setColor(0.95, 0.18, 0.18)
        love.graphics.rectangle("fill", cx - hw, cy - hl, hw * 2, hl * 2)
        love.graphics.rectangle("fill", cx - hl, cy - hw, hl * 2, hw * 2)
        -- Bright centre highlight
        love.graphics.setColor(1, 0.6, 0.6, 0.7)
        love.graphics.circle("fill", cx, cy, hw * 0.75)
    elseif self.pickupType == "weapon" and self.gunDef then
        local t = love.timer.getTime()
        local pulse = 0.7 + 0.3 * math.sin(t * 4)
        local rc = RARITY_COLORS[self.gunDef.rarity] or RARITY_COLORS.common
        local cx, cy = self.x + self.w / 2, self.y + self.h / 2 + dy

        -- Glow
        love.graphics.setColor(rc[1], rc[2], rc[3], 0.22 * pulse)
        love.graphics.circle("fill", cx, cy, 16)
        love.graphics.setColor(rc[1], rc[2], rc[3], 0.35 * pulse)
        love.graphics.circle("line", cx, cy, 16)

        -- Draw actual weapon sprite if available
        local sprite = Guns.getSprite(self.gunDef)
        if sprite then
            local sw, sh = sprite:getDimensions()
            local scale = 0.55
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(sprite, cx, cy, 0, scale, scale, sw / 2, sh / 2)
        else
            -- Fallback: colored rectangle
            love.graphics.setColor(rc[1], rc[2], rc[3], 0.9)
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
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.print(label, cx - tw / 2 + 1, self.y - 12 + dy + 1)
        love.graphics.setColor(rc[1], rc[2], rc[3], 1)
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
