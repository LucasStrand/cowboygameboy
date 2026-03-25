--- Shared deck + sprite cache for the travelling croupier's trail gamble (uses saloon Blackjack card PNGs).
local GameRng = require("src.systems.game_rng")

local M = {}

local SUITS = { "hearts", "diamonds", "clubs", "spades" }
local RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }

local cardSprites = {}
local backSprite
local nativeW, nativeH

function M.suits()
    return SUITS
end

function M.ranks()
    return RANKS
end

--- Ace high for trail high-card duel.
function M.rankValue(rank)
    if rank == "A" then return 14 end
    if rank == "K" then return 13 end
    if rank == "Q" then return 12 end
    if rank == "J" then return 11 end
    return tonumber(rank) or 0
end

function M.getNativeSize()
    if nativeW and nativeH then
        return nativeW, nativeH
    end
    return 64, 96
end

function M.getSprite(suit, rank)
    local key = suit .. ":" .. rank
    if cardSprites[key] then
        return cardSprites[key]
    end
    local path = string.format("assets/sprites/Blackjack/%s/%s.png", suit, rank)
    local ok, img = pcall(love.graphics.newImage, path)
    if not ok or not img then
        return nil
    end
    img:setFilter("nearest", "nearest")
    cardSprites[key] = img
    if not nativeW then
        nativeW = img:getWidth()
        nativeH = img:getHeight()
    end
    return img
end

function M.getBackSprite()
    if backSprite then
        return backSprite
    end
    local ok, img = pcall(love.graphics.newImage, "assets/sprites/Blackjack/backs/red.png")
    if not ok or not img then
        return nil
    end
    img:setFilter("nearest", "nearest")
    backSprite = img
    if not nativeW then
        nativeW = img:getWidth()
        nativeH = img:getHeight()
    end
    return backSprite
end

function M.buildDeck()
    local d = {}
    for _, suit in ipairs(SUITS) do
        for _, rank in ipairs(RANKS) do
            d[#d + 1] = { suit = suit, rank = rank }
        end
    end
    return d
end

function M.shuffle(deck, channel)
    local ch = channel or "trail_gamble.shuffle"
    for i = #deck, 2, -1 do
        local j = GameRng.random(ch, i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

return M
