-- Train renderer — draws train car sprites over platforms flagged with trainCar = true.
-- Also draws the rail track strip at the bottom of the world view.
--
-- Platform conventions:
--   platform.trainCar  = true              → render as a train car
--   platform.carType   = "boxcar" | ...    → which sprite to use (default: "boxcar")
--
-- Car sprites are scaled to match the platform width; height is proportional.
-- A tinted metal/wood undercarriage fill is drawn beneath the sprite when the
-- image extends less than the full h.

local TrainRenderer = {}

local ASSET_DIR = "assets/Kooky - Pixel Train assets - v0.0.1/"

-- carType → sprite filename (static PNGs only — LOVE2D can't animate GIFs natively)
local CAR_FILES = {
    boxcar    = ASSET_DIR .. "carriage_v18_car1.png",
    passenger = ASSET_DIR .. "carriage_v18_car2.png",
    flatcar   = ASSET_DIR .. "carriage_v18_car3.png",
    tanker    = ASSET_DIR .. "carriage_v18_car4.png",
    tender    = ASSET_DIR .. "carriage_v18_car5.png",
    livestock = ASSET_DIR .. "carriage_v18_car6.png",
    lumber    = ASSET_DIR .. "carriage_v18_car7.png",
    armored   = ASSET_DIR .. "carriage_v18_car8.png",
    engine    = ASSET_DIR .. "carriage_v18_car9.png",
}

local _images  = {}   -- path → Image (or false if failed)
local _railImg = nil
local _railLoaded = false

local function loadImg(path)
    if _images[path] ~= nil then return _images[path] end
    local ok, img = pcall(love.graphics.newImage, path)
    if ok then
        img:setFilter("nearest", "nearest")
        _images[path] = img
        return img
    else
        _images[path] = false
        return false
    end
end

local function loadRail()
    if _railLoaded then return _railImg end
    _railLoaded = true
    local ok, img = pcall(love.graphics.newImage, ASSET_DIR .. "railtrack_v1.png")
    if ok then
        img:setFilter("nearest", "nearest")
        img:setWrap("repeat", "clampzero")
        _railImg = img
    end
    return _railImg
end

--- Preload all car assets (call on world enter to avoid mid-game hitches).
function TrainRenderer.preload()
    for _, path in pairs(CAR_FILES) do loadImg(path) end
    loadRail()
end

--- Draw a single train car sprite fitted to the given collision rect.
--- x, y, w, h — the platform bounding box (y = roof of car).
--- carType — string key; defaults to "boxcar".
function TrainRenderer.drawCar(x, y, w, h, carType)
    local path = CAR_FILES[carType or "boxcar"] or CAR_FILES["boxcar"]
    local img  = path and loadImg(path)

    -- Undercarriage tint fill (always drawn so there's no see-through gap)
    love.graphics.setColor(0.22, 0.18, 0.14)
    love.graphics.rectangle("fill", x, y, w, h)

    if img then
        local iw, ih = img:getDimensions()
        local scaleX = w / iw
        local scaleY = scaleX   -- keep aspect ratio
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, x, y, 0, scaleX, scaleY)
    else
        -- Fallback: wooden plank look
        love.graphics.setColor(0.45, 0.30, 0.16)
        love.graphics.rectangle("fill", x, y, w, h)
        love.graphics.setColor(0.60, 0.42, 0.22)
        love.graphics.rectangle("fill", x, y, w, 5)
        -- Rivets
        love.graphics.setColor(0.25, 0.22, 0.18)
        for rx = x + 8, x + w - 8, 16 do
            love.graphics.circle("fill", rx, y + 3, 2)
        end
    end
end

--- Draw the gap between two cars — just the dark void between platforms.
--- Called automatically by drawRoomCars when it detects a gap.
local function drawCarGap(x, y, w, roomH)
    -- Dark danger void — player can see there's nothing there
    love.graphics.setColor(0.06, 0.04, 0.04, 1)
    love.graphics.rectangle("fill", x, y, w, roomH - y)
    -- Small "track" hint at the very bottom
    love.graphics.setColor(0.18, 0.14, 0.12)
    love.graphics.rectangle("fill", x, roomH - 6, w, 6)
end

--- Convenience: draw all train car platforms and their gaps for a room.
--- Pass currentRoom and the room height so we can fill gaps.
function TrainRenderer.drawRoomCars(platforms, roomH)
    -- Sort floor-level trainCar platforms left→right to detect gaps
    local cars = {}
    for _, p in ipairs(platforms) do
        if p.trainCar then
            table.insert(cars, p)
        end
    end
    table.sort(cars, function(a, b) return a.x < b.x end)

    -- Draw gaps first (behind cars)
    for i = 1, #cars - 1 do
        local a, b = cars[i], cars[i + 1]
        local gapX = a.x + a.w
        local gapW = b.x - gapX
        if gapW > 0 then
            drawCarGap(gapX, a.y, gapW, roomH)
        end
    end

    -- Draw each car
    for _, p in ipairs(cars) do
        TrainRenderer.drawCar(p.x, p.y, p.w, p.h, p.carType)
    end
end

--- Draw rail tracks tiled across the full width of the view at the bottom of the world.
--- Call in world-space (inside camera:attach) before platforms are rendered.
function TrainRenderer.drawRails(camX, camY, viewW, viewH, roomH)
    local railImg = loadRail()
    local trackY  = roomH - 4   -- just below the car floor
    local trackH  = 8

    if railImg then
        local rw = railImg:getWidth()
        local rh = railImg:getHeight()
        local scaleY = trackH / rh
        local scaleX = scaleY
        local tileW  = rw * scaleX

        love.graphics.setColor(0.75, 0.68, 0.55)
        local startX = math.floor((camX - viewW * 0.5) / tileW) * tileW
        local endX   = camX + viewW * 0.5 + tileW
        for rx = startX, endX, tileW do
            love.graphics.draw(railImg, rx, trackY, 0, scaleX, scaleY)
        end
    else
        -- Solid rail fallback
        love.graphics.setColor(0.40, 0.36, 0.30)
        local left  = camX - viewW * 0.5
        love.graphics.rectangle("fill", left, trackY, viewW + 1, trackH)
        -- Rail lines
        love.graphics.setColor(0.55, 0.50, 0.42)
        love.graphics.rectangle("fill", left, trackY + 1, viewW + 1, 2)
        love.graphics.rectangle("fill", left, trackY + 5, viewW + 1, 2)
    end

    love.graphics.setColor(1, 1, 1)
end

return TrainRenderer
