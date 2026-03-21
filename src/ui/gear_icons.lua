-- Pixel tiles from shared RPG item sheets (e.g. assets/weapons/Items.png).
-- `icon` on melee/shield gear: { sheet = path, tile = 16, col = 0-based, row = 0-based }

local GearIcons = {}

local _images = {}
local _quads = {}

local function getImage(path)
    if not _images[path] then
        local ok, img = pcall(love.graphics.newImage, path)
        if not ok or not img then
            return nil
        end
        img:setFilter("nearest", "nearest")
        _images[path] = img
    end
    return _images[path]
end

local function getQuad(path, tile, col, row)
    local key = path .. "\0" .. tostring(tile) .. "\0" .. col .. "\0" .. row
    if _quads[key] then
        return _quads[key], _images[path]
    end
    local img = getImage(path)
    if not img then
        return nil, nil
    end
    local sw, sh = img:getDimensions()
    local q = love.graphics.newQuad(col * tile, row * tile, tile, tile, sw, sh)
    _quads[key] = q
    return q, img
end

--- Draw a gear icon scaled to fit inside [x,y] + maxW×maxH. Returns true if drawn.
function GearIcons.draw(icon, x, y, maxW, maxH, pad, alpha)
    if not icon or not icon.sheet then
        return false
    end
    local tile = icon.tile or 16
    local col = icon.col or 0
    local row = icon.row or 0
    local q, img = getQuad(icon.sheet, tile, col, row)
    if not q or not img then
        return false
    end
    pad = pad or 4
    local innerW = maxW - pad * 2
    local innerH = maxH - pad * 2
    local sc = math.min(innerW / tile, innerH / tile)
    local dw = tile * sc
    local dh = tile * sc
    local dx = x + (maxW - dw) / 2
    local dy = y + (maxH - dh) / 2
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(img, q, math.floor(dx), math.floor(dy), 0, sc, sc)
    return true
end

return GearIcons
