-- Tile renderer — draws walls and platforms using a tile atlas.
-- Supports multiple themes (one per world). Each theme specifies an atlas
-- image path and a tile coordinate mapping.

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
--- theme can be nil (uses defaults) or a table from worlds.lua:
---   { grass_l = {col,row}, ..., _atlasPath = "..." }
--- Or pass the world definition directly.
local function resolveTheme(theme)
    local atlasPath = DEFAULT_ATLAS_PATH
    local tiles = DEFAULT_TILES

    if theme then
        -- If theme has an _atlasPath, use it
        if theme._atlasPath then
            atlasPath = theme._atlasPath
        end
        -- If theme has tile mappings (grass_l etc.), use them
        if theme.grass_m then
            tiles = theme
        end
    end

    return loadAtlas(atlasPath), tiles
end

--- Draw a wall (solid rectangle) using tiled texture.
--- Walls get grass on top, dirt fill, and edge tiles.
--- theme is optional — nil uses the default forest theme.
function TileRenderer.drawWall(x, y, w, h, theme)
    local atlasData, tiles = resolveTheme(theme)
    love.graphics.setColor(1, 1, 1)

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
                if isLeft then
                    quad = getQuad(atlasData, tiles, "grass_l")
                elseif isRight then
                    quad = getQuad(atlasData, tiles, "grass_r")
                else
                    quad = getQuad(atlasData, tiles, "grass_m")
                end
            elseif isBottom then
                if isLeft then
                    quad = getQuad(atlasData, tiles, "dirt_bl")
                elseif isRight then
                    quad = getQuad(atlasData, tiles, "dirt_br")
                else
                    quad = getQuad(atlasData, tiles, "dirt_bm")
                end
            elseif isLeft then
                quad = getQuad(atlasData, tiles, "dirt_l")
            elseif isRight then
                quad = getQuad(atlasData, tiles, "dirt_r")
            else
                local v = (tx + ty) % 3
                if v == 0 then
                    quad = getQuad(atlasData, tiles, "dirt")
                elseif v == 1 then
                    quad = getQuad(atlasData, tiles, "dirt2")
                else
                    quad = getQuad(atlasData, tiles, "dirt3")
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
    local atlasData, tiles = resolveTheme(theme)
    love.graphics.setColor(1, 1, 1)

    local tilesW = math.ceil(w / TILE)
    local tilesH = math.max(1, math.ceil(h / TILE))

    for ty = 0, tilesH - 1 do
        for tx = 0, tilesW - 1 do
            local quad
            local isTop = (ty == 0)

            if isTop then
                if tx == 0 then
                    quad = getQuad(atlasData, tiles, "plank_l")
                elseif tx == tilesW - 1 then
                    quad = getQuad(atlasData, tiles, "plank_r")
                else
                    quad = getQuad(atlasData, tiles, "plank_m")
                end
            else
                if tx == 0 then
                    quad = getQuad(atlasData, tiles, "dirt_l")
                elseif tx == tilesW - 1 then
                    quad = getQuad(atlasData, tiles, "dirt_r")
                else
                    if (tx + ty) % 2 == 0 then
                        quad = getQuad(atlasData, tiles, "dirt")
                    else
                        quad = getQuad(atlasData, tiles, "dirt3")
                    end
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
    if theme and theme._atlasPath then
        loadAtlas(theme._atlasPath)
    else
        loadAtlas(DEFAULT_ATLAS_PATH)
    end
end

return TileRenderer
