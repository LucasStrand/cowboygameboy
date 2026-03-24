--- Slot machine: a dusty one-armed bandit found somewhere off the beaten path.
--- Costs COST gold per play. Three reels spin and stop left-to-right.
--- Results range from gold jackpots to taking a bullet.
---
--- Callbacks (set by game.lua wireRoomEntities):
---   onResult(rtype, value)
---     rtype: "gold" | "xp" | "health" | "damage" | "weapon"
---     value: number (gold/xp/hp/damage amount) or gun table (weapon)

local Guns = require("src.data.guns")

local SlotMachine = {}
SlotMachine.__index = SlotMachine

local COST      = 15
local W, H      = 48, 72

-- Reel window geometry
local REEL_W    = 12
local REEL_H    = 20
local REEL_GAP  = 2
local REEL_Y    = 14   -- from machine top

-- How fast symbols cycle during spin (indices per second)
local SPIN_SPEED = 16

-- When each reel stops (seconds after spin start)
local STOP_T = { 0.80, 1.25, 1.70 }

-- How long to display the result before returning to idle
local RESULT_TIME = 2.0

---------------------------------------------------------------------------
-- Symbols
---------------------------------------------------------------------------
local SYM = { COIN=1, STAR=2, GEM=3, BEER=4, SKULL=5, BAR=6 }
local SYM_COUNT = 6

--- Draw a single symbol centered at (cx, cy), fitting in a ~sz×sz box.
local function drawSym(sym, cx, cy, sz)
    sz = sz or 8
    if sym == SYM.COIN then
        love.graphics.setColor(0.95, 0.80, 0.18)
        love.graphics.circle("fill", cx, cy, sz * 0.52)
        love.graphics.setColor(0.70, 0.55, 0.08)
        love.graphics.circle("line", cx, cy, sz * 0.52)
        love.graphics.setColor(0.78, 0.62, 0.10)
        love.graphics.circle("line", cx, cy, sz * 0.28)

    elseif sym == SYM.STAR then
        love.graphics.setColor(0.98, 0.85, 0.10)
        local verts = {}
        local ro, ri = sz * 0.56, sz * 0.22
        for i = 0, 9 do
            local a = i * math.pi / 5 - math.pi / 2
            local r = (i % 2 == 0) and ro or ri
            verts[#verts+1] = cx + math.cos(a) * r
            verts[#verts+1] = cy + math.sin(a) * r
        end
        love.graphics.polygon("fill", verts)

    elseif sym == SYM.GEM then
        love.graphics.setColor(0.20, 0.82, 0.95)
        local s = sz * 0.52
        love.graphics.polygon("fill", cx, cy-s, cx+s, cy, cx, cy+s, cx-s, cy)
        -- Highlight facet
        love.graphics.setColor(0.65, 0.97, 1.0, 0.75)
        love.graphics.polygon("fill", cx, cy-s, cx+s, cy, cx, cy-s*0.15)

    elseif sym == SYM.BEER then
        -- Mug body
        love.graphics.setColor(0.88, 0.56, 0.08)
        love.graphics.rectangle("fill", cx - sz*0.38, cy - sz*0.44, sz*0.76, sz*1.0, 1)
        -- Foam head
        love.graphics.setColor(0.96, 0.94, 0.88)
        love.graphics.rectangle("fill", cx - sz*0.40, cy - sz*0.60, sz*0.80, sz*0.26, 2)

    elseif sym == SYM.SKULL then
        -- Cranium
        love.graphics.setColor(0.92, 0.90, 0.84)
        love.graphics.circle("fill", cx, cy - sz*0.08, sz*0.46)
        -- Jaw
        love.graphics.rectangle("fill", cx - sz*0.30, cy + sz*0.22, sz*0.60, sz*0.34, 1)
        -- Eye sockets
        love.graphics.setColor(0.10, 0.08, 0.06)
        love.graphics.circle("fill", cx - sz*0.16, cy - sz*0.08, sz*0.13)
        love.graphics.circle("fill", cx + sz*0.16, cy - sz*0.08, sz*0.13)

    elseif sym == SYM.BAR then
        -- Three horizontal bars (classic slot "BAR" symbol)
        love.graphics.setColor(0.92, 0.18, 0.12)
        love.graphics.rectangle("fill", cx - sz*0.52, cy - sz*0.50, sz*1.04, sz*0.24, 1)
        love.graphics.setColor(0.95, 0.22, 0.14)
        love.graphics.rectangle("fill", cx - sz*0.52, cy - sz*0.12, sz*1.04, sz*0.24, 1)
        love.graphics.setColor(0.90, 0.16, 0.10)
        love.graphics.rectangle("fill", cx - sz*0.52, cy + sz*0.26,  sz*1.04, sz*0.24, 1)
    end
end

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------

function SlotMachine.new(x, y)
    local self     = setmetatable({}, SlotMachine)
    self.x         = x
    self.y         = y
    self.w         = W
    self.h         = H
    self.state     = "idle"    -- idle | spinning | result
    self.timer     = 0
    -- Each reel: pos (displayed symbol 1-6), target (what it lands on), offset (scroll progress)
    self.reels = {
        { pos = math.random(SYM_COUNT), target = 1, offset = 0, stopped = true },
        { pos = math.random(SYM_COUNT), target = 1, offset = 0, stopped = true },
        { pos = math.random(SYM_COUNT), target = 1, offset = 0, stopped = true },
    }
    self.resultMsg   = nil
    self.resultGood  = true
    self.flashTimer  = 0
    self.leverAngle  = 0    -- 0=up, 1=fully pulled down
    self.onResult    = nil  -- fn(rtype, value) — set by wireRoomEntities
    return self
end

---------------------------------------------------------------------------
-- Interaction
---------------------------------------------------------------------------

function SlotMachine:isNearPlayer(px, py)
    local cx = self.x + W * 0.5
    local cy = self.y + H * 0.5
    return (px - cx)^2 + (py - cy)^2 < 62 * 62
end

--- Called when player presses E nearby. Returns true if input consumed.
function SlotMachine:tryPlay(player)
    if self.state ~= "idle" then return false end
    if player.gold < COST then
        self.resultMsg  = "Need " .. COST .. "g!"
        self.resultGood = false
        self.state      = "result"
        self.timer      = 0
        return true
    end
    player.gold   = player.gold - COST
    self.state    = "spinning"
    self.timer    = 0
    self.leverAngle = 1.0   -- pull down
    for _, r in ipairs(self.reels) do
        r.target  = math.random(SYM_COUNT)
        r.stopped = false
        r.offset  = 0
    end
    return true
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

function SlotMachine:update(dt)
    self.flashTimer = math.max(0, self.flashTimer - dt)

    if self.state == "idle" then
        return

    elseif self.state == "spinning" then
        self.timer = self.timer + dt
        self.leverAngle = math.max(0, self.leverAngle - dt * 2.5)

        for i, r in ipairs(self.reels) do
            if not r.stopped then
                r.offset = r.offset + SPIN_SPEED * dt
                if self.timer >= STOP_T[i] then
                    r.stopped = true
                    r.pos     = r.target
                    r.offset  = 0
                end
            end
        end

        if self.reels[3].stopped then
            self.state = "result"
            self.timer = 0
            self:_computeResult()
        end

    elseif self.state == "result" then
        self.timer = self.timer + dt
        if self.timer >= RESULT_TIME then
            self.state     = "idle"
            self.resultMsg = nil
            self.timer     = 0
        end
    end
end

---------------------------------------------------------------------------
-- Result logic
---------------------------------------------------------------------------

function SlotMachine:_computeResult()
    local s1, s2, s3 = self.reels[1].target, self.reels[2].target, self.reels[3].target
    local skulls = (s1==SYM.SKULL and 1 or 0)
                 + (s2==SYM.SKULL and 1 or 0)
                 + (s3==SYM.SKULL and 1 or 0)

    -- Triple match
    if s1 == s2 and s2 == s3 then
        local sym = s1
        if sym == SYM.BAR then
            self.resultMsg  = "JACKPOT!  +80g"
            self.resultGood = true
            self.flashTimer = RESULT_TIME
            if self.onResult then self.onResult("gold", 80) end
        elseif sym == SYM.COIN then
            self.resultMsg  = "Triple coin!  +45g"
            self.resultGood = true
            if self.onResult then self.onResult("gold", 45) end
        elseif sym == SYM.STAR then
            self.resultMsg  = "Lucky star!  Weapon!"
            self.resultGood = true
            self.flashTimer = RESULT_TIME * 0.6
            local gun = Guns.rollDrop(1)  -- at least uncommon rarity
            if gun and self.onResult then self.onResult("weapon", gun) end
        elseif sym == SYM.GEM then
            self.resultMsg  = "Shiny!  +40 XP"
            self.resultGood = true
            if self.onResult then self.onResult("xp", 40) end
        elseif sym == SYM.BEER then
            self.resultMsg  = "Cheers!  +30 HP"
            self.resultGood = true
            if self.onResult then self.onResult("health", 30) end
        elseif sym == SYM.SKULL then
            self.resultMsg  = "Dead man's hand..."
            self.resultGood = false
            if self.onResult then self.onResult("damage", 28) end
        end
        return
    end

    -- Any skulls (but not triple skull, handled above)
    if skulls > 0 then
        local dmg = skulls == 2 and 18 or 8
        self.resultMsg  = skulls == 2 and "Two skulls! -"..dmg.."hp" or "Skull! -"..dmg.."hp"
        self.resultGood = false
        if self.onResult then self.onResult("damage", dmg) end
        return
    end

    -- Two matching (no skulls)
    local match = nil
    if s1 == s2 then match = s1
    elseif s1 == s3 then match = s1
    elseif s2 == s3 then match = s2
    end
    if match then
        if match == SYM.BAR then
            self.resultMsg  = "Pair bars!  +25g"
            self.resultGood = true
            if self.onResult then self.onResult("gold", 25) end
        elseif match == SYM.COIN then
            self.resultMsg  = "Pair coins!  +20g"
            self.resultGood = true
            if self.onResult then self.onResult("gold", 20) end
        elseif match == SYM.STAR then
            self.resultMsg  = "Pair stars!  +15g"
            self.resultGood = true
            if self.onResult then self.onResult("gold", 15) end
        elseif match == SYM.GEM then
            self.resultMsg  = "Pair gems!  +15 XP"
            self.resultGood = true
            if self.onResult then self.onResult("xp", 15) end
        elseif match == SYM.BEER then
            self.resultMsg  = "Pair beers!  +10 HP"
            self.resultGood = true
            if self.onResult then self.onResult("health", 10) end
        end
        return
    end

    -- No match, no skulls: consolation prize
    self.resultMsg  = "No luck...  +5g"
    self.resultGood = false
    if self.onResult then self.onResult("gold", 5) end
end

---------------------------------------------------------------------------
-- Draw
---------------------------------------------------------------------------

function SlotMachine:draw(showHint)
    local x, y = self.x, self.y
    local t     = love.timer.getTime()

    -- Jackpot flash overlay
    local flash = self.flashTimer > 0 and (math.sin(t * 20) * 0.5 + 0.5) or 0

    -- Cabinet body
    love.graphics.setColor(0.50, 0.18, 0.15)
    love.graphics.rectangle("fill", x, y + 6, W, H - 6, 3)
    -- Recessed panel
    love.graphics.setColor(0.34, 0.12, 0.10)
    love.graphics.rectangle("fill", x + 5, y + 18, W - 10, H - 30, 2)

    -- Chrome top header
    love.graphics.setColor(0.68, 0.63, 0.48)
    love.graphics.rectangle("fill", x + 2, y, W - 4, 12, 2)
    -- Header text
    love.graphics.setColor(0.18, 0.10, 0.08)
    love.graphics.printf("SLOTS", x, y + 1, W, "center")
    -- Jackpot header glow
    if flash > 0 then
        love.graphics.setColor(0.98, 0.82, 0.12, flash * 0.75)
        love.graphics.rectangle("fill", x + 2, y, W - 4, 12, 2)
    end

    -- Coin slot
    love.graphics.setColor(0.22, 0.16, 0.12)
    love.graphics.rectangle("fill", x + W/2 - 5, y + 11, 10, 3, 1)

    -- Reel windows
    local reelStartX = x + math.floor((W - (3*REEL_W + 2*REEL_GAP)) / 2)
    local reelY      = y + REEL_Y
    for i, r in ipairs(self.reels) do
        local rx = reelStartX + (i-1) * (REEL_W + REEL_GAP)
        -- Window background
        love.graphics.setColor(0.08, 0.06, 0.04)
        love.graphics.rectangle("fill", rx, reelY, REEL_W, REEL_H, 1)
        -- Symbol
        local sym
        if r.stopped then
            sym = r.pos
        else
            sym = math.floor(r.offset) % SYM_COUNT + 1
        end
        local cx = rx + REEL_W * 0.5
        local cy = reelY + REEL_H * 0.5
        drawSym(sym, cx, cy, 6)
        -- Blur during spin
        if not r.stopped then
            love.graphics.setColor(0.06, 0.04, 0.03, 0.5)
            love.graphics.rectangle("fill", rx, reelY, REEL_W, REEL_H, 1)
        end
        -- Window chrome frame
        love.graphics.setColor(0.55, 0.50, 0.36)
        love.graphics.rectangle("line", rx, reelY, REEL_W, REEL_H, 1)
    end

    -- Lever (right side)
    local leverBaseX = x + W - 4
    local leverBaseY = y + 26
    local leverTipY  = leverBaseY - 16 + math.floor(self.leverAngle * 16)
    love.graphics.setColor(0.62, 0.57, 0.42)
    love.graphics.setLineWidth(3)
    love.graphics.line(leverBaseX, leverBaseY, leverBaseX, leverTipY)
    love.graphics.setLineWidth(1)
    -- Lever knob (ball)
    love.graphics.setColor(0.80, 0.18, 0.12)
    love.graphics.circle("fill", leverBaseX, leverTipY, 4)
    love.graphics.setColor(1.0, 0.40, 0.35)
    love.graphics.circle("fill", leverBaseX - 1, leverTipY - 1, 2)

    -- Bottom feet/base
    love.graphics.setColor(0.30, 0.10, 0.08)
    love.graphics.rectangle("fill", x + 4, y + H - 6, W - 8, 6, 1)

    -- Result message (floats above machine)
    if self.resultMsg then
        local c = self.resultGood and {1.0, 0.88, 0.20, 0.95} or {1.0, 0.28, 0.18, 0.95}
        love.graphics.setColor(c[1], c[2], c[3], c[4])
        love.graphics.printf(self.resultMsg, x - 24, y - 20, W + 48, "center")
    end

    -- Interaction hint
    if showHint and self.state == "idle" then
        love.graphics.setColor(1, 0.92, 0.30, 0.9)
        love.graphics.printf("[E] Play  " .. COST .. "g", x - 18, y - 16, W + 36, "center")
    end
end

return SlotMachine
