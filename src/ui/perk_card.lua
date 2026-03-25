local Perks = require("src.data.perks")
local ContentTooltips = require("src.systems.content_tooltips")
local Font = require("src.ui.font")

local PerkCard = {}

local CARD_W = 200
local CARD_H = 250

-- Card sprite (lazy-loaded)
local _cardSprite
local function getCardSprite()
    if not _cardSprite then
        _cardSprite = love.graphics.newImage("assets/sprites/props/perk_card.png")
        _cardSprite:setFilter("nearest", "nearest")
    end
    return _cardSprite
end
local CARD_SPACING = 40

function PerkCard.draw(perks, selectedIndex, hoveredIndex)
    if not PerkCard._font then
        PerkCard._font = Font.new(15)
    end
    if not PerkCard._fontReason then
        PerkCard._fontReason = Font.new(12)
    end
    local prevFont = love.graphics.getFont()
    love.graphics.setFont(PerkCard._font)

    local screenW = GAME_WIDTH
    local screenH = GAME_HEIGHT
    local totalW = #perks * CARD_W + (#perks - 1) * CARD_SPACING
    local startX = (screenW - totalW) / 2
    local startY = (screenH - CARD_H) / 2

    -- Title
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf("LEVEL UP! Choose a perk:", 0, startY - 60, screenW, "center")

    for i, perk in ipairs(perks) do
        local x = startX + (i - 1) * (CARD_W + CARD_SPACING)
        local y = startY

        local rarityColor = Perks.rarityColors[perk.rarity] or {0.7, 0.7, 0.7}
        local isHovered = (i == hoveredIndex)
        local isSelected = (i == selectedIndex)

        -- Card background sprite
        local cardSpr = getCardSprite()
        local csw, csh = cardSpr:getDimensions()
        local cardScaleX = CARD_W / csw
        local cardScaleY = CARD_H / csh
        if isSelected then
            love.graphics.setColor(rarityColor[1], rarityColor[2], rarityColor[3], 0.8)
        elseif isHovered then
            love.graphics.setColor(0.7, 0.7, 0.7, 0.9)
        else
            love.graphics.setColor(0.5, 0.5, 0.5, 0.9)
        end
        love.graphics.draw(cardSpr, x, y, 0, cardScaleX, cardScaleY)

        -- Rarity border
        love.graphics.setColor(rarityColor[1], rarityColor[2], rarityColor[3])
        love.graphics.setLineWidth(isHovered and 3 or 2)
        love.graphics.rectangle("line", x, y, CARD_W, CARD_H, 8, 8)

        -- Rarity label
        love.graphics.setColor(rarityColor[1], rarityColor[2], rarityColor[3])
        love.graphics.printf(string.upper(perk.rarity), x, y + 15, CARD_W, "center")

        -- Name
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(perk.name, x + 10, y + 50, CARD_W - 20, "center")

        -- Tooltip
        love.graphics.setColor(0.8, 0.8, 0.8)
        love.graphics.printf(ContentTooltips.getJoinedText("perk", perk), x + 15, y + 96, CARD_W - 30, "center")

        if perk.reward_reason and perk.reward_reason ~= "" then
            love.graphics.setFont(PerkCard._fontReason)
            love.graphics.setColor(0.65, 0.78, 0.72, 1)
            love.graphics.printf(perk.reward_reason, x + 10, y + CARD_H - 56, CARD_W - 20, "center")
            love.graphics.setFont(PerkCard._font)
        end

        -- Key hint
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.printf("[" .. i .. "]", x, y + CARD_H - 22, CARD_W, "center")
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(prevFont)
end

function PerkCard.getHovered(perks, mx, my)
    local screenW = GAME_WIDTH
    local screenH = GAME_HEIGHT
    local totalW = #perks * CARD_W + (#perks - 1) * CARD_SPACING
    local startX = (screenW - totalW) / 2
    local startY = (screenH - CARD_H) / 2

    for i = 1, #perks do
        local x = startX + (i - 1) * (CARD_W + CARD_SPACING)
        if mx >= x and mx <= x + CARD_W and my >= startY and my <= startY + CARD_H then
            return i
        end
    end
    return nil
end

return PerkCard
