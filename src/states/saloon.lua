local Gamestate = require("lib.hump.gamestate")
local Font = require("src.ui.font")
local Blackjack = require("src.systems.blackjack")
local Shop = require("src.systems.shop")
local PerkCard = require("src.ui.perk_card")
local Cursor = require("src.ui.cursor")

local saloon = {}

local player = nil
local blackjackGame = nil
local shop = nil
local difficulty = 1
local mode = "main"
local message = ""
local messageTimer = 0
local perkOptions = nil
local hoveredPerk = nil
local roomManager = nil
local fonts = {}

function saloon:enter(_, _player, _roomManager)
    player = _player
    roomManager = _roomManager
    difficulty = _roomManager and _roomManager.difficulty or 1
    blackjackGame = Blackjack.new()
    shop = Shop.new(difficulty)
    mode = "main"
    message = ""
    messageTimer = 0
    perkOptions = nil
    hoveredPerk = nil

    fonts.title = Font.new(36)
    fonts.stat = Font.new(18)
    fonts.body = Font.new(16)
    fonts.card = Font.new(20)
    fonts.shopTitle = Font.new(24)
    fonts.default = Font.new(12)
    Cursor.setDefault()
end

local function applyBlackjackOutcome(outcome)
    if not outcome then return end
    if outcome.message then
        message = outcome.message
    end
    if outcome.messageTimer then
        messageTimer = outcome.messageTimer
    end
    if outcome.perkOptions then
        perkOptions = outcome.perkOptions
    end
    if outcome.mode then
        mode = outcome.mode
    end
end

function saloon:update(dt)
    if messageTimer > 0 then
        messageTimer = messageTimer - dt
    end
    if mode == "perk_selection" and perkOptions then
        local mx, my = windowToGame(love.mouse.getPosition())
        hoveredPerk = PerkCard.getHovered(perkOptions, mx, my)
    elseif mode == "blackjack" then
        local mx, my = windowToGame(love.mouse.getPosition())
        blackjackGame:updateHover(mx, my, GAME_WIDTH, GAME_HEIGHT)
    end
end

function saloon:keypressed(key)
    if mode == "main" then
        if key == "1" then
            applyBlackjackOutcome(blackjackGame:enterTable(player.gold))
        elseif key == "2" then
            mode = "shop"
        elseif key == "return" or key == "3" then
            continueGame()
        end
    elseif mode == "blackjack" then
        applyBlackjackOutcome(blackjackGame:handleKey(key, player))
    elseif mode == "shop" then
        local num = tonumber(key)
        if num and num >= 1 and num <= #shop.items then
            local success, msg = shop:buyItem(num, player)
            message = msg
            messageTimer = 2
        elseif key == "escape" or key == "backspace" then
            mode = "main"
        end
    elseif mode == "perk_selection" then
        local num = tonumber(key)
        if num and num >= 1 and num <= #perkOptions then
            player:applyPerk(perkOptions[num])
            mode = blackjackGame:completePerkSelection()
            perkOptions = nil
        end
    end
end

function saloon:mousepressed(x, y, button)
    if mode == "perk_selection" and button == 1 and hoveredPerk then
        player:applyPerk(perkOptions[hoveredPerk])
        mode = blackjackGame:completePerkSelection()
        perkOptions = nil
        return
    end
    if mode == "blackjack" then
        local mx, my = windowToGame(x, y)
        applyBlackjackOutcome(blackjackGame:handleMousePressed(mx, my, button, GAME_WIDTH, GAME_HEIGHT, player))
    end
end

function continueGame()
    if roomManager then
        roomManager:startNewCycle()
        roomManager.needsNewRooms = true
    end
    Gamestate.pop()
end

function saloon:draw()
    local screenW = GAME_WIDTH
    local screenH = GAME_HEIGHT

    -- Saloon background
    love.graphics.setColor(0.12, 0.08, 0.05)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)

    -- Decorative bar counter
    love.graphics.setColor(0.35, 0.2, 0.1)
    love.graphics.rectangle("fill", 0, screenH * 0.85, screenW, screenH * 0.15)
    love.graphics.setColor(0.5, 0.3, 0.15)
    love.graphics.rectangle("fill", 0, screenH * 0.84, screenW, 4)

    -- Title
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.setFont(fonts.title)
    love.graphics.printf("SALOON", 0, 30, screenW, "center")

    -- Player stats
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.setFont(fonts.stat)
    love.graphics.printf("Gold: $" .. player.gold .. "  |  HP: " .. player.hp .. "/" .. player:getEffectiveStats().maxHP .. "  |  Level: " .. player.level, 0, 80, screenW, "center")

    love.graphics.setFont(fonts.body)

    if mode == "main" then
        drawMainMenu(screenW, screenH)
    elseif mode == "blackjack" then
        blackjackGame:draw(screenW, screenH, fonts)
    elseif mode == "shop" then
        drawShop(screenW, screenH)
    elseif mode == "perk_selection" then
        PerkCard.draw(perkOptions, nil, hoveredPerk)
    end

    -- Message
    if messageTimer > 0 then
        love.graphics.setColor(1, 1, 0.5)
        love.graphics.printf(message, 0, screenH - 50, screenW, "center")
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(fonts.default)
end

function drawMainMenu(screenW, screenH)
    local y = screenH * 0.35
    local opts = {
        "[1] Blackjack Table  (wager gold for perks)",
        "[2] Bartender  (buy supplies)",
        "[3/ENTER] Hit the Road  (continue to next rooms)",
    }
    for _, opt in ipairs(opts) do
        love.graphics.setColor(0.9, 0.8, 0.6)
        love.graphics.printf(opt, 0, y, screenW, "center")
        y = y + 40
    end
end

function drawShop(screenW, screenH)
    local y = 150
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.setFont(fonts.shopTitle)
    love.graphics.printf("BARTENDER", 0, y, screenW, "center")
    y = y + 50

    love.graphics.setFont(fonts.body)

    for i, item in ipairs(shop.items) do
        if item.sold then
            love.graphics.setColor(0.4, 0.4, 0.4)
            love.graphics.printf("[" .. i .. "] " .. item.name .. "  -- SOLD", 0, y, screenW, "center")
        else
            local canAfford = player.gold >= item.price
            if canAfford then
                love.graphics.setColor(0.9, 0.8, 0.6)
            else
                love.graphics.setColor(0.6, 0.4, 0.3)
            end
            love.graphics.printf("[" .. i .. "] " .. item.name .. "  ($" .. item.price .. ")", 0, y, screenW, "center")
            y = y + 22
            love.graphics.setColor(0.6, 0.6, 0.6)
            love.graphics.printf("    " .. item.description, 0, y, screenW, "center")
        end
        y = y + 35
    end

    y = y + 20
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.printf("[ESC] Back to saloon", 0, y, screenW, "center")
end

return saloon
