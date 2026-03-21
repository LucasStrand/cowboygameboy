-- Game-space UI fonts (canvas is GAME_WIDTH x GAME_HEIGHT, then scaled to the window).
-- Slightly larger raster sizes + linear filter so text stays readable when scaled (e.g. 1080p).

local Font = {}

local function px(n)
    return math.floor(n * 1.12 + 0.5)
end

function Font.new(n)
    local f = love.graphics.newFont(px(n))
    f:setFilter("linear", "linear")
    return f
end

return Font
