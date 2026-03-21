local Roulette = {}
Roulette.__index = Roulette

local TWO_PI = math.pi * 2

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function easeOutCubic(t)
    return 1 - (1 - t) * (1 - t) * (1 - t)
end

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

function Roulette.new()
    local self = setmetatable({}, Roulette)
    self.state = "idle" -- betting | spinning | result
    self.wager = 0
    self.betType = "red" -- 'red' or 'black'
    self.rotation = 0
    self.spinStart = 0
    self.spinEnd = 0
    self.spinElapsed = 0
    self.spinDuration = 0
    self.resultNumber = nil
    self.resultColor = nil
    self.resultMessage = nil

    -- chip system
    self.chipValue = 10
    self.chips = {}         -- mapping betKey -> count
    self.chipsAtSpin = nil  -- copied when spin starts
    self.reserved = 0       -- amount reserved from player when spinning
    self.betLocked = false

    self.numbers = {}
    for i = 0, 36 do table.insert(self.numbers, i) end
    self.numSegments = #self.numbers
    self.segmentAngle = TWO_PI / self.numSegments

    -- Standard red numbers on a European wheel for color lookup
    self.isRed = {}
    local redList = {1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36}
    for _, v in ipairs(redList) do self.isRed[v] = true end

    self.hoveredButton = nil
    self.lastButtonsY = nil

    return self
end

function Roulette:buildResult(mode, message, messageTimer)
    local r = {}
    if mode then r.mode = mode end
    if message then r.message = message end
    if messageTimer then r.messageTimer = messageTimer end
    return r
end

-- Helper: compute current total bet based on placed chips
function Roulette:totalBet()
    local total = 0
    for k, v in pairs(self.chips) do
        total = total + (v * self.chipValue)
    end
    return total
end

-- Helper: determine payout multiplier for a betKey given result
-- returns multiplier (including returning stake), or 0 if losing
function Roulette:betMultiplier(betKey, number, color)
    if not betKey then return 0 end
    if betKey:sub(1,2) == "n:" then
        local n = tonumber(betKey:sub(3))
        if n == number then return 36 end -- straight pays 35:1 (+ stake)
        return 0
    elseif betKey:sub(1,6) == "color:" then
        local c = betKey:sub(7)
        if number == 0 then return 0 end
        if c == color then return 2 end -- 1:1 (+ stake)
        return 0
    elseif betKey:sub(1,7) == "parity:" then
        local p = betKey:sub(8)
        if number == 0 then return 0 end
        if (p == "even" and number % 2 == 0) or (p == "odd" and number % 2 == 1) then return 2 end
        return 0
    elseif betKey:sub(1,4) == "doz:" then
        local d = tonumber(betKey:sub(5))
        if not d then return 0 end
        local startv = (d - 1) * 12 + 1
        local endv = d * 12
        if number >= startv and number <= endv then return 3 end -- 2:1 (+ stake)
        return 0
    elseif betKey:sub(1,6) == "range:" then
        local range = betKey:sub(7)
        if range == "1-18" then if number >= 1 and number <= 18 then return 2 end end
        if range == "19-36" then if number >= 19 and number <= 36 then return 2 end end
        return 0
    end
    return 0
end

function Roulette:placeChip(betKey, player)
    if self.betLocked then
        self.resultMessage = "Cannot place chips while spinning"
        return false
    end
    local total = self:totalBet()
    if (player and player.gold or 0) < (total + self.chipValue) then
        self.resultMessage = "Not enough gold to place chip"
        return false
    end
    self.chips[betKey] = (self.chips[betKey] or 0) + 1
    return true
end

function Roulette:clearBets()
    self.chips = {}
    self.wager = 0
end

-- Build bet layout (returns list of { key = <betKey>, rect = {x,y,w,h} })
function Roulette:buildBetLayout(screenW, screenH)
    local betAreaX = screenW * 0.62
    local betAreaW = screenW * 0.34
    local startY = screenH * 0.12
    local padding = 8

    local rects = {}

    -- Zero slot at top
    local zeroH = 36
    rects[#rects+1] = { key = "n:0", rect = { x = betAreaX + padding, y = startY, w = betAreaW - padding * 2, h = zeroH } }

    -- Number grid 1..36: 12 rows x 3 columns
    local gridY = startY + zeroH + 12
    local cols = 3
    local rows = 12
    local cellW = (betAreaW - padding * 2) / cols
    local cellH = (screenH * 0.6 - zeroH - 12) / rows
    for r = 1, rows do
        for c = 1, cols do
            local num = (r - 1) * 3 + c
            local x = betAreaX + padding + (c - 1) * cellW
            local y = gridY + (r - 1) * cellH
            rects[#rects+1] = { key = "n:" .. num, rect = { x = x, y = y, w = cellW - 4, h = cellH - 4 } }
        end
    end

    -- Side bets below grid
    local sideY = gridY + rows * cellH + 12
    local sideH = 28
    local sideBets = { "color:red", "color:black", "parity:even", "parity:odd", "doz:1", "doz:2", "doz:3", "range:1-18", "range:19-36" }
    for i, k in ipairs(sideBets) do
        local x = betAreaX + padding
        local y = sideY + (i - 1) * (sideH + 6)
        rects[#rects+1] = { key = k, rect = { x = x, y = y, w = betAreaW - padding * 2, h = sideH } }
    end

    return rects
end

function Roulette:getBetAt(mx, my, screenW, screenH)
    local rects = self:buildBetLayout(screenW, screenH)
    for _, entry in ipairs(rects) do
        local r = entry.rect
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            return entry.key, r
        end
    end
    return nil
end

function Roulette:enterTable(playerGold)
    self.playerGold = playerGold or 0
    -- start with no staged chips; chips are placed by clicking the table
    self.wager = 0
    self.chips = {}
    self.chipsAtSpin = nil
    self.reserved = 0
    self.betLocked = false
    self.betType = "red"
    self.state = "betting"
    self.resultNumber = nil
    self.resultMessage = nil
    return self:buildResult("roulette")
end

function Roulette:startSpin(player)
    local total = self:totalBet()
    if total <= 0 then
        return self:buildResult(nil, "Place a bet first", 2)
    end
    if not player or (player.gold or 0) < total then
        return self:buildResult(nil, "Not enough gold to wager", 2)
    end

    -- Reserve the chips (deduct now)
    player.gold = player.gold - total
    self.reserved = total
    self.chipsAtSpin = {}
    for k, v in pairs(self.chips) do self.chipsAtSpin[k] = v end
    self.betLocked = true

    local selected = math.random(0, 36)
    self.resultNumber = selected

    -- compute how much to rotate so selected segment ends under the top pointer (-pi/2)
    local rotationNormalized = self.rotation % TWO_PI
    local segmentCenter = (selected + 0.5) * self.segmentAngle
    local pointerAngle = -math.pi / 2
    local requiredDelta = pointerAngle - (segmentCenter + rotationNormalized)
    while requiredDelta < 0 do requiredDelta = requiredDelta + TWO_PI end

    local spins = math.random(4, 8)
    self.spinStart = self.rotation
    self.spinEnd = self.rotation + requiredDelta + TWO_PI * spins
    self.spinElapsed = 0
    self.spinDuration = 2.5 + math.random() * 1.5
    self.state = "spinning"
    self.resultMessage = nil
    return nil
end

function Roulette:update(dt, player)
    if self.state == "spinning" then
        self.spinElapsed = self.spinElapsed + dt
        local t = clamp(self.spinElapsed / self.spinDuration, 0, 1)
        local eased = easeOutCubic(t)
        self.rotation = lerp(self.spinStart, self.spinEnd, eased)
        if t >= 1 then
            self.rotation = self.spinEnd
            self.state = "result"
            self.betLocked = false
            local num = self.resultNumber or 0
            local color
            if num == 0 then
                color = "green"
            elseif self.isRed[num] then
                color = "red"
            else
                color = "black"
            end
            self.resultColor = color

            -- compute payout based on chipsAtSpin
            local payout = 0
            local placed = self.chipsAtSpin or {}
            for betKey, count in pairs(placed) do
                local mult = self:betMultiplier(betKey, num, color) or 0
                if mult and mult > 0 then
                    payout = payout + (count * self.chipValue * mult)
                end
            end

            -- payout already includes returned stakes; add to player's gold
            player.gold = player.gold + payout

            -- build result message
            if payout > 0 then
                local net = payout - (self.reserved or 0)
                self.resultMessage = string.format("Wheel landed on %d (%s). Won $%d.", num, color:upper(), net)
            else
                self.resultMessage = string.format("Wheel landed on %d (%s). Lost $%d.", num, color:upper(), (self.reserved or 0))
            end

            -- clear reserved and placed chips
            self.reserved = 0
            self.chipsAtSpin = nil
            self.chips = {}
        end
    end
end

function Roulette:handleKey(key, player)
    if self.state == "betting" then
        if key == "r" then
            -- clear staged chips
            self:clearBets()
            return nil
        elseif key == "t" or key == "c" then
            self.betType = (self.betType == "red") and "black" or "red"
            return nil
        elseif key == "return" or key == "enter" or key == "space" then
            return self:startSpin(player) or nil
        elseif key == "escape" or key == "backspace" then
            return self:buildResult("casino_menu")
        end
    elseif self.state == "spinning" then
        -- ignore input while spinning
        return nil
    elseif self.state == "result" then
        if key == "return" or key == "enter" or key == "space" then
            local msg = self.resultMessage or ""
            self.state = "betting"
            self.resultNumber = nil
            return self:buildResult("casino_menu", msg, 3)
        end
    end
    return nil
end

function Roulette:getButtonRects(screenW, screenH)
    local btnW = math.min(220, screenW * 0.22)
    local btnH = 38
    local gap = 12
    local cx = screenW * 0.5
    local baseY = screenH * 0.78
    local totalW = btnW * 3 + gap * 2
    local startX = cx - totalW / 2
    local spinRect = { x = startX, y = baseY, w = btnW, h = btnH }
    local returnRect = { x = startX + (btnW + gap), y = baseY, w = btnW, h = btnH }
    local backRect = { x = startX + (btnW + gap) * 2, y = baseY, w = btnW, h = btnH }
    return spinRect, returnRect, backRect
end

function Roulette:isInside(mx, my, rect)
    return mx >= rect.x and mx <= rect.x + rect.w and my >= rect.y and my <= rect.y + rect.h
end

function Roulette:handleMousePressed(mx, my, button, screenW, screenH, player)
    if button ~= 1 then return nil end
    local spinRect, returnRect, backRect = self:getButtonRects(screenW, screenH)

    if self.state == "betting" then
        -- check bet table clicks
        local betKey = self:getBetAt(mx, my, screenW, screenH)
        if betKey then
            self:placeChip(betKey, player)
            return nil
        end

        if self:isInside(mx, my, spinRect) then
            return self:startSpin(player)
        elseif self:isInside(mx, my, returnRect) then
            -- clear staged chips (return them to unplaced state)
            self:clearBets()
            return nil
        elseif self:isInside(mx, my, backRect) then
            return self:buildResult("casino_menu")
        end
    elseif self.state == "result" then
        if self:isInside(mx, my, backRect) then
            local msg = self.resultMessage or ""
            self.state = "betting"
            self.resultNumber = nil
            return self:buildResult("casino_menu", msg, 3)
        end
    end
    return nil
end

function Roulette:draw(screenW, screenH, fonts)
    -- layout: wheel on left, betting table on right
    local leftCx = screenW * 0.36
    local cy = screenH * 0.4
    local radius = math.min(screenW * 0.6, screenH) * 0.28
    local innerRadius = radius * 0.45
    local sa = self.segmentAngle

    -- wheel segments
    for i = 0, self.numSegments - 1 do
        local a1 = self.rotation + i * sa
        local a2 = a1 + sa
        local num = self.numbers[i + 1]
        if num == 0 then
            love.graphics.setColor(0.1, 0.6, 0.2)
        elseif self.isRed[num] then
            love.graphics.setColor(0.8, 0.12, 0.12)
        else
            love.graphics.setColor(0.07, 0.08, 0.09)
        end
        love.graphics.arc("fill", leftCx, cy, radius, a1, a2)
    end

    -- cutout center
    love.graphics.setColor(0.12, 0.08, 0.05)
    love.graphics.circle("fill", leftCx, cy, innerRadius)

    -- small numbers
    love.graphics.setFont((fonts and fonts.default) or love.graphics.getFont())
    for i = 0, self.numSegments - 1 do
        local mid = self.rotation + (i + 0.5) * sa
        local num = self.numbers[i + 1]
        local tx = leftCx + math.cos(mid) * (radius - (radius - innerRadius) * 0.6)
        local ty = cy + math.sin(mid) * (radius - (radius - innerRadius) * 0.6)
        if num ~= 0 then
            if self.isRed[num] then love.graphics.setColor(1, 0.85, 0.85) else love.graphics.setColor(0.9, 0.9, 0.95) end
        else
            love.graphics.setColor(1, 1, 1)
        end
        love.graphics.printf(tostring(num), tx - 10, ty - 6, 20, "center")
    end

    -- pointer
    love.graphics.setColor(1, 1, 1)
    local pX = leftCx
    local pY = cy - radius - 8
    love.graphics.polygon("fill", pX - 10, pY + 12, pX + 10, pY + 12, pX, pY)

    -- header above wheel
    love.graphics.setFont((fonts and fonts.shopTitle) or ((fonts and fonts.title) or love.graphics.getFont()))
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf("ROULETTE", 0, cy - radius - 80, screenW, "center")

    -- Betting table
    local rects = self:buildBetLayout(screenW, screenH)
    local mx, my = windowToGame(love.mouse.getPosition())

    love.graphics.setFont((fonts and fonts.body) or love.graphics.getFont())
    for _, entry in ipairs(rects) do
        local r = entry.rect
        local k = entry.key
        -- background for different bet types
        if k:sub(1,2) == "n:" then
            -- number cells
            local num = tonumber(k:sub(3))
            if num == 0 then love.graphics.setColor(0.08, 0.5, 0.18) else
                if self.isRed[num] then love.graphics.setColor(0.7, 0.12, 0.12) else love.graphics.setColor(0.07, 0.08, 0.09) end
            end
        else
            love.graphics.setColor(0.2, 0.18, 0.16)
        end
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 4, 4)

        -- label
        love.graphics.setColor(1, 0.85, 0.75)
        local label = k
        if k:sub(1,2) == "n:" then label = tostring(tonumber(k:sub(3))) end
        love.graphics.printf(label, r.x + 4, r.y + 4, r.w - 8, "left")

        -- chips
        local count = self.chips[k] or 0
        if count > 0 then
            for i = 1, count do
                local cxChip = r.x + r.w - 18 - ((i - 1) % 3) * 12
                local cyChip = r.y + 8 + math.floor((i - 1) / 3) * 12
                love.graphics.setColor(1, 0.8, 0.2)
                love.graphics.circle("fill", cxChip, cyChip, 6)
                love.graphics.setColor(0.12, 0.08, 0.05)
                love.graphics.printf(tostring(self.chipValue), cxChip - 10, cyChip - 6, 20, "center")
            end
        end

        -- hover highlight
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            love.graphics.setColor(1, 1, 1, 0.06)
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 4, 4)
        end
    end

    -- bet summary
    love.graphics.setColor(0.9, 0.8, 0.6)
    love.graphics.printf(string.format("Total Bet: $%d", self:totalBet()), 0, cy + radius + 10, screenW, "center")
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.printf("Click numbers or bets to place $10 chips. [ENTER] Spin   [R] Return (clear chips)", 0, cy + radius + 32, screenW, "center")

    -- buttons (Spin / Return / Back)
    local spinRect, returnRect, backRect = self:getButtonRects(screenW, screenH)
    local hoverSpin = self:isInside(mx, my, spinRect)
    local hoverReturn = self:isInside(mx, my, returnRect)
    local hoverBack = self:isInside(mx, my, backRect)

    love.graphics.setColor(hoverSpin and {1, 0.8, 0.4} or {0.9, 0.7, 0.4})
    love.graphics.rectangle("fill", spinRect.x, spinRect.y, spinRect.w, spinRect.h, 6, 6)
    love.graphics.setColor(0.12, 0.08, 0.05)
    love.graphics.printf("SPIN", spinRect.x, spinRect.y + 8, spinRect.w, "center")

    love.graphics.setColor(hoverReturn and {0.9, 0.85, 0.6} or {0.8, 0.75, 0.5})
    love.graphics.rectangle("fill", returnRect.x, returnRect.y, returnRect.w, returnRect.h, 6, 6)
    love.graphics.setColor(0.12, 0.08, 0.05)
    love.graphics.printf("RETURN", returnRect.x, returnRect.y + 8, returnRect.w, "center")

    love.graphics.setColor(hoverBack and {0.8, 0.8, 0.8} or {0.6, 0.6, 0.6})
    love.graphics.rectangle("fill", backRect.x, backRect.y, backRect.w, backRect.h, 6, 6)
    love.graphics.setColor(0.12, 0.08, 0.05)
    love.graphics.printf("BACK", backRect.x, backRect.y + 8, backRect.w, "center")

    -- result display
    if self.state == "result" and self.resultNumber then
        love.graphics.setFont((fonts and fonts.title) or ((fonts and fonts.shopTitle) or love.graphics.getFont()))
        love.graphics.setColor(1, 0.9, 0.5)
        love.graphics.printf("Result: " .. tostring(self.resultNumber) .. " (" .. string.upper(self.resultColor or "") .. ")", 0, cy - 10, screenW, "center")
        love.graphics.setFont((fonts and fonts.body) or love.graphics.getFont())
        love.graphics.setColor(1, 0.85, 0.6)
        love.graphics.printf(self.resultMessage or "", 0, cy + radius + 60, screenW, "center")
        love.graphics.setColor(0.8, 0.8, 0.6)
        love.graphics.printf("[ENTER] Continue", 0, cy + radius + 90, screenW, "center")
    end
end

return Roulette
