-- Coin sprites from assets/Pixel Fantasy Coin Flip (6-frame flip while airborne; goldcoin-1 / silvercoin-1 when idle on ground, rotated edge-on).

local GoldCoin = {}

local FRAME_PATH_GOLD = "assets/Pixel Fantasy Coin Flip/Coin Flip (animation frames)/goldcoin-frame%d.png"
local FRAME_PATH_SILVER = "assets/Pixel Fantasy Coin Flip/Coin Flip (animation frames)/silvercoin-frame%d.png"
local IDLE_PATH_GOLD = "assets/Pixel Fantasy Coin Flip/Coin Flip/goldcoin-1.png"
local IDLE_PATH_SILVER = "assets/Pixel Fantasy Coin Flip/Coin Flip/silvercoin-1.png"

--- 90° so the flat "lying" coin reads as standing (edge-on) on the ground.
local IDLE_STAND_ROTATION = math.pi / 2

local frameCount = 6

local framesGold = {}
local framesSilver = {}
local goldOkFlag = {}
local silverOkFlag = {}

--- Legacy HUD path (same asset as idle gold coin)
local HEADS_PATH = IDLE_PATH_GOLD
local headsImg

local function loadFace(path)
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
        img:setFilter("nearest", "nearest")
        return img
    end
    return nil
end

-- Per metal: { img = img|nil, tried = bool }
local idleGold = { tried = false }
local idleSilver = { tried = false }

local function loadFrameSet(pathTemplate, out, setOkFlag)
    if setOkFlag[1] then
        return out[1] ~= nil
    end
    for i = 1, frameCount do
        local path = string.format(pathTemplate, i)
        local ok, img = pcall(love.graphics.newImage, path)
        if ok and img then
            img:setFilter("nearest", "nearest")
            out[i] = img
        end
    end
    setOkFlag[1] = true
    return out[1] ~= nil
end

function GoldCoin.ensureFrames()
    return loadFrameSet(FRAME_PATH_GOLD, framesGold, goldOkFlag)
end

function GoldCoin.ensureSilverFrames()
    return loadFrameSet(FRAME_PATH_SILVER, framesSilver, silverOkFlag)
end

local function ensureFramesForVariant(variant)
    variant = variant or "gold"
    if variant == "silver" then
        return GoldCoin.ensureSilverFrames()
    end
    return GoldCoin.ensureFrames()
end

local function framesTableForVariant(variant)
    variant = variant or "gold"
    if variant == "silver" then
        return framesSilver
    end
    return framesGold
end

local function ensureIdleImg(variant)
    variant = variant or "gold"
    local t = variant == "silver" and idleSilver or idleGold
    if t.tried then
        return t.img ~= nil
    end
    t.tried = true
    local path = variant == "silver" and IDLE_PATH_SILVER or IDLE_PATH_GOLD
    t.img = loadFace(path)
    return t.img ~= nil
end

local function getIdleImg(variant)
    variant = variant or "gold"
    local t = variant == "silver" and idleSilver or idleGold
    return t.img
end

local function ensureHeads()
    if headsImg == false then return false end
    if headsImg then return true end
    local ok, img = pcall(love.graphics.newImage, HEADS_PATH)
    if ok and img then
        img:setFilter("nearest", "nearest")
        headsImg = img
        return true
    end
    headsImg = false
    return false
end

--- Frame index 1..6 from continuous time (seconds).
--- variant: `"gold"` (default) or `"silver"`.
function GoldCoin.frameIndex(animTime, fps, variant)
    fps = fps or 10
    variant = variant or "gold"
    if not ensureFramesForVariant(variant) then return 1 end
    local fr = framesTableForVariant(variant)
    if not fr[1] then return 1 end
    local idx = math.floor(animTime * fps) % frameCount + 1
    return idx
end

--- Draw flip animation centered at (cx, cy). targetH is height in pixels; width scales proportionally.
--- opts: phase (seconds offset), fps, alpha, rotation, variant (`"gold"` | `"silver"`)
function GoldCoin.drawAnimatedCentered(cx, cy, targetH, animTime, opts)
    opts = opts or {}
    local variant = opts.variant or "gold"
    if not ensureFramesForVariant(variant) then return false end
    local fr = framesTableForVariant(variant)
    local idx = GoldCoin.frameIndex(animTime + (opts.phase or 0), opts.fps, variant)
    local img = fr[idx]
    if not img then return false end
    local w, h = img:getDimensions()
    local scale = (targetH or 14) / h
    local alpha = opts.alpha
    if alpha == nil then alpha = 1 end
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(
        img,
        cx,
        cy,
        opts.rotation or 0,
        scale,
        scale,
        w / 2,
        h / 2
    )
    love.graphics.setColor(1, 1, 1, 1)
    return true
end

--- Ground idle: static goldcoin-1 / silvercoin-1, rotated so the coin reads standing (edge-on).
--- opts: alpha, variant (`"gold"` | `"silver"`), rotation (radians; default IDLE_STAND_ROTATION)
function GoldCoin.drawIdleFaceCentered(cx, cy, targetH, opts)
    opts = opts or {}
    local variant = opts.variant or "gold"
    local alpha = opts.alpha
    if alpha == nil then alpha = 1 end
    local rotation = opts.rotation
    if rotation == nil then rotation = IDLE_STAND_ROTATION end

    local img = nil
    if ensureIdleImg(variant) then
        img = getIdleImg(variant)
    end
    if not img then
        if not ensureFramesForVariant(variant) then return false end
        local fr = framesTableForVariant(variant)
        img = fr[1]
    end
    if not img then return false end

    local w, h = img:getDimensions()
    local scale = (targetH or 14) / h
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(img, cx, cy, rotation, scale, scale, w / 2, h / 2)
    love.graphics.setColor(1, 1, 1, 1)
    return true
end

--- HUD / static icon: top-left at (x, y), box height `sizePx`.
function GoldCoin.drawHeadsTopLeft(x, y, sizePx)
    if not ensureHeads() or not headsImg then return false end
    local w, h = headsImg:getDimensions()
    local scale = sizePx / h
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(headsImg, math.floor(x + 0.5), math.floor(y + 0.5), 0, scale, scale)
    return true
end

return GoldCoin
