-- Player sprite animator.
--
-- Art modes (set PLAYER_ART_PACK below):
--   • "cowboy" — horizontal strips in assets/sprites/cowboy/ (legacy platformer frames).
--   • Structured pack (e.g. cowgoy export) — assets/sprites/<pack>/rotations/*.png plus
--     assets/sprites/<pack>/animations/<clip>/<dir>/frame_NNN.png
--   • Flat directional — assets/sprites/<pack>/east.png, west.png, optional south.png (blackcat).

local FRAME_H = 48
local SPRITE_SCALE = 0.85
local TARGET_DRAW_H = FRAME_H * SPRITE_SCALE

--- Multiplier on drawn body size (hitbox in player.lua unchanged unless you tune it).
local PLAYER_VISUAL_SCALE_MUL = 1.5

--- Switch player body art: "cowboy" (strips), "cowgoy" (structured export), "blackcat".
local PLAYER_ART_PACK = "cowboy"

local STRIP_DIR = "assets/sprites/cowboy/"

local ANIMS = {
    idle    = { file = "idle.png",      frames = 7,  fps = 6,  loop = true  },
    smoking = { file = "smoking.png",   frames = 9,  fps = 5,  loop = true  },
    run     = { file = "run.png",       frames = 8,  fps = 10, loop = true  },
    -- fps tuned so structured multi-frame clips (e.g. jumping-1) read as motion; strip mode still uses 1 cell.
    jump    = { file = "draw.png",      frames = 1,  fps = 14, loop = true, startFrame = 1 },
    fall    = { file = "draw.png",      frames = 1,  fps = 14, loop = true, startFrame = 2 },
    shoot   = { file = "shoot.png",     frames = 5,  fps = 14, loop = false },
    holster      = { file = "holster.png",      frames = 8,  fps = 12, loop = false },
    holster_spin = { file = "holster_spin.png", frames = 14, fps = 14, loop = false },
    dash    = { file = "draw.png",      frames = 3,  fps = 16, loop = true, startFrame = 1 },
    melee   = { file = "quickdraw.png", frames = 6,  fps = 14, loop = false, startFrame = 1 },
}

local Animator = {}
Animator.__index = Animator
Animator.PLAYER_ART_PACK = PLAYER_ART_PACK
Animator.PLAYER_VISUAL_SCALE_MUL = PLAYER_VISUAL_SCALE_MUL

local _sheetCache = {}
local _directionalCache = {}
local _pathImageCache = {}

--- Gameplay anim name → exported clip folder under animations/ (nil = use rotations only for draw).
local STRUCTURED_CLIP_BY_ANIM = {
    idle         = "breathing-idle",
    smoking      = nil,
    run          = "breathing-idle",
    jump         = "jumping-1",
    fall         = "jumping-1",
    shoot        = "breathing-idle",
    holster      = "breathing-idle",
    holster_spin = "breathing-idle",
    dash         = "breathing-idle",
    melee        = "breathing-idle",
}

local function loadImageAtPath(path)
    if _pathImageCache[path] then
        return _pathImageCache[path]
    end
    local ok, img = pcall(love.graphics.newImage, path)
    if not ok or not img then
        return nil
    end
    img:setFilter("nearest", "nearest")
    _pathImageCache[path] = img
    return img
end

local function loadRotationsSubdir(base)
    local rot = {}
    for _, d in ipairs({ "east", "west", "south", "north" }) do
        local p = base .. "rotations/" .. d .. ".png"
        -- Do not gate on getInfo; on some Windows/LÖVE combos file probe can fail while newImage works.
        local img = loadImageAtPath(p)
        if img then
            rot[d] = img
        end
    end
    return rot
end

local function loadClipFrames(base, clipName)
    local out = {}
    for _, d in ipairs({ "east", "west", "south", "north" }) do
        local dirPath = base .. "animations/" .. clipName .. "/" .. d
        -- getInfo(dir) is unreliable for subfolders on some platforms; list contents instead.
        local items = love.filesystem.getDirectoryItems(dirPath)
        if items and #items > 0 then
            local numbered = {}
            for _, name in ipairs(items) do
                local n = tonumber(name:match("^frame_(%d+)%.png$"))
                    or tonumber(name:match("^frame_(%d+)%.PNG$"))
                if n then
                    numbered[#numbered + 1] = { n = n, name = name }
                end
            end
            table.sort(numbered, function(a, b)
                return a.n < b.n
            end)
            local arr = {}
            for _, e in ipairs(numbered) do
                local img = loadImageAtPath(dirPath .. "/" .. e.name)
                if img then
                    arr[#arr + 1] = img
                end
            end
            if #arr > 0 then
                out[d] = arr
            end
        end
    end
    return out
end

local function maxClipFrameCount(clipTbl)
    local m = 0
    for _, arr in pairs(clipTbl) do
        if type(arr) == "table" and #arr > m then
            m = #arr
        end
    end
    return math.max(1, m)
end

--- @return table|nil { rotImages, structClips, clipFrameCount }
local function tryLoadStructuredPack(pack)
    local base = "assets/sprites/" .. pack .. "/"
    -- Avoid getInfo(base): trailing slash / directory probes can be nil on Windows even when assets exist.
    local rot = loadRotationsSubdir(base)
    if not rot.east and not rot.west then
        return nil
    end
    local structClips = {}
    local clipFrameCount = {}
    for animName, clipName in pairs(STRUCTURED_CLIP_BY_ANIM) do
        if clipName then
            local clip = loadClipFrames(base, clipName)
            if next(clip) then
                structClips[animName] = clip
                clipFrameCount[animName] = maxClipFrameCount(clip)
            end
        end
    end
    if not structClips.idle then
        return nil
    end
    return {
        rotImages = rot,
        structClips = structClips,
        clipFrameCount = clipFrameCount,
    }
end

local function pickStructuredClipFrame(clipTbl, facingRight, frameIdx)
    local function at(arr)
        if not arr or #arr == 0 then
            return nil
        end
        local i = math.min(math.max(1, frameIdx), #arr)
        return arr[i]
    end
    if facingRight then
        if clipTbl.east and #clipTbl.east > 0 then
            return at(clipTbl.east), false
        end
        if clipTbl.west and #clipTbl.west > 0 then
            return at(clipTbl.west), true
        end
    else
        if clipTbl.west and #clipTbl.west > 0 then
            return at(clipTbl.west), false
        end
        if clipTbl.east and #clipTbl.east > 0 then
            return at(clipTbl.east), true
        end
    end
    if clipTbl.south and #clipTbl.south > 0 then
        return at(clipTbl.south), false
    end
    if clipTbl.north and #clipTbl.north > 0 then
        return at(clipTbl.north), false
    end
    return nil, false
end

local function pickFlatDirectionalImage(dirImages, facingRight, animCurrent)
    if animCurrent == "smoking" and dirImages.south then
        return dirImages.south, false
    end
    if facingRight then
        if dirImages.east then
            return dirImages.east, false
        end
        if dirImages.west then
            return dirImages.west, true
        end
    else
        if dirImages.west then
            return dirImages.west, false
        end
        if dirImages.east then
            return dirImages.east, true
        end
    end
    return nil, false
end

local function loadSheet(filename)
    if not _sheetCache[filename] then
        local img = love.graphics.newImage(STRIP_DIR .. filename)
        img:setFilter("nearest", "nearest")
        _sheetCache[filename] = img
    end
    return _sheetCache[filename]
end

local function loadDirectionalPack(pack)
    if _directionalCache[pack] then
        return _directionalCache[pack]
    end
    local base = "assets/sprites/" .. pack .. "/"
    local out = {}
    for _, k in ipairs({ "east", "west", "south", "north" }) do
        local path = base .. k .. ".png"
        local ok, img = pcall(love.graphics.newImage, path)
        if ok and img then
            img:setFilter("nearest", "nearest")
            out[k] = img
        end
    end
    _directionalCache[pack] = out
    return out
end

function Animator.new()
    local self = setmetatable({}, Animator)
    self.artPack = PLAYER_ART_PACK
    self.artMode = "strips"
    self.dirImages = nil
    self.rotImages = nil
    self.structClips = nil
    self.clipFrameCount = nil
    self.sheets = {}
    self.quads = {}

    if PLAYER_ART_PACK ~= "cowboy" then
        local structured = tryLoadStructuredPack(PLAYER_ART_PACK)
        if structured then
            self.artMode = "directional_structured"
            self.rotImages = structured.rotImages
            self.structClips = structured.structClips
            self.clipFrameCount = structured.clipFrameCount
            self.dirImages = structured.rotImages
            for name in pairs(ANIMS) do
                self.quads[name] = { [1] = true }
            end
        else
            local dirs = loadDirectionalPack(PLAYER_ART_PACK)
            local eastW = dirs.east or dirs.west
            if eastW then
                self.artMode = "directional"
                self.dirImages = dirs
                for name in pairs(ANIMS) do
                    self.quads[name] = { [1] = true }
                end
            end
        end
    end

    if self.artMode == "strips" then
        for name, def in pairs(ANIMS) do
            local sheet = loadSheet(def.file)
            self.sheets[name] = sheet
            local sw, sh = sheet:getDimensions()
            local totalCols = math.floor(sw / FRAME_H)
            local startCol = (def.startFrame or 1) - 1
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
    end

    self.current = "idle"
    self.frame = 1
    self.timer = 0
    self.done = false
    return self
end

function Animator:play(name, force)
    if not self.quads[name] then return end
    if self.current == name and not force then return end
    self.current = name
    self.frame = 1
    self.timer = 0
    self.done = false
end

function Animator:update(dt)
    local def = ANIMS[self.current]
    if not def then return end
    local cap = def.frames
    if self.artMode == "directional_structured" and self.clipFrameCount then
        cap = self.clipFrameCount[self.current] or def.frames
    end
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
    love.graphics.setColor(1, 1, 1, alpha or 1)

    if self.artMode == "directional_structured" and self.rotImages and self.structClips then
        local img, mirrorX
        if self.current == "smoking" and self.rotImages.south then
            img, mirrorX = self.rotImages.south, false
        else
            local clip = self.structClips[self.current]
            if clip then
                img, mirrorX = pickStructuredClipFrame(clip, facingRight, self.frame)
            end
            if not img then
                img, mirrorX = pickFlatDirectionalImage(self.rotImages, facingRight, self.current)
            end
        end
        if not img then
            love.graphics.setColor(1, 1, 1)
            return
        end
        local iw, ih = img:getDimensions()
        local scale = TARGET_DRAW_H * PLAYER_VISUAL_SCALE_MUL / math.max(1, ih)
        local scaledW = iw * scale
        local scaledH = ih * scale
        local drawX = cx - scaledW * 0.5
        local drawY = footY - scaledH + (yOffset or 0)
        local sx = mirrorX and -scale or scale
        local flipShift = mirrorX and scaledW or 0
        love.graphics.draw(img, drawX + flipShift, drawY, 0, sx, scale)
        love.graphics.setColor(1, 1, 1)
        return
    end

    if self.artMode == "directional" and self.dirImages then
        local img, mirrorX = pickFlatDirectionalImage(self.dirImages, facingRight, self.current)
        if not img then
            return
        end
        local iw, ih = img:getDimensions()
        local scale = TARGET_DRAW_H * PLAYER_VISUAL_SCALE_MUL / math.max(1, ih)
        local scaledW = iw * scale
        local scaledH = ih * scale
        local drawX = cx - scaledW * 0.5
        local drawY = footY - scaledH + (yOffset or 0)
        local sx = mirrorX and -scale or scale
        local flipShift = mirrorX and scaledW or 0
        love.graphics.draw(img, drawX + flipShift, drawY, 0, sx, scale)
        love.graphics.setColor(1, 1, 1)
        return
    end

    local quads = self.quads[self.current]
    if not quads then return end
    local quad = quads[self.frame]
    if not quad then return end

    local sheet = self.sheets[self.current]
    local eff = SPRITE_SCALE * PLAYER_VISUAL_SCALE_MUL
    local scaledW = FRAME_H * eff
    local scaledH = FRAME_H * eff
    local drawX = cx - scaledW / 2
    local drawY = footY - scaledH + (yOffset or 0)
    local sx = facingRight and eff or -eff
    local flipShift = facingRight and 0 or scaledW

    love.graphics.draw(sheet, quad, drawX + flipShift, drawY, 0, sx, eff)
    love.graphics.setColor(1, 1, 1)
end

return Animator
