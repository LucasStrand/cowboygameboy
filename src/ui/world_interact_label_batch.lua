--- Queues world-space interact labels for one frame, resolves overlaps, then draws.
--- Higher `opts.priority` keeps its preferred spot; lower priority is nudged upward in world space.
--- Draw order: lower priority first, higher last (on top). Also nudges away from bottom-right HUD band.

local WorldInteractLabel = require("src.ui.world_interact_label")
local Font = require("src.ui.font")

local M = {}

local queue = {}
local orderSeq = 0

local _defaultFont
local function getDefaultFont()
    if not _defaultFont then
        _defaultFont = Font.new(10)
    end
    return _defaultFont
end

local function measurePill(cx, anchorTopY, text, opts)
    opts = opts or {}
    local gap = opts.gap or 6
    local font = opts.font or getDefaultFont()
    local th = font:getHeight()
    local tw = font:getWidth(text)
    local padX = opts.padX or 4
    local padY = opts.padY or 2
    local textTopY = anchorTopY - gap - th
    local bx = cx - tw * 0.5 - padX
    local by = textTopY - padY
    local bw = tw + padX * 2
    local bh = th + padY * 2
    return bx, by, bw, bh
end

local function rectsOverlap(a, b)
    return not (a.right < b.left or a.left > b.right or a.bottom < b.top or a.top > b.bottom)
end

function M.clear()
    queue = {}
    orderSeq = 0
end

--- opts.priority: higher = wins overlaps and is drawn on top. opts._order is internal.
function M.queue(cx, anchorTopY, text, opts)
    opts = opts or {}
    orderSeq = orderSeq + 1
    queue[#queue + 1] = {
        cx = cx,
        anchorTopY = anchorTopY,
        text = text,
        opts = opts,
        priority = opts.priority or 0,
        _order = orderSeq,
    }
end

local function hudAvoidScreenRect(screenW, screenH)
    local pad = 8
    return {
        left = screenW - 460 - pad,
        top = screenH - 300 - pad,
        right = screenW - pad,
        bottom = screenH - pad,
    }
end

local function screenRectOverlapsHud(bx, by, bw, bh, hud)
    local sx1, sy1 = love.graphics.transformPoint(bx, by)
    local sx2, sy2 = love.graphics.transformPoint(bx + bw, by + bh)
    local left = math.min(sx1, sx2)
    local top = math.min(sy1, sy2)
    local right = math.max(sx1, sx2)
    local bottom = math.max(sy1, sy2)
    return not (right < hud.left or left > hud.right or bottom < hud.top or top > hud.bottom)
end

function M.flush()
    if #queue == 0 then return end

    local screenW, screenH = love.graphics.getDimensions()
    local hud = hudAvoidScreenRect(screenW, screenH)

    -- Place from highest priority down (they claim space first).
    table.sort(queue, function(a, b)
        if a.priority == b.priority then
            return a._order < b._order
        end
        return a.priority > b.priority
    end)

    local placed = {}
    local STEP = 8
    local MAX_STEPS = 56

    for _, entry in ipairs(queue) do
        local cx = entry.cx
        local a = entry.anchorTopY
        local final = a
        local placedRect = false
        for _ = 0, MAX_STEPS do
            local bx, by, bw, bh = measurePill(cx, a, entry.text, entry.opts)
            local rect = { left = bx, top = by, right = bx + bw, bottom = by + bh }
            local overlap = false
            for _, p in ipairs(placed) do
                if rectsOverlap(rect, p) then
                    overlap = true
                    break
                end
            end
            local hudHit = screenRectOverlapsHud(bx, by, bw, bh, hud)
            if not overlap and not hudHit then
                final = a
                placed[#placed + 1] = rect
                placedRect = true
                break
            end
            a = a - STEP
        end
        if not placedRect then
            final = a
            local bx, by, bw, bh = measurePill(cx, final, entry.text, entry.opts)
            placed[#placed + 1] = { left = bx, top = by, right = bx + bw, bottom = by + bh }
        end
        entry.finalAnchor = final
    end

    -- Back-to-front draw: low priority first, high last (on top).
    table.sort(queue, function(a, b)
        if a.priority == b.priority then
            return a._order < b._order
        end
        return a.priority < b.priority
    end)

    for _, entry in ipairs(queue) do
        local drawOpts = {}
        for k, v in pairs(entry.opts) do
            if k ~= "priority" then
                drawOpts[k] = v
            end
        end
        WorldInteractLabel.drawAboveAnchor(entry.cx, entry.finalAnchor or entry.anchorTopY, entry.text, drawOpts)
    end

    queue = {}
    orderSeq = 0
end

return M
