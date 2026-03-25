--- SecretEntrance: a cracked-wall visual that marks the entrance to a secret area.
--- Fades away as the player approaches, revealing the passage beyond.
--- No collision — purely decorative. Shimmers subtly to hint at its presence.

local SecretEntrance = {}
SecretEntrance.__index = SecretEntrance

-- Sprite (lazy-loaded)
local _sprite
local function getSprite()
    if not _sprite then
        _sprite = love.graphics.newImage("assets/sprites/props/secret_entrance.png")
        _sprite:setFilter("nearest", "nearest")
    end
    return _sprite
end

local REVEAL_DIST    = 90    -- px: begin fading here
local FULL_FADE_DIST = 38    -- px: fully transparent here
local RESTORE_RATE   = 0.55  -- alpha per second when player moves away

function SecretEntrance.new(x, y, w, h)
    local self      = setmetatable({}, SecretEntrance)
    self.x          = x
    self.y          = y
    self.w          = w or 14
    self.h          = h or 80
    self.alpha      = 0.90
    self.discovered = false
    return self
end

function SecretEntrance:update(dt, player)
    local px   = player.x + player.w / 2
    local py   = player.y + player.h / 2
    local cx   = self.x + self.w / 2
    local cy   = self.y + self.h / 2
    local dist = math.sqrt((px - cx)^2 + (py - cy)^2)

    if dist < REVEAL_DIST then
        self.discovered = true
        local t    = math.max(0, (dist - FULL_FADE_DIST) / (REVEAL_DIST - FULL_FADE_DIST))
        self.alpha = t * 0.90
    else
        self.alpha = math.min(0.90, self.alpha + RESTORE_RATE * dt)
    end
end

function SecretEntrance:draw()
    if self.alpha < 0.02 then return end
    local t = love.timer.getTime()
    local spr = getSprite()
    local sw, sh = spr:getDimensions()
    -- Scale to fill the entity height; center horizontally
    local scale = self.h / sh
    local drawX = self.x + (self.w - sw * scale) / 2
    local drawY = self.y

    -- Draw sprite with fade alpha
    love.graphics.setColor(1, 1, 1, self.alpha)
    love.graphics.draw(spr, drawX, drawY, 0, scale, scale)

    -- Undiscovered shimmer (gold pulse — invites curiosity)
    if not self.discovered then
        local shimmer = (math.sin(t * 2.2) * 0.5 + 0.5) * 0.22
        love.graphics.setColor(0.9, 0.78, 0.25, self.alpha * shimmer)
        love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
    end
end

return SecretEntrance
