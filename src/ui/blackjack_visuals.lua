---------------------------------------------------------------------------
-- Blackjack Visuals
-- Manages table, dealer sprite, and button sprite rendering
---------------------------------------------------------------------------
local BlackjackVisuals = {}

---------------------------------------------------------------------------
-- Asset paths
---------------------------------------------------------------------------
local TABLE_PATH = "assets/sprites/blackjack_table/table.png"
local DEALER_DIR = "assets/sprites/blackjack_dealer_table"
local BTN_NORMAL_PATH = "assets/sprites/ui_buttons/button_normal.png"
local BTN_HOVER_PATH  = "assets/sprites/ui_buttons/button_hover.png"

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local loaded = false
local tableImg, btnNormalImg, btnHoverImg
local dealerFrames = {}     -- { idle = {frames}, dealing = {frames} }
local dealerAnim = "idle"
local dealerFrame = 1
local dealerTimer = 0
local dealerSpeed = 0.55    -- seconds per frame (idle breathing - slow & subtle)
local dealerDealingDone = nil  -- callback when dealing anim finishes
local dealerQuadCache = {}     -- cached quads keyed by cropTop..cropRatio..imgW..imgH

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------
function BlackjackVisuals.load()
    if loaded then return end
    loaded = true

    -- Table
    local ok, img = pcall(love.graphics.newImage, TABLE_PATH)
    if ok then
        img:setFilter("nearest", "nearest")
        tableImg = img
    end

    -- Buttons
    ok, img = pcall(love.graphics.newImage, BTN_NORMAL_PATH)
    if ok then
        img:setFilter("nearest", "nearest")
        btnNormalImg = img
    end
    ok, img = pcall(love.graphics.newImage, BTN_HOVER_PATH)
    if ok then
        img:setFilter("nearest", "nearest")
        btnHoverImg = img
    end

    -- Dealer animations (idle + dealing)
    local function loadFrames(subdir)
        local frames = {}
        local dir = DEALER_DIR .. "/animations/" .. subdir .. "/south"
        for i = 0, 20 do
            local path = string.format("%s/frame_%03d.png", dir, i)
            local s, f = pcall(love.graphics.newImage, path)
            if s then
                f:setFilter("nearest", "nearest")
                frames[#frames + 1] = f
            end
        end
        return frames
    end

    dealerFrames.idle = loadFrames("breathing-idle")
    dealerFrames.dealing = loadFrames("dealing-cards")

    -- Fallback: load static south rotation if no animation frames found
    if #(dealerFrames.idle) == 0 then
        local s, f = pcall(love.graphics.newImage, DEALER_DIR .. "/rotations/south.png")
        if s then
            f:setFilter("nearest", "nearest")
            dealerFrames.idle = { f }
        end
    end
end

---------------------------------------------------------------------------
-- Dealer animation control
---------------------------------------------------------------------------
function BlackjackVisuals.setDealerAnim(name, onDone)
    if name == dealerAnim and not onDone then return end
    if dealerFrames[name] and #dealerFrames[name] > 0 then
        dealerAnim = name
        dealerFrame = 1
        dealerTimer = 0
        dealerDealingDone = onDone
    end
end

function BlackjackVisuals.getDealerAnim()
    return dealerAnim
end

function BlackjackVisuals.update(dt)
    local frames = dealerFrames[dealerAnim]
    if not frames or #frames <= 1 then return end

    dealerTimer = dealerTimer + dt
    local spd = dealerAnim == "dealing" and 0.12 or dealerSpeed
    if dealerTimer >= spd then
        dealerTimer = dealerTimer - spd
        dealerFrame = dealerFrame + 1
        if dealerFrame > #frames then
            if dealerAnim == "dealing" then
                -- Dealing is one-shot, return to idle
                dealerAnim = "idle"
                dealerFrame = 1
                dealerTimer = 0
                if dealerDealingDone then
                    local cb = dealerDealingDone
                    dealerDealingDone = nil
                    cb()
                end
            else
                dealerFrame = 1
            end
        end
    end
end

---------------------------------------------------------------------------
-- Table rect calculation (used for layout without drawing)
---------------------------------------------------------------------------
local cachedTableRect = nil

function BlackjackVisuals.getTableRect(screenW, screenH)
    if not tableImg then return nil end
    local imgW, imgH = tableImg:getWidth(), tableImg:getHeight()
    local tableDrawW = screenW * 0.92
    local scale = tableDrawW / imgW
    local tableDrawH = imgH * scale
    local tx = (screenW - tableDrawW) * 0.5
    local ty = 20
    cachedTableRect = { x = tx, y = ty, w = tableDrawW, h = tableDrawH, scale = scale }
    return cachedTableRect
end

---------------------------------------------------------------------------
-- Drawing: Table
---------------------------------------------------------------------------
function BlackjackVisuals.drawTable(screenW, screenH)
    if not tableImg then return end
    local r = cachedTableRect or BlackjackVisuals.getTableRect(screenW, screenH)
    if not r then return end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(tableImg, r.x, r.y, 0, r.scale, r.scale)
    return r
end

---------------------------------------------------------------------------
-- Drawing: Dealer (cropped head-to-stomach, placed ON TOP of table edge)
---------------------------------------------------------------------------
local function getQuad(imgW, imgH, cropTop, cropBottom)
    local key = imgW .. "x" .. imgH .. ":" .. cropTop .. ":" .. cropBottom
    if not dealerQuadCache[key] then
        local qY = math.floor(imgH * cropTop)
        local qH = math.floor(imgH * (cropBottom - cropTop))
        dealerQuadCache[key] = love.graphics.newQuad(0, qY, imgW, qH, imgW, imgH)
    end
    return dealerQuadCache[key], math.floor(imgH * (cropBottom - cropTop))
end

function BlackjackVisuals.drawDealer(screenW, tableRect)
    local frames = dealerFrames[dealerAnim]
    if not frames or #frames == 0 then return end
    local frame = frames[math.min(dealerFrame, #frames)]
    if not frame then return end

    local imgW, imgH = frame:getWidth(), frame:getHeight()

    -- Crop: top 60% of sprite (head, chest, arms — cut at stomach/belt)
    local cropTop = 0.0
    local cropBottom = 0.60
    local quad, quadH = getQuad(imgW, imgH, cropTop, cropBottom)

    -- Scale so the cropped dealer fills a nice area above the table
    local tableTop = tableRect and tableRect.y or 20
    local tableH = tableRect and tableRect.h or (screenW * 0.4)
    -- Table inner edge (where felt begins) is about 15% from top of table image
    local feltEdgeY = tableTop + tableH * 0.15
    -- Dealer should be about 55% of table height (large, imposing)
    local targetH = tableH * 0.55
    local scale = targetH / quadH

    -- Position: bottom of cropped sprite sits at the felt edge
    local dx = screenW * 0.5 - (imgW * scale) * 0.5
    local dy = feltEdgeY - targetH

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(frame, quad, dx, dy, 0, scale, scale)
end

---------------------------------------------------------------------------
-- Drawing: Sprite-based button
---------------------------------------------------------------------------
function BlackjackVisuals.drawButton(rect, hovered, disabled, label, font)
    local img = (hovered and not disabled) and btnHoverImg or btnNormalImg
    if img then
        local imgW, imgH = img:getWidth(), img:getHeight()
        local sx = rect.w / imgW
        local sy = rect.h / imgH
        local alpha = disabled and 0.5 or 1
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(img, rect.x, rect.y, 0, sx, sy)
    else
        -- Fallback to procedural drawing
        if hovered and not disabled then
            love.graphics.setColor(0.22, 0.14, 0.08, 0.9)
        else
            love.graphics.setColor(0.12, 0.08, 0.06, disabled and 0.5 or 0.75)
        end
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 6, 6)
        love.graphics.setColor(0.85, 0.65, 0.35, (hovered and not disabled) and 1 or (disabled and 0.35 or 0.65))
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 6, 6)
        love.graphics.setLineWidth(1)
    end

    -- Text label with shadow for readability
    if label and font then
        love.graphics.setFont(font)
        local fh = font:getHeight()
        local textY = rect.y + (rect.h - fh) * 0.5
        -- Shadow
        love.graphics.setColor(0, 0, 0, disabled and 0.4 or 0.9)
        love.graphics.printf(label, rect.x + 2, textY + 1, rect.w, "center")
        -- Text (bright cream/gold)
        local tc = disabled and 0.6 or 1
        love.graphics.setColor(1, 0.92, 0.6, tc)
        love.graphics.printf(label, rect.x, textY, rect.w, "center")
    end
end

---------------------------------------------------------------------------
-- Drawing: Wager panel button (small +/- buttons)
---------------------------------------------------------------------------
function BlackjackVisuals.drawSmallButton(rect, hovered, enabled, label, font)
    local img = hovered and btnHoverImg or btnNormalImg
    if img then
        local imgW, imgH = img:getWidth(), img:getHeight()
        local sx = rect.w / imgW
        local sy = rect.h / imgH
        local alpha = enabled and 1 or 0.5
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(img, rect.x, rect.y, 0, sx, sy)
    else
        if hovered then
            love.graphics.setColor(0.22, 0.14, 0.08, enabled and 0.9 or 0.45)
        else
            love.graphics.setColor(0.12, 0.08, 0.06, enabled and 0.75 or 0.35)
        end
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 4, 4)
        love.graphics.setColor(0.85, 0.65, 0.35, hovered and 1 or (enabled and 0.65 or 0.35))
        love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 4, 4)
    end
    if label and font then
        love.graphics.setFont(font)
        -- Shadow
        love.graphics.setColor(0, 0, 0, enabled and 0.8 or 0.4)
        local textY = rect.y + (rect.h - font:getHeight()) * 0.5
        love.graphics.printf(label, rect.x + 3, textY + 1, rect.w - 4, "center")
        -- Text
        love.graphics.setColor(1, 0.95, 0.82, enabled and 1 or 0.6)
        love.graphics.printf(label, rect.x + 2, textY, rect.w - 4, "center")
    end
end

return BlackjackVisuals
