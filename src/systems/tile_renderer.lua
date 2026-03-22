-- Tile renderer — draws walls and platforms using a tile atlas or solid-fill colors.
-- Supports multiple themes (one per world). Each theme specifies either:
--   a) An atlas image path + tile coordinate mapping (forest / train)
--   b) _solidFill = true + color fields (legacy desert-style fill)
--   c) _textureFill + _groundTexture — seamless tiling; optional _waterTexture,
--      _bridgeAtlasPath for gap bridges — see TileRenderer.drawWaterBand

local TileRenderer = {}

local TILE = 16          -- pixels per tile in the atlas

-- Cache: atlas path -> { image = Image, quads = quads[row][col] }
local atlasCache = {}
-- Cache: arbitrary image path -> Image|false (seamless tiling fills)
local fillTextureCache = {}

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
        if theme._textureFill then return nil, nil, nil end
        if theme._solidFill then return nil, nil, nil end  -- handled separately
        if theme._atlasPath then atlasPath = theme._atlasPath end
        if theme.grass_m then tiles = theme end
        if theme._tint then tint = theme._tint end
    end

    return loadAtlas(atlasPath), tiles, tint
end

local function getFillTexture(path)
    if not path or path == "" then return nil end
    local c = fillTextureCache[path]
    if c ~= nil then return c ~= false and c or nil end
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
        img:setFilter("nearest", "nearest")
        fillTextureCache[path] = img
        return img
    end
    fillTextureCache[path] = false
    return nil
end

--- Tile a single image across a rectangle (world pixels). Used for desert sand / water strips.
local function drawTiledTextureRect(x, y, w, h, path, tint)
    tint = tint or {1, 1, 1}
    local img = getFillTexture(path)
    if not img then
        love.graphics.setColor(0.87, 0.74, 0.50, tint[4] or 1)
        love.graphics.rectangle("fill", x, y, w, h)
        love.graphics.setColor(1, 1, 1)
        return
    end
    local iw, ih = img:getDimensions()
    love.graphics.setColor(tint[1], tint[2], tint[3], tint[4] or 1)
    local yy = y
    while yy < y + h do
        local xx = x
        local th = math.min(ih, y + h - yy)
        while xx < x + w do
            local tw = math.min(iw, x + w - xx)
            if tw > 0 and th > 0 then
                if tw == iw and th == ih then
                    love.graphics.draw(img, xx, yy)
                else
                    local quad = love.graphics.newQuad(0, 0, tw, th, iw, ih)
                    love.graphics.draw(img, quad, xx, yy)
                end
            end
            xx = xx + iw
        end
        yy = yy + th
    end
    love.graphics.setColor(1, 1, 1)
end

-- ─── Western / seamless-texture depth (hills & mass, not literal geology) ──
-- Ridge highlights + edge shade + optional aerial perspective by platform height.

local function terrainDepthEnabled(theme)
    return theme and theme._textureFill and theme._groundTexture
        and theme._terrainDepthHills ~= false
end

--- @param variant "mass" | "thin"
local function drawTerrainDepthOverlays(x, y, w, h, theme, variant, opts)
    if not terrainDepthEnabled(theme) or w <= 0 or h <= 0 then return end
    opts = opts or {}
    local rh = opts.roomHeight

    local ridgeA = (variant == "thin") and 0.20 or 0.14
    local sideA = (variant == "thin") and 0.11 or 0.085
    local botA = (variant == "mass" and h >= 20) and 0.09 or 0
    local wave = 0.045 * math.sin(x * 0.013 + y * 0.009)

    -- Aerial perspective: higher platforms (smaller y) read farther / airier
    if rh and rh > 0 then
        local elev = 1 - (y / rh)
        elev = math.max(0, math.min(1, elev))
        local atm = 0.08 * elev
        love.graphics.setColor(0.76, 0.82, 0.92, atm)
        love.graphics.rectangle("fill", x, y, w, h)
    end

    love.graphics.setColor(1, 0.97, 0.88, ridgeA + wave)
    love.graphics.rectangle("fill", x, y, w, math.min(3, h))

    love.graphics.setColor(1, 1, 1, 0.06 + wave * 0.5)
    love.graphics.rectangle("fill", x, y, w, 1)

    love.graphics.setColor(0, 0, 0, sideA)
    local sw = variant == "thin" and 3 or 4
    love.graphics.rectangle("fill", x, y, sw, h)
    love.graphics.rectangle("fill", x + w - sw, y, sw, h)

    if botA > 0 then
        love.graphics.setColor(0, 0, 0, botA)
        love.graphics.rectangle("fill", x, y + h - 5, w, 5)
    end

    love.graphics.setColor(1, 1, 1)
end

--- Stacked horizontal bands: same seamless texture, shifted X each step + tone layers.
--- Reads as broken rock face / foothills — not a single plumb rectangle.
local function drawJaggedMountainMass(x0, yTop, w0, yBottom, theme, seed)
    if not theme or not theme._textureFill or not theme._groundTexture then return end
    if yBottom <= yTop or w0 <= 0 then return end
    seed = seed or 0
    local baseTint = theme._tint or {1, 1, 1}
    local path = theme._groundTexture
    local step = theme._mountainBandH or 20
    local tones = theme._mountainRockTones
        or {0.78, 0.62, 0.68, 0.54, 0.71, 0.52, 0.64, 0.48}
    local y = yTop
    local band = 0
    while y < yBottom do
        local h = math.min(step, yBottom - y)
        local tone = tones[(band % #tones) + 1]
        -- Horizontal stagger: mass is not straight down — reads as slope / ridge
        local stagger = 0.12 * band * math.sin(seed * 0.31 + band * 0.17)
        local jx = 14 * math.sin(seed * 1.07 + band * 0.76) + 9 * math.sin(band * 0.35) + stagger * 18
        local wVar = 18 * math.sin(seed * 0.58 + band * 0.51)
        local wcur = math.max(w0 * 0.72, w0 + wVar)
        local xcur = x0 + (w0 - wcur) / 2 + jx * 0.4
        if xcur < 2 then xcur = 2 end
        drawTiledTextureRect(xcur, y, wcur, h, path, {
            baseTint[1] * tone, baseTint[2] * tone, baseTint[3] * tone, baseTint[4] or 1,
        })
        love.graphics.setColor(0, 0, 0, 0.1)
        love.graphics.rectangle("fill", xcur, y + h - 2, wcur, 2)
        love.graphics.setColor(0, 0, 0, 0.14)
        love.graphics.rectangle("fill", xcur, y, 4, h)
        love.graphics.rectangle("fill", xcur + wcur - 4, y, 4, h)
        band = band + 1
        y = y + h
    end
    love.graphics.setColor(1, 1, 1)
end

--- Distant layered silhouette (same tiles, darker + transparent) behind gameplay.
function TileRenderer.drawWesternMountainSilhouette(roomW, roomH, waterStripH, theme)
    if not theme or not theme._mountainSilhouette or not theme._textureFill
        or not theme._groundTexture or not roomW or not roomH then
        return
    end
    waterStripH = waterStripH or 0
    local baseTint = theme._tint or {1, 1, 1}
    local path = theme._groundTexture
    local y1 = roomH - waterStripH - 12
    local y0 = math.max(8, roomH * 0.06)
    local n = 7
    for i = 0, n - 1 do
        local t = i / math.max(1, n - 1)
        local y = y0 + t * (y1 - y0 - 36)
        local stripH = 26
        local tone = 0.28 + 0.06 * math.sin(i * 1.2)
        local xoff = 22 * math.sin(i * 0.85) + 28 * t
        local rw = roomW * (0.5 + 0.12 * math.sin(i * 0.66))
        local a = 0.42
        drawTiledTextureRect(xoff + roomW * 0.18, y, rw, stripH, path, {
            baseTint[1] * tone, baseTint[2] * tone, baseTint[3] * tone, (baseTint[4] or 1) * a,
        })
    end
    love.graphics.setColor(1, 1, 1)
end

--- Visual rock mass under a thin ledge down toward the canyon floor (not floating).
function TileRenderer.drawLedgeMountainSupport(x, y, w, h, massBottomY, theme, plat)
    if not theme or not theme._mountainMassSupport then return end
    local y0 = y + h
    if y0 >= massBottomY - 2 then return end
    local seed = (plat and plat.x or x) * 0.017 + (plat and plat.y or y) * 0.029 + w * 0.008
    drawJaggedMountainMass(x, y0, w, massBottomY, theme, seed)
end

--- Two support columns under a gap bridge (planks read anchored to rock).
function TileRenderer.drawGapBridgeMountainSupports(x, y, w, h, massBottomY, theme, plat)
    if not theme or not theme._mountainMassSupport then return end
    local y0 = y + h
    if y0 >= massBottomY - 2 then return end
    local colW = math.max(16, math.min(34, w * 0.14))
    local x1 = x + w * 0.24 - colW / 2
    local x2 = x + w * 0.76 - colW / 2
    local sx = (plat and plat.x or x)
    drawJaggedMountainMass(x1, y0, colW, massBottomY, theme, sx * 0.02 + 0.7)
    drawJaggedMountainMass(x2, y0, colW, massBottomY, theme, sx * 0.02 + 1.4)
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

--- Plank + dirt underside using the forest tile atlas (used for desert gap bridges).
local function drawAtlasPlankPlatform(x, y, w, h, atlasPath, tint)
    tint = tint or {1, 1, 1}
    local atlasData = loadAtlas(atlasPath)
    local tiles = DEFAULT_TILES
    love.graphics.setColor(tint[1], tint[2], tint[3], tint[4] or 1)

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
    love.graphics.setColor(1, 1, 1)
end

--- Draw a wall (solid rectangle) using tiled texture.
--- theme is optional — nil uses the default forest theme.
--- opts optional: { roomHeight = number } for aerial perspective on seamless fills.
function TileRenderer.drawWall(x, y, w, h, theme, opts)
    if theme and theme._textureFill and theme._groundTexture then
        drawTiledTextureRect(x, y, w, h, theme._groundTexture, theme._tint)
        drawTerrainDepthOverlays(x, y, w, h, theme, "mass", opts)
        return
    end
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
--- plat optional: `isGapBridge` + theme `_bridgeAtlasPath` draws wooden planks over the gap.
--- opts optional: { roomHeight = number } for ledge ridge / haze (seamless fills).
function TileRenderer.drawPlatform(x, y, w, h, theme, plat, opts)
    if theme and theme._textureFill and theme._groundTexture then
        if plat and plat.isGapBridge and theme._bridgeAtlasPath then
            drawAtlasPlankPlatform(x, y, w, h, theme._bridgeAtlasPath, theme._bridgeTint)
            return
        end
        drawTiledTextureRect(x, y, w, h, theme._groundTexture, theme._tint)
        drawTerrainDepthOverlays(x, y, w, h, theme, "thin", opts)
        return
    end
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

--- Bottom-of-room water strip with scroll animation and surface highlights.
function TileRenderer.drawWaterBand(x, y, w, h, theme)
    if not theme or not theme._waterTexture or not h or h <= 0 or w <= 0 then return end
    local tint = theme._waterTint or {1, 1, 1, 0.92}
    local img = getFillTexture(theme._waterTexture)
    if not img then
        love.graphics.setColor(0.25, 0.45, 0.65, tint[4] or 0.92)
        love.graphics.rectangle("fill", x, y, w, h)
        love.graphics.setColor(1, 1, 1)
        return
    end

    local iw, ih = img:getDimensions()
    local t = love.timer.getTime()
    local scrollX = (t * 18) % iw

    love.graphics.setColor(tint[1], tint[2], tint[3], tint[4] or 0.92)
    local yy = y
    while yy < y + h do
        local xx = x - scrollX
        local th = math.min(ih, y + h - yy)
        while xx < x + w do
            local drawX = xx
            local tw = iw
            local srcX = 0
            if drawX < x then
                srcX = x - drawX
                tw = tw - srcX
                drawX = x
            end
            if drawX + tw > x + w then
                tw = x + w - drawX
            end
            if tw > 0 and th > 0 then
                local quad = love.graphics.newQuad(srcX, 0, tw, th, iw, ih)
                love.graphics.draw(img, quad, drawX, yy)
            end
            xx = xx + iw
        end
        yy = yy + th
    end

    local waveAlpha = (tint[4] or 0.92) * 0.35
    love.graphics.setColor(0.85, 0.92, 1.0, waveAlpha)
    local waveY = y + 1
    for wx = 0, math.floor(w / 8) - 1 do
        local px = x + wx * 8
        local wobble = math.sin(t * 2.5 + wx * 0.7) * 1.5
        love.graphics.rectangle("fill", px, waveY + wobble, 6, 1)
    end

    love.graphics.setColor(1, 1, 1, waveAlpha * 0.6)
    for wx = 0, math.floor(w / 14) - 1 do
        local px = x + wx * 14 + math.sin(t * 1.8 + wx * 1.3) * 4
        local wobble = math.sin(t * 3 + wx * 0.9) * 1
        love.graphics.rectangle("fill", px, y + wobble, 3, 1)
    end

    love.graphics.setColor(1, 1, 1)
end

--- Draw a cliff/mesa body hanging below a platform down to cliffBottom.
--- Gives elevated platforms the look of canyon buttes rather than floating slabs.
--- opts optional: { roomHeight = number } — passed through for consistency.
function TileRenderer.drawPlatformCliff(x, y, w, h, cliffBottom, theme, opts)
    local cliffY = y + h
    local cliffH = cliffBottom - cliffY
    if cliffH <= 0 then return end

    if theme and theme._textureFill and theme._groundTexture then
        local tint = theme._tint or {1, 1, 1}
        local maxV = theme._mesaCliffMaxVisualH
        local drawH = cliffH
        if not theme._mountainMassSupport and maxV and maxV > 0 then
            drawH = math.min(cliffH, maxV)
        end
        local cliffEnd = cliffY + drawH

        if theme._mountainMassSupport then
            local seed = x * 0.019 + y * 0.027
            drawJaggedMountainMass(x, cliffY, w, cliffEnd, theme, seed)
            if terrainDepthEnabled(theme) then
                love.graphics.setColor(0, 0, 0, 0.38)
                love.graphics.rectangle("fill", x, cliffY, w, math.min(14, drawH * 0.13))
            end
        else
            local darken = 0.78
            drawTiledTextureRect(x, cliffY, w, drawH, theme._groundTexture,
                {tint[1] * darken, tint[2] * darken, tint[3] * darken, tint[4] or 1})
            if terrainDepthEnabled(theme) then
                love.graphics.setColor(0, 0, 0, 0.44)
                love.graphics.rectangle("fill", x, cliffY, w, math.min(14, drawH * 0.14))
            end
            love.graphics.setColor(0, 0, 0, 0.28)
            love.graphics.rectangle("fill", x, cliffY, 5, drawH)
            love.graphics.rectangle("fill", x + w - 5, cliffY, 5, drawH)
            love.graphics.setColor(0, 0, 0, 0.14)
            local lineY = cliffY + 14
            while lineY < cliffEnd - 4 do
                love.graphics.rectangle("fill", x + 5, lineY, w - 10, 2)
                lineY = lineY + 14
            end
        end
        love.graphics.setColor(1, 1, 1)
        return
    end

    if theme and theme._solidFill then
        local maxV = theme._mesaCliffMaxVisualH
        local drawH = cliffH
        if maxV and maxV > 0 then drawH = math.min(cliffH, maxV) end
        drawSolidWall(x, cliffY, w, drawH, theme)
        return
    end

    -- Atlas-based / default: use drawWall
    local maxV = theme and theme._mesaCliffMaxVisualH
    local drawH = cliffH
    if maxV and maxV > 0 then drawH = math.min(cliffH, maxV) end
    TileRenderer.drawWall(x, cliffY, w, drawH, theme, opts)
end

--- Preload a theme's atlas (useful at world start to avoid mid-gameplay loads).
function TileRenderer.preloadTheme(theme)
    if not theme then return end
    if theme._textureFill and theme._groundTexture then
        getFillTexture(theme._groundTexture)
    end
    if theme._waterTexture then
        getFillTexture(theme._waterTexture)
    end
    if theme._solidFill then return end
    if theme._textureFill then
        if theme._bridgeAtlasPath then loadAtlas(theme._bridgeAtlasPath) end
        return
    end
    if theme._atlasPath then
        loadAtlas(theme._atlasPath)
    else
        loadAtlas(DEFAULT_ATLAS_PATH)
    end
end

return TileRenderer
