-- Fullscreen background blur for level-up overlay.
-- Uses separable Gaussian blur (H + V shader passes) for smooth results; avoids chunky mip blur.

local BlurBG = {}

local snapCanvas
local passCanvas
local blurShader
local fallbackSmall
local smallW, smallH

local shaderCode = [[
    extern vec2 direction;
    extern vec2 texelSize;

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
    {
        vec2 off = direction * texelSize;
        // 5-tap separable Gaussian (sigma ~1.5), normalized
        vec4 sum = Texel(tex, tc) * 0.2270270270;
        sum += Texel(tex, tc + off * 1.0) * 0.3162162162;
        sum += Texel(tex, tc - off * 1.0) * 0.3162162162;
        sum += Texel(tex, tc + off * 2.0) * 0.0702702703;
        sum += Texel(tex, tc - off * 2.0) * 0.0702702703;
        return sum * color;
    }
]]

local function ensure()
    if snapCanvas then
        return
    end
    snapCanvas = love.graphics.newCanvas(GAME_WIDTH, GAME_HEIGHT)
    snapCanvas:setFilter("linear", "linear")
    passCanvas = love.graphics.newCanvas(GAME_WIDTH, GAME_HEIGHT)
    passCanvas:setFilter("linear", "linear")

    local ok, sh = pcall(love.graphics.newShader, shaderCode)
    if ok then
        blurShader = sh
    end

    -- Softer fallback than old /4 if shaders fail (rare)
    if not blurShader then
        smallW = math.max(64, math.floor(GAME_WIDTH / 2))
        smallH = math.max(36, math.floor(GAME_HEIGHT / 2))
        fallbackSmall = love.graphics.newCanvas(smallW, smallH)
        fallbackSmall:setFilter("linear", "linear")
    end
end

local function drawFallbackBlur()
    love.graphics.setCanvas(fallbackSmall)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(snapCanvas, 0, 0, 0, smallW / GAME_WIDTH, smallH / GAME_HEIGHT)
end

--- Renders `gameState:draw()` to an offscreen buffer, blurs it, and draws the result
--- onto whatever canvas is currently active (the main game canvas).
function BlurBG.drawBlurredGame(gameState)
    ensure()
    local prev = love.graphics.getCanvas()
    local tw, th = 1 / GAME_WIDTH, 1 / GAME_HEIGHT

    love.graphics.setCanvas(snapCanvas)
    love.graphics.clear(0, 0, 0, 1)
    gameState.draw(gameState)

    if blurShader then
        love.graphics.setCanvas(passCanvas)
        love.graphics.clear(0, 0, 0, 1)
        love.graphics.setShader(blurShader)
        blurShader:send("direction", {1, 0})
        blurShader:send("texelSize", {tw, th})
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(snapCanvas, 0, 0)

        love.graphics.setCanvas(prev)
        blurShader:send("direction", {0, 1})
        blurShader:send("texelSize", {tw, th})
        love.graphics.draw(passCanvas, 0, 0)
        love.graphics.setShader()
    else
        drawFallbackBlur()
        love.graphics.setCanvas(prev)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(fallbackSmall, 0, 0, 0, GAME_WIDTH / smallW, GAME_HEIGHT / smallH)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return BlurBG
