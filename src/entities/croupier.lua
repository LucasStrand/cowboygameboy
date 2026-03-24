--- Travelling croupier: trail coin flip (call heads or tails). No shop.
--- Uses croupier_sprite_data for dealer pose; Pixel Fantasy coin art for the flip UI.
--- The coin is flipped physically in the world (not in a dialog).

local Sfx = require("src.systems.sfx")
local Keybinds = require("src.systems.keybinds")
local GameRng = require("src.systems.game_rng")
local TrailCoinFlip = require("src.systems.trail_coin_flip")
local CroupierSprites = require("src.entities.croupier_sprite_data")
local GoldCoinData = require("src.data.gold_coin")
local Pickup = require("src.entities.pickup")

local Croupier = {}
Croupier.__index = Croupier

local CROUPIER_W = 24
local CROUPIER_H = 36
local INTERACT_RADIUS = 60

local SPRITE_TARGET_H = 48
local SPRITE_FOOT_PAD_PX = 12
local FEET_ON_SURFACE_PX = 2
local IDLE_FRAME_DT = 0.44
local DEAL_FRAME_DT = 0.12

local COIN_PREVIEW_H = 52

---------------------------------------------------------------------------
-- Flip coin constants
---------------------------------------------------------------------------
local FLIP_COIN_SIZE   = 16       -- world pixel size of the flipped coin
local FLIP_COIN_VY     = -280     -- upward launch velocity
local FLIP_COIN_VX_RNG = 25      -- random horizontal spread
local FLIP_FPS         = 10      -- animation fps while airborne

-- How long after coin lands before we resolve outcome
local LAND_PAUSE = 0.45

-- Reward drop velocities (mimic loot drops)
local REWARD_VY = -160
local REWARD_VX_SPREAD = 60

local function sfxFlipLand()
    Sfx.play("chips_collide_" .. tostring(math.random(1, 4)), { volume = 0.45 })
end

function Croupier.new(x, y, difficulty)
    CroupierSprites.ensureLoaded()
    TrailCoinFlip.ensureLoaded()
    local self = setmetatable({}, Croupier)
    self.x = x
    self.y = y
    self.w = CROUPIER_W
    self.h = CROUPIER_H
    self.difficulty = difficulty or 1
    self.state = "idle"         -- "idle" | "gambling" | "flipping" | "landed" | "done"
    self.message = nil
    self.messageTimer = 0
    self.facing = "south"
    self.animFrame = 1
    self.animTimer = 0
    self.animMode = "idle"      -- "idle" | "deal"

    local d = self.difficulty
    self.anteOptions = {
        math.max(5, math.floor(12 + d * 4)),
        math.max(8, math.floor(22 + d * 6)),
        math.max(12, math.floor(38 + d * 8)),
    }
    self:resetGambleState()
    return self
end

function Croupier:resetGambleState()
    self.anteIndex = 1
    self.playerCall = "heads"
    self.flipResult = nil
    self.flipFace = nil
    self.currentAnte = 0
    self.outcomeText = nil

    -- Physical flip coin state
    self.flipCoin = nil         -- { x, y, vx, vy, grounded, coinPhase, landed }
    self.landTimer = 0
    self.rewardsSpawned = false
end

function Croupier:closeGamble()
    self.state = "idle"
    self:resetGambleState()
    self.animFrame = 1
    self.animTimer = 0
    self.animMode = "idle"
end

function Croupier:tryInteract()
    if self.state == "idle" then
        self.state = "gambling"
        self:resetGambleState()
        self.animFrame = 1
        self.animTimer = 0
        return true
    end
    return false
end

--- Called when player confirms the flip. Returns true if flip started.
function Croupier:tryFlip(player)
    local ante = self.anteOptions[self.anteIndex]
    if not player or player.gold < ante then
        self.message = "Stack's light"
        self.messageTimer = 1.5
        Sfx.play("chips_collide_" .. tostring(math.random(1, 4)), { volume = 0.4 })
        return false
    end
    player.gold = player.gold - ante
    self.currentAnte = ante

    -- One uniform 1..4 roll (metal × face). Use a **single** RNG channel for every flip — a new
    -- channel per flip only ever takes the *first* float off a fresh sub-seed, which clusters badly;
    -- sharing "trail_coin_flip" walks the main LCG stream so successive flips are uncorrelated.
    local n = GameRng.random("trail_coin_flip", 1, 4)
    if n == 1 then
        self.flipResult, self.flipFace = "gold", "heads"
    elseif n == 2 then
        self.flipResult, self.flipFace = "gold", "tails"
    elseif n == 3 then
        self.flipResult, self.flipFace = "silver", "heads"
    else
        self.flipResult, self.flipFace = "silver", "tails"
    end

    -- Spawn physical flip coin above dealer
    local cx = self.x + self.w / 2
    local coinX = cx - FLIP_COIN_SIZE / 2
    local coinY = self.y - 4
    local vx = (math.random() - 0.5) * FLIP_COIN_VX_RNG
    self.flipCoin = {
        x = coinX,
        y = coinY,
        w = FLIP_COIN_SIZE,
        h = FLIP_COIN_SIZE,
        vx = vx,
        vy = FLIP_COIN_VY,
        grounded = false,
        coinPhase = math.random() * 8.17,
        landed = false,
    }

    self.state = "flipping"
    self.landTimer = 0
    self.rewardsSpawned = false
    self.outcomeText = nil

    -- Dealer deal animation
    self.animMode = "deal"
    self.animFrame = 1
    self.animTimer = 0

    Sfx.play("chips_handle_" .. tostring(math.random(1, 6)), { volume = 0.5 })
    return true
end

function Croupier:resolveOutcome(player)
    if not self.flipResult or not self.flipFace then return end
    local a = self.currentAnte
    if self.playerCall == self.flipFace then
        self.outcomeText = "+" .. (a * 2) .. "g"
        self.message = self.outcomeText
        self.messageTimer = 2.5
        Sfx.play("pickup_gold", { volume = 0.65 })
    else
        self.outcomeText = "-" .. a .. "g"
        self.message = "Wrong call"
        self.messageTimer = 2.0
        Sfx.play("chips_stack_" .. tostring(math.random(1, 6)), { volume = 0.5 })
    end
    self.state = "landed"
end

--- Spawn reward pickups from dealer position into the world.
function Croupier:spawnRewards(player, world, pickups)
    if self.rewardsSpawned then return end
    self.rewardsSpawned = true
    if not self.flipFace or self.playerCall ~= self.flipFace then return end

    local reward = self.currentAnte * 2
    local cx = self.x + self.w / 2
    local spawnY = self.y

    local specs = GoldCoinData.pickupSpecsForTotal(reward, nil)
    for i, sp in ipairs(specs) do
        local spread = (i - (#specs + 1) / 2) * 8
        local px = cx - 5 + spread
        local p = Pickup.new(px, spawnY, sp.type, sp.value)
        p.vx = (math.random() - 0.5) * REWARD_VX_SPREAD
        p.vy = REWARD_VY - math.random() * 50
        if world then
            world:add(p, p.x, p.y, p.w, p.h)
        end
        if pickups then
            pickups[#pickups + 1] = p
        end
    end
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------
local FLIP_GRAVITY = 600
local FLIP_MAX_VY  = 400

function Croupier:update(dt, px, py, player, world, pickups, platforms)
    -- Message bubble timer
    if self.messageTimer > 0 then
        self.messageTimer = self.messageTimer - dt
        if self.messageTimer <= 0 then
            self.message = nil
        end
    end

    -- Face toward player
    local cx = self.x + self.w / 2
    local cy = self.y + self.h / 2
    if px and py then
        self.facing = CroupierSprites.facingTowardPlayer(px, py, cx, cy)
    end

    -- Deal anim timeout → back to idle anim
    if self.animMode == "deal" then
        local dealFrames = CroupierSprites.getDealingSouthFrames()
        if #dealFrames > 0 then
            self.animTimer = self.animTimer + dt
            if self.animTimer >= DEAL_FRAME_DT then
                self.animTimer = self.animTimer - DEAL_FRAME_DT
                self.animFrame = self.animFrame + 1
                if self.animFrame > #dealFrames then
                    self.animMode = "idle"
                    self.animFrame = 1
                    self.animTimer = 0
                end
            end
        else
            self.animMode = "idle"
        end
    end

    -- Idle breathing animation
    if self.animMode == "idle" then
        local idleLoop = CroupierSprites.getSouthIdleLoop()
        if #idleLoop > 0 and (self.facing == "south" or self.state ~= "idle") then
            self.animTimer = self.animTimer + dt
            if self.animTimer >= IDLE_FRAME_DT then
                self.animTimer = self.animTimer - IDLE_FRAME_DT
                self.animFrame = self.animFrame + 1
                if self.animFrame > #idleLoop then
                    self.animFrame = 1
                end
            end
        end
    end

    -- Physical flip coin physics
    if self.state == "flipping" and self.flipCoin then
        local coin = self.flipCoin
        if not coin.grounded then
            coin.vy = coin.vy + FLIP_GRAVITY * dt
            if coin.vy > FLIP_MAX_VY then coin.vy = FLIP_MAX_VY end
            coin.x = coin.x + coin.vx * dt
            coin.y = coin.y + coin.vy * dt

            -- Simple platform landing check
            if platforms then
                local coinBottom = coin.y + coin.h
                local coinCx = coin.x + coin.w / 2
                for _, plat in ipairs(platforms) do
                    if coin.vy > 0
                       and coinCx >= plat.x and coinCx <= plat.x + plat.w
                       and coinBottom >= plat.y and coinBottom <= plat.y + 12 then
                        coin.y = plat.y - coin.h
                        coin.vy = 0
                        coin.vx = 0
                        coin.grounded = true
                        coin.landed = true
                        sfxFlipLand()
                        break
                    end
                end
            end

            -- Failsafe: if coin falls way below dealer, force land
            if coin.y > self.y + 200 then
                coin.grounded = true
                coin.landed = true
                coin.vy = 0
                coin.vx = 0
                sfxFlipLand()
            end
        end

        -- After landing, wait then resolve
        if coin.landed then
            self.landTimer = self.landTimer + dt
            if self.landTimer >= LAND_PAUSE and self.state == "flipping" then
                self:resolveOutcome(player)
                self:spawnRewards(player, world, pickups)
            end
        end
    end

    -- "landed" state: wait for message to expire, then go back to idle
    if self.state == "landed" then
        -- Flip coin stays visible for a bit then we go done
        self.landTimer = self.landTimer + dt
        if self.landTimer >= LAND_PAUSE + 2.5 then
            self.state = "done"
        end
    end

    -- "done" state: ready to interact again
    if self.state == "done" then
        self.state = "idle"
        self:resetGambleState()
    end
end

--- Keyboard while gambling (ante selection only). game.lua handles Q / escape to close.
function Croupier:onKey(key, player)
    if self.state ~= "gambling" then return end

    if key == "w" or key == "up" then
        self.anteIndex = self.anteIndex - 1
        if self.anteIndex < 1 then
            self.anteIndex = #self.anteOptions
        end
        Sfx.play("ui_confirm", { volume = 0.35 })
        return
    end
    if key == "s" or key == "down" then
        self.anteIndex = self.anteIndex + 1
        if self.anteIndex > #self.anteOptions then
            self.anteIndex = 1
        end
        Sfx.play("ui_confirm", { volume = 0.35 })
        return
    end
    if key == "a" or key == "left" then
        self.playerCall = (self.playerCall == "heads") and "tails" or "heads"
        Sfx.play("ui_confirm", { volume = 0.32 })
        return
    end
    if key == "d" or key == "right" then
        self.playerCall = (self.playerCall == "heads") and "tails" or "heads"
        Sfx.play("ui_confirm", { volume = 0.32 })
        return
    end
    if Keybinds.matches("interact", key) or key == "return" or key == "space" or key == "kpenter" then
        self:tryFlip(player)
        return
    end
end

function Croupier:isNearPlayer(px, py)
    local cx = self.x + self.w / 2
    local cy = self.y + self.h / 2
    local dx = px - cx
    local dy = py - cy
    return dx * dx + dy * dy < INTERACT_RADIUS * INTERACT_RADIUS
end

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------

local function coinDrawSize(img, targetH)
    if not img then return 64, 64, 1 end
    local iw, ih = img:getWidth(), img:getHeight()
    local sc = targetH / ih
    return iw * sc, ih * sc, sc
end

local function drawCoinCentered(img, cx, cy, targetH)
    if not img then return end
    local _, _, sc = coinDrawSize(img, targetH)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, cx, cy, 0, sc, sc, img:getWidth() / 2, img:getHeight() / 2)
end

---------------------------------------------------------------------------
-- World draw (dealer sprite + physical flip coin)
---------------------------------------------------------------------------

function Croupier:draw(showHint, playerGold)
    local cx = self.x + self.w / 2
    local footY = self.y + self.h
    local feetY = footY - FEET_ON_SURFACE_PX

    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.2)
    love.graphics.ellipse("fill", cx, feetY, 14, 4)

    if CroupierSprites.hasSprites() then
        local dealFrames = CroupierSprites.getDealingSouthFrames()
        local idleLoop = CroupierSprites.getSouthIdleLoop()
        local img

        if self.animMode == "deal" and #dealFrames > 0 then
            img = dealFrames[math.min(self.animFrame, #dealFrames)]
        elseif (self.state ~= "idle" or self.facing == "south") and #idleLoop > 0 then
            img = idleLoop[math.min(self.animFrame, #idleLoop)]
        else
            img = CroupierSprites.getRotation(self.facing) or CroupierSprites.getRotation("south")
        end

        if img then
            local iw, ih = img:getWidth(), img:getHeight()
            local scale = SPRITE_TARGET_H / ih
            local drawW = iw * scale
            local drawH = ih * scale
            local drawX = cx - drawW * 0.5
            local drawY = feetY - drawH + SPRITE_FOOT_PAD_PX * scale
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(img, drawX, drawY, 0, scale, scale)
        end
    else
        love.graphics.setColor(0.25, 0.22, 0.18)
        love.graphics.rectangle("fill", self.x + 2, self.y + 8, self.w - 4, self.h - 10, 2)
    end

    love.graphics.setColor(0.75, 0.72, 0.85, 0.95)
    love.graphics.printf("♠", self.x, self.y + 22, self.w, "center")

    if showHint and self.state == "idle" then
        love.graphics.setColor(1, 0.92, 0.3, 0.9)
        love.graphics.printf("[E] Coin flip", cx - 52, self.y - 18, 104, "center")
    end

    if self.message and self.messageTimer > 0 then
        local alpha = math.min(1, self.messageTimer)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.printf(self.message, cx - 50, self.y - 30, 100, "center")
    end

    -- Draw the physical flip coin in the world
    if self.flipCoin then
        local coin = self.flipCoin
        local coinCx = coin.x + coin.w / 2
        local coinCy = coin.y + coin.h / 2

        if coin.grounded and self.flipResult and self.flipFace then
            -- Landed: heads/tails art only (silver coin set — no gold assets on screen)
            local landImg = TrailCoinFlip.getLandedImage("silver", self.flipFace)
            if not landImg then
                landImg = TrailCoinFlip.getImageForSide("silver")
            end
            if landImg then
                local _, _, sc = coinDrawSize(landImg, FLIP_COIN_SIZE)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(landImg, coinCx, coinCy, 0, sc, sc,
                    landImg:getWidth() / 2, landImg:getHeight() / 2)
            end
        else
            -- Airborne: silver flip animation only
            local t = love.timer.getTime() + (coin.coinPhase or 0)
            local frameIdx = math.floor(t * FLIP_FPS) % TrailCoinFlip.frameCount() + 1
            local img = TrailCoinFlip.getFlipFrame("silver", frameIdx) or TrailCoinFlip.getSilver()
            if img then
                local _, _, sc = coinDrawSize(img, FLIP_COIN_SIZE)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(img, coinCx, coinCy, 0, sc, sc,
                    img:getWidth() / 2, img:getHeight() / 2)
            end
        end
    end

    love.graphics.setColor(1, 1, 1)
end

---------------------------------------------------------------------------
-- Gamble UI panel (ante selection only — closes after flip)
---------------------------------------------------------------------------

function Croupier:drawGambleUI(screenX, screenY, playerGold, screenW)
    if self.state ~= "gambling" then return end
    screenW = screenW or 1280
    TrailCoinFlip.ensureLoaded()

    local silverImg = TrailCoinFlip.getSilver()

    local coinRowH = 150
    local headerH = 44
    local panelW = math.min(420, screenW - 48)
    local panelH = headerH + coinRowH + 36
    local px = screenX - panelW / 2
    local py = screenY - panelH - 20

    -- Panel background
    love.graphics.setColor(0.08, 0.06, 0.04, 0.94)
    love.graphics.rectangle("fill", px, py, panelW, panelH, 8)
    love.graphics.setColor(0.55, 0.42, 0.18, 0.85)
    love.graphics.rectangle("line", px, py, panelW, panelH, 8)

    -- Header
    love.graphics.setColor(0.92, 0.78, 0.35)
    love.graphics.printf("TRAIL COIN FLIP", px, py + 6, panelW, "center")
    love.graphics.setColor(0.55, 0.5, 0.38, 0.95)
    love.graphics.printf("Call heads or tails — match the landing face to win", px, py + 26, panelW, "center")

    local rowCx = px + panelW * 0.5
    local rowCy = py + headerH + coinRowH * 0.5 + 4

    -- Heads / tails previews (silver coin face art only)
    local headsPrev = TrailCoinFlip.getLandedImage("silver", "heads") or silverImg
    local tailsPrev = TrailCoinFlip.getLandedImage("silver", "tails") or silverImg
    local gap = 100
    local leftX = rowCx - gap
    local rightX = rowCx + gap
    if headsPrev then
        local a = (self.playerCall == "heads") and 1 or 0.45
        love.graphics.setColor(1, 1, 1, a)
        drawCoinCentered(headsPrev, leftX, rowCy, COIN_PREVIEW_H)
        love.graphics.setColor(0.95, 0.88, 0.75, (self.playerCall == "heads") and 1 or 0.5)
        love.graphics.printf("Heads", leftX - 48, rowCy + COIN_PREVIEW_H * 0.55, 96, "center")
    end
    if tailsPrev then
        local a = (self.playerCall == "tails") and 1 or 0.45
        love.graphics.setColor(1, 1, 1, a)
        drawCoinCentered(tailsPrev, rightX, rowCy, COIN_PREVIEW_H)
        love.graphics.setColor(0.82, 0.88, 0.95, (self.playerCall == "tails") and 1 or 0.5)
        love.graphics.printf("Tails", rightX - 48, rowCy + COIN_PREVIEW_H * 0.55, 96, "center")
    end
    if not headsPrev and not tailsPrev then
        love.graphics.setColor(0.6, 0.55, 0.5, 1)
        love.graphics.printf("Heads / Tails", px, rowCy - 8, panelW, "center")
    end

    -- Footer: ante + controls
    local a = self.anteOptions[self.anteIndex]
    love.graphics.setColor(0.85, 0.78, 0.5)
    love.graphics.printf(
        "Ante: " .. a .. "g   (W/S)   Call: (A/D)   Purse: " .. (playerGold or 0) .. "g",
        px, py + panelH - 52, panelW, "center"
    )
    love.graphics.setColor(0.55, 0.52, 0.45, 0.85)
    love.graphics.printf("[E] Flip   [Q] Walk", px, py + panelH - 30, panelW, "center")

    love.graphics.setColor(1, 1, 1)
end

return Croupier
