--- SecretEntrance: a cracked-wall visual that marks the entrance to a secret area.
--- Fades away as the player approaches, revealing the passage beyond.
--- No collision — purely decorative. Shimmers subtly to hint at its presence.

local SecretEntrance = {}
SecretEntrance.__index = SecretEntrance

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

    -- Stone slab
    love.graphics.setColor(0.36, 0.30, 0.24, self.alpha)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)

    -- Horizontal mortar lines
    love.graphics.setColor(0.20, 0.16, 0.12, self.alpha * 0.7)
    local bands = 4
    for i = 1, bands - 1 do
        local by = self.y + (self.h / bands) * i
        love.graphics.line(self.x, by, self.x + self.w, by)
    end

    -- Vertical crack
    love.graphics.setColor(0.14, 0.10, 0.08, self.alpha * 0.9)
    love.graphics.setLineWidth(1)
    local mx = self.x + self.w * 0.5
    love.graphics.line(
        mx - 1, self.y + 5,
        mx + 2, self.y + self.h * 0.35,
        mx - 2, self.y + self.h * 0.65,
        mx + 1, self.y + self.h - 5)
    love.graphics.line(
        mx + 2, self.y + self.h * 0.35,
        mx + 5, self.y + self.h * 0.52)
    love.graphics.setLineWidth(1)

    -- Undiscovered shimmer (gold pulse — invites curiosity)
    if not self.discovered then
        local shimmer = (math.sin(t * 2.2) * 0.5 + 0.5) * 0.22
        love.graphics.setColor(0.9, 0.78, 0.25, self.alpha * shimmer)
        love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
    end
end

return SecretEntrance
