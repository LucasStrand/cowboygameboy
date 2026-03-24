--- Label layout utility: prevents text labels from overlapping.
--- Game-wide solution — use anywhere labels are drawn in world space.
---
--- Usage:
---   local layout = LabelLayout.new()
---   layout:add(cx, baseY, text, font)   -- returns adjusted y
---   -- Then draw at the returned y instead of baseY.
---   -- Call layout:reset() each frame (or create a new one).

local LabelLayout = {}
LabelLayout.__index = LabelLayout

--- Minimum vertical gap between label baselines (pixels).
local MIN_GAP = 2

function LabelLayout.new()
    local self = setmetatable({}, LabelLayout)
    self.placed = {}  -- { {x, y, w, h}, ... }
    return self
end

function LabelLayout:reset()
    self.placed = {}
end

--- Register a label and return an adjusted Y that avoids overlaps.
--- @param cx number  Center X of the label
--- @param baseY number  Desired Y position
--- @param text string  Label text
--- @param f love.Font  Font used to measure
--- @return number adjustedY
function LabelLayout:add(cx, baseY, text, f)
    f = f or love.graphics.getFont()
    local tw = f:getWidth(text)
    local th = f:getHeight()
    local lx = cx - tw * 0.5
    local rx = lx + tw

    local y = baseY

    -- Push up if overlapping any existing label
    local moved = true
    local iterations = 0
    while moved and iterations < 20 do
        moved = false
        iterations = iterations + 1
        for _, p in ipairs(self.placed) do
            -- Check horizontal overlap
            if rx > p.x and lx < p.x + p.w then
                -- Check vertical overlap
                if y < p.y + p.h + MIN_GAP and y + th > p.y - MIN_GAP then
                    -- Push this label above the conflicting one
                    y = p.y - th - MIN_GAP
                    moved = true
                end
            end
        end
    end

    self.placed[#self.placed + 1] = { x = lx, y = y, w = tw, h = th }
    return y
end

return LabelLayout
