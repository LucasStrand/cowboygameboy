-- Cheap fullscreen blur: downscale + upscale with linear filtering (no shader).

local BlurBG = {}

local snapCanvas
local smallCanvas
local smallW, smallH

local function ensure()
    if snapCanvas then
        return
    end
    snapCanvas = love.graphics.newCanvas(GAME_WIDTH, GAME_HEIGHT)
    snapCanvas:setFilter("linear", "linear")
    smallW = math.max(32, math.floor(GAME_WIDTH / 4))
    smallH = math.max(18, math.floor(GAME_HEIGHT / 4))
    smallCanvas = love.graphics.newCanvas(smallW, smallH)
    smallCanvas:setFilter("linear", "linear")
end

--- Renders `gameState:draw()` to an offscreen buffer, blurs it, and draws the result
--- onto whatever canvas is currently active (the main game canvas).
function BlurBG.drawBlurredGame(gameState)
    ensure()
    local prev = love.graphics.getCanvas()

    love.graphics.setCanvas(snapCanvas)
    love.graphics.clear(0, 0, 0, 1)
    gameState.draw(gameState)

    love.graphics.setCanvas(smallCanvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(snapCanvas, 0, 0, 0, smallW / GAME_WIDTH, smallH / GAME_HEIGHT)

    love.graphics.setCanvas(prev)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(smallCanvas, 0, 0, 0, GAME_WIDTH / smallW, GAME_HEIGHT / smallH)
end

return BlurBG
