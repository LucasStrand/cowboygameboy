local Sfx = require("src.systems.sfx")
local CasinoFx = require("src.ui.casino_fx")
local GameRng = require("src.systems.game_rng")

local Slots = {}
Slots.__index = Slots

local MIN_BET = 5
local BET_STEP = 5
local MAX_BET = 25

-- Texture layout (assets/slot.png is 256x256)
local TEX_W, TEX_H = 256, 256

-- Seven symbols: source quads in texture space (x, y, w, h)
local SYMBOL_QUADS = {
    { x = 3, y = 3,   w = 26, h = 26 }, -- 7
    { x = 2, y = 41,  w = 28, h = 14 }, -- BAR
    { x = 2, y = 66,  w = 28, h = 28 }, -- bell
    { x = 3, y = 99,  w = 23, h = 27 }, -- cherry
    { x = 3, y = 131, w = 26, h = 27 }, -- grape
    { x = 2, y = 164, w = 28, h = 25 }, -- lemon
    { x = 3, y = 195, w = 26, h = 27 }, -- watermelon
}

local SYMBOL_NAMES = { "7", "BAR", "BELL", "CHERRY", "GRAPE", "LEMON", "MELON" }

-- Payout multiplier on wager for three-of-a-kind (symbol index 1..7)
local PAY_MULT = { 40, 25, 18, 14, 10, 8, 5 }
-- Two-of-a-kind pays less (keeps players hooked with small wins)
local PAY_TWO = { 5, 4, 3, 2, 2, 1, 1 }

local NUM_SYM = #SYMBOL_QUADS

local function easeOutCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

local function sfxChip()
    Sfx.play("chip_lay_" .. math.random(1, 3))
end

---------------------------------------------------------------------------
function Slots.new()
    local self = setmetatable({}, Slots)
    self.state = "betting"
    self.wager = MIN_BET
    self.exitMode = "casino_menu"
    self.pendingFloorGold = nil
    self.pendingPayout = nil
    self.resultMessage = nil
    self.resultTimer = 0
    self.resultIsWin = false

    self.reelScroll = { 0, 0, 0 }
    self.spinDuration = 2.25
    self.spinElapsed = 0
    self.spinStart = { 0, 0, 0 }
    self.spinFinal = { 0, 0, 0 }
    self.spinDelay = { 0, 0.35, 0.70 }
    self.finalSymbols = { 1, 1, 1 }

    self.lastLayout = nil

    -- Streak tracking
    self.winStreak = 0
    self.lossStreak = 0
    self.spinsPlayed = 0
    self.lastWinAmount = 0
    self.nearMiss = false

    -- Reel stop flash effect
    self.reelStopFlash = { 0, 0, 0 }
    self.reelStopped = { false, false, false }

    -- Win line glow animation
    self.winGlow = 0

    return self
end

function Slots:buildResult(mode, message, messageTimer)
    local r = {}
    if mode then r.mode = mode end
    if message then r.message = message end
    if messageTimer then r.messageTimer = messageTimer end
    return r
end

function Slots:enterTable(playerGold, exitMode)
    self.playerGold = playerGold or 0
    self.exitMode = exitMode or "casino_menu"
    self.state = "betting"
    local g = self.playerGold
    if g >= MIN_BET then
        self.wager = math.min(math.max(MIN_BET, self.wager), math.min(MAX_BET, g))
    else
        self.wager = MIN_BET
    end
    self.pendingPayout = nil
    self.resultMessage = nil
    self.resultTimer = 0
    self.resultIsWin = false
    self.reelScroll = { 0, 0, 0 }
    self.reelStopped = { false, false, false }
    self.winGlow = 0
    return self:buildResult("slots")
end

function Slots:flushPendingPayout(player)
    if not self.pendingPayout then return end
    self.pendingFloorGold = (self.pendingFloorGold or 0) + self.pendingPayout
    self.pendingPayout = nil
end

local function wrapSym(i)
    i = math.floor(i)
    while i < 1 do i = i + NUM_SYM end
    while i > NUM_SYM do i = i - NUM_SYM end
    return i
end

function Slots:startSpin(player)
    if self.state ~= "betting" then return nil end
    local w = self.wager
    if not player or (player.gold or 0) < w then
        return self:buildResult(nil, "Not enough gold.", 2)
    end

    player.gold = player.gold - w

    local function rollSymbol()
        local r = GameRng.random("slots.roll_symbol", 1, 100)
        if r <= 8 then return 1 end
        if r <= 18 then return 2 end
        if r <= 30 then return 3 end
        if r <= 48 then return 4 end
        if r <= 65 then return 5 end
        if r <= 82 then return 6 end
        return 7
    end

    local a, b, c = rollSymbol(), rollSymbol(), rollSymbol()
    self.finalSymbols = { a, b, c }

    for i = 1, 3 do
        self.spinStart[i] = self.reelScroll[i]
        local turns = GameRng.random("slots.spin_turns", 4, 9)
        self.spinFinal[i] = self.finalSymbols[i] - 1 + turns * NUM_SYM
    end

    self.spinElapsed = 0
    self.state = "spinning"
    self.resultMessage = nil
    self.resultIsWin = false
    self.nearMiss = false
    self.reelStopped = { false, false, false }
    self.reelStopFlash = { 0, 0, 0 }
    self.winGlow = 0
    Sfx.play("chips_handle_" .. math.random(1, 6))
    return nil
end

function Slots:finishSpin()
    if self.state ~= "spinning" then return end
    for i = 1, 3 do
        self.reelScroll[i] = self.finalSymbols[i] - 1
    end

    local a, b, c = self.finalSymbols[1], self.finalSymbols[2], self.finalSymbols[3]
    local win = 0
    self.spinsPlayed = self.spinsPlayed + 1
    self.nearMiss = false

    if a == b and b == c then
        win = self.wager * PAY_MULT[a]
        self.resultMessage = string.format("JACKPOT! +$%d", win)
        Sfx.play("pickup_gold", { volume = 0.9 })
        CasinoFx.startShake(8, 0.6)
        -- Big win coin explosion — coins shoot out from the machine
        local sw, sh = love.graphics.getDimensions()
        local cx, cy = sw * 0.5, sh * 0.4
        local coinCount = math.min(200, 60 + win * 2)
        CasinoFx.spawnGoldRain(cx, cy, {
            count = coinCount,
            spreadX = sw * 0.9,
            spawnYMin = -60,
            spawnYMax = sh * 0.5,
        })
        -- Extra burst from the center for dramatic effect
        CasinoFx.spawnGoldRain(cx, cy, {
            count = math.floor(coinCount * 0.4),
            spreadX = sw * 0.3,
            spawnYMin = cy - 40,
            spawnYMax = cy + 20,
        })
    elseif a == b or b == c or a == c then
        local matchSym = (a == b) and a or ((b == c) and b or a)
        win = self.wager * PAY_TWO[matchSym]
        self.resultMessage = string.format("TWO %sS! +$%d", SYMBOL_NAMES[matchSym], win)
        Sfx.play("pickup_gold", { volume = 0.6 })
        -- Smaller coin shower for two-of-a-kind
        local sw, sh = love.graphics.getDimensions()
        CasinoFx.spawnGoldRain(sw * 0.5, sh * 0.35, {
            count = 25 + win * 2,
            spreadX = sw * 0.5,
            spawnYMin = -40,
            spawnYMax = sh * 0.3,
        })
    else
        -- Near miss check
        if a == b or b == c then self.nearMiss = true end
        for _, sym in ipairs({a, b, c}) do
            local count = 0
            if a == sym then count = count + 1 end
            if b == sym then count = count + 1 end
            if c == sym then count = count + 1 end
            if count == 2 then self.nearMiss = true end
        end
    end

    if win > 0 then
        self.winStreak = self.winStreak + 1
        self.lossStreak = 0
        self.lastWinAmount = win
        self.resultIsWin = true
        self.pendingPayout = (self.pendingPayout or 0) + win

        if self.winStreak >= 5 then
            CasinoFx.spawnFloat(640, 200, "UNSTOPPABLE!", {1, 0.85, 0.2}, {scale = 1.3, life = 2.0, vy = -12})
        elseif self.winStreak >= 3 then
            CasinoFx.spawnFloat(640, 200, "HOT MACHINE!", {1, 0.7, 0.1}, {scale = 1.1, life = 1.5, vy = -12})
        elseif self.winStreak == 2 then
            CasinoFx.spawnFloat(640, 200, "ON A ROLL!", {1, 0.9, 0.4}, {life = 1.2, vy = -12})
        end
    else
        self.lossStreak = self.lossStreak + 1
        self.winStreak = 0
        self.resultIsWin = false

        local lossMessages = {
            "ALMOST! TRY AGAIN!",
            "SO CLOSE...",
            "NEXT SPIN IS THE ONE!",
            "THE REELS ARE WARMING UP...",
            "KEEP GOING!",
            "YOUR LUCK IS TURNING!",
        }
        if self.nearMiss then
            self.resultMessage = "SO CLOSE! ONE MORE SPIN!"
            CasinoFx.spawnFloat(640, 280, "SO CLOSE!", {1, 0.8, 0.2}, {scale = 1.0, life = 1.5, vy = -10})
        elseif self.lossStreak >= 2 then
            self.resultMessage = lossMessages[math.random(#lossMessages)]
        else
            self.resultMessage = "NO LUCK THIS TIME."
        end
        CasinoFx.startShake(2, 0.12)
    end

    self.state = "result"
    self.resultTimer = 2.5
end

function Slots:update(dt, player)
    CasinoFx.update(dt)

    -- Reel stop flash decay
    for i = 1, 3 do
        if self.reelStopFlash[i] > 0 then
            self.reelStopFlash[i] = math.max(0, self.reelStopFlash[i] - dt * 3)
        end
    end

    -- Win glow animation
    if self.resultIsWin and self.state == "result" then
        self.winGlow = self.winGlow + dt * 5
    end

    if self.state == "spinning" then
        self.spinElapsed = self.spinElapsed + dt
        local T = self.spinDuration
        local done = true
        for i = 1, 3 do
            local t = math.min(1, math.max(0, (self.spinElapsed - self.spinDelay[i]) / T))
            local e = easeOutCubic(t)
            self.reelScroll[i] = self.spinStart[i] + (self.spinFinal[i] - self.spinStart[i]) * e
            if t < 1 then
                done = false
            elseif not self.reelStopped[i] then
                self.reelStopped[i] = true
                self.reelStopFlash[i] = 1.0
                Sfx.play("chip_lay_" .. math.random(1, 3))
            end
        end

        if done or self.spinElapsed >= T + self.spinDelay[3] + 0.05 then
            self:finishSpin()
        end
    elseif self.state == "result" and self.resultTimer > 0 then
        self.resultTimer = self.resultTimer - dt
    end
end

---------------------------------------------------------------------------
-- Fullscreen layout
---------------------------------------------------------------------------
local function computeLayout(screenW, screenH)
    -- Reels take up most of the screen
    local reelAreaW = screenW * 0.62
    local reelAreaH = screenH * 0.48
    local reelGap = reelAreaW * 0.03
    local reelW = (reelAreaW - reelGap * 2) / 3
    local reelX = (screenW - reelAreaW) * 0.5
    local reelY = screenH * 0.18

    -- Each reel shows 3 symbols
    local cellH = reelAreaH / 3

    -- Buttons
    local btnW = math.min(180, screenW * 0.16)
    local btnH = 50
    local gap = 14
    local cx = screenW * 0.5
    local rowY = reelY + reelAreaH + 28
    local spinRect = { x = cx - btnW * 0.5, y = rowY, w = btnW, h = btnH }
    local minusRect = { x = cx - btnW * 0.5 - gap - 56, y = rowY, w = 56, h = btnH }
    local plusRect = { x = cx + btnW * 0.5 + gap, y = rowY, w = 56, h = btnH }
    local backRect = { x = cx - 70, y = rowY + btnH + 14, w = 140, h = 40 }

    return {
        reelX = reelX, reelY = reelY,
        reelW = reelW, reelH = reelAreaH,
        reelGap = reelGap,
        reelAreaW = reelAreaW,
        cellH = cellH,
        spinRect = spinRect,
        minusRect = minusRect,
        plusRect = plusRect,
        backRect = backRect,
    }
end

local function isInside(mx, my, r)
    return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

function Slots:handleKey(key, player)
    if self.state == "spinning" then return nil end

    if self.state == "betting" then
        if key == "escape" or key == "backspace" then
            return self:buildResult(self.exitMode)
        elseif key == "up" or key == "=" or key == "+" then
            local cap = math.min(MAX_BET, player and player.gold or MAX_BET)
            self.wager = math.min(cap, self.wager + BET_STEP)
            sfxChip()
        elseif key == "down" or key == "-" then
            self.wager = math.max(MIN_BET, self.wager - BET_STEP)
            sfxChip()
        elseif key == "return" or key == "enter" or key == "space" then
            return self:startSpin(player) or nil
        end
    elseif self.state == "result" then
        if key == "escape" or key == "backspace" then
            self:flushPendingPayout(player)
            self.state = "betting"
            return self:buildResult(self.exitMode)
        elseif key == "return" or key == "enter" or key == "space" then
            self:flushPendingPayout(player)
            self.state = "betting"
            return self:buildResult(nil, self.resultMessage or "", 2)
        end
    end
    return nil
end

function Slots:handleMousePressed(mx, my, button, screenW, screenH, player)
    if button ~= 1 then return nil end
    if self.state == "spinning" then return nil end

    local L = computeLayout(screenW, screenH)
    self.lastLayout = L

    if self.state == "betting" then
        if isInside(mx, my, L.backRect) then
            return self:buildResult(self.exitMode)
        elseif isInside(mx, my, L.minusRect) then
            self.wager = math.max(MIN_BET, self.wager - BET_STEP)
            sfxChip()
        elseif isInside(mx, my, L.plusRect) then
            local cap = math.min(MAX_BET, player and player.gold or MAX_BET)
            self.wager = math.min(cap, self.wager + BET_STEP)
            sfxChip()
        elseif isInside(mx, my, L.spinRect) then
            return self:startSpin(player) or nil
        end
    elseif self.state == "result" then
        if isInside(mx, my, L.backRect) then
            self:flushPendingPayout(player)
            self.state = "betting"
            return self:buildResult(self.exitMode)
        elseif isInside(mx, my, L.spinRect) then
            self:flushPendingPayout(player)
            self.state = "betting"
            return self:buildResult(nil, self.resultMessage or "", 2)
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local sheet = nil
local quads = {}

local function ensureSheet()
    if sheet then return end
    local ok, img = pcall(love.graphics.newImage, "assets/slot.png")
    if ok then
        sheet = img
        sheet:setFilter("nearest", "nearest")
        for i = 1, NUM_SYM do
            local q = SYMBOL_QUADS[i]
            quads[i] = love.graphics.newQuad(q.x, q.y, q.w, q.h, TEX_W, TEX_H)
        end
    end
end

function Slots:draw(screenW, screenH, fonts)
    ensureSheet()
    local L = computeLayout(screenW, screenH)
    self.lastLayout = L
    local fTitle = (fonts and fonts.shopTitle) or love.graphics.getFont()
    local fBody = (fonts and fonts.body) or love.graphics.getFont()
    local fDef = (fonts and fonts.default) or love.graphics.getFont()

    local shakeX, shakeY = CasinoFx.getShakeOffset()
    love.graphics.push()
    love.graphics.translate(shakeX, shakeY)

    -- === BACKGROUND ===
    -- Dark rich background
    love.graphics.setColor(0.04, 0.03, 0.02, 0.96)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)
    -- Subtle green casino felt tint
    love.graphics.setColor(0.02, 0.08, 0.03, 0.4)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)

    -- === TITLE ===
    love.graphics.setFont(fTitle)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf("SALOON SLOTS", 2, screenH * 0.04 + 2, screenW, "center")
    love.graphics.setColor(1, 0.82, 0.2)
    love.graphics.printf("SALOON SLOTS", 0, screenH * 0.04, screenW, "center")

    -- === BET DISPLAY ===
    love.graphics.setFont(fBody)
    love.graphics.setColor(0.9, 0.85, 0.55)
    love.graphics.printf(
        string.format("BET: $%d", self.wager),
        0, screenH * 0.115, screenW, "center"
    )

    -- Streak display
    if self.spinsPlayed > 0 and (self.state == "betting" or self.state == "result") then
        love.graphics.setFont(fDef)
        if self.winStreak >= 2 then
            local sc = self.winStreak >= 5 and {1, 0.7, 0.1} or (self.winStreak >= 3 and {1, 0.85, 0.2} or {0.9, 0.9, 0.5})
            love.graphics.setColor(sc[1], sc[2], sc[3])
            love.graphics.printf("WIN STREAK: " .. self.winStreak .. "X", 0, screenH * 0.145, screenW, "center")
        elseif self.lossStreak >= 3 then
            local taunts = { "THE REELS ARE DUE...", "FEELING LUCKY?", "ONE MORE SPIN...", "YOUR JACKPOT IS COMING!" }
            love.graphics.setColor(0.85, 0.75, 0.5)
            love.graphics.printf(taunts[((self.spinsPlayed - 1) % #taunts) + 1], 0, screenH * 0.145, screenW, "center")
        end
    end

    if not sheet then
        love.graphics.setColor(1, 0.3, 0.3)
        love.graphics.printf("MISSING ASSETS/SLOT.PNG", 0, screenH * 0.5, screenW, "center")
        love.graphics.pop()
        return
    end

    -- === REEL FRAME (outer decorative border) ===
    local frameX = L.reelX - 14
    local frameY = L.reelY - 14
    local frameW = L.reelAreaW + 28
    local frameH = L.reelH + 28

    -- Outer frame shadow
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", frameX + 4, frameY + 4, frameW, frameH, 10, 10)

    -- Frame body (dark wood)
    love.graphics.setColor(0.18, 0.12, 0.07)
    love.graphics.rectangle("fill", frameX, frameY, frameW, frameH, 8, 8)

    -- Frame inner bevel
    love.graphics.setColor(0.28, 0.18, 0.1)
    love.graphics.rectangle("fill", frameX + 4, frameY + 4, frameW - 8, frameH - 8, 6, 6)

    -- Gold trim
    love.graphics.setColor(0.75, 0.58, 0.18, 0.8)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", frameX, frameY, frameW, frameH, 8, 8)
    love.graphics.setColor(0.55, 0.42, 0.14, 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", frameX + 6, frameY + 6, frameW - 12, frameH - 12, 4, 4)

    -- === DRAW REELS ===
    for col = 0, 2 do
        local rx = L.reelX + col * (L.reelW + L.reelGap)
        local ry = L.reelY
        local rw = L.reelW
        local rh = L.reelH

        -- Reel background
        love.graphics.setColor(0.08, 0.06, 0.04)
        love.graphics.rectangle("fill", rx, ry, rw, rh, 4, 4)

        -- Subtle reel divider gradient
        love.graphics.setColor(0.12, 0.1, 0.08)
        love.graphics.rectangle("fill", rx + 2, ry + 2, rw - 4, rh - 4, 3, 3)

        -- Clip and draw symbols
        love.graphics.setScissor(rx, ry, rw, rh)

        local scroll = self.reelScroll[col + 1]
        local frac = scroll % 1
        local i0 = math.floor(scroll) % NUM_SYM
        local cellH = L.cellH

        -- Symbol padding inside cell
        local symPadX = rw * 0.08
        local symPadY = cellH * 0.08
        local symAreaW = rw - symPadX * 2
        local symAreaH = cellH - symPadY * 2

        for k = -1, 2 do
            local sym = wrapSym(i0 + k + 1)
            local q = quads[sym]
            local sq = SYMBOL_QUADS[sym]
            -- Fit symbol in cell, maintaining aspect ratio
            local scaleW = symAreaW / sq.w
            local scaleH = symAreaH / sq.h
            local symScale = math.min(scaleW, scaleH)
            local symDrawH = sq.h * symScale
            local symDrawW = sq.w * symScale
            -- Center symbol in cell
            local symX = rx + (rw - symDrawW) * 0.5
            local symY = ry + (k - frac) * cellH + (cellH - symDrawH) * 0.5 + cellH

            -- Dim symbols not on the payline
            local isCenter = (k == 0)
            if isCenter then
                love.graphics.setColor(1, 1, 1)
            else
                love.graphics.setColor(0.5, 0.5, 0.5, 0.6)
            end
            love.graphics.draw(sheet, q, symX, symY, 0, symScale, symScale)
        end

        love.graphics.setScissor()

        -- Reel stop flash effect
        if self.reelStopFlash[col + 1] > 0 then
            local flash = self.reelStopFlash[col + 1]
            love.graphics.setColor(1, 1, 1, flash * 0.25)
            love.graphics.rectangle("fill", rx, ry, rw, rh, 4, 4)
        end

        -- Reel border
        love.graphics.setColor(0.5, 0.38, 0.15, 0.7)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", rx, ry, rw, rh, 4, 4)
        love.graphics.setLineWidth(1)

        -- Win glow on winning reel
        if self.resultIsWin and self.state == "result" then
            local glow = 0.1 + 0.08 * math.sin(self.winGlow)
            love.graphics.setColor(1, 0.85, 0.2, glow)
            love.graphics.rectangle("fill", rx, ry, rw, rh, 4, 4)
        end
    end

    -- === PAYLINE ===
    local paylineY = L.reelY + L.reelH * 0.5
    local paylineLeft = L.reelX - 20
    local paylineRight = L.reelX + L.reelAreaW + 20

    -- Payline glow
    local paylineAlpha = 0.4
    if self.state == "spinning" then
        paylineAlpha = 0.2 + 0.15 * math.sin(love.timer.getTime() * 8)
    elseif self.resultIsWin and self.state == "result" then
        paylineAlpha = 0.5 + 0.3 * math.sin(self.winGlow)
    end
    love.graphics.setColor(1, 0.85, 0.2, paylineAlpha * 0.5)
    love.graphics.rectangle("fill", paylineLeft, paylineY - 3, paylineRight - paylineLeft, 6)
    love.graphics.setColor(1, 0.85, 0.2, paylineAlpha)
    love.graphics.setLineWidth(2)
    love.graphics.line(paylineLeft, paylineY, paylineRight, paylineY)
    love.graphics.setLineWidth(1)

    -- Payline arrows
    love.graphics.setColor(1, 0.85, 0.2, paylineAlpha + 0.2)
    love.graphics.polygon("fill", paylineLeft, paylineY, paylineLeft + 12, paylineY - 8, paylineLeft + 12, paylineY + 8)
    love.graphics.polygon("fill", paylineRight, paylineY, paylineRight - 12, paylineY - 8, paylineRight - 12, paylineY + 8)

    -- === RESULT MESSAGE ===
    if self.state == "result" and self.resultMessage then
        love.graphics.setFont(fTitle)
        local msgY = L.reelY + L.reelH + 4
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.printf(self.resultMessage, 2, msgY + 2, screenW, "center")
        if self.resultIsWin then
            local pulse = 0.8 + 0.2 * math.sin(love.timer.getTime() * 4)
            love.graphics.setColor(0.2 * pulse, 1 * pulse, 0.2 * pulse)
        else
            love.graphics.setColor(1, 0.92, 0.35)
        end
        love.graphics.printf(self.resultMessage, 0, msgY, screenW, "center")
    elseif self.state == "spinning" then
        love.graphics.setFont(fBody)
        love.graphics.setColor(1, 0.9, 0.4, 0.7)
        love.graphics.printf("SPINNING...", 0, L.reelY + L.reelH + 8, screenW, "center")
    end

    -- === CONTROLS ===
    local mx, my = 0, 0
    if windowToGame then
        mx, my = windowToGame(love.mouse.getPosition())
    else
        mx, my = love.mouse.getPosition()
    end

    local function drawBtn(r, label, hot, disabled, accent)
        local dim = disabled or false
        -- Background
        if accent and not dim then
            -- Spin button gets special treatment
            love.graphics.setColor(0.35, 0.22, 0.08, hot and 1 or 0.9)
        else
            love.graphics.setColor(0.22, 0.14, 0.08, dim and 0.45 or (hot and 0.95 or 0.75))
        end
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6, 6)
        -- Top shine
        if hot and not dim then
            love.graphics.setColor(0.45, 0.3, 0.15, 0.35)
            love.graphics.rectangle("fill", r.x + 2, r.y + 2, r.w - 4, r.h * 0.35, 5, 5)
        end
        -- Border
        local br, bg, bb = 0.85, 0.65, 0.25
        if accent then br, bg, bb = 1, 0.8, 0.25 end
        love.graphics.setColor(br, bg, bb, dim and 0.3 or (hot and 1 or 0.6))
        love.graphics.setLineWidth(hot and 2.5 or 1.5)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 6, 6)
        love.graphics.setLineWidth(1)
        -- Label
        love.graphics.setFont(fBody)
        local labelY = r.y + (r.h - fBody:getHeight()) * 0.5
        love.graphics.setColor(0, 0, 0, dim and 0.25 or 0.7)
        love.graphics.printf(label, r.x + 1, labelY + 1, r.w, "center")
        love.graphics.setColor(1, 0.95, 0.8, dim and 0.4 or 1)
        love.graphics.printf(label, r.x, labelY, r.w, "center")
    end

    if self.state == "betting" or self.state == "result" then
        drawBtn(L.minusRect, "-", isInside(mx, my, L.minusRect), false, false)
        drawBtn(L.plusRect, "+", isInside(mx, my, L.plusRect), false, false)
        local spinLabel = self.state == "result" and "SPIN AGAIN" or "SPIN"
        drawBtn(L.spinRect, spinLabel, isInside(mx, my, L.spinRect), false, true)
        drawBtn(L.backRect, "BACK", isInside(mx, my, L.backRect), false, false)
    elseif self.state == "spinning" then
        drawBtn(L.spinRect, "SPINNING...", false, true, true)
    end

    -- Wager display below buttons
    love.graphics.setFont(fDef)
    love.graphics.setColor(0.6, 0.55, 0.45)
    local wagerY = L.backRect.y + L.backRect.h + 10
    love.graphics.printf(
        string.format("MIN $%d  |  MAX $%d  |  +/- TO ADJUST", MIN_BET, MAX_BET),
        0, wagerY, screenW, "center"
    )

    -- Pulsing spin encouragement in result state
    if self.state == "result" then
        local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 3.5)
        love.graphics.setColor(1, 0.85, 0.2, pulse * 0.65)
        love.graphics.setFont(fDef)
        love.graphics.printf("PRESS SPACE TO SPIN AGAIN!", 0, screenH * 0.94, screenW, "center")
    end

    -- === PAYOUT TABLE (right side) ===
    love.graphics.setFont(fDef)
    local ptX = L.reelX + L.reelAreaW + 30
    local ptW = screenW - ptX - 16
    if ptW > 100 then
        local ptY = L.reelY + 4
        -- Panel background
        love.graphics.setColor(0.06, 0.04, 0.02, 0.85)
        love.graphics.rectangle("fill", ptX - 6, ptY - 6, ptW + 12, NUM_SYM * 22 + 38, 6, 6)
        love.graphics.setColor(0.55, 0.42, 0.15, 0.5)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", ptX - 6, ptY - 6, ptW + 12, NUM_SYM * 22 + 38, 6, 6)

        love.graphics.setColor(1, 0.85, 0.2)
        love.graphics.printf("PAYOUTS", ptX, ptY, ptW, "center")
        ptY = ptY + 24
        for i = 1, NUM_SYM do
            -- Highlight the winning symbol
            if self.resultIsWin and self.state == "result" then
                local a, b, c = self.finalSymbols[1], self.finalSymbols[2], self.finalSymbols[3]
                if (a == i and b == i and c == i) or (a == i and b == i) or (b == i and c == i) or (a == i and c == i) then
                    love.graphics.setColor(1, 0.9, 0.4)
                else
                    love.graphics.setColor(0.65, 0.6, 0.5)
                end
            else
                love.graphics.setColor(0.75, 0.7, 0.55)
            end
            love.graphics.print(string.format("%s  3X=%d  2X=%d", SYMBOL_NAMES[i], PAY_MULT[i], PAY_TWO[i]), ptX + 2, ptY)
            ptY = ptY + 20
        end
    end

    love.graphics.pop()

    -- Effects layer
    CasinoFx.draw()

    -- Key hints
    love.graphics.setColor(0.4, 0.38, 0.32)
    love.graphics.setFont(fDef)
    love.graphics.printf("[SPACE] SPIN   [ESC] BACK   +/- BET", 0, screenH - 28, screenW, "center")
end

return Slots
