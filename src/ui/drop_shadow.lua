--[[
  Flat elliptical ground shadow. baseY = bottom of feet; ellipse sits on the floor.
]]
local DropShadow = {}

function DropShadow.drawEllipse(cx, baseY, rx, ry, alpha)
    if not rx or rx <= 0 or not ry or ry <= 0 then return end
    alpha = alpha or 0.3
    local cy = baseY - ry
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.ellipse("fill", cx, cy, rx, ry)
    love.graphics.setColor(1, 1, 1)
end

return DropShadow
