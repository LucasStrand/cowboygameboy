--- Slot machine: a dusty one-armed bandit found somewhere off the beaten path.
--- Costs COST gold per play. Three reels spin and stop left-to-right.
--- Results range from gold jackpots to taking a bullet.
---
--- Visual: fullscreen overlay identical to the saloon Slots when active.
--- Behavior: old wild-slot behavior (flat cost, gold/xp/health/damage/weapon rewards,
---           auto-dismisses after RESULT_TIME — no betting UI).
---
--- Callbacks (set by game.lua wireRoomEntities):
---   onResult(rtype, value)
---     rtype: "gold" | "xp" | "health" | "damage" | "weapon"
---     value: number or gun table

local Guns = require("src.data.guns")
local Font = require("src.ui.font")

local SlotMachine = {}
SlotMachine.__index = SlotMachine

local COST        = 15
-- Sprite drawn at the same scale the saloon uses (0.195 on an 86×229 source quad)
local DRAW_SCALE  = 0.195
local W           = math.floor(86  * DRAW_SCALE + 0.5)   -- ~17
local H           = math.floor(229 * DRAW_SCALE + 0.5)   -- ~45
local SPIN_SPEED  = 14          -- symbol indices / second
local STOP_T      = { 0.80, 1.25, 1.70 }
local RESULT_TIME = 2.5

---------------------------------------------------------------------------
-- Symbols — 7 entries matching slot.png (same as saloon Slots)
---------------------------------------------------------------------------
local NUM_SYM = 7
local SYM = { SEVEN=1, BAR=2, BELL=3, CHERRY=4, GRAPE=5, LEMON=6, MELON=7 }

local TEX_W, TEX_H = 256, 256
local SYMBOL_QUADS_DEF = {
    { x = 3,  y = 3,   w = 26, h = 26 }, -- 1: 7
    { x = 2,  y = 41,  w = 28, h = 14 }, -- 2: BAR
    { x = 2,  y = 66,  w = 28, h = 28 }, -- 3: BELL
    { x = 3,  y = 99,  w = 23, h = 27 }, -- 4: CHERRY
    { x = 3,  y = 131, w = 26, h = 27 }, -- 5: GRAPE
    { x = 2,  y = 164, w = 28, h = 25 }, -- 6: LEMON
    { x = 3,  y = 195, w = 26, h = 27 }, -- 7: MELON
}
local SYMBOL_NAMES = { "7", "BAR", "BELL", "CHERRY", "GRAPE", "LEMON", "MELON" }

-- Machine body in slot.png — same quad the saloon uses (saloon.lua line ~539)
local MACH_SX, MACH_SY = 86, 27
local MACH_SW, MACH_SH = 86, 229

---------------------------------------------------------------------------
-- Assets
---------------------------------------------------------------------------
local _sheet    = nil
local _symQuads = {}
local _machQuad = nil
local _fonts    = nil

local function ensureAssets()
    if _sheet then return end
    local ok, img = pcall(love.graphics.newImage, "assets/slot.png")
    if ok then
        img:setFilter("nearest", "nearest")
        _sheet = img
        for i, def in ipairs(SYMBOL_QUADS_DEF) do
            _symQuads[i] = love.graphics.newQuad(def.x, def.y, def.w, def.h, TEX_W, TEX_H)
        end
        _machQuad = love.graphics.newQuad(MACH_SX, MACH_SY, MACH_SW, MACH_SH, TEX_W, TEX_H)
    end
    _fonts = {
        title = Font.new(24),
        body  = Font.new(14),
        small = Font.new(12),
    }
end

local function wrapSym(i)
    i = math.floor(i)
    while i < 1 do i = i + NUM_SYM end
    while i > NUM_SYM do i = i - NUM_SYM end
    return i
end

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------
function SlotMachine.new(x, y)
    local self         = setmetatable({}, SlotMachine)
    self.x             = x
    self.y             = y
    self.w             = W
    self.h             = H
    self.state         = "idle"
    self.timer         = 0
    self.reels = {
        { pos = math.random(NUM_SYM), target = 1, offset = 0, stopped = true },
        { pos = math.random(NUM_SYM), target = 1, offset = 0, stopped = true },
        { pos = math.random(NUM_SYM), target = 1, offset = 0, stopped = true },
    }
    self.reelStopFlash = { 0, 0, 0 }
    self.resultMsg     = nil
    self.resultIsWin   = false
    self.winGlow       = 0
    self.flashTimer    = 0
    self.onResult      = nil
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

function SlotMachine:tryPlay(player)
    if self.state ~= "idle" then return false end
    if player.gold < COST then
        self.resultMsg   = "Need " .. COST .. "g!"
        self.resultIsWin = false
        self.state       = "result"
        self.timer       = 0
        return true
    end
    player.gold        = player.gold - COST
    self.state         = "spinning"
    self.timer         = 0
    self.reelStopFlash = { 0, 0, 0 }
    self.winGlow       = 0
    for _, r in ipairs(self.reels) do
        r.target  = math.random(NUM_SYM)
        r.stopped = false
        r.offset  = r.pos - 1
    end
    return true
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------
function SlotMachine:update(dt)
    self.flashTimer = math.max(0, self.flashTimer - dt)
    for i = 1, 3 do
        if self.reelStopFlash[i] > 0 then
            self.reelStopFlash[i] = math.max(0, self.reelStopFlash[i] - dt * 3)
        end
    end

    if self.state == "idle" then
        return

    elseif self.state == "spinning" then
        self.timer = self.timer + dt
        for i, r in ipairs(self.reels) do
            if not r.stopped then
                r.offset = r.offset + SPIN_SPEED * dt
                if self.timer >= STOP_T[i] then
                    r.stopped           = true
                    r.pos               = r.target
                    r.offset            = r.target - 1
                    self.reelStopFlash[i] = 1.0
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
        if self.resultIsWin then
            self.winGlow = self.winGlow + dt * 5
        end
        if self.timer >= RESULT_TIME then
            self.state       = "idle"
            self.resultMsg   = nil
            self.resultIsWin = false
            self.winGlow     = 0
            self.timer       = 0
        end
    end
end

---------------------------------------------------------------------------
-- Result logic (original wild-slot behavior)
---------------------------------------------------------------------------
function SlotMachine:_computeResult()
    local s1, s2, s3 = self.reels[1].target, self.reels[2].target, self.reels[3].target
    local melons = ((s1==SYM.MELON) and 1 or 0)
                 + ((s2==SYM.MELON) and 1 or 0)
                 + ((s3==SYM.MELON) and 1 or 0)

    if s1 == s2 and s2 == s3 then
        self.resultIsWin = (s1 ~= SYM.MELON)
        if s1 == SYM.SEVEN then
            self.resultMsg  = "JACKPOT!  +80g"
            self.flashTimer = RESULT_TIME
            if self.onResult then self.onResult("gold", 80) end
        elseif s1 == SYM.BAR then
            self.resultMsg = "Triple BAR!  +45g"
            if self.onResult then self.onResult("gold", 45) end
        elseif s1 == SYM.BELL then
            self.resultMsg = "Lucky Bells!  Weapon!"
            self.flashTimer = RESULT_TIME * 0.6
            local gun = Guns.rollDrop(1)
            if gun and self.onResult then self.onResult("weapon", gun) end
        elseif s1 == SYM.CHERRY then
            self.resultMsg = "Cherries!  +40 XP"
            if self.onResult then self.onResult("xp", 40) end
        elseif s1 == SYM.GRAPE then
            self.resultMsg = "Grapes!  +30 HP"
            if self.onResult then self.onResult("health", 30) end
        elseif s1 == SYM.LEMON then
            self.resultMsg   = "Lemons...  +5g"
            self.resultIsWin = false
            if self.onResult then self.onResult("gold", 5) end
        elseif s1 == SYM.MELON then
            self.resultMsg = "Dead man's hand..."
            if self.onResult then self.onResult("damage", 28) end
        end
        return
    end

    if melons > 0 then
        local dmg = melons == 2 and 18 or 8
        self.resultMsg   = melons == 2 and "Two melons!  -"..dmg.."hp" or "Melon!  -"..dmg.."hp"
        self.resultIsWin = false
        if self.onResult then self.onResult("damage", dmg) end
        return
    end

    local match = nil
    if s1 == s2 then match = s1
    elseif s1 == s3 then match = s1
    elseif s2 == s3 then match = s2
    end
    if match then
        self.resultIsWin = true
        if match == SYM.SEVEN then
            self.resultMsg = "Pair 7s!  +30g"
            if self.onResult then self.onResult("gold", 30) end
        elseif match == SYM.BAR then
            self.resultMsg = "Pair BARs!  +25g"
            if self.onResult then self.onResult("gold", 25) end
        elseif match == SYM.BELL then
            self.resultMsg = "Pair bells!  +20g"
            if self.onResult then self.onResult("gold", 20) end
        elseif match == SYM.CHERRY then
            self.resultMsg = "Pair cherries!  +15 XP"
            if self.onResult then self.onResult("xp", 15) end
        elseif match == SYM.GRAPE then
            self.resultMsg = "Pair grapes!  +10 HP"
            if self.onResult then self.onResult("health", 10) end
        elseif match == SYM.LEMON then
            self.resultMsg = "Pair lemons!  +8g"
            if self.onResult then self.onResult("gold", 8) end
        end
        return
    end

    self.resultMsg   = "No luck...  +5g"
    self.resultIsWin = false
    if self.onResult then self.onResult("gold", 5) end
end

---------------------------------------------------------------------------
-- Compact reel panel — saloon visual style, positioned above the machine
---------------------------------------------------------------------------
-- 3 reels × 3 symbols each, same dark-wood frame + gold trim as saloon
local CELL_H    = 22
local REEL_W    = 32
local REEL_H    = CELL_H * 3
local REEL_GAP  = math.floor(REEL_W * 0.03 + 2)   -- same proportion as saloon
local FRAME_PAD = 14

local PANEL_REEL_AREA_W = 3 * REEL_W + 2 * REEL_GAP
local PANEL_W = PANEL_REEL_AREA_W + FRAME_PAD * 2
local PANEL_H = REEL_H + FRAME_PAD * 2

-- screenCX, screenCY: the machine center in screen/canvas coordinates
local function drawReelPanel(sm, screenCX, screenCY)
    if not _sheet then return end

    local px = screenCX - PANEL_W * 0.5
    local py = screenCY - PANEL_H - 10

    local reelX = px + FRAME_PAD
    local reelY = py + FRAME_PAD

    -- === FRAME (identical style to saloon) ===
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", px + 4, py + 4, PANEL_W, PANEL_H, 10, 10)
    love.graphics.setColor(0.18, 0.12, 0.07)
    love.graphics.rectangle("fill", px, py, PANEL_W, PANEL_H, 8, 8)
    love.graphics.setColor(0.28, 0.18, 0.1)
    love.graphics.rectangle("fill", px + 4, py + 4, PANEL_W - 8, PANEL_H - 8, 6, 6)
    love.graphics.setColor(0.75, 0.58, 0.18, 0.8)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", px, py, PANEL_W, PANEL_H, 8, 8)
    love.graphics.setColor(0.55, 0.42, 0.14, 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", px + 6, py + 6, PANEL_W - 12, PANEL_H - 12, 4, 4)

    -- === REELS (identical logic to saloon) ===
    for col = 0, 2 do
        local rx   = reelX + col * (REEL_W + REEL_GAP)
        local ry   = reelY
        local reel = sm.reels[col + 1]

        local scroll
        if reel.stopped then
            scroll = reel.pos - 1
        else
            scroll = reel.offset % NUM_SYM
        end

        love.graphics.setColor(0.08, 0.06, 0.04)
        love.graphics.rectangle("fill", rx, ry, REEL_W, REEL_H, 4, 4)
        love.graphics.setColor(0.12, 0.1, 0.08)
        love.graphics.rectangle("fill", rx + 2, ry + 2, REEL_W - 4, REEL_H - 4, 3, 3)

        love.graphics.setScissor(rx, ry, REEL_W, REEL_H)

        local frac      = scroll % 1
        local i0        = math.floor(scroll) % NUM_SYM
        local symPadX   = REEL_W * 0.08
        local symPadY   = CELL_H * 0.08
        local symAreaW  = REEL_W - symPadX * 2
        local symAreaH  = CELL_H - symPadY * 2

        for k = -1, 2 do
            local sym = wrapSym(i0 + k + 1)
            local def = SYMBOL_QUADS_DEF[sym]
            local symScale = math.min(symAreaW / def.w, symAreaH / def.h)
            local dw = def.w * symScale
            local dh = def.h * symScale
            local dx = rx + (REEL_W - dw) * 0.5
            local dy = ry + (k - frac) * CELL_H + (CELL_H - dh) * 0.5 + CELL_H

            if k == 0 then
                love.graphics.setColor(1, 1, 1)
            else
                love.graphics.setColor(0.5, 0.5, 0.5, 0.6)
            end
            love.graphics.draw(_sheet, _symQuads[sym], dx, dy, 0, symScale, symScale)
        end

        love.graphics.setScissor()

        -- Stop flash
        if sm.reelStopFlash[col + 1] > 0 then
            love.graphics.setColor(1, 1, 1, sm.reelStopFlash[col + 1] * 0.25)
            love.graphics.rectangle("fill", rx, ry, REEL_W, REEL_H, 4, 4)
        end

        -- Reel border
        love.graphics.setColor(0.5, 0.38, 0.15, 0.7)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", rx, ry, REEL_W, REEL_H, 4, 4)
        love.graphics.setLineWidth(1)

        -- Win glow
        if sm.resultIsWin and sm.state == "result" then
            local glow = 0.1 + 0.08 * math.sin(sm.winGlow)
            love.graphics.setColor(1, 0.85, 0.2, glow)
            love.graphics.rectangle("fill", rx, ry, REEL_W, REEL_H, 4, 4)
        end
    end

    -- === PAYLINE (identical to saloon) ===
    local paylineY     = reelY + REEL_H * 0.5
    local paylineLeft  = reelX - 8
    local paylineRight = reelX + PANEL_REEL_AREA_W + 8
    local t = love.timer.getTime()
    local paylineAlpha = 0.4
    if sm.state == "spinning" then
        paylineAlpha = 0.2 + 0.15 * math.sin(t * 8)
    elseif sm.resultIsWin and sm.state == "result" then
        paylineAlpha = 0.5 + 0.3 * math.sin(sm.winGlow)
    end
    love.graphics.setColor(1, 0.85, 0.2, paylineAlpha * 0.5)
    love.graphics.rectangle("fill", paylineLeft, paylineY - 3, paylineRight - paylineLeft, 6)
    love.graphics.setColor(1, 0.85, 0.2, paylineAlpha)
    love.graphics.setLineWidth(2)
    love.graphics.line(paylineLeft, paylineY, paylineRight, paylineY)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 0.85, 0.2, paylineAlpha + 0.2)
    love.graphics.polygon("fill", paylineLeft,  paylineY, paylineLeft+8,  paylineY-5, paylineLeft+8,  paylineY+5)
    love.graphics.polygon("fill", paylineRight, paylineY, paylineRight-8, paylineY-5, paylineRight-8, paylineY+5)

    -- === RESULT / SPINNING MESSAGE above panel ===
    local msgY = py - 18
    if sm.state == "result" and sm.resultMsg then
        if sm.resultIsWin then
            local pulse = 0.8 + 0.2 * math.sin(t * 4)
            love.graphics.setColor(0.2 * pulse, 1 * pulse, 0.2 * pulse)
        else
            love.graphics.setColor(1, 0.92, 0.35)
        end
        love.graphics.printf(sm.resultMsg, px - 20, msgY, PANEL_W + 40, "center")
    elseif sm.state == "spinning" then
        love.graphics.setColor(1, 0.9, 0.4, 0.7)
        love.graphics.printf("SPINNING...", px, msgY, PANEL_W, "center")
    end
end

---------------------------------------------------------------------------
-- Draw
---------------------------------------------------------------------------
function SlotMachine:draw(showHint)
    ensureAssets()
    local x, y = self.x, self.y

    -- World-space: machine body sprite
    if _sheet and _machQuad then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(_sheet, _machQuad, x, y, 0, DRAW_SCALE, DRAW_SCALE)
    else
        love.graphics.setColor(0.40, 0.15, 0.10)
        love.graphics.rectangle("fill", x, y, W, H, 3)
        love.graphics.setColor(0.60, 0.45, 0.20)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, W, H, 3)
        love.graphics.setLineWidth(1)
    end

    -- World-space hint when idle
    if showHint and self.state == "idle" then
        love.graphics.setColor(1, 0.92, 0.30, 0.9)
        love.graphics.printf("[E] Play  " .. COST .. "g", x - 18, y - 16, W + 36, "center")
    end

    -- Reel panel: transform machine position to screen coords, then draw
    -- in screen space so setScissor and all sizing works correctly
    if self.state == "spinning" or self.state == "result" then
        local screenCX, screenCY = love.graphics.transformPoint(self.x + W * 0.5, self.y)
        love.graphics.push()
        love.graphics.origin()
        drawReelPanel(self, screenCX, screenCY)
        love.graphics.pop()
    end
end

return SlotMachine
