local Perks = require("src.data.perks")
local Sfx = require("src.systems.sfx")

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

local function drawCardRow(self, cards, centerX, y, faceDownIndex, maxWidth, maxHeight)
    if not cards or #cards == 0 then return y end
    local scale, gap, drawW, drawH = cardLayout(self, maxWidth, maxHeight, #cards)
    local totalW = #cards * drawW + (#cards - 1) * gap
    local x = centerX - totalW * 0.5
    for i, card in ipairs(cards) do
        local img
        if faceDownIndex and i == faceDownIndex then
            img = getBackSprite(self)
        else
            img = getCardSprite(self, card.suit, card.rank)
        end
        if not self.cardNativeW then
            self.cardNativeW = img:getWidth()
            self.cardNativeH = img:getHeight()
            scale, gap, drawW, drawH = cardLayout(self, maxWidth, maxHeight, #cards)
            totalW = #cards * drawW + (#cards - 1) * gap
            x = centerX - totalW * 0.5
        end
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, x, y, 0, scale, scale)
        x = x + drawW + gap
    end
    return y + drawH
end

local function buttonLabelsForState(state)
    if state == "betting" then
        return {
            { id = "deal", label = "Deal" },
            { id = "leave", label = "Back" },
        }
    elseif state == "playing" then
        return {
            { id = "hit", label = "Hit (H)" },
            { id = "stand", label = "Stand (S)" },
            { id = "double", label = "Double (D)" },
            { id = "split", label = "Split (P)" },
        }
    elseif state == "result" then
        return {
            { id = "continue", label = "Continue" },
            { id = "deal_again", label = "Deal Again (D)" },
        }
    end
    return nil
end

local function blackjackButtonLayout(screenW, screenH, labels, baseY)
    if not labels or #labels == 0 then return nil end
    local bw, bh = 210, 44
    local gap = 10
    local totalW = #labels * bw + (#labels - 1) * gap
    local x0 = (screenW - totalW) * 0.5
    local barTop = screenH * 0.85
    local barH = screenH * 0.15
    local y = barTop + (barH - bh) * 0.5
    if baseY then
        y = math.max(y, baseY)
    end
    local rects = {}
    for i, b in ipairs(labels) do
        rects[i] = { id = b.id, label = b.label, x = x0 + (i - 1) * (bw + gap), y = y, w = bw, h = bh }
    end
    return rects
end

local function blackjackWagerLayout(rowRect)
    if not rowRect then return nil end
    local panelW, panelH = 180, rowRect.h
    local gap = 18
    local x = rowRect.x - panelW - gap
    local y = rowRect.y
    local pad = 4
    local btnGap = 4
    local btnW = 32
    local btnH = (panelH - pad * 2 - btnGap) * 0.5
    local btnX = x + panelW - pad - btnW
    local topBtnY = y + pad
    local bottomBtnY = topBtnY + btnH + btnGap
    return {
        panel = { x = x, y = y, w = panelW, h = panelH },
        plus = { id = "wager_up", x = btnX, y = topBtnY, w = btnW, h = btnH },
        minus = { id = "wager_down", x = btnX, y = bottomBtnY, w = btnW, h = btnH },
        text = { x = x + pad, y = y + pad, w = panelW - btnW - pad * 2 - 6, h = panelH - pad * 2 },
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

local function resolveReward(self, player, dealAgain)
    local reward = self:getReward()
    player.gold = player.gold + reward.gold
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
    return self
end

function Blackjack:buildDeck()
    self.deck = {}
    for _, suit in ipairs(SUITS) do
        for _, rank in ipairs(RANKS) do
            table.insert(self.deck, {suit = suit, rank = rank})
        end
    end
    -- Shuffle
    for i = #self.deck, 2, -1 do
        local j = math.random(i)
        self.deck[i], self.deck[j] = self.deck[j], self.deck[i]
    end
end

function Blackjack:drawCard()
    return table.remove(self.deck)
end

function Blackjack:handValue(hand)
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

function Blackjack:displayValue(hand)
    local value, soft = self:handValue(hand)
    if not soft then
        return tostring(value)
    end
    -- Soft hand: show both totals (e.g., 7/17)
    return string.format("%d/%d", value - 10, value)
end

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

function Blackjack:currentHand()
    return self.hands[self.activeHand]
end

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

function Blackjack:deal(wager)
    self:resetRound()
    self:buildDeck()
    self.wager = wager
    self.state = "playing"
    self.hoveredButton = nil
    self.lastButtonsY = nil

    local hand = {
        cards = {},
        wager = wager,
        done = false,
        busted = false,
        doubled = false,
        isSplit = false,
        splitAces = false,
        isBlackjack = false,
        result = nil,
    }

    table.insert(hand.cards, self:drawCard())
    table.insert(self.dealerHand, self:drawCard())
    table.insert(hand.cards, self:drawCard())
    table.insert(self.dealerHand, self:drawCard())

    self.hands = { hand }
    self.activeHand = 1

    local playerVal = handValue(hand.cards)
    local dealerVal = handValue(self.dealerHand)
    local playerBJ = playerVal == 21 and #hand.cards == 2
    local dealerBJ = dealerVal == 21 and #self.dealerHand == 2

    if playerBJ or dealerBJ then
        self.state = "result"
        if playerBJ and dealerBJ then
            hand.result = "push"
            self.result = "push"
            self.resultMessage = "Push. Both blackjack."
            self.payout = hand.wager
        elseif playerBJ then
            hand.isBlackjack = true
            hand.result = "blackjack"
            self.result = "blackjack"
            self.resultMessage = "BLACKJACK!"
            self.payout = math.floor(hand.wager * 2.5)
            self.anyWin = true
            self.anyBlackjack = true
        else
            hand.result = "lose"
            self.result = "lose"
            self.resultMessage = "Dealer blackjack."
            self.payout = 0
        end
    end
end

function Blackjack:isSoft17(hand)
    local v, soft = handValue(hand)
    return v == 17 and soft
end

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

function Blackjack:finishDealer()
    self.state = "dealer_turn"
    local anyLive = false
    for _, h in ipairs(self.hands) do
        if not h.busted then
            anyLive = true
            break
        end
    end

    if anyLive then
        while true do
            local dv, soft = handValue(self.dealerHand)
            if dv < 17 then
                table.insert(self.dealerHand, self:drawCard())
            elseif dv == 17 and soft then
                break
            else
                break
            end
        end
    end

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
    elseif payout > 0 then
        self.result = "push"
        self.resultMessage = "Push. Payout: $" .. payout
    else
        self.result = "lose"
        self.resultMessage = "No wins."
    end
end

function Blackjack:hit()
    if self.state ~= "playing" then return end
    local hand = self:currentHand()
    if not hand or hand.done or hand.busted or hand.splitAces then return end

    table.insert(hand.cards, self:drawCard())
    local val = handValue(hand.cards)
    if val > 21 then
        hand.busted = true
        hand.done = true
        hand.result = "bust"
        self:advanceHand()
    elseif val == 21 then
        hand.done = true
        self:advanceHand()
    end
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
    table.insert(hand.cards, self:drawCard())
    local val = handValue(hand.cards)
    if val > 21 then
        hand.busted = true
        hand.result = "bust"
    end
    hand.done = true
    self:advanceHand()
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

    local h1 = newHand(hand.wager, card1)
    local h2 = newHand(hand.wager, card2)
    h1.isSplit = true
    h2.isSplit = true
    h1.splitAces = splitAces
    h2.splitAces = splitAces

    table.remove(self.hands, self.activeHand)
    table.insert(self.hands, self.activeHand, h2)
    table.insert(self.hands, self.activeHand, h1)

    table.insert(h1.cards, self:drawCard())
    table.insert(h2.cards, self:drawCard())

    if splitAces then
        h1.done = true
        h2.done = true
        self:advanceHand()
    end

    return cost
end

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

function Blackjack:updateHover(mx, my, screenW, screenH)
    self.hoveredButton = self:hitButton(mx, my, screenW, screenH)
    return self.hoveredButton
end

function Blackjack:drawButtons(screenW, screenH, baseY, fonts, labels, wagerControl)
    self.lastButtonsY = baseY
    local rects = blackjackButtonLayout(screenW, screenH, labels, baseY)
    local firstRect = rects and rects[1] or nil
    local wagerRects = blackjackWagerLayout(firstRect)
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
        love.graphics.printf("Wager", wagerRects.text.x, panel.y + 6, wagerRects.text.w, "left")
        love.graphics.printf("$" .. wagerControl.wager, wagerRects.text.x, panel.y + 22, wagerRects.text.w, "left")

        local function drawWagerBtn(btn, label)
            local hov = self.hoveredButton == btn.id
            if hov then
                love.graphics.setColor(0.22, 0.14, 0.08, enabled and 0.9 or 0.45)
            else
                love.graphics.setColor(0.12, 0.08, 0.06, enabled and 0.75 or 0.35)
            end
            love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, 4, 4)
            love.graphics.setColor(0.85, 0.65, 0.35, hov and 1 or (enabled and 0.65 or 0.35))
            love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h, 4, 4)
            love.graphics.setColor(1, 0.95, 0.82, enabled and 1 or 0.6)
            local textY = btn.y + (btn.h - fonts.body:getHeight()) * 0.5 - 1
            love.graphics.printf(label, btn.x + 2, textY, btn.w - 4, "center")
        end

        drawWagerBtn(wagerRects.plus, "+")
        drawWagerBtn(wagerRects.minus, "-")
    end

    if not rects then return end
    for _, r in ipairs(rects) do
        local hov = self.hoveredButton == r.id
        if hov then
            love.graphics.setColor(0.22, 0.14, 0.08, 0.9)
        else
            love.graphics.setColor(0.12, 0.08, 0.06, 0.75)
        end
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6, 6)
        love.graphics.setColor(0.85, 0.65, 0.35, hov and 1 or 0.65)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 6, 6)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 0.95, 0.82)
        love.graphics.setFont(fonts.body)
        love.graphics.printf(r.label, r.x, r.y + 12, r.w, "center")
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
        local msgY = lastRect.y + 12
        local msgW = math.max(0, screenW - msgX - 16)
        love.graphics.printf(self.resultMessage, msgX, msgY, msgW, "left")
    end
end

function Blackjack:draw(screenW, screenH, fonts)
    local y = 130
    love.graphics.setFont(fonts.card)
    local lineH = fonts.card:getHeight()
    getBackSprite(self)

    local barTop = screenH * 0.85
    local layoutBottom = barTop - 8
    local rowH = {
        wager = 40,
        bettingHelp = 26,
        dealerLabel = lineH + 10,
        dealerValue = lineH + 6,
        handsHeader = lineH + 10,
        handLabel = lineH + 6,
        handValue = lineH + 4,
    }

    local handCount = #self.hands
    local maxHandCards = 2
    for _, hand in ipairs(self.hands) do
        maxHandCards = math.max(maxHandCards, #hand.cards)
    end
    local hasDealerValue = self.state ~= "playing"
    local fixedBase = rowH.wager + rowH.dealerLabel + rowH.handsHeader
        + (handCount * (rowH.handLabel + rowH.handValue))
        + (hasDealerValue and rowH.dealerValue or 0)
    local availableH = math.max(0, layoutBottom - y)
    local fixedScale = math.min(1, availableH / (fixedBase + 1))
    fixedScale = math.max(0.7, fixedScale)
    rowH.wager = rowH.wager * fixedScale
    rowH.dealerLabel = rowH.dealerLabel * fixedScale
    rowH.dealerValue = rowH.dealerValue * fixedScale
    rowH.handsHeader = rowH.handsHeader * fixedScale
    rowH.handLabel = rowH.handLabel * fixedScale
    rowH.handValue = rowH.handValue * fixedScale
    fixedBase = rowH.wager + rowH.dealerLabel + rowH.handsHeader
        + (handCount * (rowH.handLabel + rowH.handValue))
        + (hasDealerValue and rowH.dealerValue or 0)

    local cardsAvail = math.max(0, availableH - fixedBase)
    local dealerTargetH = cardDrawHeight(self, screenW * 0.9, nil, math.max(2, #self.dealerHand))
    local handTargetH = cardDrawHeight(self, screenW * 0.9, nil, maxHandCards)
    local totalTargetCardsH = dealerTargetH + (handCount * handTargetH)
    local cardHeightScale = totalTargetCardsH > 0 and math.min(1, cardsAvail / totalTargetCardsH) or 1
    local dealerCardH = dealerTargetH * cardHeightScale
    local handCardH = handCount > 0 and handTargetH * cardHeightScale or 0

    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf("Current wager: $" .. self.wager, 0, y, screenW, "center")
    y = y + rowH.wager

    if self.state == "betting" then
        love.graphics.setColor(0.9, 0.8, 0.6)
        love.graphics.printf("Use the wager control or A/D / -/+ to change bet (min $" .. self.minBet .. ")", 0, y, screenW, "center")
        y = y + rowH.bettingHelp
        love.graphics.printf("Press ENTER to deal, ESC to leave", 0, y, screenW, "center")
        self:drawButtons(screenW, screenH, y + 12, fonts, buttonLabelsForState(self.state), {
            wager = self.wager,
            enabled = true,
        })
        return
    end

    love.graphics.setColor(0.8, 0.6, 0.4)
    love.graphics.printf("Dealer:", 0, y, screenW, "center")
    y = y + rowH.dealerLabel
    local dealerStartY = y
    y = drawCardRow(
        self,
        self.dealerHand,
        screenW * 0.5,
        y,
        (self.state == "playing") and 2 or nil,
        screenW * 0.9,
        dealerCardH
    )
    local dealerRowH = math.max(y - dealerStartY, math.max(12, dealerCardH * 0.2))
    y = dealerStartY + dealerRowH
    if self.state ~= "playing" then
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("(" .. self:displayValue(self.dealerHand) .. ")", 0, y, screenW, "center")
        y = y + rowH.dealerValue
    end

    local handsSectionH = rowH.handsHeader + (handCount * (rowH.handLabel + handCardH + rowH.handValue))
    local desiredHandsY = layoutBottom - 6 - handsSectionH
    if desiredHandsY > y then
        y = desiredHandsY
    end

    love.graphics.setColor(0.8, 0.6, 0.4)
    love.graphics.printf("Your hands:", 0, y, screenW, "center")
    y = y + rowH.handsHeader
    for i, hand in ipairs(self.hands) do
        local prefix = "  "
        if self.state == "playing" and i == self.activeHand then
            prefix = "> "
        end
        local label = prefix .. "Hand " .. i .. "  ($" .. hand.wager .. ")"
        if hand.doubled then
            label = label .. "  [Double]"
        elseif hand.isSplit then
            label = label .. "  [Split]"
        end
        if self.state == "result" and hand.result then
            label = label .. "  - " .. string.upper(hand.result)
        end
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(label, 0, y, screenW, "center")
        y = y + rowH.handLabel
        local handStartY = y
        y = drawCardRow(
            self,
            hand.cards,
            screenW * 0.5,
            y,
            nil,
            screenW * 0.9,
            handCardH
        )
        local handRowH = math.max(y - handStartY, math.max(10, handCardH * 0.18))
        y = handStartY + handRowH
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("(" .. self:displayValue(hand.cards) .. ")", 0, y, screenW, "center")
        y = y + rowH.handValue
    end

    y = y + 6
    if self.state == "playing" then
        self:drawButtons(screenW, screenH, y + 12, fonts, buttonLabelsForState(self.state), {
            wager = self.wager,
            enabled = false,
        })
    elseif self.state == "result" then
        self:drawButtons(screenW, screenH, y + 12, fonts, buttonLabelsForState(self.state), {
            wager = self.wager,
            enabled = true,
        })
    end
end

function Blackjack:hitButton(mx, my, screenW, screenH)
    local labels = buttonLabelsForState(self.state)
    if not labels then return nil end
    local rects = blackjackButtonLayout(screenW, screenH, labels, self.lastButtonsY)
    local firstRect = rects and rects[1] or nil
    local wagerRects = blackjackWagerLayout(firstRect)
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

function Blackjack:handleAction(action, player)
    if self.state == "betting" then
        if action == "wager_down" then
            self:adjustWager(-self.betStep, player.gold)
        elseif action == "wager_up" then
            self:adjustWager(self.betStep, player.gold)
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
        elseif action == "wager_up" then
            self:adjustWager(self.betStep, player.gold)
        elseif action == "continue" then
            return resolveReward(self, player, false)
        elseif action == "deal_again" then
            return resolveReward(self, player, true)
        end
    end
    return nil
end

function Blackjack:handleKey(key, player)
    if self.state == "betting" then
        if key == "left" or key == "a" or key == "-" or key == "kp-" then
            self:adjustWager(-self.betStep, player.gold)
        elseif key == "right" or key == "d" or key == "=" or key == "kp+" then
            self:adjustWager(self.betStep, player.gold)
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
            return self:handleAction("continue", player)
        elseif key == "d" then
            return self:handleAction("deal_again", player)
        end
    end
    return nil
end

function Blackjack:handleMousePressed(mx, my, button, screenW, screenH, player)
    if button ~= 1 then return nil end
    local action = self:hitButton(mx, my, screenW, screenH)
    if not action then return nil end
    self.hoveredButton = action
    return self:handleAction(action, player)
end

function Blackjack.cardToString(card)
    return card.rank .. SUIT_SYMBOLS[card.suit]
end

return Blackjack
