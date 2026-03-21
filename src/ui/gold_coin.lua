-- Gold coin sprites from assets/Pixel Fantasy Coin Flip (6-frame flip cycle + static heads).

local GoldCoin = {}

local FRAME_PATH = "assets/Pixel Fantasy Coin Flip/Coin Flip (animation frames)/goldcoin-frame%d.png"
local HEADS_PATH = "assets/Pixel Fantasy Coin Flip/Coin Flip/goldcoin-heads.png"

local frames = {}
local frameCount = 6
local framesOk = false
local headsImg

function GoldCoin.ensureFrames()
    if framesOk then return true end
    if frames[1] then
        framesOk = true
        return true
    end
    for i = 1, frameCount do
        local path = string.format(FRAME_PATH, i)
        local ok, img = pcall(love.graphics.newImage, path)
        if ok and img then
            img:setFilter("nearest", "nearest")
            frames[i] = img
        end
    end
    framesOk = frames[1] ~= nil
    return framesOk
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
function GoldCoin.frameIndex(animTime, fps)
    fps = fps or 10
    if not GoldCoin.ensureFrames() or not frames[1] then return 1 end
    local idx = math.floor(animTime * fps) % frameCount + 1
    return idx
end

--- Draw flip animation centered at (cx, cy). targetH is height in pixels; width scales proportionally.
--- opts: phase (seconds offset), fps, alpha, rotation
function GoldCoin.drawAnimatedCentered(cx, cy, targetH, animTime, opts)
    opts = opts or {}
    if not GoldCoin.ensureFrames() then return false end
    local idx = GoldCoin.frameIndex(animTime + (opts.phase or 0), opts.fps)
    local img = frames[idx]
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
