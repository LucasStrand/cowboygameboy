-- Background gap fills (bgFillRects) — dimmed ground tile behind the
-- gameplay layer so platform gaps read as depth, not empty space.

local TileRenderer = require("src.systems.tile_renderer")

local DesertMidground = {}

--- Fill gaps between platforms with a dimmed version of the ground texture.
function DesertMidground.drawBgFills(room, theme)
    if not room or not theme then return end
    local fills = room.bgFillRects
    if not fills or #fills == 0 then return end
    if not theme._groundTexture then return end

    local dimFactor = theme._bgCanyonDimFactor or 0.45
    local bgAlpha = theme._bgCanyonAlpha or 0.92

    -- Build a simple fill theme that just tiles the ground texture dimmed
    local fillTheme = {
        _textureFill = true,
        _groundTexture = theme._groundTexture,
        _tint = {dimFactor, dimFactor, dimFactor, bgAlpha},
    }

    for _, fill in ipairs(fills) do
        if fill.w > 0 and fill.h > 0 then
            TileRenderer.drawWall(fill.x, fill.y, fill.w, fill.h, fillTheme)
        end
    end
end

return DesertMidground
