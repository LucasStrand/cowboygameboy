local Gamestate = require("lib.hump.gamestate")

local gameover = {}

local stats = {}
local timer = 0
local fonts = {}

function gameover:enter(_, playerStats)
    stats = playerStats or {}
    timer = 0
    fonts.title = love.graphics.newFont(48)
    fonts.stat = love.graphics.newFont(20)
    fonts.prompt = love.graphics.newFont(18)
    fonts.default = love.graphics.newFont(12)
end

function gameover:update(dt)
    timer = timer + dt
end

function gameover:keypressed(key)
    if timer > 1 then
        if key == "return" or key == "space" then
            local game = require("src.states.game")
            Gamestate.switch(game)
        end
        if key == "escape" then
            local menu = require("src.states.menu")
            Gamestate.switch(menu)
        end
    end
end

function gameover:draw()
    local screenW = GAME_WIDTH
    local screenH = GAME_HEIGHT

    -- Dark background
    love.graphics.setColor(0.05, 0.02, 0.02)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)

    -- Death text
    love.graphics.setColor(0.8, 0.1, 0.1)
    love.graphics.setFont(fonts.title)
    love.graphics.printf("YOU DIED", 0, screenH * 0.2, screenW, "center")

    -- Stats
    love.graphics.setColor(0.8, 0.7, 0.5)
    love.graphics.setFont(fonts.stat)

    local y = screenH * 0.4
    local lineH = 35

    love.graphics.printf("Level: " .. (stats.level or 1), 0, y, screenW, "center")
    y = y + lineH
    love.graphics.printf("Rooms Cleared: " .. (stats.roomsCleared or 0), 0, y, screenW, "center")
    y = y + lineH
    love.graphics.printf("Gold Earned: " .. (stats.gold or 0), 0, y, screenW, "center")
    y = y + lineH
    love.graphics.printf("Perks Collected: " .. (stats.perksCount or 0), 0, y, screenW, "center")

    -- Restart prompt
    if timer > 1 then
        local flicker = math.floor(timer * 2) % 2 == 0
        if flicker then
            love.graphics.setColor(1, 0.85, 0.2)
        else
            love.graphics.setColor(0.7, 0.6, 0.2)
        end
        love.graphics.setFont(fonts.prompt)
        love.graphics.printf("Press ENTER to try again  |  ESC for menu", 0, screenH * 0.8, screenW, "center")
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(fonts.default)
end

return gameover
