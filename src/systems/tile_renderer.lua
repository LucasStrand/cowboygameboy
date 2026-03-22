-- Tile renderer — draws walls and platforms using a tile atlas or solid-fill colors.
-- Supports multiple themes (one per world). Each theme specifies either:
--   a) An atlas image path + tile coordinate mapping (forest / train)
--   b) _solidFill = true + color fields (desert, or any world without a tile atlas)

local TileRenderer = {}

local TILE = 16          -- pixels per tile in the atlas

-- Cache: atlas path -> { image = Image, quads = quads[row][col] }
local atlasCache = {}

-- Default forest theme (backward compatible)
local DEFAULT_TILES = {
    grass_l   = {3, 1},
    grass_m   = {4, 1},
    grass_r   = {5, 1},
    grass_bl  = {2, 2},
    grass_bm  = {5, 2},
    grass_br  = {6, 2},
    dirt      = {4, 4},
    dirt2     = {3, 4},
    dirt3     = {5, 4},
    dirt_l    = {2, 3},
    dirt_r    = {6, 3},
    dirt_bl   = {3, 6},
    dirt_bm   = {4, 6},
    dirt_br   = {5, 6},
    plank_l   = {7, 9},
    plank_m   = {8, 9},
    plank_r   = {9, 9},
}

local DEFAULT_ATLAS_PATH = "assets/Tiles/Tiles/Assets/Assets.png"

local function loadAtlas(path)
    if atlasCache[path] then return atlasCache[path] end

    local image = love.graphics.newImage(path)
    image:setFilter("nearest", "nearest")
    local sw, sh = image:getDimensions()
    local cols = math.floor(sw / TILE)
    local rows = math.floor(sh / TILE)
    local quads = {}
    for r = 1, rows do
        quads[r] = {}
        for c = 1, cols do
            quads[r][c] = love.graphics.newQuad(
                (c - 1) * TILE, (r - 1) * TILE,
                TILE, TILE, sw, sh
            )
        end
    end

    atlasCache[path] = { image = image, quads = quads }
    return atlasCache[path]
end

local function getQuad(atlasData, tiles, name)
    local t = tiles[name]
    if not t then return nil end
    local col, row = t[1], t[2]
    local quads = atlasData.quads
    return quads[row] and quads[row][col]
end

--- Resolve theme to atlas data and tile mapping.
--- theme can be nil (uses defaults) or a table from worlds.lua with tile coords,
--- or a table with _solidFill = true for color-based rendering.
local function resolveTheme(theme)
    local atlasPath = DEFAULT_ATLAS_PATH
    local tiles = DEFAULT_TILES
    local tint = {1, 1, 1}

    if theme then
        if theme._solidFill then return nil, nil, nil end  -- handled separately
        if theme._atlasPath then atlasPath = theme._atlasPath end
        if theme.grass_m then tiles = theme end
        if theme._tint then tint = theme._tint end
    end

    return loadAtlas(atlasPath), tiles, tint
end

-- ─── Solid-fill drawing (for worlds without a tile atlas) ──────────────────
-- Draws a mesa/rock look: sandy top cap, layered rock face, dark base.

local function drawSolidWall(x, y, w, h, theme)
    local topColor  = theme._topColor  or {0.88, 0.76, 0.52}
    local faceColor = theme._faceColor or {0.72, 0.50, 0.32}
    local baseColor = theme._baseColor or {0.52, 0.34, 0.20}
    local capH = math.min(6, h)
    local baseH = math.min(4, h - capH)

    -- Rock face fill
    love.graphics.setColor(faceColor)
    love.graphics.rectangle("fill", x, y, w, h)

    -- Subtle horizontal rock strata lines
    love.graphics.setColor(baseColor[1], baseColor[2], baseColor[3], 0.3)
    local stride = 12
    local lineY = y + capH + stride
    while lineY < y + h - baseH - 2 do
        love.graphics.rectangle("fill", x + 2, lineY, w - 4, 2)
        lineY = lineY + stride
    end

    -- Sandy top cap
    love.graphics.setColor(topColor)
    love.graphics.rectangle("fill", x, y, w, capH)

    -- Dark base
    love.graphics.setColor(baseColor)
    love.graphics.rectangle("fill", x, y + h - baseH, w, baseH)
end

local function drawSolidPlatform(x, y, w, h, theme)
    local topColor  = theme._topColor  or {0.88, 0.76, 0.52}
    local faceColor = theme._faceColor or {0.72, 0.50, 0.32}
    local capH = math.min(4, h)

    -- Rock body
    love.graphics.setColor(faceColor)
    love.graphics.rectangle("fill", x, y, w, h)

    -- Sandy top cap
    love.graphics.setColor(topColor)
    love.graphics.rectangle("fill", x, y, w, capH)

    -- Slight edge darkening left/right
    love.graphics.setColor(0, 0, 0, 0.12)
    love.graphics.rectangle("fill", x, y, 3, h)
    love.graphics.rectangle("fill", x + w - 3, y, 3, h)
end

-- ─── Atlas-based drawing ───────────────────────────────────────────────────

--- Draw a wall (solid rectangle) using tiled texture.
--- theme is optional — nil uses the default forest theme.
function TileRenderer.drawWall(x, y, w, h, theme)
    if theme and theme._solidFill then
        drawSolidWall(x, y, w, h, theme)
        return
    end

    local atlasData, tiles, tint = resolveTheme(theme)
    love.graphics.setColor(tint)

    local tilesW = math.ceil(w / TILE)
    local tilesH = math.ceil(h / TILE)

    for ty = 0, tilesH - 1 do
        for tx = 0, tilesW - 1 do
            local quad
            local isTop    = (ty == 0)
            local isBottom = (ty == tilesH - 1) and tilesH > 1
            local isLeft   = (tx == 0)
            local isRight  = (tx == tilesW - 1)

            if isTop then
                if isLeft then      quad = getQuad(atlasData, tiles, "grass_l")
                elseif isRight then quad = getQuad(atlasData, tiles, "grass_r")
                else               quad = getQuad(atlasData, tiles, "grass_m")
                end
            elseif isBottom then
                if isLeft then      quad = getQuad(atlasData, tiles, "dirt_bl")
                elseif isRight then quad = getQuad(atlasData, tiles, "dirt_br")
                else               quad = getQuad(atlasData, tiles, "dirt_bm")
                end
            elseif isLeft then
                quad = getQuad(atlasData, tiles, "dirt_l")
            elseif isRight then
                quad = getQuad(atlasData, tiles, "dirt_r")
            else
                local v = (tx + ty) % 3
                if v == 0 then      quad = getQuad(atlasData, tiles, "dirt")
                elseif v == 1 then  quad = getQuad(atlasData, tiles, "dirt2")
                else               quad = getQuad(atlasData, tiles, "dirt3")
                end
            end

            if quad then
                love.graphics.draw(atlasData.image, quad, x + tx * TILE, y + ty * TILE)
            end
        end
    end
end

--- Draw a thin platform (one-way) using plank tiles.
--- theme is optional — nil uses the default forest theme.
function TileRenderer.drawPlatform(x, y, w, h, theme)
    if theme and theme._solidFill then
        drawSolidPlatform(x, y, w, h, theme)
        return
    end

    local atlasData, tiles, tint = resolveTheme(theme)
    love.graphics.setColor(tint)

    local tilesW = math.ceil(w / TILE)
    local tilesH = math.max(1, math.ceil(h / TILE))

    for ty = 0, tilesH - 1 do
        for tx = 0, tilesW - 1 do
            local quad
            local isTop = (ty == 0)

            if isTop then
                if tx == 0 then            quad = getQuad(atlasData, tiles, "plank_l")
                elseif tx == tilesW - 1 then quad = getQuad(atlasData, tiles, "plank_r")
                else                       quad = getQuad(atlasData, tiles, "plank_m")
                end
            else
                if tx == 0 then            quad = getQuad(atlasData, tiles, "dirt_l")
                elseif tx == tilesW - 1 then quad = getQuad(atlasData, tiles, "dirt_r")
                elseif (tx + ty) % 2 == 0 then quad = getQuad(atlasData, tiles, "dirt")
                else                       quad = getQuad(atlasData, tiles, "dirt3")
                end
            end

            if quad then
                love.graphics.draw(atlasData.image, quad, x + tx * TILE, y + ty * TILE)
            end
        end
    end
end

--- Preload a theme's atlas (useful at world start to avoid mid-gameplay loads).
function TileRenderer.preloadTheme(theme)
    if theme and theme._solidFill then return end  -- nothing to preload
    if theme and theme._atlasPath then
        loadAtlas(theme._atlasPath)
    else
        loadAtlas(DEFAULT_ATLAS_PATH)
    end
end

return TileRenderer
