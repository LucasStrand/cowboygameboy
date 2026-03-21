local Gamestate = require("lib.hump.gamestate")
local Font = require("src.ui.font")
local Blackjack = require("src.systems.blackjack")
local Shop = require("src.systems.shop")
local Perks = require("src.data.perks")
local PerkCard = require("src.ui.perk_card")
local Cursor = require("src.ui.cursor")

local saloon = {}

local bgImage = nil
local player = nil
local blackjackGame = nil
local shop = nil
local difficulty = 1
local mode = "main"
local message = ""
local messageTimer = 0
local perkOptions = nil
local hoveredPerk = nil
local hoveredBlackjackButton = nil
local roomManager = nil
local fonts = {}

function saloon:enter(_, _player, _roomManager)
    if not bgImage then
        local ok, img = pcall(love.graphics.newImage, "assets/backgrounds/saloonLobby.png")
        bgImage = ok and img or nil
    end
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

function saloon:update(dt)
    if messageTimer > 0 then
        messageTimer = messageTimer - dt
    end
    if mode == "perk_selection" and perkOptions then
        local mx, my = windowToGame(love.mouse.getPosition())
        hoveredPerk = PerkCard.getHovered(perkOptions, mx, my)
    elseif mode == "blackjack" then
        local mx, my = windowToGame(love.mouse.getPosition())
        hoveredBlackjackButton = hitBlackjackButton(mx, my)
    end
end

function saloon:keypressed(key)
    if mode == "main" then
        if key == "1" then
            if player.gold < blackjackGame.minBet then
                message = "Need at least $" .. blackjackGame.minBet .. " to play blackjack."
                messageTimer = 2
            else
                mode = "blackjack"
                blackjackGame:beginBetting()
            end
        elseif key == "2" then
            mode = "shop"
        elseif key == "return" or key == "3" then
            continueGame()
        end
    elseif mode == "blackjack" then
        if blackjackGame.state == "betting" then
            if key == "left" or key == "a" or key == "-" or key == "kp-" then
                blackjackGame:adjustWager(-blackjackGame.betStep, player.gold)
            elseif key == "right" or key == "d" or key == "=" or key == "kp+" then
                blackjackGame:adjustWager(blackjackGame.betStep, player.gold)
            elseif key == "return" or key == "space" then
                if blackjackGame.wager >= blackjackGame.minBet and player.gold >= blackjackGame.wager then
                    player.gold = player.gold - blackjackGame.wager
                    blackjackGame:deal(blackjackGame.wager)
                else
                    message = "Not enough gold to bet that much!"
                    messageTimer = 2
                end
            elseif key == "escape" or key == "backspace" then
                mode = "main"
            end
        elseif blackjackGame.state == "playing" then
            if key == "h" then
                blackjackGame:hit()
            elseif key == "s" then
                blackjackGame:stand()
            elseif key == "d" then
                local cost = blackjackGame:doubleDown(player.gold)
                if cost then
                    player.gold = player.gold - cost
                else
                    message = "Cannot double."
                    messageTimer = 1.2
                end
            elseif key == "p" then
                local cost = blackjackGame:split(player.gold)
                if cost then
                    player.gold = player.gold - cost
                else
                    message = "Cannot split."
                    messageTimer = 1.2
                end
            end
        elseif blackjackGame.state == "result" then
            if key == "return" or key == "space" then
                local reward = blackjackGame:getReward()
                player.gold = player.gold + reward.gold
                if reward.perkRarity == "rare" or reward.anyWin then
                    perkOptions = Perks.rollPerks(3, player.stats.luck)
                    mode = "perk_selection"
                else
                    mode = "main"
                end
            end
        end
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
            mode = "main"
            perkOptions = nil
        end
    end
end

function saloon:mousepressed(x, y, button)
    if mode == "perk_selection" and button == 1 and hoveredPerk then
        player:applyPerk(perkOptions[hoveredPerk])
        mode = "main"
        perkOptions = nil
        return
    end
    if mode == "blackjack" and button == 1 then
        local mx, my = windowToGame(x, y)
        local action = hitBlackjackButton(mx, my)
        if action then
            handleBlackjackAction(action)
        end
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
    if bgImage then
        love.graphics.setColor(1, 1, 1)
        local bw, bh = bgImage:getDimensions()
        local scale = math.max(screenW / bw, screenH / bh)
        local drawX = (screenW - bw * scale) / 2
        local drawY = (screenH - bh * scale) / 2
        love.graphics.draw(bgImage, drawX, drawY, 0, scale, scale)
        -- Darken slightly so text stays readable
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)
    else
        love.graphics.setColor(0.12, 0.08, 0.05)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)
        love.graphics.setColor(0.35, 0.2, 0.1)
        love.graphics.rectangle("fill", 0, screenH * 0.85, screenW, screenH * 0.15)
        love.graphics.setColor(0.5, 0.3, 0.15)
        love.graphics.rectangle("fill", 0, screenH * 0.84, screenW, 4)
    end

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
        drawBlackjack(screenW, screenH)
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

function drawBlackjack(screenW, screenH)
    local y = 130
    love.graphics.setFont(fonts.card)

    -- Wager
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf("Wager: $" .. blackjackGame.wager, 0, y, screenW, "center")
    y = y + 40

    if blackjackGame.state == "betting" then
        love.graphics.setColor(0.9, 0.8, 0.6)
        love.graphics.printf("Use A/D or -/+ to change bet (min $" .. blackjackGame.minBet .. ")", 0, y, screenW, "center")
        y = y + 26
        love.graphics.printf("Press ENTER to deal, ESC to leave", 0, y, screenW, "center")
        drawBlackjackButtons(screenW, screenH, {
            { id = "bet_down", label = "-" },
            { id = "bet_up", label = "+" },
            { id = "deal", label = "Deal" },
            { id = "leave", label = "Back" },
        })
        return
    end

    -- Dealer hand
    love.graphics.setColor(0.8, 0.6, 0.4)
    love.graphics.printf("Dealer:", 0, y, screenW, "center")
    y = y + 30
    local dealerStr = ""
    for i, card in ipairs(blackjackGame.dealerHand) do
        if i > 1 and blackjackGame.state == "playing" then
            dealerStr = dealerStr .. " [??]"
        else
            dealerStr = dealerStr .. " [" .. Blackjack.cardToString(card) .. "]"
        end
    end
    if blackjackGame.state ~= "playing" then
        dealerStr = dealerStr .. "  (" .. blackjackGame:handValue(blackjackGame.dealerHand) .. ")"
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(dealerStr, 0, y, screenW, "center")
    y = y + 50

    -- Player hands
    love.graphics.setColor(0.8, 0.6, 0.4)
    love.graphics.printf("Your hands:", 0, y, screenW, "center")
    y = y + 30
    for i, hand in ipairs(blackjackGame.hands) do
        local prefix = "  "
        if blackjackGame.state == "playing" and i == blackjackGame.activeHand then
            prefix = "> "
        end
        local handStr = prefix .. "Hand " .. i .. "  ($" .. hand.wager .. ")"
        local cardsStr = ""
        for _, card in ipairs(hand.cards) do
            cardsStr = cardsStr .. " [" .. Blackjack.cardToString(card) .. "]"
        end
        local val = blackjackGame:handValue(hand.cards)
        handStr = handStr .. cardsStr .. "  (" .. val .. ")"
        if hand.doubled then
            handStr = handStr .. "  [Double]"
        elseif hand.isSplit then
            handStr = handStr .. "  [Split]"
        end
        if blackjackGame.state == "result" and hand.result then
            handStr = handStr .. "  - " .. string.upper(hand.result)
        end
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(handStr, 0, y, screenW, "center")
        y = y + 28
    end
    y = y + 12

    if blackjackGame.state == "playing" then
        love.graphics.setColor(0.9, 0.8, 0.6)
        love.graphics.printf("[H] Hit  |  [S] Stand  |  [D] Double  |  [P] Split", 0, y, screenW, "center")
        drawBlackjackButtons(screenW, screenH, {
            { id = "hit", label = "Hit" },
            { id = "stand", label = "Stand" },
            { id = "double", label = "Double" },
            { id = "split", label = "Split" },
        })
    elseif blackjackGame.state == "result" then
        local resultColor = {1, 1, 1}
        if blackjackGame.result == "win" or blackjackGame.result == "blackjack" then
            resultColor = {0.2, 1, 0.2}
        elseif blackjackGame.result == "push" then
            resultColor = {1, 0.9, 0.4}
        elseif blackjackGame.result == "lose" or blackjackGame.result == "bust" then
            resultColor = {1, 0.3, 0.3}
        end
        love.graphics.setColor(resultColor[1], resultColor[2], resultColor[3])
        love.graphics.printf(blackjackGame.resultMessage, 0, y, screenW, "center")
        y = y + 40
        love.graphics.setColor(0.7, 0.7, 0.7)
        love.graphics.printf("Press ENTER to continue", 0, y, screenW, "center")
        drawBlackjackButtons(screenW, screenH, {
            { id = "continue", label = "Continue" },
        })
    end
end

local function blackjackButtonLayout(screenW, screenH, labels)
    local bw, bh = 140, 44
    local gap = 12
    local totalW = #labels * bw + (#labels - 1) * gap
    local x0 = (screenW - totalW) * 0.5
    local y = screenH * 0.76
    local rects = {}
    for i, b in ipairs(labels) do
        rects[i] = { id = b.id, label = b.label, x = x0 + (i - 1) * (bw + gap), y = y, w = bw, h = bh }
    end
    return rects
end

function drawBlackjackButtons(screenW, screenH, labels)
    local rects = blackjackButtonLayout(screenW, screenH, labels)
    for _, r in ipairs(rects) do
        local hov = hoveredBlackjackButton == r.id
        if hov then
            love.graphics.setColor(0.22, 0.14, 0.08, 0.9)
        else
            love.graphics.setColor(0.12, 0.08, 0.06, 0.75)
        end
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6, 6)
        love.graphics.setColor(0.85, 0.65, 0.35, hov and 1 or 0.65)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 6, 6)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 0.95, 0.82)
        love.graphics.setFont(fonts.body)
        love.graphics.printf(r.label, r.x, r.y + 12, r.w, "center")
    end
end

function hitBlackjackButton(mx, my)
    if mode ~= "blackjack" then return nil end
    local labels = nil
    if blackjackGame.state == "betting" then
        labels = {
            { id = "bet_down", label = "-" },
            { id = "bet_up", label = "+" },
            { id = "deal", label = "Deal" },
            { id = "leave", label = "Back" },
        }
    elseif blackjackGame.state == "playing" then
        labels = {
            { id = "hit", label = "Hit" },
            { id = "stand", label = "Stand" },
            { id = "double", label = "Double" },
            { id = "split", label = "Split" },
        }
    elseif blackjackGame.state == "result" then
        labels = {
            { id = "continue", label = "Continue" },
        }
    end
    if not labels then return nil end
    local rects = blackjackButtonLayout(GAME_WIDTH, GAME_HEIGHT, labels)
    for _, r in ipairs(rects) do
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            return r.id
        end
    end
    return nil
end

function handleBlackjackAction(action)
    if blackjackGame.state == "betting" then
        if action == "bet_down" then
            blackjackGame:adjustWager(-blackjackGame.betStep, player.gold)
        elseif action == "bet_up" then
            blackjackGame:adjustWager(blackjackGame.betStep, player.gold)
        elseif action == "deal" then
            if blackjackGame.wager >= blackjackGame.minBet and player.gold >= blackjackGame.wager then
                player.gold = player.gold - blackjackGame.wager
                blackjackGame:deal(blackjackGame.wager)
            else
                message = "Not enough gold to bet that much!"
                messageTimer = 2
            end
        elseif action == "leave" then
            mode = "main"
        end
    elseif blackjackGame.state == "playing" then
        if action == "hit" then
            blackjackGame:hit()
        elseif action == "stand" then
            blackjackGame:stand()
        elseif action == "double" then
            local cost = blackjackGame:doubleDown(player.gold)
            if cost then
                player.gold = player.gold - cost
            else
                message = "Cannot double."
                messageTimer = 1.2
            end
        elseif action == "split" then
            local cost = blackjackGame:split(player.gold)
            if cost then
                player.gold = player.gold - cost
            else
                message = "Cannot split."
                messageTimer = 1.2
            end
        end
    elseif blackjackGame.state == "result" then
        if action == "continue" then
            local reward = blackjackGame:getReward()
            player.gold = player.gold + reward.gold
            if reward.perkRarity == "rare" or reward.anyWin then
                perkOptions = Perks.rollPerks(3, player.stats.luck)
                mode = "perk_selection"
            else
                mode = "main"
            end
        end
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
