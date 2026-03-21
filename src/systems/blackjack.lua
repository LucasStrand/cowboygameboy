local Perks = require("src.data.perks")
local Sfx = require("src.systems.sfx")
local Timer = require("lib.hump.timer")
local CasinoFx = require("src.ui.casino_fx")
local BlackjackVisuals = require("src.ui.blackjack_visuals")

local Blackjack = {}
Blackjack.__index = Blackjack

local SUITS = {"hearts", "diamonds", "clubs", "spades"}
local RANKS = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}

local SUIT_SYMBOLS = {
    hearts = "H",
    diamonds = "D",
    clubs = "C",
    spades = "S",
}

local MIN_BET = 5
local BET_STEP = 5
local CARD_DRAW_W = 90
local CARD_GAP = 16

-- Animation timing
local DEAL_SLIDE_TIME = 0.18
local DEAL_GAP_TIME = 0.12
local FLIP_HALF_TIME = 0.12
local DEALER_THINK_TIME = 0.45
local RESULT_PAUSE_TIME = 0.6

-- Deck position (cards slide from dealer area)
local DECK_X, DECK_Y = 640, 30

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function sfxRandom(base, n)
    Sfx.play(base .. "_" .. math.random(1, n))
end

local function getCardSprite(self, suit, rank)
    local key = suit .. ":" .. rank
    if self.cardSprites[key] then return self.cardSprites[key] end
    local path = string.format("assets/sprites/Blackjack/%s/%s.png", suit, rank)
    local img = love.graphics.newImage(path)
    img:setFilter("nearest", "nearest")
    self.cardSprites[key] = img
    if not self.cardNativeW then
        self.cardNativeW = img:getWidth()
        self.cardNativeH = img:getHeight()
    end
    return img
end

local function getBackSprite(self)
    if self.backSprite then return self.backSprite end
    self.backSprite = love.graphics.newImage("assets/sprites/Blackjack/backs/red.png")
    self.backSprite:setFilter("nearest", "nearest")
    if not self.cardNativeW then
        self.cardNativeW = self.backSprite:getWidth()
        self.cardNativeH = self.backSprite:getHeight()
    end
    return self.backSprite
end

local function targetCardScale(self)
    if not self.cardNativeW or self.cardNativeW <= 0 then return 1 end
    return CARD_DRAW_W / self.cardNativeW
end

local function cardGapRatio(count)
    local ratio = CARD_GAP / CARD_DRAW_W
    if count >= 6 then
        return ratio * 0.65
    elseif count >= 5 then
        return ratio * 0.75
    elseif count >= 4 then
        return ratio * 0.85
    end
    return ratio
end

local function cardLayout(self, maxWidth, maxHeight, count)
    if not self.cardNativeW or self.cardNativeW <= 0 or not count or count < 1 then
        return 1, CARD_GAP, CARD_DRAW_W, CARD_DRAW_W * 1.5
    end

    local gapRatio = cardGapRatio(count)
    local scale = targetCardScale(self)
    if maxHeight ~= nil then
        scale = math.min(scale, math.max(0, maxHeight) / self.cardNativeH)
    end
    if maxWidth ~= nil then
        local widthUnits = count + math.max(0, count - 1) * gapRatio
        scale = math.min(scale, math.max(0, maxWidth) / (self.cardNativeW * widthUnits))
    end

    local drawW = self.cardNativeW * scale
    local drawH = self.cardNativeH * scale
    local gap = drawW * gapRatio
    if maxWidth ~= nil and maxWidth > 0 and count > 1 then
        gap = math.min(gap, math.max(0, (maxWidth - count * drawW) / (count - 1)))
    end

    return scale, gap, drawW, drawH
end

local function cardDrawHeight(self, maxWidth, maxHeight, count)
    local _, _, _, drawH = cardLayout(self, maxWidth, maxHeight, count)
    return drawH
end

---------------------------------------------------------------------------
-- Card target position calculation
---------------------------------------------------------------------------
local function computeCardTargets(self, cards, centerX, y, maxWidth, maxHeight)
    local count = #cards
    if count == 0 then return end
    local scale, gap, drawW, drawH = cardLayout(self, maxWidth, maxHeight, count)
    local totalW = count * drawW + (count - 1) * gap
    local x = centerX - totalW * 0.5
    local mid = (count + 1) / 2
    for i, card in ipairs(cards) do
        card.targetX = x + (i - 1) * (drawW + gap)
        card.targetY = y
        card.drawScale = scale
        card.rotation = (i - mid) * 0.025
    end
    return y + drawH
end

---------------------------------------------------------------------------
-- Animated card row drawing
---------------------------------------------------------------------------
local function drawAnimatedCardRow(self, cards, maxWidth, maxHeight)
    if not cards or #cards == 0 then return end
    for _, card in ipairs(cards) do
        local img
        if not card.faceUp then
            img = getBackSprite(self)
        else
            img = getCardSprite(self, card.suit, card.rank)
        end
        if not self.cardNativeW then
            self.cardNativeW = img:getWidth()
            self.cardNativeH = img:getHeight()
        end
        local s = card.drawScale or targetCardScale(self)
        local sx = s * (card.scaleX or 1)
        local sy = s
        local cx = card.x + (self.cardNativeW * s) * 0.5
        local cy = card.y + (self.cardNativeH * s) * 0.5
        love.graphics.setColor(1, 1, 1, card.alpha or 1)
        love.graphics.draw(img, cx, cy, card.rotation or 0, sx, sy,
            self.cardNativeW * 0.5, self.cardNativeH * 0.5)
    end
end

---------------------------------------------------------------------------
-- Card object creation
---------------------------------------------------------------------------
local function newCardObj(suit, rank, faceUp)
    return {
        suit = suit,
        rank = rank,
        faceUp = faceUp ~= false,
        x = DECK_X,
        y = DECK_Y,
        targetX = 0,
        targetY = 0,
        scaleX = 1,
        alpha = 1,
        rotation = 0,
        drawScale = 1,
    }
end

---------------------------------------------------------------------------
-- Button layout (same API as before)
---------------------------------------------------------------------------
local function buttonLabelsForState(state)
    if state == "betting" then
        return {
            { id = "deal", label = "DEAL" },
            { id = "leave", label = "BACK" },
        }
    elseif state == "result" then
        return {
            { id = "continue", label = "CONTINUE" },
            { id = "deal_again", label = "DEAL AGAIN" },
        }
    end
    return nil
end

function Blackjack:getButtonLabels()
    if self.state == "playing" then
        local gold = self._player and self._player.gold or 0
        local out = {
            { id = "hit", label = "HIT" },
            { id = "stand", label = "STAND" },
            { id = "double", label = "DOUBLE" },
        }
        if self:canSplit(gold) then
            out[#out + 1] = { id = "split", label = "SPLIT" }
        end
        return out
    end
    return buttonLabelsForState(self.state)
end

local function blackjackButtonLayout(screenW, screenH, labels, baseY)
    if not labels or #labels == 0 then return nil end
    local bw, bh = 160, 56
    local gap = 12
    local totalW = #labels * bw + (#labels - 1) * gap
    local x0 = (screenW - totalW) * 0.5
    local y = screenH - bh - 16
    if baseY then
        y = math.max(y, baseY)
    end
    local rects = {}
    for i, b in ipairs(labels) do
        rects[i] = { id = b.id, label = b.label, x = x0 + (i - 1) * (bw + gap), y = y, w = bw, h = bh }
    end
    return rects
end

local function blackjackWagerLayout(screenW, screenH, buttonY)
    -- Wager panel centered above the action buttons
    local panelW, panelH = 200, 50
    local x = (screenW - panelW) * 0.5
    local y = (buttonY or screenH - 56 - 16) - panelH - 10
    local pad = 6
    local btnSize = 38
    local btnY = y + (panelH - btnSize) * 0.5
    return {
        panel = { x = x, y = y, w = panelW, h = panelH },
        minus = { id = "wager_down", x = x + pad, y = btnY, w = btnSize, h = btnSize },
        plus = { id = "wager_up", x = x + panelW - pad - btnSize, y = btnY, w = btnSize, h = btnSize },
        text = { x = x + pad + btnSize + 6, y = y + pad, w = panelW - 2*pad - 2*btnSize - 12, h = panelH - pad * 2 },
    }
end

local function buildResult(mode, message, messageTimer, perkOptions)
    return {
        mode = mode,
        message = message,
        messageTimer = messageTimer,
        perkOptions = perkOptions,
    }
end

---------------------------------------------------------------------------
-- Hand value helpers
---------------------------------------------------------------------------
local function handValue(hand)
    local value = 0
    local aces = 0
    for _, card in ipairs(hand) do
        if card.rank == "A" then
            aces = aces + 1
            value = value + 11
        elseif card.rank == "J" or card.rank == "Q" or card.rank == "K" then
            value = value + 10
        else
            value = value + tonumber(card.rank)
        end
    end
    while value > 21 and aces > 0 do
        value = value - 10
        aces = aces - 1
    end
    local soft = aces > 0
    return value, soft
end

---------------------------------------------------------------------------
-- Resolve reward (perk integration)
---------------------------------------------------------------------------
local function resolveReward(self, player, dealAgain)
    local reward = self:getReward()
    local add = reward.gold
    if self.payoutGoldApplied then
        add = 0
    end
    player.gold = player.gold + add
    if reward.perkRarity == "rare" or reward.anyWin then
        self.returnToBlackjack = dealAgain and true or false
        return buildResult("perk_selection", nil, nil, Perks.rollPerks(3, player.stats.luck))
    end
    self.returnToBlackjack = false
    if dealAgain then
        self:beginBetting()
        return buildResult("blackjack")
    end
    return buildResult("main")
end

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------
function Blackjack.new()
    local self = setmetatable({}, Blackjack)
    self.deck = {}
    self.dealerHand = {}
    self.hands = {}
    self.activeHand = 1
    self.state = "betting" -- betting, playing, dealer_turn, result
    self.wager = MIN_BET
    self.minBet = MIN_BET
    self.betStep = BET_STEP
    self.splitCount = 0
    self.result = nil
    self.resultMessage = ""
    self.payout = 0
    self.anyWin = false
    self.anyBlackjack = false
    self.cardSprites = {}
    self.backSprite = nil
    self.cardNativeW = nil
    self.cardNativeH = nil
    self.hoveredButton = nil
    self.lastButtonsY = nil
    self.returnToBlackjack = false
    self.animating = false
    self.timer = Timer.new()
    self.screenW = 1280
    self.screenH = 720
    self._player = nil
    self.payoutGoldApplied = false
    self.payoutScheduledAmount = nil
    self.pendingFloorGold = nil
    BlackjackVisuals.load()
    return self
end

---------------------------------------------------------------------------
-- Deck
---------------------------------------------------------------------------
function Blackjack:buildDeck()
    self.deck = {}
    for _, suit in ipairs(SUITS) do
        for _, rank in ipairs(RANKS) do
            table.insert(self.deck, {suit = suit, rank = rank})
        end
    end
    for i = #self.deck, 2, -1 do
        local j = math.random(i)
        self.deck[i], self.deck[j] = self.deck[j], self.deck[i]
    end
end

function Blackjack:drawCard()
    return table.remove(self.deck)
end

---------------------------------------------------------------------------
-- Hand value display
---------------------------------------------------------------------------
function Blackjack:handValue(hand)
    return handValue(hand)
end

function Blackjack:displayValue(hand)
    local value, soft = handValue(hand)
    if not soft then
        return tostring(value)
    end
    return string.format("%d/%d", value - 10, value)
end

---------------------------------------------------------------------------
-- Animation helpers
---------------------------------------------------------------------------
local function slideCard(self, card, duration, onDone)
    duration = duration or DEAL_SLIDE_TIME
    self.timer:tween(duration, card, {x = card.targetX, y = card.targetY}, "out-cubic", onDone)
end

local function flipCard(self, card, onDone)
    self.timer:tween(FLIP_HALF_TIME, card, {scaleX = 0}, "in-quad", function()
        card.faceUp = not card.faceUp
        self.timer:tween(FLIP_HALF_TIME, card, {scaleX = 1}, "out-quad", onDone)
    end)
end

-- Card row Y positions (must match draw(): headers are drawn above these rows)
local ROW_DEALER_CARDS_Y = 175
-- Minimum Y for first player card row; actual row is max(this, below dealer section + gap)
local ROW_HAND_FIRST_Y = 370
local HAND_ROW_SPACING = 155
local SECTION_GAP_AFTER_DEALER = 36

local function handRowY(firstHandY, hi)
    local y = firstHandY
    for i = 2, hi do
        y = y + HAND_ROW_SPACING
    end
    return y
end

--- Vertical position of first player card row: clears dealer total / cards so labels never overlap.
local function computeFirstHandRowY(self, screenW)
    screenW = screenW or self.screenW or GAME_WIDTH or 1280
    local lh = self._lineHForLayout or 20
    local dealerY = ROW_DEALER_CARDS_Y
    local dc = math.max(2, #self.dealerHand)
    local dealerCardH = cardDrawHeight(self, screenW * 0.9, nil, dc)
    local dealerValueY = dealerY + dealerCardH + 6
    local dealerBlockBottom
    if self.state == "playing" then
        -- No dealer total shown — leave margin under card row
        dealerBlockBottom = dealerY + dealerCardH + 6 + 10
    else
        dealerBlockBottom = dealerValueY + lh + 16
    end
    return math.max(ROW_HAND_FIRST_Y, dealerBlockBottom + SECTION_GAP_AFTER_DEALER)
end

local function recalcAllTargets(self)
    local screenW = self.screenW or GAME_WIDTH or 1280
    local centerX = screenW * 0.5
    local maxW = screenW * 0.9

    local firstHandY = computeFirstHandRowY(self, screenW)
    self._layoutFirstHandY = firstHandY

    local dealerY = ROW_DEALER_CARDS_Y
    if #self.dealerHand > 0 then
        computeCardTargets(self, self.dealerHand, centerX, dealerY, maxW, nil)
    end

    for hi, hand in ipairs(self.hands) do
        local handY = handRowY(firstHandY, hi)
        if #hand.cards > 0 then
            computeCardTargets(self, hand.cards, centerX, handY, maxW, nil)
        end
    end
end

---------------------------------------------------------------------------
-- Reset / Betting
---------------------------------------------------------------------------
local function newHand(wager, card)
    return {
        cards = { card },
        wager = wager,
        done = false,
        busted = false,
        doubled = false,
        isSplit = false,
        splitAces = false,
        isBlackjack = false,
        result = nil,
    }
end

function Blackjack:resetRound()
    self.deck = {}
    self.dealerHand = {}
    self.hands = {}
    self.activeHand = 1
    self.splitCount = 0
    self.result = nil
    self.resultMessage = ""
    self.payout = 0
    self.anyWin = false
    self.anyBlackjack = false
    self.payoutGoldApplied = false
    self.payoutScheduledAmount = nil
    self.timer:clear()
    self.animating = false
    CasinoFx.clear()
end

function Blackjack:beginBetting()
    self:resetRound()
    self.state = "betting"
    self.hoveredButton = nil
    self.lastButtonsY = nil
    if not self.wager or self.wager < self.minBet then
        self.wager = self.minBet
    end
end

function Blackjack:setWager(amount, maxGold)
    local w = math.floor(tonumber(amount) or self.minBet)
    w = math.max(self.minBet, w)
    if maxGold then
        w = math.min(w, math.floor(maxGold))
    end
    self.wager = w
    return w
end

function Blackjack:adjustWager(delta, maxGold)
    return self:setWager((self.wager or self.minBet) + delta, maxGold)
end

--- Fly coins + delay, then queue gold as saloon floor pickups (see resolveReward; no instant wallet credit).
function Blackjack:schedulePayoutGold(amount)
    if amount <= 0 then return end
    local w = self.screenW or 1280
    local h = self.screenH or 720
    self.payoutGoldApplied = false
    self.payoutScheduledAmount = amount
    CasinoFx.spawnGoldRain(w * 0.5, h * 0.48, {
        count = 80,
        spreadX = w * 0.85,
        spawnYMin = -120,
        spawnYMax = h * 0.14,
    })
    self.timer:after(1.72, function()
        self.payoutGoldApplied = true
        self.pendingFloorGold = (self.pendingFloorGold or 0) + (self.payoutScheduledAmount or 0)
        self.payoutScheduledAmount = nil
    end)
end

function Blackjack:currentHand()
    return self.hands[self.activeHand]
end

---------------------------------------------------------------------------
-- Deal (animated)
---------------------------------------------------------------------------
function Blackjack:deal(wager)
    self:resetRound()
    self:buildDeck()
    self.wager = wager
    self.animating = true
    self.state = "playing"
    self.hoveredButton = nil
    self.lastButtonsY = nil

    -- Ensure sprites are loaded for layout calc
    getBackSprite(self)

    -- Draw 4 cards from deck
    local raw = {}
    for _ = 1, 4 do
        raw[#raw + 1] = self:drawCard()
    end

    -- Create card objects: player gets [1],[3], dealer gets [2],[4]
    local pCard1 = newCardObj(raw[1].suit, raw[1].rank, true)
    local dCard1 = newCardObj(raw[2].suit, raw[2].rank, true)
    local pCard2 = newCardObj(raw[3].suit, raw[3].rank, true)
    local dCard2 = newCardObj(raw[4].suit, raw[4].rank, false) -- face down

    local hand = {
        cards = { pCard1, pCard2 },
        wager = wager,
        done = false,
        busted = false,
        doubled = false,
        isSplit = false,
        splitAces = false,
        isBlackjack = false,
        result = nil,
    }

    self.dealerHand = { dCard1, dCard2 }
    self.hands = { hand }
    self.activeHand = 1

    -- Compute target positions
    recalcAllTargets(self)

    -- Trigger dealer dealing animation
    BlackjackVisuals.setDealerAnim("dealing")

    -- Animate dealing sequence
    local dealOrder = { pCard1, dCard1, pCard2, dCard2 }
    sfxRandom("card_fan", 2)

    self.timer:script(function(wait)
        for i, card in ipairs(dealOrder) do
            sfxRandom("card_slide", 8)
            slideCard(self, card, DEAL_SLIDE_TIME)
            wait(DEAL_SLIDE_TIME + DEAL_GAP_TIME)
        end

        -- Check for immediate blackjack
        local playerVal = handValue(hand.cards)
        local dealerVal = handValue(self.dealerHand)
        local playerBJ = playerVal == 21 and #hand.cards == 2
        local dealerBJ = dealerVal == 21 and #self.dealerHand == 2

        if playerBJ or dealerBJ then
            -- Reveal dealer card
            sfxRandom("card_shove", 4)
            flipCard(self, dCard2)
            wait(FLIP_HALF_TIME * 2 + 0.1)

            self.state = "result"
            if playerBJ and dealerBJ then
                hand.result = "push"
                self.result = "push"
                self.resultMessage = "Push. Both blackjack."
                self.payout = hand.wager
                CasinoFx.spawnFloat(self.screenW * 0.5, 340, "PUSH", {1, 0.9, 0.4})
            elseif playerBJ then
                hand.isBlackjack = true
                hand.result = "blackjack"
                self.result = "blackjack"
                self.resultMessage = "BLACKJACK!"
                self.payout = math.floor(hand.wager * 2.5)
                self.anyWin = true
                self.anyBlackjack = true
                CasinoFx.spawnFloat(self.screenW * 0.5, 300, "BLACKJACK!", {1, 0.85, 0.2}, {scale = 1.4, life = 2.0})
                sfxRandom("chips_collide", 4)
            else
                hand.result = "lose"
                self.result = "lose"
                self.resultMessage = "Dealer blackjack."
                CasinoFx.spawnFloat(self.screenW * 0.5, 340, "DEALER BLACKJACK", {1, 0.3, 0.3})
                CasinoFx.startShake(4, 0.2)
            end
        end

        if self.payout > 0 then
            self:schedulePayoutGold(self.payout)
        end

        self.animating = false
    end)
end

---------------------------------------------------------------------------
-- Soft 17 check
---------------------------------------------------------------------------
function Blackjack:isSoft17(hand)
    local v, soft = handValue(hand)
    return v == 17 and soft
end

---------------------------------------------------------------------------
-- Advance to next hand or finish dealer
---------------------------------------------------------------------------
function Blackjack:advanceHand()
    local nextIndex = self.activeHand + 1
    while nextIndex <= #self.hands and self.hands[nextIndex].done do
        nextIndex = nextIndex + 1
    end
    if nextIndex <= #self.hands then
        self.activeHand = nextIndex
        return
    end
    self:finishDealer()
end

---------------------------------------------------------------------------
-- Animated dealer turn
---------------------------------------------------------------------------
function Blackjack:finishDealer()
    self.state = "dealer_turn"
    self.animating = true

    local anyLive = false
    for _, h in ipairs(self.hands) do
        if not h.busted then
            anyLive = true
            break
        end
    end

    self.timer:script(function(wait)
        -- Flip hidden card
        local dCard2 = self.dealerHand[2]
        if dCard2 and not dCard2.faceUp then
            sfxRandom("card_shove", 4)
            flipCard(self, dCard2)
            wait(FLIP_HALF_TIME * 2 + 0.15)
        end

        -- Dealer draws
        if anyLive then
            while true do
                local dv, soft = handValue(self.dealerHand)
                if dv < 17 then
                    wait(DEALER_THINK_TIME)
                    BlackjackVisuals.setDealerAnim("dealing")
                    local raw = self:drawCard()
                    local card = newCardObj(raw.suit, raw.rank, true)
                    table.insert(self.dealerHand, card)
                    recalcAllTargets(self)
                    sfxRandom("card_slide", 8)
                    slideCard(self, card, DEAL_SLIDE_TIME)
                    wait(DEAL_SLIDE_TIME + 0.1)

                    if handValue(self.dealerHand) > 21 then
                        CasinoFx.startShake(3, 0.15)
                        wait(0.15)
                    end
                else
                    break
                end
            end
        end

        -- Resolve all hands
        local dealerVal = handValue(self.dealerHand)
        local dealerBust = dealerVal > 21
        local payout = 0
        local anyWin = false
        local anyBlackjack = false

        for _, h in ipairs(self.hands) do
            if h.result == "blackjack" then
                payout = payout + math.floor(h.wager * 2.5)
                anyWin = true
                anyBlackjack = true
            elseif h.busted then
                h.result = "bust"
            else
                local hv = handValue(h.cards)
                if dealerBust then
                    h.result = "win"
                    payout = payout + h.wager * 2
                    anyWin = true
                elseif hv > dealerVal then
                    h.result = "win"
                    payout = payout + h.wager * 2
                    anyWin = true
                elseif hv == dealerVal then
                    h.result = "push"
                    payout = payout + h.wager
                else
                    h.result = "lose"
                end
            end
        end

        self.payout = payout
        self.anyWin = anyWin
        self.anyBlackjack = anyBlackjack
        self.state = "result"

        if anyWin then
            self.result = "win"
            self.resultMessage = "Payout: $" .. payout
            CasinoFx.spawnFloat(self.screenW * 0.5, 300, "+$" .. payout, {0.2, 1, 0.2}, {life = 1.5})
            sfxRandom("chips_collide", 4)
        elseif payout > 0 then
            self.result = "push"
            self.resultMessage = "Push. Payout: $" .. payout
            CasinoFx.spawnFloat(self.screenW * 0.5, 340, "PUSH", {1, 0.9, 0.4})
        else
            self.result = "lose"
            self.resultMessage = "No wins."
            CasinoFx.startShake(3, 0.2)
            CasinoFx.spawnFloat(self.screenW * 0.5, 340, "LOSE", {1, 0.3, 0.3})
        end

        if payout > 0 then
            self:schedulePayoutGold(payout)
        end

        wait(RESULT_PAUSE_TIME)
        self.animating = false
    end)
end

---------------------------------------------------------------------------
-- Player actions (animated)
---------------------------------------------------------------------------
function Blackjack:hit()
    if self.state ~= "playing" then return end
    local hand = self:currentHand()
    if not hand or hand.done or hand.busted or hand.splitAces then return end

    self.animating = true
    BlackjackVisuals.setDealerAnim("dealing")
    local raw = self:drawCard()
    local card = newCardObj(raw.suit, raw.rank, true)
    table.insert(hand.cards, card)
    recalcAllTargets(self)

    sfxRandom("card_place", 4)
    self.timer:script(function(wait)
        slideCard(self, card, DEAL_SLIDE_TIME)
        wait(DEAL_SLIDE_TIME + 0.05)

        local val = handValue(hand.cards)
        if val > 21 then
            hand.busted = true
            hand.done = true
            hand.result = "bust"
            CasinoFx.startShake(4, 0.2)
            CasinoFx.spawnFloat(card.targetX + 40, card.targetY, "BUST", {1, 0.3, 0.3})
            wait(0.25)
            self.animating = false
            self:advanceHand()
        elseif val == 21 then
            hand.done = true
            self.animating = false
            self:advanceHand()
        else
            self.animating = false
        end
    end)
end

function Blackjack:stand()
    if self.state ~= "playing" then return end
    local hand = self:currentHand()
    if not hand or hand.done then return end
    hand.done = true
    self:advanceHand()
end

function Blackjack:canDouble(bankroll)
    if self.state ~= "playing" then return false end
    local hand = self:currentHand()
    if not hand or hand.done or hand.busted then return false end
    if hand.doubled or #hand.cards ~= 2 then return false end
    if hand.splitAces then return false end
    return bankroll >= hand.wager
end

function Blackjack:doubleDown(bankroll)
    if not self:canDouble(bankroll) then return nil end
    local hand = self:currentHand()
    local cost = hand.wager
    hand.wager = hand.wager * 2
    hand.doubled = true

    self.animating = true
    BlackjackVisuals.setDealerAnim("dealing")
    local raw = self:drawCard()
    local card = newCardObj(raw.suit, raw.rank, true)
    table.insert(hand.cards, card)
    recalcAllTargets(self)

    sfxRandom("card_slide", 8)
    sfxRandom("chips_stack", 6)
    CasinoFx.spawnFloat(self.screenW * 0.5, 380, "DOUBLE DOWN", {1, 0.85, 0.2}, {life = 0.8, vy = -20})

    self.timer:script(function(wait)
        slideCard(self, card, DEAL_SLIDE_TIME)
        wait(DEAL_SLIDE_TIME + 0.1)

        local val = handValue(hand.cards)
        if val > 21 then
            hand.busted = true
            hand.result = "bust"
            CasinoFx.startShake(4, 0.2)
            CasinoFx.spawnFloat(card.targetX + 40, card.targetY, "BUST", {1, 0.3, 0.3})
            wait(0.2)
        end
        hand.done = true
        self.animating = false
        self:advanceHand()
    end)

    return cost
end

function Blackjack:canSplit(bankroll)
    if self.state ~= "playing" then return false end
    local hand = self:currentHand()
    if not hand or hand.done or hand.busted then return false end
    if #hand.cards ~= 2 then return false end
    if self.splitCount >= 1 then return false end
    local r1 = hand.cards[1].rank
    local r2 = hand.cards[2].rank
    if r1 ~= r2 then return false end
    return bankroll >= hand.wager
end

function Blackjack:split(bankroll)
    if not self:canSplit(bankroll) then return nil end
    local hand = self:currentHand()
    local cost = hand.wager
    self.splitCount = self.splitCount + 1

    local card1 = hand.cards[1]
    local card2 = hand.cards[2]
    local splitAces = card1.rank == "A"

    -- Draw new cards for each hand
    local raw1 = self:drawCard()
    local raw2 = self:drawCard()
    local newCard1 = newCardObj(raw1.suit, raw1.rank, true)
    local newCard2 = newCardObj(raw2.suit, raw2.rank, true)

    local h1 = {
        cards = { card1, newCard1 },
        wager = hand.wager,
        done = false, busted = false, doubled = false,
        isSplit = true, splitAces = splitAces, isBlackjack = false, result = nil,
    }
    local h2 = {
        cards = { card2, newCard2 },
        wager = hand.wager,
        done = false, busted = false, doubled = false,
        isSplit = true, splitAces = splitAces, isBlackjack = false, result = nil,
    }

    table.remove(self.hands, self.activeHand)
    table.insert(self.hands, self.activeHand, h2)
    table.insert(self.hands, self.activeHand, h1)

    recalcAllTargets(self)

    -- Animate split
    self.animating = true
    sfxRandom("card_shove", 4)
    CasinoFx.spawnFloat(self.screenW * 0.5, 380, "SPLIT", {1, 0.85, 0.2}, {life = 0.8, vy = -20})

    self.timer:script(function(wait)
        -- Slide existing cards to new positions
        slideCard(self, card1, 0.2)
        slideCard(self, card2, 0.2)
        wait(0.25)

        -- Deal new cards
        sfxRandom("card_slide", 8)
        slideCard(self, newCard1, DEAL_SLIDE_TIME)
        wait(DEAL_SLIDE_TIME + DEAL_GAP_TIME)
        sfxRandom("card_slide", 8)
        slideCard(self, newCard2, DEAL_SLIDE_TIME)
        wait(DEAL_SLIDE_TIME + 0.1)

        if splitAces then
            h1.done = true
            h2.done = true
            self.animating = false
            self:advanceHand()
        else
            self.animating = false
        end
    end)

    return cost
end

---------------------------------------------------------------------------
-- Reward
---------------------------------------------------------------------------
function Blackjack:getReward()
    return {
        gold = self.payout or 0,
        perkRarity = self.anyBlackjack and "rare" or nil,
        anyWin = self.anyWin and true or false,
    }
end

function Blackjack:completePerkSelection()
    if self.returnToBlackjack then
        self.returnToBlackjack = false
        self:beginBetting()
        return "blackjack"
    end
    return "main"
end

function Blackjack:enterTable(playerGold)
    if playerGold < self.minBet then
        return buildResult(nil, "Need at least $" .. self.minBet .. " to play blackjack.", 2)
    end
    self:beginBetting()
    return buildResult("blackjack")
end

---------------------------------------------------------------------------
-- Update (call every frame)
---------------------------------------------------------------------------
function Blackjack:update(dt, player)
    self._player = player
    self.timer:update(dt)
    CasinoFx.update(dt)
    BlackjackVisuals.update(dt)
end

---------------------------------------------------------------------------
-- Hover
---------------------------------------------------------------------------
function Blackjack:updateHover(mx, my, screenW, screenH)
    self.screenW = screenW
    self.screenH = screenH
    self.hoveredButton = self:hitButton(mx, my, screenW, screenH)
    return self.hoveredButton
end

---------------------------------------------------------------------------
-- Draw
---------------------------------------------------------------------------
function Blackjack:drawButtons(screenW, screenH, baseY, fonts, labels, wagerControl)
    self.lastButtonsY = baseY
    local rects = blackjackButtonLayout(screenW, screenH, labels, baseY)
    local buttonY = rects and rects[1] and rects[1].y or nil
    local wagerRects = blackjackWagerLayout(screenW, screenH, buttonY)
    if wagerRects and wagerControl then
        local enabled = wagerControl.enabled
        local panel = wagerRects.panel
        love.graphics.setColor(0.12, 0.08, 0.06, enabled and 0.75 or 0.45)
        love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h, 6, 6)
        love.graphics.setColor(0.85, 0.65, 0.35, enabled and 0.65 or 0.35)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", panel.x, panel.y, panel.w, panel.h, 6, 6)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 0.95, 0.82, enabled and 1 or 0.6)
        love.graphics.setFont(fonts.body)
        local amt = "$" .. wagerControl.wager
        love.graphics.printf(amt, wagerRects.text.x, panel.y + 6, wagerRects.text.w, "center")
        local chipCx = wagerRects.text.x + wagerRects.text.w * 0.5
        CasinoFx.drawChipStack(chipCx, panel.y + panel.h - 4, wagerControl.wager, 5)

        BlackjackVisuals.drawSmallButton(wagerRects.minus, self.hoveredButton == "wager_down", enabled, "−", fonts.card or fonts.body)
        BlackjackVisuals.drawSmallButton(wagerRects.plus, self.hoveredButton == "wager_up", enabled, "+", fonts.card or fonts.body)
    end

    if not rects then return end
    for _, r in ipairs(rects) do
        local hov = self.hoveredButton == r.id
        local disabled = self.animating
        BlackjackVisuals.drawButton(r, hov, disabled, r.label, fonts.card or fonts.body)
    end

    if self.state == "result" and self.resultMessage and self.resultMessage ~= "" then
        local resultColor = {1, 1, 1}
        if self.result == "win" or self.result == "blackjack" then
            resultColor = {0.2, 1, 0.2}
        elseif self.result == "push" then
            resultColor = {1, 0.9, 0.4}
        elseif self.result == "lose" or self.result == "bust" then
            resultColor = {1, 0.3, 0.3}
        end
        love.graphics.setColor(resultColor[1], resultColor[2], resultColor[3])
        love.graphics.setFont(fonts.body)
        local lastRect = rects[#rects]
        local msgX = lastRect.x + lastRect.w + 24
        local msgY = lastRect.y + 14
        local msgW = math.max(0, screenW - msgX - 16)
        love.graphics.printf(self.resultMessage, msgX, msgY, msgW, "left")
    end
end

function Blackjack:draw(screenW, screenH, fonts)
    self.screenW = screenW
    self.screenH = screenH

    -- Apply screen shake
    local shakeX, shakeY = CasinoFx.getShakeOffset()
    love.graphics.push()
    love.graphics.translate(shakeX, shakeY)

    -- Draw table first, then dealer on top (cropped at stomach so he looks behind the table)
    local tableRect = BlackjackVisuals.drawTable(screenW, screenH)
    BlackjackVisuals.drawDealer(screenW, tableRect)

    love.graphics.setFont(fonts.card)
    local lineH = fonts.card:getHeight()
    self._lineHForLayout = lineH
    getBackSprite(self)

    local barTop = screenH * 0.85
    local layoutBottom = barTop - 8

    -- Wager display (positioned at bottom of table area, not overlapping dealer)
    local wagerY = (tableRect and (tableRect.y + tableRect.h * 0.35)) or 160
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.printf("Wager: $" .. self.wager, 1, wagerY + 1, screenW, "center")
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf("Wager: $" .. self.wager, 0, wagerY, screenW, "center")
    local y = wagerY + 36

    if self.state == "betting" then
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.printf("A/D or -/+ to change bet  |  ENTER to deal  |  ESC to leave", 1, y + 1, screenW, "center")
        love.graphics.setColor(0.9, 0.8, 0.6)
        love.graphics.printf("A/D or -/+ to change bet  |  ENTER to deal  |  ESC to leave", 0, y, screenW, "center")

        self:drawButtons(screenW, screenH, y + 12, fonts, self:getButtonLabels(), {
            wager = self.wager,
            enabled = true,
        })
        love.graphics.pop()
        CasinoFx.draw()
        return
    end

    -- Keep card targets in sync with window size (horizontal layout depends on screenW)
    recalcAllTargets(self)

    -- Dealer card section
    local dealerY = ROW_DEALER_CARDS_Y

    drawAnimatedCardRow(self, self.dealerHand)

    local dealerCardH = cardDrawHeight(self, screenW * 0.9, nil, math.max(2, #self.dealerHand))
    local dealerValueY = dealerY + dealerCardH + 6
    if self.state ~= "playing" then
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.printf("(" .. self:displayValue(self.dealerHand) .. ")", 1, dealerValueY + 1, screenW, "center")
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("(" .. self:displayValue(self.dealerHand) .. ")", 0, dealerValueY, screenW, "center")
        y = dealerValueY + lineH + 10
    else
        y = dealerValueY + lineH + 10
    end

    local firstHandY = self._layoutFirstHandY or computeFirstHandRowY(self, screenW)
    local dealerTextBottom
    if self.state == "playing" then
        dealerTextBottom = dealerY + dealerCardH + 6 + 6
    else
        dealerTextBottom = dealerValueY + lineH
    end
    -- Keep section title clearly below dealer score / cards (fixes overlap on result screen)
    local yourHandsY = math.max(firstHandY - 2 * lineH - 30, dealerTextBottom + 8)

    for i, hand in ipairs(self.hands) do
        local rowY = handRowY(firstHandY, i)
        local labelY = rowY - lineH - 14
        local prefix = "  "
        if self.state == "playing" and i == self.activeHand then
            prefix = "> "
            -- Subtle glow behind active hand
            local firstCard = hand.cards[1]
            if firstCard and firstCard.targetX then
                local lastCard = hand.cards[#hand.cards]
                local glowX = firstCard.targetX - 8
                local glowW = (lastCard.targetX + (self.cardNativeW or 70) * (firstCard.drawScale or 1)) - firstCard.targetX + 16
                local glowY = firstCard.targetY - 4
                local glowH = (self.cardNativeH or 100) * (firstCard.drawScale or 1) + 8
                love.graphics.setColor(1, 0.85, 0.2, 0.08)
                love.graphics.rectangle("fill", glowX, glowY, glowW, glowH, 8, 8)
            end
        end
        local label = prefix .. "Hand " .. i .. "  ($" .. hand.wager .. ")"
        if hand.doubled then
            label = label .. "  ·  Doubled"
        elseif hand.isSplit then
            label = label .. "  ·  Split hand"
        end
        if self.state == "result" and hand.result then
            label = label .. "  - " .. string.upper(hand.result)
        end
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.printf(label, 1, labelY + 1, screenW, "center")
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(label, 0, labelY, screenW, "center")

        drawAnimatedCardRow(self, hand.cards)

        local handCardH = cardDrawHeight(self, screenW * 0.9, nil, math.max(2, #hand.cards))
        local handValueY = rowY + handCardH + 8
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.printf("(" .. self:displayValue(hand.cards) .. ")", 1, handValueY + 1, screenW, "center")
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("(" .. self:displayValue(hand.cards) .. ")", 0, handValueY, screenW, "center")
        y = handValueY + lineH + 10
    end

    y = y + 12
    if self.state == "playing" then
        self:drawButtons(screenW, screenH, y + 12, fonts, self:getButtonLabels(), {
            wager = self.wager,
            enabled = false,
        })
    elseif self.state == "result" then
        self:drawButtons(screenW, screenH, y + 12, fonts, self:getButtonLabels(), {
            wager = self.wager,
            enabled = true,
        })
    elseif self.state == "dealer_turn" then
        -- Show "Dealer's turn..." text
        love.graphics.setColor(1, 0.85, 0.2, 0.8)
        love.graphics.printf("Dealer's turn...", 0, screenH * 0.88, screenW, "center")
    end

    love.graphics.pop()

    -- Draw effects (not affected by shake)
    CasinoFx.draw()
end

---------------------------------------------------------------------------
-- Hit testing
---------------------------------------------------------------------------
function Blackjack:hitButton(mx, my, screenW, screenH)
    local labels = self:getButtonLabels()
    if not labels then return nil end
    local rects = blackjackButtonLayout(screenW, screenH, labels, self.lastButtonsY)
    local buttonY = rects and rects[1] and rects[1].y or nil
    local wagerRects = blackjackWagerLayout(screenW, screenH, buttonY)
    local wagerEnabled = self.state == "betting" or self.state == "result"
    if wagerRects and wagerEnabled then
        if mx >= wagerRects.plus.x and mx <= wagerRects.plus.x + wagerRects.plus.w
            and my >= wagerRects.plus.y and my <= wagerRects.plus.y + wagerRects.plus.h then
            return "wager_up"
        end
        if mx >= wagerRects.minus.x and mx <= wagerRects.minus.x + wagerRects.minus.w
            and my >= wagerRects.minus.y and my <= wagerRects.minus.y + wagerRects.minus.h then
            return "wager_down"
        end
    end
    if not rects then return nil end
    for _, r in ipairs(rects) do
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            return r.id
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Input handling
---------------------------------------------------------------------------
function Blackjack:handleAction(action, player)
    if self.animating then return nil end

    if self.state == "betting" then
        if action == "wager_down" then
            self:adjustWager(-self.betStep, player.gold)
            sfxRandom("chips_handle", 6)
        elseif action == "wager_up" then
            self:adjustWager(self.betStep, player.gold)
            sfxRandom("chips_handle", 6)
        elseif action == "deal" then
            if self.wager >= self.minBet and player.gold >= self.wager then
                player.gold = player.gold - self.wager
                self:deal(self.wager)
            else
                return buildResult(nil, "Not enough gold to bet that much!", 2)
            end
        elseif action == "leave" then
            return buildResult("main")
        end
    elseif self.state == "playing" then
        if action == "hit" then
            self:hit()
        elseif action == "stand" then
            self:stand()
        elseif action == "double" then
            local cost = self:doubleDown(player.gold)
            if cost then
                player.gold = player.gold - cost
            else
                return buildResult(nil, "Cannot double.", 1.2)
            end
        elseif action == "split" then
            local cost = self:split(player.gold)
            if cost then
                player.gold = player.gold - cost
            else
                return buildResult(nil, "Cannot split.", 1.2)
            end
        end
    elseif self.state == "result" then
        if action == "wager_down" then
            self:adjustWager(-self.betStep, player.gold)
            sfxRandom("chips_handle", 6)
        elseif action == "wager_up" then
            self:adjustWager(self.betStep, player.gold)
            sfxRandom("chips_handle", 6)
        elseif action == "continue" then
            local reward = self:getReward()
            if reward.gold > 0 and not self.payoutGoldApplied then
                return nil
            end
            return resolveReward(self, player, false)
        elseif action == "deal_again" then
            local reward = self:getReward()
            if reward.gold > 0 and not self.payoutGoldApplied then
                return nil
            end
            return resolveReward(self, player, true)
        end
    end
    return nil
end

function Blackjack:handleKey(key, player)
    if self.animating then return nil end

    if self.state == "betting" then
        if key == "left" or key == "a" or key == "-" or key == "kp-" then
            self:adjustWager(-self.betStep, player.gold)
            sfxRandom("chips_handle", 6)
        elseif key == "right" or key == "d" or key == "=" or key == "kp+" then
            self:adjustWager(self.betStep, player.gold)
            sfxRandom("chips_handle", 6)
        elseif key == "return" or key == "space" then
            return self:handleAction("deal", player)
        elseif key == "escape" or key == "backspace" then
            return self:handleAction("leave", player)
        end
    elseif self.state == "playing" then
        if key == "h" then
            return self:handleAction("hit", player)
        elseif key == "s" then
            return self:handleAction("stand", player)
        elseif key == "d" then
            return self:handleAction("double", player)
        elseif key == "p" then
            return self:handleAction("split", player)
        end
    elseif self.state == "result" then
        if key == "return" or key == "space" then
            local reward = self:getReward()
            if reward.gold > 0 and not self.payoutGoldApplied then
                return nil
            end
            return self:handleAction("continue", player)
        elseif key == "d" then
            local reward = self:getReward()
            if reward.gold > 0 and not self.payoutGoldApplied then
                return nil
            end
            return self:handleAction("deal_again", player)
        elseif key == "left" or key == "a" or key == "-" or key == "kp-" then
            self:adjustWager(-self.betStep, player.gold)
            sfxRandom("chips_handle", 6)
        elseif key == "right" or key == "d" or key == "=" or key == "kp+" then
            self:adjustWager(self.betStep, player.gold)
            sfxRandom("chips_handle", 6)
        end
    end
    return nil
end

function Blackjack:handleMousePressed(mx, my, button, screenW, screenH, player)
    if button ~= 1 then return nil end
    if self.animating then return nil end
    local action = self:hitButton(mx, my, screenW, screenH)
    if not action then return nil end
    self.hoveredButton = action
    return self:handleAction(action, player)
end

function Blackjack.cardToString(card)
    return card.rank .. SUIT_SYMBOLS[card.suit]
end

return Blackjack
