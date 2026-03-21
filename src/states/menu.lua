local Gamestate = require("lib.hump.gamestate")
local Font = require("src.ui.font")

local menu = {}

local titleTimer = 0
local flickerTimer = 0
local fonts = {}

function menu:enter()
    titleTimer = 0
    flickerTimer = 0
    fonts.title = Font.new(48)
    fonts.subtitle = Font.new(16)
    fonts.prompt = Font.new(20)
    fonts.hint = Font.new(14)
    fonts.default = Font.new(12)
end

function menu:update(dt)
    titleTimer = titleTimer + dt
    flickerTimer = flickerTimer + dt
end

function menu:keypressed(key)
    if key == "return" or key == "space" then
        local game = require("src.states.game")
        Gamestate.switch(game)
    end
    if key == "escape" then
        love.event.quit()
    end
end

function menu:draw()
    local screenW = GAME_WIDTH
    local screenH = GAME_HEIGHT

    -- Background
    love.graphics.setColor(0.08, 0.05, 0.03)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)

    -- Decorative lines
    love.graphics.setColor(0.5, 0.3, 0.1, 0.5)
    love.graphics.rectangle("fill", 0, screenH * 0.35, screenW, 2)
    love.graphics.rectangle("fill", 0, screenH * 0.65, screenW, 2)

    -- Title
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.setFont(fonts.title)
    love.graphics.printf("SIX CHAMBERS", 0, screenH * 0.3, screenW, "center")

    -- Subtitle
    love.graphics.setColor(0.7, 0.5, 0.3)
    love.graphics.setFont(fonts.subtitle)
    love.graphics.printf("A Cowboy Roguelike", 0, screenH * 0.3 + 60, screenW, "center")

    -- Start prompt (flicker)
    if math.floor(flickerTimer * 2) % 2 == 0 then
        love.graphics.setColor(1, 1, 1)
    else
        love.graphics.setColor(0.7, 0.7, 0.7)
    end
    love.graphics.setFont(fonts.prompt)
    love.graphics.printf("Press ENTER to start", 0, screenH * 0.6, screenW, "center")

    -- Controls hint
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.setFont(fonts.hint)
    love.graphics.printf("A/D - Move  |  SPACE - Jump  |  SHIFT - Dash  |  CTRL - Shield  |  F - Melee (aim w/ mouse)  |  E - Exit", 0, screenH * 0.70, screenW, "center")
    love.graphics.printf("LMB shoot  |  RMB slots: auto gun/melee (+ shield only if shield allows)  |  R reload  |  F1 debug", 0, screenH * 0.76, screenW, "center")

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(fonts.default)
end

return menu
