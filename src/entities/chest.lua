--- Chest entity: a lootable world object that can trigger a skeleton ambush when opened.
--- Not a bump physics body — drawn as a prop, interacted with via proximity check.

local LootTable = require("src.data.loot_table")
local WorldInteractLabel = require("src.ui.world_interact_label")

local Chest = {}
Chest.__index = Chest

-- Sprite sheet: 240×256, 5 columns (frames) × 8 rows (chest types).
-- Each frame is 48×32. Row 0 = wooden brown, Row 3 = gold/ornate, Row 7 = blue.
local CHEST_FRAME_W = 48
local CHEST_FRAME_H = 32
local CHEST_COLS    = 5
local CHEST_OPEN_FRAMES = 5      -- frames 1..5 on the opening row (row+1)
local CHEST_OPEN_FPS    = 6      -- how fast the opening animation plays

-- No vertical offset needed — 32px frame height matches art closely.
local CHEST_DRAW_OFFSET = 0

local _chestSheet = nil
local _chestQuads = {}           -- [row][frame 1..5]

local function loadChestSheet()
    if _chestSheet then return end
    local ok, img = pcall(love.graphics.newImage, "assets/sprites/chest/chest_sheet.png")
    if not ok then return end
    img:setFilter("nearest", "nearest")
    _chestSheet = img
    local sw, sh = img:getDimensions()
    local rows = math.floor(sh / CHEST_FRAME_H)
    for row = 0, rows - 1 do
        _chestQuads[row] = {}
        for col = 0, CHEST_COLS - 1 do
            _chestQuads[row][col + 1] = love.graphics.newQuad(
                col * CHEST_FRAME_W, row * CHEST_FRAME_H,
                CHEST_FRAME_W, CHEST_FRAME_H,
                sw, sh
            )
        end
    end
end

-- Visual constants for the bone-pile prop drawn near each chest.
local BONE_COLOR  = {0.80, 0.76, 0.62}
local BONE_SHADOW = {0.45, 0.42, 0.32, 0.5}

local _skullImg = nil
local function loadSkullImg()
    if _skullImg then return end
    local ok, img = pcall(love.graphics.newImage,
        "assets/free-undead-loot-pixel-art-icons/PNG/Transperent/Icon1.png")
    if not ok then return end
    img:setFilter("nearest", "nearest")
    _skullImg = img
end

--- Draw a tiny pile of bones at (px, py).
--- scale: 0..1 (used during the rising animation to shrink the pile as it becomes a skeleton)
local function drawBonePile(px, py, scale, alpha)
    alpha = alpha or 1
    scale = scale or 1
    -- Shadow
    love.graphics.setColor(BONE_SHADOW[1], BONE_SHADOW[2], BONE_SHADOW[3], BONE_SHADOW[4] * alpha)
    love.graphics.ellipse("fill", px, py + 2, 14 * scale, 4 * scale)
    -- Tibias (procedural)
    love.graphics.setColor(BONE_COLOR[1], BONE_COLOR[2], BONE_COLOR[3], alpha)
    love.graphics.rectangle("fill", px - 9 * scale, py - 3 * scale, 12 * scale, 4 * scale, 2)
    love.graphics.rectangle("fill", px - 2 * scale, py - 7 * scale, 4 * scale, 10 * scale, 2)
    -- Rib fragments
    love.graphics.setColor(BONE_COLOR[1], BONE_COLOR[2], BONE_COLOR[3], alpha * 0.85)
    love.graphics.rectangle("fill", px - 6 * scale, py - 1 * scale, 7 * scale, 2 * scale, 1)
    love.graphics.rectangle("fill", px + 1 * scale, py + 1 * scale, 9 * scale, 2 * scale, 1)
    -- Skull sprite (or fallback circle)
    if _skullImg then
        local iw, ih = _skullImg:getDimensions()
        local skullSize = 14 * scale   -- target render size in pixels
        local sx = skullSize / iw
        local sy = skullSize / ih
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(_skullImg, px + 2 * scale, py - 12 * scale, 0, sx, sy)
    else
        love.graphics.setColor(BONE_COLOR[1], BONE_COLOR[2], BONE_COLOR[3], alpha)
        love.graphics.circle("fill", px + 5 * scale, py - 6 * scale, 5 * scale)
        love.graphics.setColor(0.3, 0.28, 0.22, alpha * 0.8)
        love.graphics.circle("fill", px + 4 * scale, py - 7 * scale, 2 * scale)
        love.graphics.circle("fill", px + 7 * scale, py - 7 * scale, 2 * scale)
    end
end

--- Prompt above the chest sprite (cy = top of chest draw rect).
local function drawInteractHint(cx, chestTopY)
    WorldInteractLabel.drawAboveAnchor(cx, chestTopY, "[E] Open", {
        bobAmp = 1,
        bobTime = love.timer.getTime(),
    })
end

--- Snap chest top Y so the 32px-tall hitbox bottom sits on the platform surface under its center.
--- Refines placement when several platforms overlap horizontally (e.g. bridges).
function Chest.snapYToGround(platforms, ax, ay, chestH)
    chestH = chestH or CHEST_FRAME_H
    local cx = ax + CHEST_FRAME_W / 2
    local targetBottom = ay + chestH
    local bestY = ay
    local bestDist = math.huge
    for _, plat in ipairs(platforms or {}) do
        if cx >= plat.x and cx <= plat.x + plat.w then
            local d = math.abs(plat.y - targetBottom)
            if d < bestDist then
                bestDist = d
                -- Subtract draw offset so sprite visual bottom aligns with platform top
                bestY = plat.y - chestH - CHEST_DRAW_OFFSET
            end
        end
    end
    return bestY
end

-- ─── Constructor ──────────────────────────────────────────────────────────────

--- opts:
---   tier        "normal" | "rich" | "cursed"   (default "normal")
---   spriteRow   0..4   which chest graphic row  (default: tier-based)
---   bonePiles   list of {x=, y=} positions for bone piles (skeletons that rise)
---   fakeAmbush  if true, bone piles are visual-only (no skeletons spawn)
function Chest.new(x, y, opts)
    loadChestSheet()
    loadSkullImg()
    opts = opts or {}
    local self = setmetatable({}, Chest)
    self.x = x
    self.y = y
    -- Chest hitbox (for interaction proximity, not physics)
    self.w = CHEST_FRAME_W
    self.h = CHEST_FRAME_H
    self.tier = opts.tier or "normal"
    -- Which sprite row
    if opts.spriteRow then
        self.spriteRow = opts.spriteRow
    elseif self.tier == "rich" then
        self.spriteRow = 4   -- gold/ornate chest row
    elseif self.tier == "cursed" then
        self.spriteRow = 2   -- dark chest (even row = idle, row 3 = opening anim)
    else
        self.spriteRow = 0   -- wooden brown
    end
    self.bonePiles = opts.bonePiles or {}  -- [{x,y,w,h, _skelRef, riseProgress}, ...]
    -- State: "closed" | "ambushing" | "opening" | "open"
    -- Flow:  closed → (E pressed, has guards) → ambushing → (all dead) → opening → open
    --        closed → (E pressed, no guards)  → opening → open
    self.state = "closed"
    self.animFrame  = 1
    self.animTimer  = 0
    -- Set by game.lua — called with bonePiles when ambush triggers
    self.onAmbush = nil
    -- Set by game.lua — called with (drops) when loot should spawn
    self.onLoot = nil
    self.lootSpawned = false
    self.ambushFired = false
    -- Shake effect on open
    self.shakeTimer  = 0
    -- Cursed: deal damage when the chest is triggered
    self.cursedDamage = (self.tier == "cursed") and 15 or 0
    -- Fake ambush: bone piles are cosmetic only, no skeletons spawn
    self.fakeAmbush = opts.fakeAmbush or false
    return self
end

-- ─── Update ───────────────────────────────────────────────────────────────────

function Chest:update(dt)
    if self.shakeTimer > 0 then
        self.shakeTimer = self.shakeTimer - dt
    end

    if self.state == "ambushing" then
        -- Wait until every linked skeleton is dead before opening
        local allDead = true
        for _, bp in ipairs(self.bonePiles) do
            if bp._skelRef and bp._skelRef.alive ~= false then
                allDead = false
                break
            end
        end
        if allDead then

            self.state = "opening"
            self.animFrame = 1
            self.animTimer = 0
            self.shakeTimer = 0.25
        end
    end

    if self.state == "opening" then
        self.animTimer = self.animTimer + dt

        local interval = 1 / CHEST_OPEN_FPS
        while self.animTimer >= interval do
            self.animTimer = self.animTimer - interval
            if self.animFrame < CHEST_OPEN_FRAMES then
                self.animFrame = self.animFrame + 1
                -- Burst loot at frame 3 (lid visibly lifting) so items fly out mid-animation
                if self.animFrame >= 3 and not self.lootSpawned then
                    self.lootSpawned = true
                    if self.onLoot then
                        self.onLoot(LootTable.rollChest(self.tier))
                    end
                end
            else
                self.state = "open"
                -- Safety fallback in case frame 3 branch was skipped
                if not self.lootSpawned then
                    self.lootSpawned = true
                    if self.onLoot then
                        self.onLoot(LootTable.rollChest(self.tier))
                    end
                end
                break
            end
        end
    end
end

--- Called by game.lua when the player presses E near this chest.
function Chest:tryOpen(player, applyDamage)

    if self.state ~= "closed" then return false end

    -- Cursed chests bite back immediately when triggered
    if self.cursedDamage > 0 and applyDamage then
        applyDamage(self.cursedDamage)
    end

    if not self.ambushFired and #self.bonePiles > 0 and not self.fakeAmbush then
        -- Trigger the skeleton ambush — chest stays locked until guards are defeated

        self.ambushFired = true
        self.state = "ambushing"
        self.shakeTimer = 0.3
        if self.onAmbush then
            self.onAmbush(self.bonePiles)
        end
    else
        -- No guards — open immediately

        self.state = "opening"
        self.animFrame = 1
        self.animTimer = 0
        self.shakeTimer = 0.25
    end
    return true
end

--- Returns the world position from which loot should burst (visual chest opening).
--- The sprite draws from chest.y + CHEST_DRAW_OFFSET; the lid sits near the top of that.
function Chest:getSpawnPos()
    local cx = self.x + self.w / 2
    local cy = self.y + CHEST_DRAW_OFFSET + 6  -- just inside the lid
    return cx, cy
end

--- Returns true when the player is close enough to interact.
function Chest:isNearPlayer(px, py)
    local cx = self.x + self.w / 2
    local cy = self.y + self.h / 2
    local dx = px - cx
    local dy = py - cy
    return dx * dx + dy * dy < 52 * 52
end

-- ─── Draw ─────────────────────────────────────────────────────────────────────

function Chest:draw(player, showHint)
    local sx = 0
    if self.shakeTimer > 0 then
        sx = (math.random() - 0.5) * 4
    end

    -- Bone piles (visible before and during ambush; scale down to zero as skeleton rises)
    for _, bp in ipairs(self.bonePiles) do
        local pileScale = bp.riseProgress and (1 - bp.riseProgress) or 1
        local pileAlpha = pileScale
        if pileAlpha > 0.05 then
            drawBonePile(bp.x + bp.w / 2, bp.y + bp.h, pileScale, pileAlpha)
        end
    end

    -- Chest sprite — paired rows: even = idle (closed), odd = opening animation
    local drawRow = self.spriteRow
    if self.state == "opening" or self.state == "open" then
        drawRow = self.spriteRow + 1
    end
    local row = _chestQuads[drawRow]
    if _chestSheet and row then
        local quad = row[self.animFrame]
        if quad then
            love.graphics.setColor(1, 1, 1)
            local drawX = self.x + sx
            local drawY = self.y + CHEST_DRAW_OFFSET
            love.graphics.draw(_chestSheet, quad, drawX, drawY)
        else
            self:_drawFallback(sx)
        end
    else
        self:_drawFallback(sx)
    end

    -- Interaction hint (only when closed and nearby)
    if showHint and self.state == "closed" then
        local cx = self.x + self.w / 2
        drawInteractHint(cx, self.y + CHEST_DRAW_OFFSET)
    end

    -- "Defeat them!" hint while ambush is active
    if showHint and self.state == "ambushing" then
        local cx = self.x + self.w / 2
        WorldInteractLabel.drawAboveAnchor(cx, self.y + CHEST_DRAW_OFFSET, "Defeat them!", {
            bobAmp = 0.8,
            bobTime = love.timer.getTime(),
            fg = { 1, 0.42, 0.32 },
        })
    end

    -- Cursed warning glow
    if self.state == "closed" and self.tier == "cursed" then
        local dy = CHEST_DRAW_OFFSET
        love.graphics.setColor(0.8, 0.1, 0.05, 0.18 + 0.12 * math.sin(love.timer.getTime() * 4))
        love.graphics.rectangle("fill", self.x - 4, self.y + dy - 4, self.w + 8, self.h + 8, 4)
    end
end

function Chest:_drawFallback(sx)
    sx = sx or 0
    local dy = CHEST_DRAW_OFFSET
    -- Fallback procedural chest when sprite not loaded
    love.graphics.setColor(0.45, 0.28, 0.12)
    love.graphics.rectangle("fill", self.x + sx, self.y + dy + self.h * 0.4, self.w, self.h * 0.6, 3)
    if self.state == "closed" or self.state == "opening" then
        local lidOpen = (self.state == "opening") and ((self.animFrame - 1) / (CHEST_OPEN_FRAMES - 1)) or 0
        local lidH = self.h * 0.45
        love.graphics.setColor(0.55, 0.35, 0.15)
        love.graphics.rectangle("fill",
            self.x + sx,
            self.y + dy + self.h * 0.4 - lidH + lidH * lidOpen * 0.8,
            self.w, lidH, 3)
    end
    -- Latch
    love.graphics.setColor(0.75, 0.62, 0.18)
    love.graphics.rectangle("fill", self.x + self.w / 2 - 3 + sx, self.y + dy + self.h * 0.38, 6, 6, 2)
end

return Chest
