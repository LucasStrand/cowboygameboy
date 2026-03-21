-- Game-space UI fonts (canvas is GAME_WIDTH × GAME_HEIGHT, usually equal to the window).
-- Prefer project TTF; fall back to LÖVE default bitmap font if the file is missing.

local Font = {}

local TTF_PATH = "assets/fonts/PixelEmulator-xq08.ttf"

local function px(n)
    return math.floor(n * 1.12 + 0.5)
end

local function tryTtf(sizePx)
    local ok, f = pcall(love.graphics.newFont, TTF_PATH, sizePx)
    if ok and f then
        -- Pixel font: keep edges crisp when the game canvas is scaled
        f:setFilter("nearest", "nearest")
        return f
    end
    return nil
end

function Font.new(n)
    local sizePx = px(n)
    local f = tryTtf(sizePx)
    if f then
        return f
    end
    f = love.graphics.newFont(sizePx)
    f:setFilter("linear", "linear")
    return f
end

function Font.hudPrimary()
    return Font.new(16)
end

function Font.hudSecondary()
    return Font.new(11)
end

return Font
