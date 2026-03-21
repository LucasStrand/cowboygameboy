local Gamestate = require("lib.hump.gamestate")
local Progression = require("src.systems.progression")
local PerkCard = require("src.ui.perk_card")
local BlurBG = require("src.ui.blur_bg")
local Cursor = require("src.ui.cursor")
local game = require("src.states.game")

local levelup = {}

local perks = {}
local player = nil
local hoveredIndex = nil
local callback = nil

function levelup:enter(_, _player, _callback)
    player = _player
    callback = _callback
    perks = Progression.rollLevelUpPerks(player)
    hoveredIndex = nil
    Cursor.setDefault()
end

function levelup:update(dt)
    local mx, my = windowToGame(love.mouse.getPosition())
    hoveredIndex = PerkCard.getHovered(perks, mx, my)
end

function levelup:keypressed(key)
    local num = tonumber(key)
    if num and num >= 1 and num <= #perks then
        selectPerk(num)
    end
end

function levelup:mousepressed(x, y, button)
    if button == 1 and hoveredIndex then
        selectPerk(hoveredIndex)
    end
end

function selectPerk(index)
    local perk = perks[index]
    if perk then
        Progression.applyPerk(player, perk)
        Gamestate.pop()
        if callback then
            callback()
        end
    end
end

function levelup:draw()
    BlurBG.drawBlurredGame(game)
    -- Lighten readabilty over the blurred gameplay
    love.graphics.setColor(0, 0, 0, 0.28)
    love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)
    love.graphics.setColor(1, 1, 1, 1)
    PerkCard.draw(perks, nil, hoveredIndex)
end

return levelup
