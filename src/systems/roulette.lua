local Timer = require("lib.hump.timer")
local Sfx = require("src.systems.sfx")
local CasinoFx = require("src.ui.casino_fx")
local TextLayout = require("src.ui.text_layout")
local GameRng = require("src.systems.game_rng")

local Roulette = {}
Roulette.__index = Roulette

local TWO_PI = math.pi * 2
local PI = math.pi

---------------------------------------------------------------------------
-- Sprite assets
---------------------------------------------------------------------------
local sprites = {}
local spritesLoaded = false

local CHIP_DENOMS = {5, 10, 25, 50, 100, 500}
local CHIP_FILES = {
    [5]   = "chip_white.png",
    [10]  = "chip_red.png",
    [25]  = "chip_green.png",
    [50]  = "chip_blue.png",
    [100] = "chip_black.png",
    [500] = "chip_purple.png",
}
-- Chip colors for procedural fallback and table rendering
local CHIP_COLORS = {
    [5]   = {0.9, 0.9, 0.9},
    [10]  = {0.85, 0.15, 0.15},
    [25]  = {0.15, 0.7, 0.2},
    [50]  = {0.2, 0.35, 0.85},
    [100] = {0.12, 0.12, 0.12},
    [500] = {0.55, 0.2, 0.7},
}

local function loadSprites()
    if spritesLoaded then return end
    spritesLoaded = true
    local base = "assets/sprites/roulette/"
    local ok, img
    ok, img = pcall(love.graphics.newImage, base .. "wheel.png")
    if ok then
        img:setFilter("nearest", "nearest")
        sprites.wheel = img
    end
    ok, img = pcall(love.graphics.newImage, base .. "ball.png")
    if ok then
        img:setFilter("nearest", "nearest")
        sprites.ball = img
    end
    ok, img = pcall(love.graphics.newImage, base .. "table.png")
    if ok then
        img:setFilter("nearest", "nearest")
        sprites.table = img
    end
    sprites.chips = {}
    for denom, file in pairs(CHIP_FILES) do
        ok, img = pcall(love.graphics.newImage, base .. file)
        if ok then
            img:setFilter("nearest", "nearest")
            sprites.chips[denom] = img
        end
    end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function lerp(a, b, t)
    return a + (b - a) * t
end

local function easeOutCubic(t)
    return 1 - (1 - t) * (1 - t) * (1 - t)
end

local function easeOutQuart(t)
    return 1 - (1 - t) ^ 4
end

local function easeOutBounce(t)
    local n1 = 7.5625
    local d1 = 2.75
    if t < 1 / d1 then
        return n1 * t * t
    elseif t < 2 / d1 then
        t = t - 1.5 / d1
        return n1 * t * t + 0.75
    elseif t < 2.5 / d1 then
        t = t - 2.25 / d1
        return n1 * t * t + 0.9375
    else
        t = t - 2.625 / d1
        return n1 * t * t + 0.984375
    end
end

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function copyBetMap(tbl)
    local o = {}
    if tbl then
        for k, v in pairs(tbl) do o[k] = v end
    end
    return o
end

local function betMapIsEmpty(tbl)
    if not tbl then return true end
    for _ in pairs(tbl) do return false end
    return true
end

local function betMapsEqual(a, b)
    if not a or not b then return false end
    for k, v in pairs(a) do
        if (b[k] or 0) ~= v then return false end
    end
    for k, v in pairs(b) do
        if (a[k] or 0) ~= v then return false end
    end
    return true
end

local function sfxRandom(base, n, opts)
    Sfx.play(base .. "_" .. math.random(1, n), opts)
end

---------------------------------------------------------------------------
-- Grid number mapping
-- Grid: 3 rows × 12 cols
-- row 0 (top): 3,6,9,...,36
-- row 1 (mid): 2,5,8,...,35
-- row 2 (bot): 1,4,7,...,34
---------------------------------------------------------------------------
local function gridNumberAt(col, row)
    return (col + 1) * 3 - row
end

local function numberToGrid(n)
    if n <= 0 then return nil, nil end
    local col = math.floor((n - 1) / 3)
    local row = 2 - ((n - 1) % 3)
    return col, row
end

-- Inside bet payout multipliers (including return of stake)
-- 35:1 = 36x, 17:1 = 18x, 11:1 = 12x, 8:1 = 9x, 5:1 = 6x
local INSIDE_PAYOUTS = { [1] = 36, [2] = 18, [3] = 12, [4] = 9, [6] = 6 }

-- Build a sorted bet key from a list of numbers
local function makeBetKey(nums)
    table.sort(nums)
    local parts = {}
    for _, n in ipairs(nums) do parts[#parts+1] = tostring(n) end
    return "i:" .. table.concat(parts, ",")
end

---------------------------------------------------------------------------
-- European roulette wheel number sequence (clockwise)
---------------------------------------------------------------------------
local WHEEL_ORDER = {
    0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
    5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26
}

-- Pretty labels for outside bets
local SIDE_BET_LABELS = {
    ["color:red"] = "RED",
    ["color:black"] = "BLACK",
    ["parity:even"] = "EVEN",
    ["parity:odd"] = "ODD",
    ["doz:1"] = "1st 12",
    ["doz:2"] = "2nd 12",
    ["doz:3"] = "3rd 12",
    ["range:1-18"] = "1-18",
    ["range:19-36"] = "19-36",
    ["col:1"] = "2:1",
    ["col:2"] = "2:1",
    ["col:3"] = "2:1",
}

-- Standard red numbers on a European wheel
local RED_SET = {}
local RED_LIST = {1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36}
for _, v in ipairs(RED_LIST) do RED_SET[v] = true end

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------
function Roulette.new()
    local self = setmetatable({}, Roulette)
    self.state = "idle"
    self.wager = 0
    self.rotation = 0
    self.spinStart = 0
    self.spinEnd = 0
    self.spinElapsed = 0
    self.spinDuration = 0
    self.resultNumber = nil
    self.resultColor = nil
    self.resultMessage = nil

    -- chip system — betKey -> dollar amount placed
    self.chips = {}
    self.chipsAtSpin = nil
    self.reserved = 0
    self.betLocked = false
    self.selectedDenom = 10
    self.lastRepeatSnapshot = nil

    -- animated chips
    self.animChips = {}

    loadSprites()

    self.numbers = WHEEL_ORDER
    self.numSegments = #WHEEL_ORDER
    self.segmentAngle = TWO_PI / self.numSegments

    self.numToSegIdx = {}
    for i, n in ipairs(WHEEL_ORDER) do
        self.numToSegIdx[n] = i
    end

    self.isRed = RED_SET

    -- Ball
    self.ball = {
        angle = 0, radius = 0, targetRadius = 0,
        visible = false, settled = false,
    }
    self.lastTickSegment = -1

    -- Timer
    self.timer = Timer.new()
    self.animating = false
    self.vpW = 1280
    self.vpH = 720
    self.pendingPayout = nil
    self.pendingFloorGold = nil

    -- Result display
    self.resultTimer = 0
    self.winningSegmentPulse = 0
    self.showResult = false
    self.winningBets = {}

    -- Streak tracking (predatory engagement)
    self.winStreak = 0
    self.lossStreak = 0
    self.spinsPlayed = 0
    self.totalWon = 0
    self.totalLost = 0
    self.nearMissMessage = nil

    -- Hover state (updated each frame in draw)
    self.hoverBet = nil -- { key, nums, chipX, chipY }

    -- Grid geometry (set in buildGridGeometry)
    self.grid = nil

    return self
end

---------------------------------------------------------------------------
-- Outcome builder
---------------------------------------------------------------------------
function Roulette:buildResult(mode, message, messageTimer)
    local r = {}
    if mode then r.mode = mode end
    if message then r.message = message end
    if messageTimer then r.messageTimer = messageTimer end
    return r
end

---------------------------------------------------------------------------
-- Betting
---------------------------------------------------------------------------
function Roulette:totalBet()
    local total = 0
    for _, v in pairs(self.chips) do
        total = total + v
    end
    return total
end

--- Compute payout multiplier for a bet key given the winning number/color.
--- Returns the multiplier including stake return (e.g. 36 for straight up).
function Roulette:betMultiplier(betKey, number, color)
    if not betKey then return 0 end

    -- Inside bets: "i:1,2,3" format
    if betKey:sub(1,2) == "i:" then
        local numStr = betKey:sub(3)
        local count = 0
        local matched = false
        for s in numStr:gmatch("[^,]+") do
            count = count + 1
            if tonumber(s) == number then matched = true end
        end
        if matched then
            return INSIDE_PAYOUTS[count] or 0
        end
        return 0
    end

    -- Outside bets (existing logic)
    if betKey:sub(1,6) == "color:" then
        local c = betKey:sub(7)
        if number == 0 then return 0 end
        if c == color then return 2 end
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
        if number >= startv and number <= endv then return 3 end
        return 0
    elseif betKey:sub(1,6) == "range:" then
        local range = betKey:sub(7)
        if range == "1-18" then if number >= 1 and number <= 18 then return 2 end end
        if range == "19-36" then if number >= 19 and number <= 36 then return 2 end end
        return 0
    elseif betKey:sub(1,4) == "col:" then
        local c = tonumber(betKey:sub(5))
        if not c or number == 0 then return 0 end
        if ((number - 1) % 3) + 1 == c then return 3 end
        return 0
    end
    return 0
end

function Roulette:placeChip(betKey, player, chipX, chipY)
    if self.betLocked then
        self.resultMessage = "Cannot place chips while spinning"
        return false
    end
    local denom = self.selectedDenom
    local total = self:totalBet()
    if (player and player.gold or 0) < (total + denom) then
        self.resultMessage = "Not enough gold to place chip"
        return false
    end
    self.chips[betKey] = (self.chips[betKey] or 0) + denom
    sfxRandom("chip_lay", 3)

    if chipX and chipY then
        self.animChips[#self.animChips + 1] = {
            x = chipX, y = chipY,
            scale = 1.4, targetScale = 1.0,
            alpha = 0.7, t = 0, life = 0.2,
            denom = denom,
        }
    end
    return true
end

function Roulette:clearBets()
    self.chips = {}
    self.wager = 0
    self.animChips = {}
end

--- Restore last spin's layout if the table differs; if already matching or repeat is unavailable, double all stacks.
function Roulette:repeatOrDoubleBets(player)
    if self.betLocked or self.animating or self.state ~= "betting" then return false end
    local g = player and (player.gold or 0) or 0
    local snap = self.lastRepeatSnapshot

    local sumRepeat = 0
    if not betMapIsEmpty(snap) then
        for _, v in pairs(snap) do sumRepeat = sumRepeat + v end
    end

    local canRestore = sumRepeat > 0 and g >= sumRepeat and not betMapsEqual(self.chips, snap)
    if canRestore then
        self.chips = copyBetMap(snap)
        self.resultMessage = nil
        sfxRandom("chips_stack", 6)
        return true
    end

    local tb = self:totalBet()
    if tb > 0 and g >= tb * 2 then
        for k, v in pairs(self.chips) do
            self.chips[k] = v * 2
        end
        self.resultMessage = nil
        sfxRandom("chips_stack", 6)
        return true
    end

    if tb <= 0 then
        if sumRepeat > 0 and g < sumRepeat then
            self.resultMessage = "Not enough gold to repeat"
        elseif betMapIsEmpty(snap) then
            self.resultMessage = "Place chips first"
        else
            self.resultMessage = "Nothing on table to double"
        end
        return false
    end

    self.resultMessage = "Not enough gold to double"
    return false
end

function Roulette:repeatLastBet(player)
    return self:repeatOrDoubleBets(player)
end

--- For UI: whether repeat/double is available and which label to show.
function Roulette:getRepeatButtonState(player)
    if self.betLocked or self.animating or self.state ~= "betting" then
        return false, "REPEAT", false, false
    end
    local g = player and (player.gold or 0) or 0
    local snap = self.lastRepeatSnapshot
    local sumRepeat = 0
    if not betMapIsEmpty(snap) then
        for _, v in pairs(snap) do sumRepeat = sumRepeat + v end
    end
    local canRepeatRestore = sumRepeat > 0 and g >= sumRepeat and not betMapsEqual(self.chips, snap)
    local tb = self:totalBet()
    local canDouble = tb > 0 and g >= tb * 2
    local active = canRepeatRestore or canDouble
    local label = canRepeatRestore and "REPEAT" or (canDouble and "DOUBLE" or "REPEAT")
    return active, label, canRepeatRestore, canDouble
end

---------------------------------------------------------------------------
-- Grid geometry — compute once per frame in draw
---------------------------------------------------------------------------
function Roulette:buildGridGeometry(screenW, screenH)
    local tableX = screenW * 0.38
    local tableW = screenW * 0.59
    -- Lower than before so "ROULETTE" title and HUD have room above the felt
    local tableY = screenH * 0.118
    local tableH = screenH * 0.56

    local numCols = 12
    local numRows = 3
    local zeroW = tableW * 0.055
    local colBetW = tableW * 0.065
    local gridW = tableW - zeroW - colBetW - 6
    local cellW = gridW / numCols
    local gridH = tableH * 0.52
    local cellH = gridH / numRows
    local gridX = tableX + zeroW + 3
    local gridY = tableY

    self.grid = {
        tableX = tableX, tableW = tableW,
        tableY = tableY, tableH = tableH,
        gridX = gridX, gridY = gridY,
        gridW = gridW, gridH = gridH,
        cellW = cellW, cellH = cellH,
        numCols = numCols, numRows = numRows,
        zeroW = zeroW, colBetW = colBetW,
    }
    return self.grid
end

---------------------------------------------------------------------------
-- Smart bet detection — detects all bet types from mouse position
---------------------------------------------------------------------------
function Roulette:detectBetAt(mx, my, screenW, screenH)
    local g = self.grid
    if not g then return nil end

    -- === Zero cell ===
    local zeroRect = { x = g.tableX, y = g.gridY, w = g.zeroW - 2, h = g.gridH - 2 }
    if mx >= zeroRect.x and mx <= zeroRect.x + zeroRect.w and my >= zeroRect.y and my <= zeroRect.y + zeroRect.h then
        local fy = (my - zeroRect.y) / zeroRect.h  -- 0=top, 1=bottom
        local fx = (mx - zeroRect.x) / zeroRect.w  -- 0=left, 1=right
        local E = 0.25

        if fx > 1 - E then
            -- Near the border with the number grid
            if fy < 0.33 then
                -- Near top → could be split 0-3 or trio 0-2-3
                if fy < E * 0.33 then
                    -- Very near top-right corner → trio 0-2-3
                    return makeBetKey({0,2,3}), {0,2,3},
                        zeroRect.x + zeroRect.w, zeroRect.y + g.cellH * 0.5
                else
                    return makeBetKey({0,3}), {0,3},
                        zeroRect.x + zeroRect.w, zeroRect.y + g.cellH * 0.5
                end
            elseif fy > 0.67 then
                -- Near bottom → could be split 0-1 or trio 0-1-2
                if fy > 1 - E * 0.33 then
                    return makeBetKey({0,1,2}), {0,1,2},
                        zeroRect.x + zeroRect.w, zeroRect.y + g.cellH * 2.5
                else
                    return makeBetKey({0,1}), {0,1},
                        zeroRect.x + zeroRect.w, zeroRect.y + g.cellH * 2.5
                end
            else
                -- Middle → split 0-2
                return makeBetKey({0,2}), {0,2},
                    zeroRect.x + zeroRect.w, zeroRect.y + g.cellH * 1.5
            end
        end
        -- Center of zero → straight up
        return "i:0", {0},
            zeroRect.x + zeroRect.w * 0.5, zeroRect.y + zeroRect.h * 0.5
    end

    -- === Number grid (inside bets) ===
    local relX = (mx - g.gridX) / g.cellW
    local relY = (my - g.gridY) / g.cellH

    -- Street zone below the grid
    if relY >= g.numRows and relY < g.numRows + 0.45 and relX >= 0 and relX < g.numCols then
        local col = math.floor(relX)
        local fx = relX - col

        if fx < 0.2 and col > 0 then
            -- Six line between col-1 and col
            local nums = {}
            for r = 0, 2 do
                nums[#nums+1] = gridNumberAt(col - 1, r)
                nums[#nums+1] = gridNumberAt(col, r)
            end
            local cx = g.gridX + col * g.cellW
            local cy = g.gridY + g.gridH
            return makeBetKey(nums), nums, cx, cy
        elseif fx > 0.8 and col < g.numCols - 1 then
            -- Six line between col and col+1
            local nums = {}
            for r = 0, 2 do
                nums[#nums+1] = gridNumberAt(col, r)
                nums[#nums+1] = gridNumberAt(col + 1, r)
            end
            local cx = g.gridX + (col + 1) * g.cellW
            local cy = g.gridY + g.gridH
            return makeBetKey(nums), nums, cx, cy
        else
            -- Street for this column
            local nums = {}
            for r = 0, 2 do nums[#nums+1] = gridNumberAt(col, r) end
            local cx = g.gridX + (col + 0.5) * g.cellW
            local cy = g.gridY + g.gridH
            return makeBetKey(nums), nums, cx, cy
        end
    end

    -- Main grid area
    if relX < 0 or relX >= g.numCols or relY < 0 or relY >= g.numRows then
        -- Not in number grid — check outside bets
        return self:detectOutsideBet(mx, my, screenW, screenH)
    end

    local col = math.floor(relX)
    local row = math.floor(relY)
    local fx = relX - col
    local fy = relY - row

    local E = 0.22 -- edge zone fraction

    local nearL = fx < E
    local nearR = fx > 1 - E
    local nearT = fy < E
    local nearB = fy > 1 - E

    -- Corner bets (4 numbers)
    if nearL and nearT and col > 0 and row > 0 then
        local nums = {gridNumberAt(col-1,row-1), gridNumberAt(col,row-1),
                      gridNumberAt(col-1,row), gridNumberAt(col,row)}
        local cx = g.gridX + col * g.cellW
        local cy = g.gridY + row * g.cellH
        return makeBetKey(nums), nums, cx, cy
    end
    if nearR and nearT and col < g.numCols-1 and row > 0 then
        local nums = {gridNumberAt(col,row-1), gridNumberAt(col+1,row-1),
                      gridNumberAt(col,row), gridNumberAt(col+1,row)}
        local cx = g.gridX + (col+1) * g.cellW
        local cy = g.gridY + row * g.cellH
        return makeBetKey(nums), nums, cx, cy
    end
    if nearL and nearB and col > 0 and row < g.numRows-1 then
        local nums = {gridNumberAt(col-1,row), gridNumberAt(col,row),
                      gridNumberAt(col-1,row+1), gridNumberAt(col,row+1)}
        local cx = g.gridX + col * g.cellW
        local cy = g.gridY + (row+1) * g.cellH
        return makeBetKey(nums), nums, cx, cy
    end
    if nearR and nearB and col < g.numCols-1 and row < g.numRows-1 then
        local nums = {gridNumberAt(col,row), gridNumberAt(col+1,row),
                      gridNumberAt(col,row+1), gridNumberAt(col+1,row+1)}
        local cx = g.gridX + (col+1) * g.cellW
        local cy = g.gridY + (row+1) * g.cellH
        return makeBetKey(nums), nums, cx, cy
    end

    -- Split bets (2 numbers)
    if nearL and col > 0 then
        local nums = {gridNumberAt(col-1, row), gridNumberAt(col, row)}
        local cx = g.gridX + col * g.cellW
        local cy = g.gridY + (row + 0.5) * g.cellH
        return makeBetKey(nums), nums, cx, cy
    end
    if nearR and col < g.numCols-1 then
        local nums = {gridNumberAt(col, row), gridNumberAt(col+1, row)}
        local cx = g.gridX + (col+1) * g.cellW
        local cy = g.gridY + (row + 0.5) * g.cellH
        return makeBetKey(nums), nums, cx, cy
    end
    if nearT and row > 0 then
        local nums = {gridNumberAt(col, row-1), gridNumberAt(col, row)}
        local cx = g.gridX + (col + 0.5) * g.cellW
        local cy = g.gridY + row * g.cellH
        return makeBetKey(nums), nums, cx, cy
    end
    if nearB and row < g.numRows-1 then
        local nums = {gridNumberAt(col, row), gridNumberAt(col, row+1)}
        local cx = g.gridX + (col + 0.5) * g.cellW
        local cy = g.gridY + (row+1) * g.cellH
        return makeBetKey(nums), nums, cx, cy
    end

    -- Straight up (center of cell)
    local num = gridNumberAt(col, row)
    local cx = g.gridX + (col + 0.5) * g.cellW
    local cy = g.gridY + (row + 0.5) * g.cellH
    return "i:" .. num, {num}, cx, cy
end

--- Detect outside bets (dozen, column, color, parity, range)
function Roulette:detectOutsideBet(mx, my, screenW, screenH)
    local g = self.grid
    if not g then return nil end
    local pad = 2

    -- Column bets (2:1) — right of grid
    local colX = g.gridX + g.numCols * g.cellW + pad
    for row = 0, 2 do
        local colNum = 3 - row -- row0=col3, row1=col2, row2=col1
        local y = g.gridY + row * g.cellH
        local r = { x = colX, y = y, w = g.colBetW - pad, h = g.cellH - pad }
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            return "col:" .. colNum, nil, r.x + r.w * 0.5, r.y + r.h * 0.5
        end
    end

    -- Dozen bets
    local dozY = g.gridY + g.gridH + pad * 2
    local dozH = g.tableH * 0.14
    local dozW = g.gridW / 3
    local dozBets = {"doz:1", "doz:2", "doz:3"}
    for i, k in ipairs(dozBets) do
        local x = g.gridX + (i - 1) * dozW
        local r = { x = x, y = dozY, w = dozW - pad, h = dozH - pad }
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            return k, nil, r.x + r.w * 0.5, r.y + r.h * 0.5
        end
    end

    -- Even-money bets
    local emY = dozY + dozH + pad
    local emH = g.tableH * 0.14
    local emW = g.gridW / 6
    local emBets = {"range:1-18", "parity:even", "color:red", "color:black", "parity:odd", "range:19-36"}
    for i, k in ipairs(emBets) do
        local x = g.gridX + (i - 1) * emW
        local r = { x = x, y = emY, w = emW - pad, h = emH - pad }
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            return k, nil, r.x + r.w * 0.5, r.y + r.h * 0.5
        end
    end

    return nil
end

--- Get the screen position for a placed chip (for drawing)
function Roulette:getChipPosition(betKey)
    local g = self.grid
    if not g then return nil, nil end

    if betKey:sub(1,2) == "i:" then
        local nums = {}
        for s in betKey:sub(3):gmatch("[^,]+") do
            nums[#nums+1] = tonumber(s)
        end
        -- Average the grid positions of all numbers
        local sumX, sumY, count = 0, 0, 0
        for _, n in ipairs(nums) do
            if n == 0 then
                sumX = sumX + g.tableX + (g.zeroW - 2) * 0.5
                sumY = sumY + g.gridY + g.gridH * 0.5
            else
                local col, row = numberToGrid(n)
                if col then
                    sumX = sumX + g.gridX + (col + 0.5) * g.cellW
                    sumY = sumY + g.gridY + (row + 0.5) * g.cellH
                end
            end
            count = count + 1
        end
        if count > 0 then
            return sumX / count, sumY / count
        end
    end

    -- Outside bets — find center of the matching rect
    -- (We compute these the same way as detectOutsideBet)
    local pad = 2
    if betKey:sub(1,4) == "col:" then
        local c = tonumber(betKey:sub(5))
        if c then
            local row = 3 - c
            local colX = g.gridX + g.numCols * g.cellW + pad
            return colX + (g.colBetW - pad) * 0.5, g.gridY + (row + 0.5) * g.cellH
        end
    elseif betKey:sub(1,4) == "doz:" then
        local d = tonumber(betKey:sub(5))
        if d then
            local dozY = g.gridY + g.gridH + pad * 2
            local dozH = g.tableH * 0.14
            local dozW = g.gridW / 3
            return g.gridX + (d - 0.5) * dozW, dozY + dozH * 0.5
        end
    else
        local emY = g.gridY + g.gridH + pad * 2 + g.tableH * 0.14 + pad
        local emH = g.tableH * 0.14
        local emW = g.gridW / 6
        local emBets = {"range:1-18", "parity:even", "color:red", "color:black", "parity:odd", "range:19-36"}
        for i, k in ipairs(emBets) do
            if k == betKey then
                return g.gridX + (i - 0.5) * emW, emY + emH * 0.5
            end
        end
    end
    return nil, nil
end

---------------------------------------------------------------------------
-- Enter table
---------------------------------------------------------------------------
function Roulette:enterTable(playerGold)
    self.playerGold = playerGold or 0
    self.wager = 0
    self.chips = {}
    self.chipsAtSpin = nil
    self.reserved = 0
    self.betLocked = false
    self.state = "betting"
    self.resultNumber = nil
    self.resultMessage = nil
    self.ball.visible = false
    self.showResult = false
    self.winningBets = {}
    self.animChips = {}
    self.animating = false
    self.hoverBet = nil
    self.timer:clear()
    CasinoFx.clear()
    self.pendingPayout = nil
    self.lastRepeatSnapshot = nil
    return self:buildResult("roulette")
end

function Roulette:flushPendingPayout(player)
    if not self.pendingPayout then return end
    self.pendingFloorGold = (self.pendingFloorGold or 0) + self.pendingPayout
    self.pendingPayout = nil
end

---------------------------------------------------------------------------
-- Spin
---------------------------------------------------------------------------
function Roulette:startSpin(player)
    local total = self:totalBet()
    if total <= 0 then
        return self:buildResult(nil, "Place a bet first", 2)
    end
    if not player or (player.gold or 0) < total then
        return self:buildResult(nil, "Not enough gold to wager", 2)
    end

    player.gold = player.gold - total
    self.reserved = total
    self.chipsAtSpin = copyBetMap(self.chips)
    self.lastRepeatSnapshot = copyBetMap(self.chips)
    self.betLocked = true
    self.animating = true
    self.showResult = false
    self.winningBets = {}
    self.hoverBet = nil

    local selected = GameRng.random("roulette.result_number", 0, 36)
    self.resultNumber = selected

    local segIdx = self.numToSegIdx[selected] or 1
    local rotationNormalized = self.rotation % TWO_PI
    local segmentCenter = (segIdx - 1 + 0.5) * self.segmentAngle
    local pointerAngle = -PI / 2
    local requiredDelta = pointerAngle - (segmentCenter + rotationNormalized)
    while requiredDelta < 0 do requiredDelta = requiredDelta + TWO_PI end

    local spins = math.random(4, 8)
    self.spinStart = self.rotation
    self.spinEnd = self.rotation + requiredDelta + TWO_PI * spins
    self.spinElapsed = 0
    self.spinDuration = 3.0 + math.random() * 1.5
    self.state = "spinning"
    self.resultMessage = nil
    self.resultTimer = 0
    self.lastTickSegment = -1

    self.ball.visible = true
    self.ball.settled = false
    self.ball.angle = self.rotation + PI
    self.ball.bouncePhase = 0

    sfxRandom("card_shove", 4)
    return nil
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------
function Roulette:update(dt, player)
    self.timer:update(dt)
    CasinoFx.update(dt)

    for i = #self.animChips, 1, -1 do
        local ac = self.animChips[i]
        ac.t = ac.t + dt
        local p = math.min(1, ac.t / ac.life)
        ac.scale = lerp(ac.scale, ac.targetScale, p * 3 * dt / ac.life)
        ac.alpha = lerp(0.7, 1, p)
        if ac.t >= ac.life then
            table.remove(self.animChips, i)
        end
    end

    if self.showResult then
        self.winningSegmentPulse = self.winningSegmentPulse + dt * 4
    end

    if self.state ~= "spinning" then return end

    self.spinElapsed = self.spinElapsed + dt
    local t = clamp(self.spinElapsed / self.spinDuration, 0, 1)
    local eased = easeOutCubic(t)
    self.rotation = lerp(self.spinStart, self.spinEnd, eased)

    local ball = self.ball
    local ballSpeed = lerp(12, 0.5, easeOutQuart(t))
    ball.angle = ball.angle - ballSpeed * dt

    local outerR = 1.0
    local innerR = 0.72
    if t > 0.6 then
        local spiralT = (t - 0.6) / 0.4
        ball.radius = lerp(outerR, innerR, spiralT)
        if t > 0.85 then
            local bounceT = (t - 0.85) / 0.15
            local bounce = (1 - easeOutBounce(bounceT)) * 0.08
            ball.radius = ball.radius + bounce
        end
    else
        ball.radius = outerR
    end

    local segIdx = math.floor(((ball.angle % TWO_PI) + TWO_PI) % TWO_PI / self.segmentAngle) + 1
    if segIdx ~= self.lastTickSegment then
        self.lastTickSegment = segIdx
        local vol = 0.15 + 0.6 * t
        sfxRandom("chip_lay", 3, {volume = vol})
    end

    if t >= 1 then
        self.rotation = self.spinEnd
        self.state = "result"
        self.betLocked = false
        self.showResult = true
        self.winningSegmentPulse = 0
        ball.settled = true

        local num = self.resultNumber or 0
        local color
        if num == 0 then color = "green"
        elseif self.isRed[num] then color = "red"
        else color = "black"
        end
        self.resultColor = color

        local payout = 0
        local placed = self.chipsAtSpin or {}
        for betKey, amount in pairs(placed) do
            local mult = self:betMultiplier(betKey, num, color) or 0
            if mult > 0 then
                payout = payout + (amount * mult)
            end
        end

        if payout > 0 then
            local w = self.vpW or 1280
            local h = self.vpH or 720
            self.pendingPayout = payout
            CasinoFx.spawnGoldRain(w * 0.5, h * 0.34, {
                count = 80, spreadX = w * 0.85,
                spawnYMin = -120, spawnYMax = h * 0.14,
            })
            self.timer:after(1.72, function()
                if self.pendingPayout then
                    self.pendingFloorGold = (self.pendingFloorGold or 0) + self.pendingPayout
                    self.pendingPayout = nil
                end
            end)
        else
            self.pendingPayout = nil
        end

        self.winningBets = {}
        for betKey, _ in pairs(placed) do
            local mult = self:betMultiplier(betKey, num, color) or 0
            if mult > 0 then
                self.winningBets[betKey] = true
            end
        end

        self.spinsPlayed = self.spinsPlayed + 1
        self.nearMissMessage = nil

        if payout > 0 then
            local net = payout - (self.reserved or 0)
            self.winStreak = self.winStreak + 1
            self.lossStreak = 0
            self.totalWon = self.totalWon + net
            self.resultMessage = string.format("Landed on %d (%s). Won $%d!", num, color:upper(), net)
            CasinoFx.spawnFloat(self.vpW * 0.5, 260, "+$" .. net, {0.2, 1, 0.2}, {scale = 1.2, life = 2.0})
            sfxRandom("chips_collide", 4)
            -- Predatory streak messages
            if self.winStreak >= 5 then
                CasinoFx.spawnFloat(self.vpW * 0.5, 230, "UNSTOPPABLE!", {1, 0.85, 0.2}, {scale = 1.3, life = 2.0, vy = -12})
            elseif self.winStreak >= 3 then
                CasinoFx.spawnFloat(self.vpW * 0.5, 230, "HOT TABLE!", {1, 0.7, 0.1}, {scale = 1.1, life = 1.8, vy = -12})
            elseif self.winStreak == 2 then
                CasinoFx.spawnFloat(self.vpW * 0.5, 230, "Luck is on your side!", {1, 0.9, 0.4}, {life = 1.4, vy = -12})
            end
        else
            self.lossStreak = self.lossStreak + 1
            self.winStreak = 0
            self.totalLost = self.totalLost + (self.reserved or 0)
            CasinoFx.startShake(3, 0.2)
            CasinoFx.spawnFloat(self.vpW * 0.5, 280, "-$" .. (self.reserved or 0), {1, 0.3, 0.3}, {life = 1.5})

            -- Near-miss detection: check if any straight-up bet was 1-2 positions away
            local nearMiss = false
            local landedIdx = self.numToSegIdx[num] or 1
            for betKey, _ in pairs(placed) do
                if betKey:sub(1,2) == "i:" then
                    local betNums = {}
                    for s in betKey:sub(3):gmatch("[^,]+") do betNums[#betNums+1] = tonumber(s) end
                    if #betNums <= 2 then
                        for _, bn in ipairs(betNums) do
                            local betIdx = self.numToSegIdx[bn]
                            if betIdx then
                                local diff = math.abs(betIdx - landedIdx)
                                if diff > self.numSegments / 2 then diff = self.numSegments - diff end
                                if diff <= 2 and diff > 0 then
                                    nearMiss = true
                                    break
                                end
                            end
                        end
                    end
                    if nearMiss then break end
                end
            end

            if nearMiss then
                self.nearMissMessage = "SO CLOSE!"
                CasinoFx.spawnFloat(self.vpW * 0.5, 310, "SO CLOSE!", {1, 0.8, 0.2}, {scale = 1.1, life = 1.8, vy = -8})
            end

            -- Predatory loss-chasing messages
            local lossMessages = {
                "Landed on %d (%s). Try again!",
                "Landed on %d (%s). Next spin's yours!",
                "Landed on %d (%s). So close...",
                "Landed on %d (%s). The wheel is warming up!",
            }
            if self.lossStreak >= 2 then
                self.resultMessage = string.format(lossMessages[math.random(#lossMessages)], num, color:upper())
            else
                self.resultMessage = string.format("Landed on %d (%s). Lost $%d.", num, color:upper(), (self.reserved or 0))
            end
        end

        self.reserved = 0
        self.chipsAtSpin = nil
        self.chips = {}

        self.animating = true
        self.timer:after(1.2, function()
            self.animating = false
        end)
    end
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------
function Roulette:handleKey(key, player)
    if self.animating then return nil end

    if self.state == "betting" then
        if key == "r" then
            self:clearBets()
            return nil
        elseif key == "tab" then
            local idx = 1
            for i, d in ipairs(CHIP_DENOMS) do
                if d == self.selectedDenom then idx = i; break end
            end
            idx = idx % #CHIP_DENOMS + 1
            self.selectedDenom = CHIP_DENOMS[idx]
            sfxRandom("chip_lay", 3)
            return nil
        elseif key == "return" or key == "enter" or key == "space" then
            return self:startSpin(player) or nil
        elseif key == "b" then
            self:repeatOrDoubleBets(player)
            return nil
        elseif key == "escape" or key == "backspace" then
            return self:buildResult("casino_menu")
        end
    elseif self.state == "spinning" then
        return nil
    elseif self.state == "result" then
        if key == "return" or key == "enter" or key == "space" then
            self:flushPendingPayout(player)
            local msg = self.resultMessage or ""
            self.state = "betting"
            self.resultNumber = nil
            self.showResult = false
            self.ball.visible = false
            self.winningBets = {}
            return self:buildResult(nil, msg, 3)
        elseif key == "escape" or key == "backspace" then
            self:flushPendingPayout(player)
            self.state = "betting"
            self.resultNumber = nil
            self.showResult = false
            self.ball.visible = false
            self.winningBets = {}
            return self:buildResult("casino_menu")
        end
    end
    return nil
end

function Roulette:getButtonRects(screenW, screenH)
    local btnW = math.min(132, screenW * 0.11)
    local btnH = 40
    local gap = 8
    local cx = screenW * 0.5
    local baseY = screenH * 0.872
    local totalW = btnW * 4 + gap * 3
    local startX = cx - totalW / 2
    local spinRect = { x = startX, y = baseY, w = btnW, h = btnH }
    local repeatRect = { x = startX + (btnW + gap), y = baseY, w = btnW, h = btnH }
    local returnRect = { x = startX + (btnW + gap) * 2, y = baseY, w = btnW, h = btnH }
    local backRect = { x = startX + (btnW + gap) * 3, y = baseY, w = btnW, h = btnH }
    return spinRect, repeatRect, returnRect, backRect
end

local function isInside(mx, my, rect)
    return mx >= rect.x and mx <= rect.x + rect.w and my >= rect.y and my <= rect.y + rect.h
end

--- Chip row is laid out upward from the action buttons (must be above handleMousePressed — Lua local scope).
local function getChipSelectorLayout(screenW, screenH, fonts)
    local gap = 8
    local chipSize = 42
    local totalW = #CHIP_DENOMS * (chipSize + gap) - gap
    local maxW = screenW * 0.36
    if totalW > maxW then
        chipSize = math.floor((maxW + gap) / #CHIP_DENOMS - gap)
        chipSize = math.max(30, chipSize)
        totalW = #CHIP_DENOMS * (chipSize + gap) - gap
    end
    local defFont = (fonts and fonts.default) or love.graphics.getFont()
    local denomH = defFont:getHeight() + 2
    local selectChipH = 16
    local chipBlockH = selectChipH + chipSize + denomH
    local gapChipBtn = math.max(16, screenH * 0.022)
    local buttonTopY = screenH * 0.872
    local chipRowY = buttonTopY - gapChipBtn - chipBlockH
    return chipRowY, chipSize, gap, totalW
end

function Roulette:handleMousePressed(mx, my, button, screenW, screenH, player, fonts)
    if button ~= 1 then return nil end
    if self.animating then return nil end
    local spinRect, repeatRect, returnRect, backRect = self:getButtonRects(screenW, screenH)

    if self.state == "betting" then
        -- Check chip selector (same layout as draw)
        local chipRowY, chipSize, gap = getChipSelectorLayout(screenW, screenH, fonts)
        local chipRects = self:getChipSelectorRects(screenW, screenH, chipRowY, chipSize, gap)
        for _, cr in ipairs(chipRects) do
            if mx >= cr.x and mx <= cr.x + cr.w and my >= cr.y and my <= cr.y + cr.h then
                self.selectedDenom = cr.denom
                sfxRandom("chip_lay", 3)
                return nil
            end
        end

        -- Check bet zones
        local betKey, _, chipX, chipY = self:detectBetAt(mx, my, screenW, screenH)
        if betKey then
            self:placeChip(betKey, player, chipX, chipY)
            return nil
        end

        if isInside(mx, my, spinRect) then
            return self:startSpin(player)
        elseif isInside(mx, my, repeatRect) then
            self:repeatOrDoubleBets(player)
            return nil
        elseif isInside(mx, my, returnRect) then
            self:clearBets()
            return nil
        elseif isInside(mx, my, backRect) then
            return self:buildResult("casino_menu")
        end
    elseif self.state == "result" then
        if isInside(mx, my, backRect) then
            -- BACK exits directly from result
            self:flushPendingPayout(player)
            self.state = "betting"
            self.resultNumber = nil
            self.showResult = false
            self.ball.visible = false
            self.winningBets = {}
            return self:buildResult("casino_menu")
        elseif isInside(mx, my, spinRect) or isInside(mx, my, repeatRect)
            or isInside(mx, my, returnRect) then
            self:flushPendingPayout(player)
            local msg = self.resultMessage or ""
            self.state = "betting"
            self.resultNumber = nil
            self.showResult = false
            self.ball.visible = false
            self.winningBets = {}
            return self:buildResult(nil, msg, 3)
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Drawing — Wheel (sprite-based with procedural fallback)
---------------------------------------------------------------------------
local function getSegmentColor(self, num)
    if num == 0 then return 0.1, 0.6, 0.2
    elseif self.isRed[num] then return 0.78, 0.1, 0.1
    else return 0.08, 0.08, 0.1 end
end

function Roulette:drawWheel(cx, cy, radius)
    -- Shadow
    love.graphics.setColor(0.02, 0.01, 0.01, 0.6)
    love.graphics.circle("fill", cx + 4, cy + 4, radius + 6)

    if sprites.wheel then
        -- Dark circle behind wheel
        love.graphics.setColor(0.05, 0.04, 0.03)
        love.graphics.circle("fill", cx, cy, radius + 2)
        -- Stencil clips tighter than sprite to crop the silver rim
        local clipRadius = radius * 0.93
        love.graphics.stencil(function()
            love.graphics.circle("fill", cx, cy, clipRadius)
        end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
        local iw = sprites.wheel:getWidth()
        local scale = (clipRadius * 2.08) / iw
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(sprites.wheel, cx, cy, self.rotation,
            scale, scale, iw * 0.5, iw * 0.5)
        love.graphics.setStencilTest()
        -- Decorative rim
        love.graphics.setColor(0.35, 0.28, 0.15, 0.8)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", cx, cy, clipRadius)
        love.graphics.setLineWidth(1)

        if self.showResult and self.resultNumber then
            local sa = self.segmentAngle
            local segIdx2 = self.numToSegIdx[self.resultNumber] or 1
            local a1 = self.rotation + (segIdx2 - 1) * sa
            local a2 = a1 + sa
            local pulse = 0.15 + 0.1 * math.sin(self.winningSegmentPulse)
            love.graphics.setColor(1, 1, 0.6, pulse)
            love.graphics.arc("fill", cx, cy, radius * 0.92, a1, a2)
        end
    else
        -- Procedural fallback
        local sa = self.segmentAngle
        local innerRadius = radius * 0.42
        love.graphics.setColor(0.32, 0.28, 0.22)
        love.graphics.circle("fill", cx, cy, radius + 2)
        for i = 0, self.numSegments - 1 do
            local a1 = self.rotation + i * sa
            local a2 = a1 + sa
            local num = self.numbers[i + 1]
            local r, g, b = getSegmentColor(self, num)
            if self.showResult and num == self.resultNumber then
                local pulse2 = 0.2 * math.sin(self.winningSegmentPulse) ^ 2
                r = math.min(1, r + pulse2); g = math.min(1, g + pulse2); b = math.min(1, b + pulse2)
            end
            love.graphics.setColor(r, g, b)
            love.graphics.arc("fill", cx, cy, radius, a1, a2)
        end
        love.graphics.setLineWidth(1)
        for i = 0, self.numSegments - 1 do
            local a = self.rotation + i * sa
            love.graphics.setColor(0.55, 0.45, 0.3, 0.5)
            love.graphics.line(cx + math.cos(a) * innerRadius, cy + math.sin(a) * innerRadius,
                               cx + math.cos(a) * radius, cy + math.sin(a) * radius)
        end
        for i = 0, self.numSegments - 1 do
            local mid = self.rotation + (i + 0.5) * sa
            local num = self.numbers[i + 1]
            local tr = (radius + innerRadius) * 0.54
            local tx = cx + math.cos(mid) * tr
            local ty = cy + math.sin(mid) * tr
            love.graphics.setColor(1, 1, 1)
            local text = tostring(num)
            local font = love.graphics.getFont()
            love.graphics.push()
            love.graphics.translate(tx, ty)
            love.graphics.rotate(mid + PI / 2)
            love.graphics.print(text, -font:getWidth(text) * 0.5, -font:getHeight() * 0.5)
            love.graphics.pop()
        end
        love.graphics.setColor(0.16, 0.1, 0.06)
        love.graphics.circle("fill", cx, cy, innerRadius)
        love.graphics.setColor(0.22, 0.15, 0.08)
        love.graphics.circle("fill", cx, cy, innerRadius * 0.8)
    end

    -- Ball
    if self.ball.visible then
        local bll = self.ball
        local innerRadius = radius * 0.42
        local ballR = radius * bll.radius
        if ballR < innerRadius then ballR = innerRadius + 3 end
        local bx = cx + math.cos(bll.angle) * ballR
        local by = cy + math.sin(bll.angle) * ballR
        if sprites.ball then
            local bw = sprites.ball:getWidth()
            local ballSize = math.max(6, radius * 0.06)
            local bs = (ballSize * 2) / bw
            love.graphics.setColor(0, 0, 0, 0.4)
            love.graphics.draw(sprites.ball, bx + 1, by + 1, 0, bs, bs, bw * 0.5, bw * 0.5)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(sprites.ball, bx, by, 0, bs, bs, bw * 0.5, bw * 0.5)
        else
            love.graphics.setColor(0, 0, 0, 0.35)
            love.graphics.circle("fill", bx + 1, by + 1, 4)
            love.graphics.setColor(0.95, 0.95, 0.92)
            love.graphics.circle("fill", bx, by, 3.5)
        end
    end

    -- Pointer
    love.graphics.setColor(1, 0.85, 0.2)
    local pX, pY = cx, cy - radius - 8
    love.graphics.polygon("fill", pX - 6, pY + 10, pX + 6, pY + 10, pX, pY)
    love.graphics.setColor(0.8, 0.6, 0.1, 0.7)
    love.graphics.polygon("line", pX - 6, pY + 10, pX + 6, pY + 10, pX, pY)
end

---------------------------------------------------------------------------
-- Drawing — Chip selector
---------------------------------------------------------------------------
function Roulette:getChipSelectorRects(screenW, screenH, chipRowY, chipSize, gap)
    chipSize = chipSize or 42
    gap = gap or 8
    local totalW = #CHIP_DENOMS * (chipSize + gap) - gap
    local startX = (screenW - totalW) * 0.5
    local y = chipRowY
    local rects = {}
    for i, denom in ipairs(CHIP_DENOMS) do
        rects[i] = {
            denom = denom,
            x = startX + (i - 1) * (chipSize + gap),
            y = y,
            w = chipSize, h = chipSize,
        }
    end
    return rects
end

function Roulette:drawChipSelector(screenW, screenH, mx, my, chipRowY, chipSize, gap, fonts)
    local rects = self:getChipSelectorRects(screenW, screenH, chipRowY, chipSize, gap)
    love.graphics.setFont((fonts and fonts.default) or love.graphics.getFont())
    local font = love.graphics.getFont()
    local selectChipH = 16

    -- Label
    love.graphics.setColor(0.8, 0.75, 0.55)
    local selectorW = rects[#rects].x + rects[#rects].w - rects[1].x
    love.graphics.printf("SELECT CHIP", rects[1].x, rects[1].y - selectChipH, selectorW, "center")

    for _, cr in ipairs(rects) do
        local isSel = cr.denom == self.selectedDenom
        local isHov = mx >= cr.x and mx <= cr.x + cr.w and my >= cr.y and my <= cr.y + cr.h
        local chipSprite = sprites.chips[cr.denom]
        local centerX = cr.x + cr.w * 0.5
        local centerY = cr.y + cr.h * 0.5

        -- Selection glow
        if isSel then
            love.graphics.setColor(1, 0.85, 0.2, 0.45)
            love.graphics.circle("fill", centerX, centerY, cr.w * 0.58)
        end

        if chipSprite then
            local iw = chipSprite:getWidth()
            local scale = (cr.w * 0.9) / iw
            if isSel then scale = scale * 1.1 end
            love.graphics.setColor(1, 1, 1, isSel and 1 or (isHov and 0.9 or 0.55))
            love.graphics.draw(chipSprite, centerX, centerY, 0, scale, scale, iw * 0.5, iw * 0.5)
        else
            local c = CHIP_COLORS[cr.denom] or {0.5,0.5,0.5}
            local alpha = isSel and 1 or (isHov and 0.85 or 0.5)
            love.graphics.setColor(c[1], c[2], c[3], alpha)
            love.graphics.circle("fill", centerX, centerY, cr.w * 0.42)
        end

        -- Denomination label below chip
        local denomText = "$" .. cr.denom
        local dtw = font:getWidth(denomText)
        -- Dark bg for readability
        love.graphics.setColor(0, 0, 0, isSel and 0.7 or 0.5)
        love.graphics.rectangle("fill", centerX - dtw * 0.5 - 3, cr.y + cr.h + 1, dtw + 6, font:getHeight() + 2, 2, 2)
        love.graphics.setColor(1, 0.95, 0.7, isSel and 1 or 0.7)
        love.graphics.printf(denomText, cr.x - 6, cr.y + cr.h + 2, cr.w + 12, "center")

        -- Hover ring
        if isHov and not isSel then
            love.graphics.setColor(1, 0.85, 0.2, 0.4)
            love.graphics.setLineWidth(2)
            love.graphics.circle("line", centerX, centerY, cr.w * 0.52)
            love.graphics.setLineWidth(1)
        end
    end
end

---------------------------------------------------------------------------
-- Draw a placed chip on the table
---------------------------------------------------------------------------
local function drawTableChip(cx, cy, amount, chipSize)
    -- Find the largest denomination that fits for display
    local displayDenom = 5
    for di = #CHIP_DENOMS, 1, -1 do
        if CHIP_DENOMS[di] <= amount then
            displayDenom = CHIP_DENOMS[di]
            break
        end
    end
    local numChips = math.min(math.floor(amount / displayDenom), 4)
    if numChips < 1 then numChips = 1 end

    local chipSprite = sprites.chips[displayDenom]
    for ci = 1, numChips do
        local yOff = -(ci - 1) * 2
        if chipSprite then
            local iw = chipSprite:getWidth()
            local scale = chipSize / iw
            love.graphics.setColor(1, 1, 1, 0.95)
            love.graphics.draw(chipSprite, cx, cy + yOff, 0, scale, scale, iw * 0.5, iw * 0.5)
        else
            local c = CHIP_COLORS[displayDenom] or {0.5, 0.5, 0.5}
            love.graphics.setColor(c[1], c[2], c[3], 0.9)
            love.graphics.circle("fill", cx, cy + yOff, chipSize * 0.45)
            love.graphics.setColor(c[1]*0.5, c[2]*0.5, c[3]*0.5, 0.7)
            love.graphics.circle("line", cx, cy + yOff, chipSize * 0.45)
        end
    end
    -- Amount label
    local label = "$" .. amount
    local font = love.graphics.getFont()
    local tw = font:getWidth(label)
    -- Background for readability
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", cx - tw * 0.5 - 2, cy + chipSize * 0.35, tw + 4, font:getHeight(), 2, 2)
    love.graphics.setColor(1, 1, 0.8, 1)
    love.graphics.printf(label, cx - tw * 0.5, cy + chipSize * 0.35, tw + 1, "center")
end

---------------------------------------------------------------------------
-- Drawing — Main
---------------------------------------------------------------------------
function Roulette:draw(screenW, screenH, fonts, player)
    self.vpW = screenW
    self.vpH = screenH

    -- Dark backdrop
    love.graphics.setColor(0.05, 0.04, 0.03, 0.94)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)
    love.graphics.setColor(0.04, 0.16, 0.06, 0.55)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)

    local shakeX, shakeY = CasinoFx.getShakeOffset()
    love.graphics.push()
    love.graphics.translate(shakeX, shakeY)

    -- Wheel (slightly lower to match table / title spacing)
    local wheelRadius = math.min(screenW * 0.17, screenH * 0.30)
    local wheelCx = screenW * 0.18
    local wheelCy = screenH * 0.388

    -- Header — below HUD bar so the title is fully visible
    local titleY = screenH * 0.056
    love.graphics.setFont((fonts and fonts.shopTitle) or love.graphics.getFont())
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.printf("ROULETTE", 2, titleY + 2, screenW, "center")
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf("ROULETTE", 0, titleY, screenW, "center")

    -- Draw wheel
    love.graphics.setFont((fonts and fonts.default) or love.graphics.getFont())
    self:drawWheel(wheelCx, wheelCy, wheelRadius)

    -- Build grid geometry
    local g = self:buildGridGeometry(screenW, screenH)

    -- Get mouse position
    local mx, my = 0, 0
    if windowToGame then
        mx, my = windowToGame(love.mouse.getPosition())
    end

    -- Detect hover bet
    self.hoverBet = nil
    if self.state == "betting" and not self.animating then
        local hKey, hNums, hcx, hcy = self:detectBetAt(mx, my, screenW, screenH)
        if hKey then
            self.hoverBet = { key = hKey, nums = hNums, chipX = hcx, chipY = hcy }
        end
    end

    -- === Draw table background ===
    -- Table background area (includes outside bets below the grid)
    local dozH = g.tableH * 0.14
    local emH = g.tableH * 0.14
    local fullTableH = g.gridH + dozH + emH + 12
    local tableBgX = g.tableX - 12
    local tableBgY = g.tableY - 12
    local tableBgW = g.gridX + g.numCols * g.cellW + g.colBetW - g.tableX + 24
    local tableBgH = fullTableH + 24
    if sprites.table then
        local tw = sprites.table:getWidth()
        local th = sprites.table:getHeight()
        -- Crop 12% from each edge of the sprite to remove gray border
        local cropFrac = 0.12
        local cropPxW = tw * cropFrac
        local cropPxH = th * cropFrac
        local innerW = tw - cropPxW * 2
        local innerH = th - cropPxH * 2
        local quad = love.graphics.newQuad(cropPxW, cropPxH, innerW, innerH, tw, th)
        local scaleX = tableBgW / innerW
        local scaleY = tableBgH / innerH
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.draw(sprites.table, quad, tableBgX, tableBgY, 0, scaleX, scaleY)
    else
        -- Procedural felt background
        love.graphics.setColor(0.02, 0.12, 0.04, 0.8)
        love.graphics.rectangle("fill", tableBgX, tableBgY, tableBgW, tableBgH, 6, 6)
        -- Border
        love.graphics.setColor(0.45, 0.35, 0.2, 0.7)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", tableBgX, tableBgY, tableBgW, tableBgH, 6, 6)
        love.graphics.setLineWidth(1)
    end

    -- === Draw number grid ===
    local pad = 2

    -- Zero cell
    local zeroRect = { x = g.tableX, y = g.gridY, w = g.zeroW - pad, h = g.gridH - pad }
    love.graphics.setColor(0.08, 0.48, 0.16)
    love.graphics.rectangle("fill", zeroRect.x, zeroRect.y, zeroRect.w, zeroRect.h, 2, 2)
    love.graphics.setColor(1, 1, 1)
    local font = love.graphics.getFont()
    love.graphics.printf("0", zeroRect.x, zeroRect.y + (zeroRect.h - font:getHeight()) * 0.5, zeroRect.w, "center")

    -- Number cells
    for row = 0, g.numRows - 1 do
        for col = 0, g.numCols - 1 do
            local num = gridNumberAt(col, row)
            local x = g.gridX + col * g.cellW
            local y = g.gridY + row * g.cellH
            local w = g.cellW - pad
            local h = g.cellH - pad

            -- Background color
            if self.isRed[num] then
                love.graphics.setColor(0.68, 0.1, 0.1)
            else
                love.graphics.setColor(0.06, 0.06, 0.08)
            end
            love.graphics.rectangle("fill", x, y, w, h, 2, 2)

            -- Winning glow
            if self.winningBets then
                for bk, _ in pairs(self.winningBets) do
                    if bk:sub(1,2) == "i:" then
                        for s in bk:sub(3):gmatch("[^,]+") do
                            if tonumber(s) == num then
                                local glow = 0.18 + 0.12 * math.sin(self.winningSegmentPulse)
                                love.graphics.setColor(1, 0.85, 0.2, glow)
                                love.graphics.rectangle("fill", x, y, w, h, 2, 2)
                            end
                        end
                    end
                end
            end

            -- Number label
            love.graphics.setColor(1, 0.95, 0.9)
            love.graphics.printf(tostring(num), x + 2, y + (h - font:getHeight()) * 0.5, w - 4, "center")
        end
    end

    -- Hover highlight for inside bets
    if self.hoverBet and self.hoverBet.nums then
        for _, n in ipairs(self.hoverBet.nums) do
            if n == 0 then
                love.graphics.setColor(1, 0.85, 0.2, 0.35)
                love.graphics.rectangle("fill", zeroRect.x, zeroRect.y, zeroRect.w, zeroRect.h, 2, 2)
                love.graphics.setColor(1, 0.85, 0.2, 0.8)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", zeroRect.x, zeroRect.y, zeroRect.w, zeroRect.h, 2, 2)
                love.graphics.setLineWidth(1)
            else
                local col, row = numberToGrid(n)
                if col then
                    local x = g.gridX + col * g.cellW
                    local y2 = g.gridY + row * g.cellH
                    love.graphics.setColor(1, 0.85, 0.2, 0.35)
                    love.graphics.rectangle("fill", x, y2, g.cellW - pad, g.cellH - pad, 2, 2)
                    love.graphics.setColor(1, 0.85, 0.2, 0.8)
                    love.graphics.setLineWidth(2)
                    love.graphics.rectangle("line", x, y2, g.cellW - pad, g.cellH - pad, 2, 2)
                    love.graphics.setLineWidth(1)
                end
            end
        end

        -- Show bet type label at hover position
        local hb = self.hoverBet
        local numCount = #hb.nums
        local betLabel = ""
        if numCount == 1 then betLabel = "Straight (35:1)"
        elseif numCount == 2 then betLabel = "Split (17:1)"
        elseif numCount == 3 then betLabel = "Street (11:1)"
        elseif numCount == 4 then betLabel = "Corner (8:1)"
        elseif numCount == 6 then betLabel = "Six Line (5:1)"
        end
        if betLabel ~= "" then
            local lw = font:getWidth(betLabel)
            love.graphics.setColor(0, 0, 0, 0.8)
            love.graphics.rectangle("fill", hb.chipX - lw * 0.5 - 4, hb.chipY - 22, lw + 8, font:getHeight() + 4, 3, 3)
            love.graphics.setColor(1, 0.9, 0.6)
            love.graphics.printf(betLabel, hb.chipX - lw * 0.5, hb.chipY - 20, lw + 1, "center")
        end
    end

    -- Column bets (2:1) — right of grid
    local colX = g.gridX + g.numCols * g.cellW + pad
    for row = 0, 2 do
        local colNum = 3 - row
        local y = g.gridY + row * g.cellH
        local key = "col:" .. colNum
        local r = { x = colX, y = y, w = g.colBetW - pad, h = g.cellH - pad }

        love.graphics.setColor(0.18, 0.16, 0.14)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 2, 2)

        -- Hover/winning
        local hov = mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
        if hov and self.state == "betting" then
            love.graphics.setColor(1, 0.85, 0.2, 0.35)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 2, 2)
            love.graphics.setLineWidth(1)
        end
        if self.winningBets[key] then
            local glow2 = 0.18 + 0.12 * math.sin(self.winningSegmentPulse)
            love.graphics.setColor(1, 0.85, 0.2, glow2)
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 2, 2)
        end

        love.graphics.setColor(1, 0.95, 0.9)
        love.graphics.printf("2:1", r.x + 2, r.y + (r.h - font:getHeight()) * 0.5, r.w - 4, "center")

        -- Placed chips
        local betAmt = self.chips[key] or 0
        if betAmt > 0 then
            drawTableChip(r.x + r.w * 0.5, r.y + r.h * 0.5, betAmt, math.min(r.w, r.h) * 0.7)
        end
    end

    -- Dozen bets
    local dozY = g.gridY + g.gridH + pad * 2
    local dozH = g.tableH * 0.14
    local dozW = g.gridW / 3
    local dozBets = {"doz:1", "doz:2", "doz:3"}
    local dozLabels = {"1st 12", "2nd 12", "3rd 12"}
    for i, k in ipairs(dozBets) do
        local x = g.gridX + (i - 1) * dozW
        local r = { x = x, y = dozY, w = dozW - pad, h = dozH - pad }
        love.graphics.setColor(0.15, 0.14, 0.12)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 2, 2)
        local hov = mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
        if hov and self.state == "betting" then
            love.graphics.setColor(1, 0.85, 0.2, 0.35)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 2, 2)
            love.graphics.setLineWidth(1)
        end
        if self.winningBets[k] then
            local glow3 = 0.18 + 0.12 * math.sin(self.winningSegmentPulse)
            love.graphics.setColor(1, 0.85, 0.2, glow3)
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 2, 2)
        end
        love.graphics.setColor(1, 0.95, 0.9)
        love.graphics.printf(dozLabels[i], r.x + 2, r.y + (r.h - font:getHeight()) * 0.5, r.w - 4, "center")
        local betAmt2 = self.chips[k] or 0
        if betAmt2 > 0 then
            drawTableChip(r.x + r.w * 0.5, r.y + r.h * 0.5, betAmt2, math.min(r.w, r.h) * 0.6)
        end
    end

    -- Even-money bets
    local emY = dozY + dozH + pad
    local emH = g.tableH * 0.14
    local emW = g.gridW / 6
    local emBets = {"range:1-18", "parity:even", "color:red", "color:black", "parity:odd", "range:19-36"}
    local emLabels = {"1-18", "EVEN", "RED", "BLACK", "ODD", "19-36"}
    for i, k in ipairs(emBets) do
        local x = g.gridX + (i - 1) * emW
        local r = { x = x, y = emY, w = emW - pad, h = emH - pad }

        if k == "color:red" then love.graphics.setColor(0.55, 0.08, 0.08)
        elseif k == "color:black" then love.graphics.setColor(0.06, 0.06, 0.06)
        else love.graphics.setColor(0.15, 0.14, 0.12) end
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 2, 2)

        local hov = mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
        if hov and self.state == "betting" then
            love.graphics.setColor(1, 0.85, 0.2, 0.35)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 2, 2)
            love.graphics.setLineWidth(1)
        end
        if self.winningBets[k] then
            local glow4 = 0.18 + 0.12 * math.sin(self.winningSegmentPulse)
            love.graphics.setColor(1, 0.85, 0.2, glow4)
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 2, 2)
        end
        love.graphics.setColor(1, 0.95, 0.9)
        love.graphics.printf(emLabels[i], r.x + 2, r.y + (r.h - font:getHeight()) * 0.5, r.w - 4, "center")
        local betAmt3 = self.chips[k] or 0
        if betAmt3 > 0 then
            drawTableChip(r.x + r.w * 0.5, r.y + r.h * 0.5, betAmt3, math.min(r.w, r.h) * 0.6)
        end
    end

    -- Table border (only if no sprite asset)
    if not sprites.table then
        local borderX = g.tableX - 4
        local borderY = g.gridY - 4
        local borderW = g.gridX + g.numCols * g.cellW + g.colBetW - g.tableX + 8
        local borderH = emY + emH - g.gridY + 8
        love.graphics.setColor(0.5, 0.4, 0.25, 0.6)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", borderX, borderY, borderW, borderH, 4, 4)
        love.graphics.setLineWidth(1)
    end

    -- Draw placed chips on inside bets
    local chipSize = math.min(g.cellW, g.cellH) * 0.65
    for betKey, amount in pairs(self.chips) do
        if betKey:sub(1,2) == "i:" then
            local cx, cy = self:getChipPosition(betKey)
            if cx and cy then
                drawTableChip(cx, cy, amount, chipSize)
            end
        end
    end

    -- Street zone indicator (thin strip below grid)
    if self.state == "betting" then
        love.graphics.setColor(0.3, 0.25, 0.15, 0.3)
        love.graphics.rectangle("fill", g.gridX, g.gridY + g.gridH + 1,
            g.gridW, g.cellH * 0.35, 2, 2)
        love.graphics.setColor(0.5, 0.45, 0.3, 0.4)
        love.graphics.printf("STREETS / SIX LINES", g.gridX, g.gridY + g.gridH + 3,
            g.gridW, "center")
    end

    -- Bet summary beside wheel (keeps bottom strip free for chip picker + buttons)
    local titleFont = (fonts and fonts.title) or love.graphics.getFont()
    local statFont = (fonts and fonts.stat) or love.graphics.getFont()
    local tb = self:totalBet()
    local betPanelW = math.min(200, screenW * 0.17)
    local padT = 6
    local betPanelInnerH = statFont:getHeight() + 3 + titleFont:getHeight() + 6 + statFont:getHeight()
    local betPanelH = padT + betPanelInnerH + 6
    local betPanelX = wheelCx + wheelRadius + 12
    local betPanelY = wheelCy - betPanelH * 0.5
    local tableLeft = screenW * 0.38
    if betPanelX + betPanelW > tableLeft - 6 then
        betPanelX = tableLeft - betPanelW - 8
    end
    if betPanelX < 4 then betPanelX = 4 end
    love.graphics.setColor(0.06, 0.04, 0.02, 0.88)
    love.graphics.rectangle("fill", betPanelX - 4, betPanelY - 2, betPanelW + 8, betPanelH + 4, 6, 6)
    love.graphics.setColor(0.72, 0.55, 0.18, 0.88)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", betPanelX - 4, betPanelY - 2, betPanelW + 8, betPanelH + 4, 6, 6)
    love.graphics.setLineWidth(1)
    local ty = betPanelY + padT
    love.graphics.setFont(statFont)
    love.graphics.setColor(0.75, 0.68, 0.5)
    love.graphics.printf("TOTAL BET", betPanelX, ty, betPanelW, "center")
    ty = ty + statFont:getHeight() + 3
    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 0.92, 0.45)
    love.graphics.printf(string.format("$%d", tb), betPanelX, ty, betPanelW, "center")
    ty = ty + titleFont:getHeight() + 6
    love.graphics.setFont(statFont)
    love.graphics.setColor(0.82, 0.74, 0.55)
    love.graphics.printf(string.format("Chip  $%d", self.selectedDenom), betPanelX, ty, betPanelW, "center")

    -- Chip selector (Y from bottom layout — does not overlap bet panel)
    local chipRowY, chipSize, chipGap = getChipSelectorLayout(screenW, screenH, fonts)
    if self.state == "betting" then
        self:drawChipSelector(screenW, screenH, mx, my, chipRowY, chipSize, chipGap, fonts)
    end

    -- Streak / session stats (predatory engagement)
    if self.spinsPlayed > 0 and self.state == "betting" then
        local streakFont = (fonts and fonts.default) or love.graphics.getFont()
        love.graphics.setFont(streakFont)
        local streakY = wheelCy + wheelRadius + 16
        if self.winStreak >= 2 then
            local streakColor = self.winStreak >= 5 and {1, 0.7, 0.1} or (self.winStreak >= 3 and {1, 0.85, 0.2} or {0.9, 0.9, 0.5})
            local streakText = "Win Streak: " .. self.winStreak .. "x"
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.printf(streakText, wheelCx - 100 + 1, streakY + 1, 200, "center")
            love.graphics.setColor(streakColor[1], streakColor[2], streakColor[3])
            love.graphics.printf(streakText, wheelCx - 100, streakY, 200, "center")
        elseif self.lossStreak >= 2 then
            local tauntMessages = {
                "The wheel is due...",
                "Feeling lucky?",
                "One more spin...",
                "Your number's coming!",
            }
            local taunt = tauntMessages[((self.spinsPlayed - 1) % #tauntMessages) + 1]
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.printf(taunt, wheelCx - 100 + 1, streakY + 1, 200, "center")
            love.graphics.setColor(0.85, 0.75, 0.5)
            love.graphics.printf(taunt, wheelCx - 100, streakY, 200, "center")
        end
    end

    -- Key hints
    love.graphics.setColor(0.5, 0.48, 0.38)
    love.graphics.printf("[ENTER] Spin   [B] Repeat / Double   [R] Clear   [TAB] Chip   [ESC] Back",
        0, screenH * 0.96, screenW, "center")

    -- Buttons (wood + gold trim; matches saloon / table tone)
    local spinRect, repeatRect, returnRect, backRect = self:getButtonRects(screenW, screenH)
    local repeatActive, repeatLabel = self:getRepeatButtonState(player)
    local hoverSpin = isInside(mx, my, spinRect) and not self.animating
    local hoverRepeat = isInside(mx, my, repeatRect) and not self.animating and repeatActive
    local hoverReturn = isInside(mx, my, returnRect) and not self.animating
    local hoverBack = isInside(mx, my, backRect) and not self.animating
    local btnFont = (fonts and fonts.default) or love.graphics.getFont()

    local function drawWoodBtn(rect, label, hov, accentStrong, faded)
        local dim = faded or self.animating
        love.graphics.setColor(0.32, 0.2, 0.11, dim and 0.45 or 0.95)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 5, 5)
        love.graphics.setColor(0.48, 0.32, 0.18, dim and 0.25 or 0.42)
        love.graphics.rectangle("fill", rect.x + 2, rect.y + 2, rect.w - 4, rect.h * 0.38, 4, 4)
        local gr, gg, gb = 0.78, 0.58, 0.18
        if accentStrong then gr, gg, gb = 0.95, 0.78, 0.28 end
        if dim then gr, gg, gb = gr * 0.55, gg * 0.55, gb * 0.55 end
        love.graphics.setColor(gr, gg, gb, (hov and not dim) and 0.95 or 0.65)
        love.graphics.setLineWidth(hov and not dim and 2 or 1)
        love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 5, 5)
        love.graphics.setLineWidth(1)
        love.graphics.setFont(btnFont)
        local ty = TextLayout.printfYCenteredInRect(btnFont, rect.y, rect.h)
        love.graphics.setColor(0.96, 0.9, 0.78, dim and 0.45 or 1)
        love.graphics.printf(label, rect.x, ty, rect.w, "center")
    end

    drawWoodBtn(spinRect, "SPIN", hoverSpin, true, false)
    drawWoodBtn(repeatRect, repeatLabel or "REPEAT", hoverRepeat, false, not repeatActive)
    drawWoodBtn(returnRect, "CLEAR", hoverReturn, false, false)
    drawWoodBtn(backRect, "BACK", hoverBack, false, false)

    -- Result overlay
    if self.showResult and self.resultNumber then
        love.graphics.setFont((fonts and fonts.shopTitle) or love.graphics.getFont())
        local resultText = tostring(self.resultNumber) .. " " .. string.upper(self.resultColor or "")

        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", wheelCx - 55, wheelCy - 18, 110, 36, 6, 6)

        if self.resultNumber == 0 then love.graphics.setColor(0.2, 1, 0.4)
        elseif self.isRed[self.resultNumber] then love.graphics.setColor(1, 0.35, 0.35)
        else love.graphics.setColor(0.85, 0.85, 0.9) end
        love.graphics.printf(resultText, wheelCx - 55, wheelCy - 14, 110, "center")

        love.graphics.setFont((fonts and fonts.body) or love.graphics.getFont())
        love.graphics.setColor(1, 0.92, 0.7)
        love.graphics.printf(self.resultMessage or "", 0, screenH * 0.62, screenW, "center")

        -- More enticing continue prompt
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 3)
        love.graphics.setColor(1, 0.85, 0.2, pulse)
        love.graphics.printf("Click anywhere or press ENTER to spin again!", 0, screenH * 0.67, screenW, "center")
        love.graphics.setColor(0.55, 0.5, 0.4, 0.6)
        love.graphics.printf("[ESC] to leave", 0, screenH * 0.72, screenW, "center")
    end

    love.graphics.pop()
    CasinoFx.draw()
end

return Roulette
