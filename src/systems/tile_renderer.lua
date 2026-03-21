-- Tile renderer draws walls and platforms from a themed atlas instead of
-- plain colored rectangles. The default atlas remains the original terrain
-- sheet, while the dev arena can switch to a desert proof-of-concept atlas.

local TileRenderer = {}

local DRAW_TILE = 16     -- world-space pixels per tile
local atlas = nil
local quads = {}         -- quads[row][col] (1-indexed)
local activeTheme = "default"

local THEMES = {
    default = {
        atlasPath = "assets/Tiles/Tiles/Assets/Assets.png",
        sourceTile = 16,
        spacing = 0,
        tiles = {
            grass_l = {3, 1},
            grass_m = {4, 1},
            grass_r = {5, 1},
            grass_bl = {2, 2},
            grass_bm = {5, 2},
            grass_br = {6, 2},
            dirt = {4, 4},
            dirt2 = {3, 4},
            dirt3 = {5, 4},
            dirt_l = {2, 3},
            dirt_r = {6, 3},
            dirt_bl = {3, 6},
            dirt_bm = {4, 6},
            dirt_br = {5, 6},
            plank_l = {7, 9},
            plank_m = {8, 9},
            plank_r = {9, 9},
        },
    },
    desert = {
        atlasPath = "assets/terrain/platformer-blocks/Tilemap/sand_packed.png",
        sourceTile = 18,
        spacing = 0,
        tiles = {
            grass_l = { {1, 4}, {4, 4}, {7, 4}, {1, 7}, {4, 7}, {7, 7} },
            grass_m = { {2, 4}, {5, 4}, {8, 4}, {2, 7}, {5, 7}, {8, 7} },
            grass_r = { {3, 4}, {6, 4}, {9, 4}, {3, 7}, {6, 7}, {9, 7} },
            grass_bl = { {1, 5}, {4, 5}, {7, 5}, {1, 8}, {4, 8}, {7, 8} },
            grass_bm = { {2, 5}, {5, 5}, {8, 5}, {2, 8}, {5, 8}, {8, 8} },
            grass_br = { {3, 5}, {6, 5}, {9, 5}, {3, 8}, {6, 8}, {9, 8} },
            dirt = { {2, 5}, {5, 5}, {8, 5}, {2, 8}, {5, 8}, {8, 8} },
            dirt2 = { {1, 5}, {4, 5}, {7, 5}, {1, 8}, {4, 8}, {7, 8} },
            dirt3 = { {3, 5}, {6, 5}, {9, 5}, {3, 8}, {6, 8}, {9, 8} },
            dirt_l = { {1, 5}, {4, 5}, {7, 5}, {1, 8}, {4, 8}, {7, 8} },
            dirt_r = { {3, 5}, {6, 5}, {9, 5}, {3, 8}, {6, 8}, {9, 8} },
            dirt_bl = { {1, 6}, {4, 6}, {7, 6}, {1, 9}, {4, 9}, {7, 9} },
            dirt_bm = { {2, 6}, {5, 6}, {8, 6}, {2, 9}, {5, 9}, {8, 9} },
            dirt_br = { {3, 6}, {6, 6}, {9, 6}, {3, 9}, {6, 9}, {9, 9} },
            plank_l = { {1, 4}, {4, 4}, {7, 4}, {1, 7}, {4, 7}, {7, 7} },
            plank_m = { {2, 4}, {5, 4}, {8, 4}, {2, 7}, {5, 7}, {8, 7} },
            plank_r = { {3, 4}, {6, 4}, {9, 4}, {3, 7}, {6, 7}, {9, 7} },
        },
    },
}

function TileRenderer.setTheme(name)
    local nextTheme = THEMES[name] and name or "default"
    if activeTheme == nextTheme and atlas then
        return
    end
    activeTheme = nextTheme
    atlas = nil
    quads = {}
end

local function theme()
    return THEMES[activeTheme] or THEMES.default
end

local function init()
    if atlas then return end

    local cfg = theme()
    atlas = love.graphics.newImage(cfg.atlasPath)
    atlas:setFilter("nearest", "nearest")

    local sw, sh = atlas:getDimensions()
    local tile = cfg.sourceTile
    local spacing = cfg.spacing or 0
    local step = tile + spacing
    local cols = math.floor((sw + spacing) / step)
    local rows = math.floor((sh + spacing) / step)

    for r = 1, rows do
        quads[r] = {}
        for c = 1, cols do
            quads[r][c] = love.graphics.newQuad(
                (c - 1) * step,
                (r - 1) * step,
                tile,
                tile,
                sw,
                sh
            )
        end
    end
end

local function getQuad(name, variant)
    local t = theme().tiles[name]
    if not t then return nil end
    local col, row
    if type(t[1]) == "table" then
        local idx = ((variant or 1) - 1) % #t + 1
        col, row = t[idx][1], t[idx][2]
    else
        col, row = t[1], t[2]
    end
    return quads[row] and quads[row][col]
end

local function drawTile(quad, x, y)
    if not quad then return end
    local scale = DRAW_TILE / theme().sourceTile
    love.graphics.draw(atlas, quad, x, y, 0, scale, scale)
end

function TileRenderer.drawWall(x, y, w, h)
    init()
    love.graphics.setColor(1, 1, 1)

    local tilesW = math.ceil(w / DRAW_TILE)
    local tilesH = math.ceil(h / DRAW_TILE)

    for ty = 0, tilesH - 1 do
        for tx = 0, tilesW - 1 do
            local quad
            local isTop = (ty == 0)
            local isBottom = (ty == tilesH - 1) and tilesH > 1
            local isLeft = (tx == 0)
            local isRight = (tx == tilesW - 1)

            if isTop then
                if isLeft then
                    quad = getQuad("grass_l", ty + 1)
                elseif isRight then
                    quad = getQuad("grass_r", ty + 1)
                else
                    quad = getQuad("grass_m", tx + 1)
                end
            elseif isBottom then
                if isLeft then
                    quad = getQuad("dirt_bl", tx + 1)
                elseif isRight then
                    quad = getQuad("dirt_br", tx + 1)
                else
                    quad = getQuad("dirt_bm", tx + 1)
                end
            elseif isLeft then
                quad = getQuad("dirt_l", ty + 1)
            elseif isRight then
                quad = getQuad("dirt_r", ty + 1)
            else
                local v = (tx + ty) % 3
                if v == 0 then
                    quad = getQuad("dirt", tx + ty + 1)
                elseif v == 1 then
                    quad = getQuad("dirt2", tx + ty + 1)
                else
                    quad = getQuad("dirt3", tx + ty + 1)
                end
            end

            drawTile(quad, x + tx * DRAW_TILE, y + ty * DRAW_TILE)
        end
    end
end

function TileRenderer.drawPlatform(x, y, w, h)
    init()
    love.graphics.setColor(1, 1, 1)

    local tilesW = math.ceil(w / DRAW_TILE)
    local tilesH = math.max(1, math.ceil(h / DRAW_TILE))

    for ty = 0, tilesH - 1 do
        for tx = 0, tilesW - 1 do
            local quad
            local isTop = (ty == 0)

            if isTop then
                if tx == 0 then
                    quad = getQuad("plank_l", tx + 1)
                elseif tx == tilesW - 1 then
                    quad = getQuad("plank_r", tx + 1)
                else
                    quad = getQuad("plank_m", tx + 1)
                end
            else
                if tx == 0 then
                    quad = getQuad("dirt_l", ty + 1)
                elseif tx == tilesW - 1 then
                    quad = getQuad("dirt_r", ty + 1)
                else
                    if (tx + ty) % 2 == 0 then
                        quad = getQuad("dirt", tx + ty + 1)
                    else
                        quad = getQuad("dirt3", tx + ty + 1)
                    end
                end
            end

            drawTile(quad, x + tx * DRAW_TILE, y + ty * DRAW_TILE)
        end
    end
end

return TileRenderer
