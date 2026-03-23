--[[
  Shared vision: screen-space ellipse (player lamp) + fog-of-war grid.
  world_lighting uses the same radius / ellipse as gameplay visibility.

  Fog-of-war polish: use a tiny per-cell canvas, draw 1×1 px per cell, then scale up
  with linear filtering — smooth edges without a texture asset. Optional later:
  multiply with a tiling noise/grunge PNG (alpha) for organic variation.
]]
local Vision = {}

--- Base screen radius (pixels); tuned for clearer navigation in night rooms.
Vision.VISION_SCREEN_RADIUS = 460

--- Ellipse axes as multiples of VISION_SCREEN_RADIUS (mirrored into world_lighting shader uniforms).
--- Keep the lamp slightly forward-biased, but much less tunnel-like than before.
Vision.LIGHT_RADIUS_ALONG = 1.24
Vision.LIGHT_RADIUS_ACROSS = 1.02

--- World radius used to mark explored fog cells (matches outer reach of vision).
function Vision.worldExploreRadius(cameraZoom)
    return Vision.VISION_SCREEN_RADIUS * math.max(Vision.LIGHT_RADIUS_ALONG, Vision.LIGHT_RADIUS_ACROSS)
        / cameraZoom
end

--- Unit forward in screen space (player → aim, else facing). Shake cancels in differences.
function Vision.computeScreenForward(player, camera, shakeX, shakeY)
    local px = player.x + player.w * 0.5
    local py = player.y + player.h * 0.5
    local ax = player.effectiveAimX
    local ay = player.effectiveAimY
    if not ax or not ay then
        ax = px + (player.facingRight and 96 or -96)
        ay = py
    end
    local sx1, sy1 = camera:cameraCoords(ax, ay, 0, 0, GAME_WIDTH, GAME_HEIGHT)
    local sx0, sy0 = camera:cameraCoords(px, py, 0, 0, GAME_WIDTH, GAME_HEIGHT)
    local fdx = sx1 - sx0
    local fdy = sy1 - sy0
    local flen = math.sqrt(fdx * fdx + fdy * fdy)
    if flen < 1e-4 then
        return 1, 0
    end
    return fdx / flen, fdy / flen
end

--- Ellipse metric in screen space; <= 1 means “inside” the lit shape (matches shader falloff region).
function Vision.playerLightMetric(player, wx, wy, camera, shakeX, shakeY)
    if not player or not camera then
        return 0
    end
    local px = player.x + player.w * 0.5
    local py = player.y + player.h * 0.5
    local psx, psy = camera:cameraCoords(px, py, 0, 0, GAME_WIDTH, GAME_HEIGHT)
    local esx, esy = camera:cameraCoords(wx, wy, 0, 0, GAME_WIDTH, GAME_HEIGHT)
    local dx = esx - psx
    local dy = esy - psy
    local fdx, fdy = Vision.computeScreenForward(player, camera, shakeX, shakeY)
    local along = dx * fdx + dy * fdy
    local across = dx * (-fdy) + dy * fdx
    local R = Vision.VISION_SCREEN_RADIUS
    local rx = R * Vision.LIGHT_RADIUS_ALONG
    local ry = R * Vision.LIGHT_RADIUS_ACROSS
    local te = math.sqrt((along / rx) * (along / rx) + (across / ry) * (across / ry))
    return te
end

--- True if world point lies in the player lamp (ellipse, screen space).
function Vision.isInLightVision(player, wx, wy, camera, shakeX, shakeY)
    return Vision.playerLightMetric(player, wx, wy, camera, shakeX, shakeY) <= 1.0
end

--- True if (wx, wy) lies in a fog cell that has been explored (revealed map).
function Vision.isExploredFog(room, wx, wy)
    if not room or not room.fogExplored then
        return false
    end
    local cell = room.fogCellSize
    local ci = math.floor(wx / cell) + 1
    local cj = math.floor(wy / cell) + 1
    if ci < 1 or ci > room.fogGridW or cj < 1 or cj > room.fogGridH then
        return false
    end
    return room.fogExplored[ci][cj]
end

--- Drawing / gameplay: visible in lamp OR in already-explored fog (so mobs aren’t invisible in dim explored areas).
function Vision.isEntityVisibleToPlayer(room, player, wx, wy, camera, shakeX, shakeY)
    if not room or not room.nightMode then
        return true
    end
    if Vision.isInLightVision(player, wx, wy, camera, shakeX, shakeY) then
        return true
    end
    return Vision.isExploredFog(room, wx, wy)
end

function Vision.initFogForRoom(room)
    local cell = 16
    local gw = math.ceil(room.width / cell)
    local gh = math.ceil(room.height / cell)
    local grid = {}
    for i = 1, gw do
        grid[i] = {}
        for j = 1, gh do
            grid[i][j] = false
        end
    end
    local fogCanvasLQ = love.graphics.newCanvas(gw, gh)
    fogCanvasLQ:setFilter("linear", "linear")
    return {
        fogCellSize = cell,
        fogGridW = gw,
        fogGridH = gh,
        fogExplored = grid,
        fogCanvasLQ = fogCanvasLQ,
        fogDirty = true,
    }
end

--- Mark fog cells whose centers fall inside the exploration circle (per frame while alive).
function Vision.markFogExplored(room, player, cameraZoom)
    if not room or not room.fogExplored then
        return
    end
    local px = player.x + player.w * 0.5
    local py = player.y + player.h * 0.5
    local r = Vision.worldExploreRadius(cameraZoom)
    local cell = room.fogCellSize
    local gw, gh = room.fogGridW, room.fogGridH
    local ext = cell * 0.75
    local r2 = (r + ext) * (r + ext)
    for ci = 1, gw do
        for cj = 1, gh do
            local ccx = (ci - 0.5) * cell
            local ccy = (cj - 0.5) * cell
            local dx = ccx - px
            local dy = ccy - py
            if dx * dx + dy * dy <= r2 then
                if not room.fogExplored[ci][cj] then
                    room.fogExplored[ci][cj] = true
                    room.fogDirty = true
                end
            end
        end
    end
end

local FOG_UNEXPLORED_RGB = { 0.14, 0.12, 0.22 }
local FOG_UNEXPLORED_ALPHA = 0.78
local FOG_FRONTIER_SOFT = 0.42

local function cellTouchesExplored(room, gw, gh, ci, cj)
    for di = -1, 1 do
        for dj = -1, 1 do
            if not (di == 0 and dj == 0) then
                local ni, nj = ci + di, cj + dj
                if ni >= 1 and ni <= gw and nj >= 1 and nj <= gh then
                    if room.fogExplored[ni][nj] then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function Vision.refreshFogCanvas(room)
    local canvas = room.fogCanvasLQ
    if not canvas then
        return
    end
    local gw, gh = room.fogGridW, room.fogGridH
    local prev = love.graphics.getCanvas()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    for ci = 1, gw do
        for cj = 1, gh do
            if not room.fogExplored[ci][cj] then
                local frontier = cellTouchesExplored(room, gw, gh, ci, cj)
                local edge = frontier and FOG_FRONTIER_SOFT or 1
                love.graphics.setColor(
                    FOG_UNEXPLORED_RGB[1],
                    FOG_UNEXPLORED_RGB[2],
                    FOG_UNEXPLORED_RGB[3],
                    FOG_UNEXPLORED_ALPHA * edge
                )
                love.graphics.rectangle("fill", ci - 1, cj - 1, 1, 1)
            end
        end
    end
    love.graphics.setCanvas(prev)
    love.graphics.setColor(1, 1, 1, 1)
end

--- Fog: 1×1 px per cell on a small canvas, scaled by cell size → smooth edges (linear filter).
function Vision.drawFogOfWar(room, viewL, viewT, viewR, viewB)
    if not room or not room.fogExplored or not room.fogCanvasLQ then
        return
    end
    if room.fogDirty then
        Vision.refreshFogCanvas(room)
        room.fogDirty = false
    end
    local cell = room.fogCellSize
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(room.fogCanvasLQ, 0, 0, 0, cell, cell)
end

return Vision
