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
}

-- cowboy_v2 (PixelLab-generated, character_id: e4dda30e-08d1-4fbe-b4fe-97bb2b46a52e)
-- footYOffset: world pixels to push the strip down so feet (not the 48² cell bottom) sit on ground.
-- Smoking reads correct at 0; other strips have more empty padding below the feet in-frame.
SKIN_ANIMS["cowboy_v2"] = {
    idle         = { file = "idle.png",         frames = 8,  fps = 6,  loop = true,  footYOffset = 8 },
    smoking      = { file = "smoking.png",       frames = 8,  fps = 5,  loop = true,  footYOffset = 0 },
    run          = { file = "run.png",           frames = 8,  fps = 10, loop = true,  footYOffset = 8 },
    jump         = { file = "draw.png",          frames = 1,  fps = 1,  loop = true,  startFrame = 1, footYOffset = 8 },
    fall         = { file = "draw.png",          frames = 1,  fps = 1,  loop = true,  startFrame = 5, footYOffset = 8 },
    dash         = { file = "dash.png",          frames = 6,  fps = 16, loop = true,  footYOffset = 8 },
    shoot        = { file = "shoot.png",         frames = 6,  fps = 14, loop = false, footYOffset = 8 },
    melee        = { file = "quickdraw.png",     frames = 6,  fps = 14, loop = false, startFrame = 1, footYOffset = 8 },
}

local ANIMS = assert(SKIN_ANIMS[SKIN], "Unknown skin: " .. SKIN)

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
