-- Sprite animator — loads individual horizontal sprite-strip PNGs from
-- assets/sprites/<SKIN>/.  Each strip is a single row of equal-width frames
-- at 48 px tall.  Frame width is derived from image width / frame count.
--
-- To switch skins change SKIN below (see docs/character_skin_template.md).

local FRAME_H      = 48
-- World scale for player sprite (was 0.85; ~48px tall at 1.0 reads closer to NPC scale)
local SPRITE_SCALE = 1.0

local SKIN      = "cowboy_v2"   -- "cowboy" = original hand-authored, "cowboy_v2" = PixelLab generated
local STRIP_DIR = "assets/sprites/" .. SKIN .. "/"

-- Per-skin animation definitions.  Frame counts must match the actual strip widths.
local SKIN_ANIMS = {}

-- cowboy (original hand-authored strips)
SKIN_ANIMS["cowboy"] = {
    idle         = { file = "idle.png",         frames = 7,  fps = 6,  loop = true  },
    smoking      = { file = "smoking.png",       frames = 9,  fps = 5,  loop = true  },
    run          = { file = "run.png",           frames = 8,  fps = 10, loop = true  },
    jump         = { file = "draw.png",          frames = 1,  fps = 1,  loop = true,  startFrame = 1 },
    fall         = { file = "draw.png",          frames = 1,  fps = 1,  loop = true,  startFrame = 2 },
    dash         = { file = "draw.png",          frames = 3,  fps = 16, loop = true,  startFrame = 1 },
    shoot        = { file = "shoot.png",         frames = 5,  fps = 14, loop = false },
    melee        = { file = "quickdraw.png",     frames = 6,  fps = 14, loop = false, startFrame = 1 },
    crouch       = { file = "idle.png",          frames = 1,  fps = 1,  loop = true,  startFrame = 1 },
    crouch_walk  = { file = "run.png",           frames = 8,  fps = 10, loop = true },
}

-- cowboy_v2 (PixelLab-generated, character_id: e4dda30e-08d1-4fbe-b4fe-97bb2b46a52e)
-- footYOffset: shifts sprite down (quad bottom = footY + footYOffset) when soles sit above
-- the 48px cell bottom. All v2 strips use the same ~5px padding; 8 overshot into the floor.
-- Jab: generic 3×48 strip; knife uses knife-jab.png when present (see Animator.new).
local COWBOY_V2_JAB = { file = "jab.png", frames = 3, fps = 10, loop = false, footYOffset = 5 }
local COWBOY_V2_KNIFE_JAB = { file = "knife-jab.png", frames = 3, fps = 10, loop = false, footYOffset = 5 }
-- Only if jab.png is missing from disk (normal case: melee uses jab.png).
local COWBOY_V2_MELEE_FILE_FALLBACK = { file = "quickdraw.png", frames = 6, fps = 14, loop = false, startFrame = 1, footYOffset = 5 }

SKIN_ANIMS["cowboy_v2"] = {
    -- idle.png: current strip is 288x48, so the idle loop is 6 frames at 48px each.
    idle         = { file = "idle.png",         frames = 6,  fps = 6,  loop = true,  footYOffset = 5 },
    -- Standing ready when active slot is melee (gun holstered / empty slot).
    idle_melee   = { file = "fightstance.png",  frames = 8,  fps = 6,  loop = true,  footYOffset = 5 },
    -- Interact (E): equip weapon from floor — dedicated 5-frame bend/reach strip.
    pickup       = { file = "pickup.png",       frames = 5,  fps = 12, loop = false, footYOffset = 5 },
    smoking      = { file = "smoking.png",       frames = 8,  fps = 5,  loop = true,  footYOffset = 5 },
    run          = { file = "run.png",           frames = 8,  fps = 10, loop = true,  footYOffset = 5 },
    -- Air: same idea as original v2 `draw.png` — one pose rising, one pose falling (not a looping jump cycle).
    -- draw.png was removed; `jumping-1` per-frame pack is stitched to a strip; columns match frame_000.. order.
    jump         = { stripFromDir = "animations/jumping-1/east", frames = 1, fps = 1,  loop = true,  startFrame = 1, footYOffset = 5 },
    fall         = { stripFromDir = "animations/jumping-1/east", frames = 1, fps = 1,  loop = true,  startFrame = 5, footYOffset = 5 },
    -- Landing pose: frame_002 (deep crouch impact). Single frame held ~0.22s via fps so it doesn’t flash away.
    land         = { stripFromDir = "animations/jumping-1/east", frames = 1, fps = 1 / 0.22, loop = false, startFrame = 3, footYOffset = 5 },
    -- 3-frame strip plays in DASH_STRIP_TIME; rest of Player DASH_DURATION holds last frame (longer dash pose).
    dash         = { file = "dash.png",          frames = 3,  fps = 3 / 0.10, loop = false, footYOffset = 5 },
    -- shoot.png: 8×56px frames (448 wide). Recoil/muzzle frames shift the body in-cell; anchorFeet pins bottom-center so the cowboy doesn’t moonwalk.
    shoot        = { file = "shoot.png",         frames = 8,  fps = 14, loop = false, footYOffset = 5, cellH = 48, inferCellWidth = true, anchorFeet = true },
    -- Rifle/long-gun shoot: custom 16-frame strip built from per-frame PNGs.
    shoot_rifle  = { stripFromDir = "animations/rifle-shoot/east", frames = 16, fps = 20, loop = false, footYOffset = 5 },
    -- AK-47: 512×64 cells, drawn 1:1. Startup foot align: ~16 sank into floor, ~12 floated — split at 14.
    shoot_ak47_startup = { file = "ak47shooting.png", startFrame = 1, frames = 4, fps = 16, loop = false, footYOffset = 14, cellW = 64, cellH = 64, scaleCellToFrameHeight = false },
    shoot_ak47_loop    = { file = "ak47shooting.png", startFrame = 5, frames = 3, fps = 22, loop = true,  footYOffset = 13, cellW = 64, cellH = 64, scaleCellToFrameHeight = false },
    shoot_ak47_end     = { file = "ak47shooting.png", startFrame = 8, frames = 1, fps = 16, loop = false, footYOffset = 14, cellW = 64, cellH = 64, scaleCellToFrameHeight = false },
    jab          = COWBOY_V2_JAB,
    knife_jab    = COWBOY_V2_KNIFE_JAB,
    melee_fist   = COWBOY_V2_JAB,
    melee        = COWBOY_V2_JAB,
    -- 7 frames in ~0.95s; Player.DEATH_DURATION is longer so the last pose holds before game over.
    death        = { file = "death.png",         frames = 7,  fps = 7 / 0.95, loop = false, footYOffset = 5 },
    -- Built from per-frame PNGs (see stripFromDir); saloon Monster drink + matches bartender/dealer art.
    drinking     = { stripFromDir = "animations/drinking/east", frames = 6, fps = 10, loop = false, footYOffset = 5 },
    -- Static crouch = frame 1; walk cycles all 6 (crouching.png).
    crouch       = { file = "crouching.png",     frames = 1, fps = 6,  loop = true,  startFrame = 1, footYOffset = 5 },
    crouch_walk  = { file = "crouching.png",     frames = 6, fps = 9,  loop = true,  startFrame = 1, footYOffset = 5 },
}

local ANIMS = assert(SKIN_ANIMS[SKIN], "Unknown skin: " .. SKIN)

local Animator = {}
Animator.__index = Animator

local cowboyV2MeleeResolved = false
local EPSILON = 0.0001

-- Shared sheet cache so each PNG is loaded once across all players / animators.
local _sheetCache = {}
local _rotationCache = {}

local function loadSheet(filename)
    if not _sheetCache[filename] then
        local img = love.graphics.newImage(STRIP_DIR .. filename)
        img:setFilter("nearest", "nearest")
        _sheetCache[filename] = img
    end
    return _sheetCache[filename]
end

--- Horizontal strip from frame_000.png … under STRIP_DIR .. dirRel (e.g. animations/drinking/east).
local function loadSheetFromDir(dirRel, frameCount)
    local cacheKey = "dir:" .. dirRel .. ":" .. tostring(frameCount)
    if _sheetCache[cacheKey] then
        return _sheetCache[cacheKey]
    end
    local base = STRIP_DIR .. dirRel
    if base:sub(-1) ~= "/" then
        base = base .. "/"
    end
    local w, h = frameCount * FRAME_H, FRAME_H
    local sheet = love.image.newImageData(w, h)
    for i = 0, frameCount - 1 do
        local path = string.format("%sframe_%03d.png", base, i)
        local ok, tile = pcall(love.image.newImageData, path)
        if not ok or not tile then
            error("Animator: missing frame " .. path)
        end
        sheet:paste(tile, i * FRAME_H, 0, 0, 0, FRAME_H, FRAME_H)
    end
    local img = love.graphics.newImage(sheet)
    img:setFilter("nearest", "nearest")
    _sheetCache[cacheKey] = img
    return img
end

local function loadRotationSprite(name)
    if _rotationCache[name] ~= nil then
        return _rotationCache[name] or nil
    end
    local path = STRIP_DIR .. "rotations/" .. name .. ".png"
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
        img:setFilter("nearest", "nearest")
        _rotationCache[name] = img
        return img
    end
    _rotationCache[name] = false
    return nil
end

function Animator.new()
    if not cowboyV2MeleeResolved and SKIN == "cowboy_v2" then
        cowboyV2MeleeResolved = true
        local v2 = SKIN_ANIMS["cowboy_v2"]
        if not love.filesystem.getInfo(STRIP_DIR .. "knife-jab.png") then
            if love.filesystem.getInfo(STRIP_DIR .. "jab.png") then
                v2.knife_jab = COWBOY_V2_JAB
            else
                v2.knife_jab = COWBOY_V2_MELEE_FILE_FALLBACK
            end
        end
        if not love.filesystem.getInfo(STRIP_DIR .. "jab.png") then
            v2.jab = COWBOY_V2_MELEE_FILE_FALLBACK
            v2.melee = COWBOY_V2_MELEE_FILE_FALLBACK
            v2.melee_fist = COWBOY_V2_MELEE_FILE_FALLBACK
        end
        if not love.filesystem.getInfo(STRIP_DIR .. "pickup.png") then
            v2.pickup = { file = "quickdraw.png", frames = 6, fps = 14, loop = false, footYOffset = 5 }
        end
    end

    local self = setmetatable({}, Animator)
    self.sheets = {}    -- sheet per animation name
    self.quads  = {}    -- quads[animName][frameIndex]
    self.frameCaps = {} -- max frame index with a valid quad (never > strip columns)

    for name, def in pairs(ANIMS) do
        local sheet
        if def.stripFromDir then
            -- Load enough source tiles so startFrame + span fits (e.g. fall uses frame 5 of jumping-1).
            local spanEnd = (def.startFrame or 1) + (def.frames or 1) - 1
            local stripTileCount = math.max(def.frames, spanEnd)
            sheet = loadSheetFromDir(def.stripFromDir, stripTileCount)
        else
            sheet = loadSheet(def.file)
        end
        self.sheets[name] = sheet
        local sw, sh = sheet:getDimensions()
        local cellW = def.cellW or FRAME_H
        local cellH = def.cellH or FRAME_H
        if def.inferCellWidth then
            cellW = math.floor(sw / def.frames)
        end
        -- Frame index along the strip (each cell is cellW wide)
        local totalCols = math.floor(sw / cellW)
        local startCol  = (def.startFrame or 1) - 1  -- 0-indexed
        self.quads[name] = {}
        local built = 0
        for i = 0, def.frames - 1 do
            local col = startCol + i
            if col < totalCols then
                built = built + 1
                self.quads[name][built] = love.graphics.newQuad(
                    col * cellW, 0, cellW, cellH, sw, sh
                )
            end
        end
        self.frameCaps[name] = math.max(1, built)
    end

    self.current = "idle"
    self.frame   = 1
    self.timer   = 0
    self.done    = false
    self.motionSpeed = 0
    self.motionVy = 0
    self.squashStretchImpulse = 0
    self.squashStretchDamping = 8.5
    return self
end

function Animator:play(name, force)
    if not self.quads[name] then return end
    if self.current == name and not force then return end
    self.current = name
    self.frame   = 1
    self.timer   = 0
    self.done    = false
end

function Animator:update(dt)
    local def = ANIMS[self.current]
    if not def then return end
    local cap = (self.frameCaps and self.frameCaps[self.current]) or def.frames
    self.timer = self.timer + dt
    local interval = 1 / def.fps
    if self.timer >= interval then
        self.timer = self.timer - interval
        if self.frame < cap then
            self.frame = self.frame + 1
        elseif def.loop then
            self.frame = 1
        else
            self.done = true
        end
    end
    local damp = math.exp(-self.squashStretchDamping * dt)
    self.squashStretchImpulse = self.squashStretchImpulse * damp
end

function Animator:setMotion(vx, vy)
    self.motionSpeed = math.abs(vx or 0)
    self.motionVy = vy or 0
end

function Animator:triggerSquashStretch(amount)
    if amount == nil then return end
    self.squashStretchImpulse = math.max(-0.4, math.min(0.4, (self.squashStretchImpulse or 0) + amount))
end

function Animator:drawCentered(cx, footY, facingRight, yOffset, alpha)
    local quads = self.quads[self.current]
    if not quads then return end
    local quad = quads[self.frame]
    if not quad then return end

    local def = ANIMS[self.current]
    local footDy = (def and def.footYOffset) or 0

    local sheet   = self.sheets[self.current]
    local cellW = def.cellW or FRAME_H
    local cellH = def.cellH or FRAME_H
    if def.inferCellWidth then
        local sw = sheet:getDimensions()
        cellW = math.floor(sw / def.frames)
    end
    -- Default: squash tall cells down to FRAME_H world height (uniform scale). Optional off for 1:1 texels (AK vs idle).
    local squash = def.scaleCellToFrameHeight
    if squash == nil then squash = true end
    local norm = 1
    if squash then
        norm = FRAME_H / cellH
    end
    local sm = SPRITE_SCALE * norm
    local speedStretch = math.min(0.09, (self.motionSpeed or 0) / 560)
    local airborneStretch = 0
    if self.current == "jump" or self.current == "fall" or self.current == "dash" then
        airborneStretch = math.min(0.12, math.abs(self.motionVy or 0) / 900 * 0.12)
    end
    local impulse = self.squashStretchImpulse or 0
    local stretchY = speedStretch + airborneStretch - impulse
    local syMul = math.max(0.82, 1 + stretchY)
    local sxMul = 1 / math.max(EPSILON, syMul)
    local sxm = sm * sxMul
    local sym = sm * syMul
    local scaledW = cellW * sxm
    local scaledH = cellH * sym

    love.graphics.setColor(1, 1, 1, alpha or 1)
    local yWorld = footY + footDy + (yOffset or 0)

    -- Pin bottom-center of the frame to (cx, yWorld): recoil art shifts inside the cell; centering the whole cell slides the body.
    if def.anchorFeet then
        if facingRight then
            love.graphics.draw(sheet, quad, cx, yWorld, 0, sxm, sym, cellW / 2, cellH)
        else
            -- Flip around the foot anchor (negative sx + origin can smear on some drivers).
            love.graphics.push()
            love.graphics.translate(cx, yWorld)
            love.graphics.scale(-1, 1)
            love.graphics.draw(sheet, quad, 0, 0, 0, sxm, sym, cellW / 2, cellH)
            love.graphics.pop()
        end
    else
        local sx = facingRight and sxm or -sxm
        local drawX = cx - scaledW / 2
        local drawY = footY - scaledH + (yOffset or 0) + footDy
        local flipShift = facingRight and 0 or scaledW
        love.graphics.draw(sheet, quad, drawX + flipShift, drawY, 0, sx, sym)
    end
end

function Animator:getRotation(name)
    if not name then return nil end
    return loadRotationSprite(name)
end

function Animator:drawRotation(name, cx, footY, alpha)
    local img = self:getRotation(name)
    if not img then return false end
    local iw, ih = img:getDimensions()
    local idleDef = ANIMS.idle or {}
    local footDy = idleDef.footYOffset or 0
    local norm = FRAME_H / math.max(1, ih)
    local sm = SPRITE_SCALE * norm
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(img, cx, footY + footDy, 0, sm, sm, iw / 2, ih)
    return true
end

local function drawCenteredInternal(self, animName, frameIndex, cx, footY, facingRight, yOffset, alpha, sliceTop, sliceHeight)
    local quads = self.quads[animName]
    if not quads then return end
    local quad = quads[frameIndex]
    if not quad then return end

    local def = ANIMS[animName]
    local footDy = (def and def.footYOffset) or 0

    local sheet = self.sheets[animName]
    local cellW = def.cellW or FRAME_H
    local cellH = def.cellH or FRAME_H
    if def.inferCellWidth then
        local sw = sheet:getDimensions()
        cellW = math.floor(sw / def.frames)
    end
    local squash = def.scaleCellToFrameHeight
    if squash == nil then squash = true end
    local norm = squash and (FRAME_H / cellH) or 1
    local sm = SPRITE_SCALE * norm
    local speedStretch = math.min(0.09, (self.motionSpeed or 0) / 560)
    local airborneStretch = 0
    if animName == "jump" or animName == "fall" or animName == "dash" then
        airborneStretch = math.min(0.12, math.abs(self.motionVy or 0) / 900 * 0.12)
    end
    local impulse = self.squashStretchImpulse or 0
    local stretchY = speedStretch + airborneStretch - impulse
    local syMul = math.max(0.82, 1 + stretchY)
    local sxMul = 1 / math.max(EPSILON, syMul)
    local sxm = sm * sxMul
    local sym = sm * syMul

    local qx, qy, qw, qh = quad:getViewport()
    local top = math.max(0, math.floor(sliceTop or 0))
    local height = math.max(1, math.floor(sliceHeight or cellH))
    if top >= qh then
        return
    end
    if top + height > qh then
        height = qh - top
    end
    local subQuad = love.graphics.newQuad(qx, qy + top, qw, height, sheet:getDimensions())
    local yWorld = footY + footDy + (yOffset or 0)

    love.graphics.setColor(1, 1, 1, alpha or 1)
    -- For sliced compositing (run+gun), force foot anchoring so upper/lower
    -- halves from different strips align on the same world baseline.
    local useAnchorFeet = def.anchorFeet or (sliceTop ~= nil and sliceHeight ~= nil)
    if useAnchorFeet then
        -- Keep the same world foot anchor as the full frame.
        -- For a cropped slice that starts at `top`, the correct origin is the
        -- distance from slice-top to full-frame bottom.
        local oy = cellH - top
        if facingRight then
            love.graphics.draw(sheet, subQuad, cx, yWorld, 0, sxm, sym, cellW / 2, oy)
        else
            love.graphics.push()
            love.graphics.translate(cx, yWorld)
            love.graphics.scale(-1, 1)
            love.graphics.draw(sheet, subQuad, 0, 0, 0, sxm, sym, cellW / 2, oy)
            love.graphics.pop()
        end
    else
        local sx = facingRight and sxm or -sxm
        local scaledW = cellW * sxm
        local scaledH = cellH * sym
        local drawX = cx - scaledW / 2
        local drawY = footY - scaledH + (yOffset or 0) + footDy
        local topWorld = drawY + top * sym
        local flipShift = facingRight and 0 or scaledW
        love.graphics.draw(sheet, subQuad, drawX + flipShift, topWorld, 0, sx, sym)
    end
end

function Animator:drawCenteredSlice(animName, frameIndex, cx, footY, facingRight, yOffset, alpha, sliceTop, sliceHeight)
    drawCenteredInternal(self, animName, frameIndex, cx, footY, facingRight, yOffset, alpha, sliceTop, sliceHeight)
end

function Animator:getFrameCap(animName)
    return (self.frameCaps and self.frameCaps[animName]) or nil
end

return Animator
