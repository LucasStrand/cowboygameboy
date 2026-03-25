-- Sprite animator — loads individual horizontal sprite-strip PNGs from
-- assets/sprites/cowboy/.  Each strip is a single row of equal-width frames
-- at 64 px tall.  Frame width is derived from image width / frame count.

local FRAME_H     = 64
local SPRITE_SCALE = 0.64   -- 64 * 0.64 ≈ 41 px drawn height (close to 28 px AABB + headroom)

local STRIP_DIR = "assets/sprites/cowboy/"

-- Animation definitions: file, frame count, fps, loop, and optional sub-range.
-- "file" is the strip PNG basename (without directory).
-- footTrimSrcPx: empty rows below the soles in each 64×64 cell (texture bottom was aligned to
-- collision foot, so soles floated). Shift draw down by footTrimSrcPx * SPRITE_SCALE.
-- For jump/fall/dash/melee we re-use existing strips with startFrame / frames subset.
local ANIMS = {
    idle    = { file = "idle.png",   frames = 15, fps = 8,  loop = true,  footTrimSrcPx = 12 },
    smoking = { file = "idle.png",   frames = 15, fps = 5,  loop = true,  footTrimSrcPx = 12 },  -- no smoking strip; reuse breathe
    run     = { file = "run.png",    frames = 8,  fps = 10, loop = true,  footTrimSrcPx = 12 },
    jump    = { file = "draw.png",   frames = 1,  fps = 1,  loop = true, startFrame = 1, footTrimSrcPx = 6 },
    fall    = { file = "draw.png",   frames = 1,  fps = 1,  loop = true, startFrame = 4, footTrimSrcPx = 6 },
    shoot   = { file = "shoot.png",  frames = 3,  fps = 12, loop = false, footTrimSrcPx = 6 },
    holster      = { file = "draw.png",   frames = 6,  fps = 12, loop = false, footTrimSrcPx = 6 },  -- no holster strip; reuse draw
    holster_spin = { file = "draw.png",   frames = 6,  fps = 14, loop = false, footTrimSrcPx = 6 },  -- no spin strip; reuse draw
    dash    = { file = "draw.png",   frames = 3,  fps = 16, loop = true, startFrame = 1, footTrimSrcPx = 6 },
    melee   = { file = "draw.png",   frames = 6,  fps = 14, loop = false, startFrame = 1, footTrimSrcPx = 6 },  -- no melee strip; reuse draw
}

local Animator = {}
Animator.__index = Animator

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

function Animator.new()
    local self = setmetatable({}, Animator)
    self.sheets = {}  -- sheet per animation name
    self.quads  = {}  -- quads[animName][frameIndex]

    for name, def in pairs(ANIMS) do
        local sheet = loadSheet(def.file)
        self.sheets[name] = sheet
        local sw, sh = sheet:getDimensions()
        -- Derive total columns in this strip from image width / frame height (square frames)
        local totalCols = math.floor(sw / FRAME_H)
        local startCol  = (def.startFrame or 1) - 1  -- 0-indexed
        self.quads[name] = {}
        for i = 0, def.frames - 1 do
            local col = startCol + i
            if col < totalCols then
                self.quads[name][i + 1] = love.graphics.newQuad(
                    col * FRAME_H, 0, FRAME_H, FRAME_H, sw, sh
                )
            end
        end
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
    self.timer = self.timer + dt
    local interval = 1 / def.fps
    if self.timer >= interval then
        self.timer = self.timer - interval
        if self.frame < def.frames then
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

    local def       = ANIMS[self.current]
    local footTrim  = (def and def.footTrimSrcPx) or 0
    local sheet     = self.sheets[self.current]
    local scaledW   = FRAME_H * SPRITE_SCALE
    local scaledH   = FRAME_H * SPRITE_SCALE

    local drawX     = cx - scaledW / 2
    local drawY     = footY - scaledH + (yOffset or 0) + footTrim * SPRITE_SCALE

    local sx        = facingRight and SPRITE_SCALE or -SPRITE_SCALE
    local flipShift = facingRight and 0 or scaledW

    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(sheet, quad, drawX + flipShift, drawY, 0, sx, SPRITE_SCALE)
end

return Animator
