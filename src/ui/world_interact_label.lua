--- Single-line world interaction prompts: readable contrast, anchored above a world point
--- (e.g. sprite top) so text does not sit on top of the interactable.

local Font = require("src.ui.font")

local M = {}

local _defaultFont

local function getDefaultFont()
    if not _defaultFont then
        _defaultFont = Font.new(10)
    end
    return _defaultFont
end

--- Draw a centered label entirely above `anchorTopY` (world Y of the top edge of the sprite/object).
--- opts: gap (default 6), font, padX, padY, bobAmp, bobTime (elapsed seconds for vertical bob)
--- opts.fg: optional {r,g,b} for main text (default warm yellow-white)
--- opts.alpha: multiply all opacities (e.g. pickup air fade)
function M.drawAboveAnchor(cx, anchorTopY, text, opts)
    opts = opts or {}
    local gap = opts.gap or 6
    local a = opts.alpha or 1
    if a <= 0.001 then return nil end
    local fg = opts.fg or { 1, 0.93, 0.48 }
    local prevFont = love.graphics.getFont()
    local font = opts.font or getDefaultFont()
    love.graphics.setFont(font)

    local th = font:getHeight()
    local tw = font:getWidth(text)
    local padX = opts.padX or 4
    local padY = opts.padY or 2

    local bob = 0
    if opts.bobAmp and opts.bobTime then
        bob = math.sin(opts.bobTime * 3) * opts.bobAmp
    end

    -- Top-left of text: bottom edge of line is (anchorTopY - gap) + bob
    local textTopY = anchorTopY - gap - th + bob
    local bx = cx - tw * 0.5 - padX
    local by = textTopY - padY
    local bw = tw + padX * 2
    local bh = th + padY * 2

    love.graphics.setColor(0.06, 0.05, 0.04, 0.85 * a)
    love.graphics.rectangle("fill", math.floor(bx) + 0.5, math.floor(by) + 0.5, bw, bh, 4, 4)
    love.graphics.setColor(0.92, 0.88, 0.72, 0.35 * a)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", math.floor(bx) + 0.5, math.floor(by) + 0.5, bw, bh, 4, 4)
    love.graphics.setLineWidth(1)

    local tx = math.floor(cx - tw * 0.5)
    local ty = math.floor(textTopY)
    love.graphics.setColor(0, 0, 0, 0.88 * a)
    love.graphics.print(text, tx + 1, ty + 1)
    love.graphics.setColor(fg[1], fg[2], fg[3], a)
    love.graphics.print(text, tx, ty)

    love.graphics.setFont(prevFont)
    love.graphics.setColor(1, 1, 1)
    -- Top edge of pill (world Y); use to stack another label further above.
    return by
end

return M
