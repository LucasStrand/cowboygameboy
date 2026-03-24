--- Pixel coin art for the travelling croupier trail gamble (player calls heads or tails).
--- Loads gold + silver assets; **croupier UI/world draws silver art only** (RNG may still roll gold/silver internally).
--- 6-frame flip animations and heads/tails landing sprites per metal.
local M = {}

local COIN_DIR = "assets/Pixel Fantasy Coin Flip/Coin Flip/"
local ANIM_DIR = "assets/Pixel Fantasy Coin Flip/Coin Flip (animation frames)/"

local loaded = false

-- Static face images (goldcoin-1, silvercoin-1)
local goldImg  --- @type love.Image|nil
local silverImg --- @type love.Image|nil

-- 6-frame flip animation per metal
local goldFrames = {}   --- @type love.Image[]
local silverFrames = {} --- @type love.Image[]
local FRAME_COUNT = 6

-- Heads/tails landing sprites
local goldHeads   --- @type love.Image|nil
local goldTails   --- @type love.Image|nil
local silverHeads --- @type love.Image|nil
local silverTails --- @type love.Image|nil

local function tryLoad(path)
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
        img:setFilter("nearest", "nearest")
        return img
    end
    return nil
end

function M.ensureLoaded()
    if loaded then return end
    loaded = true

    goldImg   = tryLoad(COIN_DIR .. "goldcoin-1.png")
    silverImg = tryLoad(COIN_DIR .. "silvercoin-1.png")

    for i = 1, FRAME_COUNT do
        goldFrames[i]   = tryLoad(ANIM_DIR .. string.format("goldcoin-frame%d.png", i))
        silverFrames[i] = tryLoad(ANIM_DIR .. string.format("silvercoin-frame%d.png", i))
    end

    goldHeads   = tryLoad(COIN_DIR .. "goldcoin-heads.png")
    goldTails   = tryLoad(COIN_DIR .. "goldcoin-tails.png")
    silverHeads = tryLoad(COIN_DIR .. "silvercoin-heads.png")
    silverTails = tryLoad(COIN_DIR .. "silvercoin-tails.png")
end

function M.getGold()   return goldImg end
function M.getSilver() return silverImg end

function M.hasAnyCoin()
    return goldImg ~= nil or silverImg ~= nil
end

--- @param side "gold"|"silver"
function M.getImageForSide(side)
    return side == "silver" and silverImg or goldImg
end

--- Get a flip animation frame (1-based index, wraps).
--- @param side "gold"|"silver"
--- @param idx number  Frame index 1..6
function M.getFlipFrame(side, idx)
    local fr = (side == "silver") and silverFrames or goldFrames
    local i = ((idx - 1) % FRAME_COUNT) + 1
    return fr[i]
end

--- Get the heads/tails landing sprite for a given result.
--- @param side "gold"|"silver"  Which metal the coin is
--- @param face "heads"|"tails"  Which face landed up
function M.getLandedImage(side, face)
    if side == "silver" then
        return face == "tails" and silverTails or silverHeads
    else
        return face == "tails" and goldTails or goldHeads
    end
end

--- Number of flip animation frames.
function M.frameCount() return FRAME_COUNT end

return M
