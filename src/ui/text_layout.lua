-- Helpers for aligning UI text in rectangles (LÖVE printf uses top-left y).

local TextLayout = {}

--- Y position for love.graphics.printf so one line is vertically centered in the rect.
function TextLayout.printfYCenteredInRect(font, rectY, rectH)
    return rectY + (rectH - font:getHeight()) * 0.5
end

return TextLayout
