-- Tile renderer — draws walls and platforms using the tile atlas instead of
-- plain colored rectangles.  Loads assets/Tiles/Tiles/Assets/Assets.png as a
-- 16×16 grid (400×400 image → 25 columns).

local TileRenderer = {}

local TILE = 16          -- pixels per tile in the atlas
local atlas = nil
local quads = {}         -- quads[row][col]  (1-indexed)

-- Tile coordinates {col, row} in the 16×16 grid (1-indexed).
-- Identified by analysing average RGB of each cell in the 400×400 atlas.
local TILES = {
    -- Green grass top (bright green tiles from the terrain top edge)
    grass_l   = {3, 1},   -- (82,114,45) green, left-ish
    grass_m   = {4, 1},   -- (82,113,46) green, middle (100% fill)
    grass_r   = {5, 1},   -- (85,131,45) green, right-ish
    -- Grass-to-dirt transition row (greenish-brown, below the grass)
    grass_bl  = {2, 2},   -- (82,114,45) green-tinted dirt
    grass_bm  = {5, 2},   -- (82,96,48)  green-brown transition
    grass_br  = {6, 2},   -- (85,131,45) green edge
    -- Brown dirt fill (interior terrain, ~107,62,64 range)
    dirt      = {4, 4},   -- (107,62,64) solid brown fill (100%)
    dirt2     = {3, 4},   -- (107,62,64) solid brown fill (99%)
    dirt3     = {5, 4},   -- (107,62,64) solid brown fill (98%)
    -- Dirt edges (border tiles of the terrain mass)
    dirt_l    = {2, 3},   -- (108,63,64) left edge
    dirt_r    = {6, 3},   -- (109,63,65) right edge
    dirt_bl   = {3, 6},   -- (96,56,60) bottom-left darker
    dirt_bm   = {4, 6},   -- (84,50,56) bottom middle darker
    dirt_br   = {5, 6},   -- (93,54,59) bottom-right darker
    -- Wooden plank tiles (lighter brown ~158,96,80 for platforms)
    plank_l   = {7, 9},   -- (158,96,80) wood left
    plank_m   = {8, 9},   -- (158,96,80) wood middle
    plank_r   = {9, 9},   -- (161,99,80) wood right
}

local function init()
    if atlas then return end
    atlas = love.graphics.newImage("assets/Tiles/Tiles/Assets/Assets.png")
    atlas:setFilter("nearest", "nearest")
    local sw, sh = atlas:getDimensions()
    local cols = math.floor(sw / TILE)
    local rows = math.floor(sh / TILE)
    for r = 1, rows do
        quads[r] = {}
        for c = 1, cols do
            quads[r][c] = love.graphics.newQuad(
                (c - 1) * TILE, (r - 1) * TILE,
                TILE, TILE, sw, sh
            )
        end
    end
end

local function getQuad(name)
    local t = TILES[name]
    if not t then return nil end
    local col, row = t[1], t[2]
    return quads[row] and quads[row][col]
end

--- Draw a wall (solid rectangle) using tiled texture.
--- Walls get grass on top, dirt fill, and edge tiles.
function TileRenderer.drawWall(x, y, w, h)
    init()
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
                -- Grass top row
                if isLeft then
                    quad = getQuad("grass_l")
                elseif isRight then
                    quad = getQuad("grass_r")
                else
                    quad = getQuad("grass_m")
                end
            elseif isBottom then
                if isLeft then
                    quad = getQuad("dirt_bl")
                elseif isRight then
                    quad = getQuad("dirt_br")
                else
                    quad = getQuad("dirt_bm")
                end
            elseif isLeft then
                quad = getQuad("dirt_l")
            elseif isRight then
                quad = getQuad("dirt_r")
            else
                -- Interior: alternate between dirt fills for variety
                local v = (tx + ty) % 3
                if v == 0 then
                    quad = getQuad("dirt")
                elseif v == 1 then
                    quad = getQuad("dirt2")
                else
                    quad = getQuad("dirt3")
                end
            end

            if quad then
                love.graphics.draw(atlas, quad, x + tx * TILE, y + ty * TILE)
            end
        end
    end
end

--- Draw a thin platform (one-way) using plank tiles.
function TileRenderer.drawPlatform(x, y, w, h)
    init()
    love.graphics.setColor(1, 1, 1)

    local tilesW = math.ceil(w / TILE)
    local tilesH = math.max(1, math.ceil(h / TILE))

    for ty = 0, tilesH - 1 do
        for tx = 0, tilesW - 1 do
            local quad
            local isTop = (ty == 0)

            if isTop then
                -- Top row: plank tiles
                if tx == 0 then
                    quad = getQuad("plank_l")
                elseif tx == tilesW - 1 then
                    quad = getQuad("plank_r")
                else
                    quad = getQuad("plank_m")
                end
            else
                -- Below top: dirt fill for thicker platforms
                if tx == 0 then
                    quad = getQuad("dirt_l")
                elseif tx == tilesW - 1 then
                    quad = getQuad("dirt_r")
                else
                    if (tx + ty) % 2 == 0 then
                        quad = getQuad("dirt")
                    else
                        quad = getQuad("dirt3")
                    end
                end
            end

            if quad then
                love.graphics.draw(atlas, quad, x + tx * TILE, y + ty * TILE)
            end
        end
    end
end

return TileRenderer
