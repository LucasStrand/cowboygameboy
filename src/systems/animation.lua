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
-- Only if jab.png is missing from disk (normal case: melee uses jab.png; pickup uses quickdraw.png).
local COWBOY_V2_MELEE_FILE_FALLBACK = { file = "quickdraw.png", frames = 6, fps = 14, loop = false, startFrame = 1, footYOffset = 5 }

SKIN_ANIMS["cowboy_v2"] = {
    -- idle.png: 48px-tall cells; frame count = image width / 48 (Animator clamps if data overshoots).
    idle         = { file = "idle.png",         frames = 8,  fps = 6,  loop = true,  footYOffset = 5 },
    -- Standing ready when active slot is melee (gun holstered / empty slot).
    idle_melee   = { file = "fightstance.png",  frames = 8,  fps = 6,  loop = true,  footYOffset = 5 },
    -- Loot magnet + weapon equip from floor (reach at end of strip).
    pickup       = { file = "quickdraw.png",    frames = 6,  fps = 14, loop = false, footYOffset = 5 },
    smoking      = { file = "smoking.png",       frames = 8,  fps = 5,  loop = true,  footYOffset = 5 },
    run          = { file = "run.png",           frames = 8,  fps = 10, loop = true,  footYOffset = 5 },
    -- Air: PixelLab `jumping-1` pack (per-frame east); same strip for fall so descent isn’t a static idle frame.
    jump         = { stripFromDir = "animations/jumping-1/east", frames = 9, fps = 12, loop = true,  footYOffset = 5 },
    fall         = { stripFromDir = "animations/jumping-1/east", frames = 9, fps = 12, loop = true,  footYOffset = 5 },
    dash         = { file = "dash.png",          frames = 6,  fps = 16, loop = true,  footYOffset = 5 },
    shoot        = { file = "shoot.png",         frames = 6,  fps = 14, loop = false, footYOffset = 5 },
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

-- Shared sheet cache so each PNG is loaded once across all players / animators.
local _sheetCache = {}

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
    end

    local self = setmetatable({}, Animator)
    self.sheets = {}    -- sheet per animation name
    self.quads  = {}    -- quads[animName][frameIndex]
    self.frameCaps = {} -- max frame index with a valid quad (never > strip columns)

    for name, def in pairs(ANIMS) do
        local sheet
        if def.stripFromDir then
            sheet = loadSheetFromDir(def.stripFromDir, def.frames)
        else
            sheet = loadSheet(def.file)
        end
        self.sheets[name] = sheet
        local sw, sh = sheet:getDimensions()
        -- Derive total columns in this strip from image width / frame height (square frames)
        local totalCols = math.floor(sw / FRAME_H)
        local startCol  = (def.startFrame or 1) - 1  -- 0-indexed
        self.quads[name] = {}
        local built = 0
        for i = 0, def.frames - 1 do
            local col = startCol + i
            if col < totalCols then
                built = built + 1
                self.quads[name][built] = love.graphics.newQuad(
                    col * FRAME_H, 0, FRAME_H, FRAME_H, sw, sh
                )
            end
        end
        self.frameCaps[name] = math.max(1, built)
    end

    self.current = "idle"
    self.frame   = 1
    self.timer   = 0
    self.done    = false
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
end

function Animator:drawCentered(cx, footY, facingRight, yOffset, alpha)
    local quads = self.quads[self.current]
    if not quads then return end
    local quad = quads[self.frame]
    if not quad then return end

    local def = ANIMS[self.current]
    local footDy = (def and def.footYOffset) or 0

    local sheet   = self.sheets[self.current]
    local scaledW = FRAME_H * SPRITE_SCALE
    local scaledH = FRAME_H * SPRITE_SCALE

    local drawX   = cx - scaledW / 2
    local drawY   = footY - scaledH + (yOffset or 0) + footDy

    local sx        = facingRight and SPRITE_SCALE or -SPRITE_SCALE
    local flipShift = facingRight and 0 or scaledW

    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(sheet, quad, drawX + flipShift, drawY, 0, sx, SPRITE_SCALE)
end

return Animator
