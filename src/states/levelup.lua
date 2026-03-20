local Gamestate = require("lib.hump.gamestate")
local Progression = require("src.systems.progression")
local PerkCard = require("src.ui.perk_card")

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
    -- Draw underlying game state (dimmed)
    local prev = Gamestate.current()

    PerkCard.draw(perks, nil, hoveredIndex)
end

return levelup
