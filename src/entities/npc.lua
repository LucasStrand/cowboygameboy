local Font = require("src.ui.font")
local WorldInteractLabel = require("src.ui.world_interact_label")

local NPC = {}
NPC.__index = NPC

local INTERACT_RADIUS = 40
local PROMPT_BOB_SPEED = 3
local PROMPT_BOB_AMP = 2

--- Rows of transparent pixels below the lowest opaque pixel (feet alignment).
local function bottomPadFromImageData(id)
    local w, h = id:getDimensions()
    for y = h - 1, 0, -1 do
        for x = 0, w - 1 do
            local _, _, _, a = id:getPixel(x, y)
            if a > 0.05 then
                return h - 1 - y
            end
        end
    end
    return 0
end

--- Load animation frames from a directory of frame_000.png, frame_001.png, ...
--- Returns frames and per-frame bottom padding (rows of transparency below lowest opaque pixel).
local function loadFrames(basePath)
    local frames = {}
    local pads = {}
    local i = 0
    while true do
        local path = basePath .. string.format("frame_%03d.png", i)
        local okId, id = pcall(love.image.newImageData, path)
        if okId and id then
            table.insert(pads, bottomPadFromImageData(id))
            local img = love.graphics.newImage(id)
            img:setFilter("nearest", "nearest")
            table.insert(frames, img)
            i = i + 1
        else
            break
        end
    end
    return frames, pads
end

function NPC.new(config)
    local self = setmetatable({}, NPC)
    self.type = config.type          -- "dealer" or "bartender"
    self.x = config.x
    self.y = config.y
    self.w = config.w or 20
    self.h = config.h or 32
    self.isNPC = true
    self.facingRight = config.facingRight or false
    self.interactRadius = config.interactRadius or INTERACT_RADIUS

    -- Multiple named animations: { name = { frames = {}, speed = n } }
    self.animations = {}
    self.currentAnim = nil
    self.frameIndex = 1
    self.animTimer = 0

    -- Load animations from config.anims: { {name, path, speed}, ... }
    self.refFrameW = nil
    self.refFrameH = nil
    if config.anims then
        for _, anim in ipairs(config.anims) do
            local frames, bottomPads = loadFrames(anim.path)
            if #frames > 0 then
                local fw, fh = frames[1]:getDimensions()
                self.animations[anim.name] = {
                    frames = frames,
                    bottomPads = bottomPads,
                    speed = anim.speed or 0.25,
                    frameW = fw,
                    frameH = fh,
                    -- Extra uniform scale for clips where character fills less of the canvas (e.g. padded 128² vs tight 80²)
                    drawScale = anim.drawScale or 1,
                }
                -- Set first loaded animation as current
                if not self.currentAnim then
                    self.currentAnim = anim.name
                end
            end
        end
    end

    -- Legacy single-animation support
    if not self.currentAnim and config.framesPath then
        local frames, bottomPads = loadFrames(config.framesPath)
        if #frames > 0 then
            local fw, fh = frames[1]:getDimensions()
            self.animations["idle"] = {
                frames = frames,
                bottomPads = bottomPads,
                speed = config.animSpeed or 0.25,
                frameW = fw,
                frameH = fh,
            }
            self.currentAnim = "idle"
        end
    end

    -- Fallback: single static image
    if not self.currentAnim and config.spritePath then
        local okId, id = pcall(love.image.newImageData, config.spritePath)
        if okId and id then
            local bottomPad = bottomPadFromImageData(id)
            local img = love.graphics.newImage(id)
            img:setFilter("nearest", "nearest")
            local fw, fh = img:getDimensions()
            self.animations["idle"] = {
                frames = { img },
                bottomPads = { bottomPad },
                speed = 1,
                frameW = fw,
                frameH = fh,
            }
            self.currentAnim = "idle"
        else
            local ok, img = pcall(love.graphics.newImage, config.spritePath)
            if ok then
                img:setFilter("nearest", "nearest")
                local fw, fh = img:getDimensions()
                self.animations["idle"] = {
                    frames = { img },
                    bottomPads = { 0 },
                    speed = 1,
                    frameW = fw,
                    frameH = fh,
                }
                self.currentAnim = "idle"
            end
        end
    end

    -- Canonical scale: match the "idle" clip (or config.refAnim) so mixed canvas sizes
    -- (e.g. 80×80 idle + 128×128 action) don't upscale idle to the larger clip.
    local refName = config.refAnim or "idle"
    local refAnim = self.animations[refName]
    local maxW, maxH = 0, 0
    if refAnim then
        for _, img in ipairs(refAnim.frames) do
            local fw, fh = img:getDimensions()
            if fw > maxW then maxW = fw end
            if fh > maxH then maxH = fh end
        end
    end
    if maxH <= 0 then
        for _, anim in pairs(self.animations) do
            for _, img in ipairs(anim.frames) do
                local fw, fh = img:getDimensions()
                if fw > maxW then maxW = fw end
                if fh > maxH then maxH = fh end
            end
        end
    end
    if maxH > 0 then
        self.refFrameW = maxW
        self.refFrameH = maxH
    end

    -- Animation cycling: randomly switch between clips after variable dwell times
    self.animNames = {}  -- ordered list of animation names
    if config.anims then
        for _, anim in ipairs(config.anims) do
            if self.animations[anim.name] then
                table.insert(self.animNames, anim.name)
            end
        end
    end
    if #self.animNames > 0 then
        self:setAnim(self.animNames[math.random(#self.animNames)])
    end

    self.animCycleTimer = 0
    self.animCycleMin = config.animCycleMin or 2.2
    self.animCycleMax = config.animCycleMax or 6.5
    if self.animCycleMax < self.animCycleMin then
        self.animCycleMax = self.animCycleMin
    end
    self.animCycleDuration = math.random() * (self.animCycleMax - self.animCycleMin) + self.animCycleMin

    -- Sprite scale
    self.scale = config.scale or 1

    -- Interaction prompt
    self.promptVisible = false
    self.promptTimer = 0
    self.promptFont = Font.new(10)
    self.promptLabel = config.promptLabel or "[E] Talk"

    -- Speech — quiet, rare, at most once per visit
    self.speechText = nil
    self.speechLife = 0
    self.speechDuration = 3.0
    self.speechHasSpoken = false
    self.speechTimer = math.random(6, 20)  -- delay before maybe speaking
    self.speechChance = 0.4  -- 40% chance they even say anything
    self.speechLines = config.speechLines or {}

    if #self.speechLines == 0 then
        if self.type == "bartender" then
            self.speechLines = {
                "...",
                "Mm.",
                "Glass is clean enough.",
                "Same old faces.",
                "Hm.",
                "Slow night.",
                "You again.",
                "Monster's in the fridge.",
            }
        elseif self.type == "dealer" then
            self.speechLines = {
                "...",
                "Heh.",
                "Cards don't lie.",
                "Seen worse luck.",
                "Table's open.",
                "Mm-hm.",
                "You remind me of someone.",
                "Suit yourself.",
            }
        end
    end

    return self
end

function NPC:getAnim()
    return self.currentAnim and self.animations[self.currentAnim]
end

function NPC:setAnim(name)
    if self.animations[name] and self.currentAnim ~= name then
        self.currentAnim = name
        self.frameIndex = 1
        self.animTimer = 0
    end
end

function NPC:update(dt)
    local anim = self:getAnim()
    if anim and #anim.frames > 1 then
        self.animTimer = self.animTimer + dt
        if self.animTimer >= anim.speed then
            self.animTimer = self.animTimer - anim.speed
            self.frameIndex = (self.frameIndex % #anim.frames) + 1
        end
    end

    -- Random clip + random dwell (shuffle / idle / drinking / etc.)
    if #self.animNames > 1 then
        self.animCycleTimer = self.animCycleTimer + dt
        if self.animCycleTimer >= self.animCycleDuration then
            self.animCycleTimer = 0
            self.animCycleDuration = math.random() * (self.animCycleMax - self.animCycleMin) + self.animCycleMin
            local n = #self.animNames
            local nextName
            repeat
                nextName = self.animNames[math.random(n)]
            until nextName ~= self.currentAnim or n <= 1
            self:setAnim(nextName)
        end
    end

    self.promptTimer = self.promptTimer + dt

    -- Speech — once at most, maybe not at all
    if self.speechText then
        self.speechLife = self.speechLife + dt
        if self.speechLife >= self.speechDuration then
            self.speechText = nil
            self.speechLife = 0
        end
    elseif not self.speechHasSpoken and #self.speechLines > 0 then
        self.speechTimer = self.speechTimer - dt
        if self.speechTimer <= 0 then
            self.speechHasSpoken = true
            if math.random() < self.speechChance then
                self.speechText = self.speechLines[math.random(#self.speechLines)]
                self.speechLife = 0
            end
        end
    end
end

--- World Y of the top edge of the current sprite frame (for prompts above the head).
function NPC:getSpriteTopY()
    local anim = self:getAnim()
    if not anim or #anim.frames == 0 then
        return self.y
    end
    local frame = anim.frames[self.frameIndex]
    local fw, fh = frame:getDimensions()
    local normScale = 1
    if self.refFrameH and self.refFrameH > 0 then
        normScale = self.refFrameH / fh
    end
    local animMul = anim.drawScale or 1
    local sy = math.abs(self.scale * normScale * animMul)
    local pads = anim.bottomPads
    local bottomPad = (pads and pads[self.frameIndex]) or 0
    local drawY = self.y + self.h + bottomPad * sy
    return drawY - fh * sy
end

function NPC:canInteract(px, py, pw, ph)
    local cx = self.x + self.w / 2
    local cy = self.y + self.h / 2
    local pcx = px + (pw or 16) / 2
    local pcy = py + (ph or 28) / 2
    local dx = cx - pcx
    local dy = cy - pcy
    return (dx * dx + dy * dy) <= self.interactRadius * self.interactRadius
end

function NPC:draw()
    local anim = self:getAnim()
    if not anim or #anim.frames == 0 then
        -- Fallback: colored rectangle
        if self.type == "dealer" then
            love.graphics.setColor(0.2, 0.6, 0.2)
        else
            love.graphics.setColor(0.6, 0.3, 0.1)
        end
        love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
        love.graphics.setColor(1, 1, 1)
        return
    end

    local frame = anim.frames[self.frameIndex]
    local fw, fh = frame:getDimensions()

    -- Uniform scale so every frame matches ref height (canonical = idle)
    local normScale = 1
    if self.refFrameH and self.refFrameH > 0 then
        normScale = self.refFrameH / fh
    end

    local animMul = anim.drawScale or 1
    local sx = self.scale * normScale * animMul
    local sy = self.scale * normScale * animMul

    -- Bottom-center origin: lowest opaque row (feet) on ground (self.y + self.h), not the texture's bottom edge
    local pads = anim.bottomPads
    local bottomPad = (pads and pads[self.frameIndex]) or 0
    local drawX = self.x + self.w / 2
    local drawY = self.y + self.h + bottomPad * sy

    -- Flip if facing left
    if not self.facingRight then
        sx = -sx
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(frame, drawX, drawY, 0, sx, sy, fw / 2, fh)
end

function NPC:drawPrompt()
    if not self.promptVisible then return end

    local cx = self.x + self.w / 2
    WorldInteractLabel.drawAboveAnchor(cx, self:getSpriteTopY(), self.promptLabel, {
        font = self.promptFont,
        bobAmp = PROMPT_BOB_AMP,
        bobTime = self.promptTimer,
    })
end

function NPC:drawSpeech()
    if not self.speechText then return end

    local cx = self.x + self.w / 2
    local alpha = 1
    if self.speechLife < 0.4 then
        alpha = self.speechLife / 0.4
    elseif self.speechLife > self.speechDuration - 0.8 then
        alpha = (self.speechDuration - self.speechLife) / 0.8
    end

    local top = self:getSpriteTopY()
    local py = top - 26 - self.speechLife * 2

    local font = self.promptFont
    love.graphics.setFont(font)
    local tw = font:getWidth(self.speechText)

    love.graphics.setColor(0, 0, 0, 0.4 * alpha)
    love.graphics.print(self.speechText, math.floor(cx - tw / 2) + 1, math.floor(py) + 1)
    love.graphics.setColor(0.7, 0.65, 0.55, 0.7 * alpha)
    love.graphics.print(self.speechText, math.floor(cx - tw / 2), math.floor(py))
    love.graphics.setColor(1, 1, 1)
end

return NPC
