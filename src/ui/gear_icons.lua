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

--- Held weapon in world space (e.g. knife swing). Pivot is (originX, originY) as fractions of the tile.
--- `angleRad` is aim direction; `angleOffset` rotates art so the blade points along aim (sprite-dependent).
--- `flipX` / `flipY`: mirror the tile in local space (matches gun: Y-flip when facing one side).
--- When flipping, mirror the pivot so the grip stays correct on the mirrored art.
function GearIcons.drawHeld(icon, worldX, worldY, angleRad, opts)
    if not icon or not icon.sheet then
        return false
    end
    opts = opts or {}
    local tile = icon.tile or 16
    local col = icon.col or 0
    local row = icon.row or 0
    local q, img = getQuad(icon.sheet, tile, col, row)
    if not q or not img then
        return false
    end
    local scale = opts.scale or 1.45
    local oxFrac = opts.originX or 0.42
    local oyFrac = opts.originY or 0.58
    local angleOffset = opts.angleOffset or (math.pi * 0.5)
    local alpha = opts.alpha or 1
    local ox = tile * oxFrac
    local oy = tile * oyFrac
    local sx = scale
    local sy = scale
    if opts.flipX then
        sx = -scale
        ox = tile - ox
    end
    if opts.flipY then
        sy = -scale
        oy = tile - oy
    end
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(img, q, worldX, worldY, angleRad + angleOffset, sx, sy, ox, oy)
    return true
end

return GearIcons
