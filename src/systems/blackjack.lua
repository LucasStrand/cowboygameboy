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

function Blackjack.new()
    local self = setmetatable({}, Blackjack)
    self.deck = {}
    self.playerHand = {}
    self.dealerHand = {}
    self.state = "betting" -- betting, playing, dealer_turn, result
    self.wager = 0
    self.result = nil
    self.resultMessage = ""
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
    return value
end

function Blackjack:startGame(wager)
    self:buildDeck()
    self.wager = wager
    self.playerHand = {}
    self.dealerHand = {}
    self.result = nil
    self.resultMessage = ""

    table.insert(self.playerHand, self:drawCard())
    table.insert(self.dealerHand, self:drawCard())
    table.insert(self.playerHand, self:drawCard())
    table.insert(self.dealerHand, self:drawCard())

    if self:handValue(self.playerHand) == 21 then
        self.state = "result"
        self.result = "blackjack"
        self.resultMessage = "BLACKJACK! Gold x3 + Rare Perk!"
        return
    end

    self.state = "playing"
end

function Blackjack:hit()
    if self.state ~= "playing" then return end

    table.insert(self.playerHand, self:drawCard())
    local val = self:handValue(self.playerHand)
    if val > 21 then
        self.state = "result"
        self.result = "bust"
        self.resultMessage = "BUST! You lose " .. self.wager .. " gold."
    elseif val == 21 then
        self:stand()
    end
end

function Blackjack:stand()
    if self.state ~= "playing" then return end
    self.state = "dealer_turn"

    while self:handValue(self.dealerHand) < 17 do
        table.insert(self.dealerHand, self:drawCard())
    end

    local playerVal = self:handValue(self.playerHand)
    local dealerVal = self:handValue(self.dealerHand)

    self.state = "result"
    if dealerVal > 21 then
        self.result = "win"
        self.resultMessage = "Dealer busts! You win " .. self.wager .. " gold + free perk!"
    elseif playerVal > dealerVal then
        self.result = "win"
        self.resultMessage = "You win! +" .. self.wager .. " gold + free perk!"
    elseif playerVal == dealerVal then
        self.result = "push"
        self.resultMessage = "Push. Gold returned."
    else
        self.result = "lose"
        self.resultMessage = "Dealer wins. You lose " .. self.wager .. " gold."
    end
end

function Blackjack:getReward()
    if self.result == "blackjack" then
        return {gold = self.wager * 3, perkRarity = "rare"}
    elseif self.result == "win" then
        return {gold = self.wager * 2, perkRarity = nil}
    elseif self.result == "push" then
        return {gold = self.wager, perkRarity = nil}
    else
        return {gold = 0, perkRarity = nil}
    end
end

function Blackjack.cardToString(card)
    return card.rank .. SUIT_SYMBOLS[card.suit]
end

return Blackjack
