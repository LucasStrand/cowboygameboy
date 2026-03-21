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
    Sfx.play("casino_shuffle")

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

function Blackjack.cardToString(card)
    return card.rank .. SUIT_SYMBOLS[card.suit]
end

return Blackjack
