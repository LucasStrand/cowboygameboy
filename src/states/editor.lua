-- Level Editor — a gamestate for creating and editing room layouts.
-- Accessible from the main menu. Supports placing platforms, spawns, doors,
-- saving/loading, and test-playing rooms.

local Gamestate = require("lib.hump.gamestate")
local Camera = require("lib.hump.camera")
local Font = require("src.ui.font")
local Cursor = require("src.ui.cursor")
local TileRenderer = require("src.systems.tile_renderer")
local Worlds = require("src.data.worlds")
local RoomSerializer = require("src.systems.room_serializer")
local RoomLoader = require("src.systems.room_loader")

local editor = {}

-- Constants
local GRID = 16
local MIN_PLAT_SIZE = 16
local HANDLE_SIZE = 6
local TOOLBAR_W = 140
local PANEL_W = 180
local TOPBAR_H = 32
local DEFAULT_WORLD_ID = Worlds.default or "forest"

-- Tools
local TOOLS = {
    { id = "select",  label = "Select (V)",  key = "v" },
    { id = "platform", label = "Platform (P)", key = "p" },
    { id = "spawn",   label = "Spawn (S)",    key = "s" },
    { id = "door",    label = "Door (D)",     key = "d" },
    { id = "enemy",   label = "Enemy (E)",    key = "e" },
    { id = "eraser",  label = "Eraser (X)",   key = "x" },
}

local ENEMY_TYPES = { "bandit", "gunslinger", "buzzard" }
local ENEMY_COLORS = {
    bandit = {0.9, 0.3, 0.2},
    gunslinger = {0.2, 0.5, 0.9},
    buzzard = {0.8, 0.7, 0.2},
}

-- State
local cam
local camX, camY = 0, 0
local camZoom = 1.0
local fonts = {}

local currentTool = "select"
local enemyTypeIndex = 1

-- Room data being edited
local room = nil
local selectedIndex = nil   -- index into platforms
local selectedType = nil    -- "platform", "spawn", "enemy", "door"

-- Drag state
local dragging = false
local dragStartX, dragStartY = 0, 0
local dragOffX, dragOffY = 0, 0
local drawingPlatform = false  -- currently click-dragging to create a platform
local drawRect = nil           -- {x,y,w,h} being drawn

-- Resize
local resizeHandle = nil  -- "tl","tr","bl","br" or nil
local resizeOrigRect = nil

-- Grid toggle
local showGrid = true

-- File browser
local fileBrowserOpen = false
local fileBrowserRooms = {}
local fileBrowserScroll = 0
local fileBrowserHover = nil

-- World selector
local worldOptions = {}
local worldSelectOpen = false

-- Status message
local statusMsg = ""
local statusTimer = 0

-- Test play return flag
local returnFromTestPlay = false

local function snap(v)
    return math.floor(v / GRID + 0.5) * GRID
end

local function newRoom()
    return {
        id = "new_room",
        world = DEFAULT_WORLD_ID,
        width = 2400,
        height = 800,
        platforms = {},
        spawns = {},
        playerSpawn = {x = 80, y = 700},
        exitDoor = {x = 2340, y = 704, w = 32, h = 32},
    }
end

local function setStatus(msg)
    statusMsg = msg
    statusTimer = 3
end

local function screenToWorld(sx, sy)
    -- Convert screen coords to world coords accounting for camera and UI panels
    local wx = (sx - TOOLBAR_W) / camZoom + camX
    local wy = (sy - TOPBAR_H) / camZoom + camY
    return wx, wy
end

local function worldToScreen(wx, wy)
    local sx = (wx - camX) * camZoom + TOOLBAR_W
    local sy = (wy - camY) * camZoom + TOPBAR_H
    return sx, sy
end

local function pointInRect(px, py, rx, ry, rw, rh)
    return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

local function getTheme()
    if not room then return nil end
    local worldDef = Worlds.get(room.world or DEFAULT_WORLD_ID)
    if not worldDef then return nil end
    local theme = {}
    for k, v in pairs(worldDef.theme) do
        theme[k] = v
    end
    theme._atlasPath = worldDef.tileAtlas
    return theme
end

-- Find what element is under world coords
local function hitTest(wx, wy)
    if not room then return nil, nil end

    -- Check platforms (reverse order = top-most first)
    for i = #room.platforms, 1, -1 do
        local p = room.platforms[i]
        if pointInRect(wx, wy, p.x, p.y, p.w, p.h) then
            return "platform", i
        end
    end

    -- Check enemy spawns
    for i = #room.spawns, 1, -1 do
        local s = room.spawns[i]
        if pointInRect(wx, wy, s.x - 8, s.y - 8, 16, 16) then
            return "enemy", i
        end
    end

    -- Check player spawn
    if room.playerSpawn then
        local ps = room.playerSpawn
        if pointInRect(wx, wy, ps.x - 8, ps.y - 8, 16, 16) then
            return "spawn", 1
        end
    end

    -- Check exit door
    if room.exitDoor then
        local d = room.exitDoor
        if pointInRect(wx, wy, d.x, d.y, d.w, d.h) then
            return "door", 1
        end
    end

    return nil, nil
end

-- Check if mouse is over a resize handle of the selected platform
local function hitResizeHandle(sx, sy)
    if selectedType ~= "platform" or not selectedIndex then return nil end
    local p = room.platforms[selectedIndex]
    if not p then return nil end
    local hs = HANDLE_SIZE / camZoom
    local corners = {
        {id = "tl", x = p.x, y = p.y},
        {id = "tr", x = p.x + p.w, y = p.y},
        {id = "bl", x = p.x, y = p.y + p.h},
        {id = "br", x = p.x + p.w, y = p.y + p.h},
    }
    local wx, wy = screenToWorld(sx, sy)
    for _, c in ipairs(corners) do
        if math.abs(wx - c.x) <= hs and math.abs(wy - c.y) <= hs then
            return c.id
        end
    end
    return nil
end

function editor:enter()
    fonts.title = Font.new(20)
    fonts.body = Font.new(14)
    fonts.small = Font.new(11)
    Cursor.setDefault()

    -- Build world options
    worldOptions = {}
    for _, id in ipairs(Worlds.order) do
        local w = Worlds.get(id)
        worldOptions[#worldOptions + 1] = { id = id, name = w and w.name or id }
    end

    if not room then
        room = newRoom()
    end

    camX = 0
    camY = room.height / 2 - 300
    camZoom = 1.0
    selectedIndex = nil
    selectedType = nil
    fileBrowserOpen = false
    worldSelectOpen = false
    setStatus("Level Editor ready")
end

function editor:leave()
end

function editor:update(dt)
    -- Camera pan with WASD / arrow keys
    local speed = 400 / camZoom
    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
        camX = camX - speed * dt
    end
    if love.keyboard.isDown("d") or love.keyboard.isDown("right") then
        camX = camX + speed * dt
    end
    if love.keyboard.isDown("w") or love.keyboard.isDown("up") then
        camY = camY - speed * dt
    end
    if love.keyboard.isDown("s") or love.keyboard.isDown("down") then
        camY = camY + speed * dt
    end

    if statusTimer > 0 then
        statusTimer = statusTimer - dt
    end
end

function editor:keypressed(key)
    if fileBrowserOpen then
        if key == "escape" then fileBrowserOpen = false end
        return
    end

    if key == "escape" then
        local menu = require("src.states.menu")
        Gamestate.switch(menu)
        return
    end

    -- Tool shortcuts (only when not typing)
    for _, t in ipairs(TOOLS) do
        if key == t.key then
            currentTool = t.id
            selectedIndex = nil
            selectedType = nil
            return
        end
    end

    -- Enemy type cycling (number keys)
    if currentTool == "enemy" then
        local n = tonumber(key)
        if n and n >= 1 and n <= #ENEMY_TYPES then
            enemyTypeIndex = n
        end
    end

    if key == "g" then
        showGrid = not showGrid
    end

    if key == "delete" or key == "backspace" then
        if selectedType == "platform" and selectedIndex then
            table.remove(room.platforms, selectedIndex)
            selectedIndex = nil
            selectedType = nil
        elseif selectedType == "enemy" and selectedIndex then
            table.remove(room.spawns, selectedIndex)
            selectedIndex = nil
            selectedType = nil
        end
    end

    -- Ctrl+S to save
    if key == "s" and love.keyboard.isDown("lctrl", "rctrl") then
        if room.id and room.id ~= "" then
            local ok, path = RoomSerializer.save(room)
            if ok then
                setStatus("Saved: " .. path)
            else
                setStatus("Save failed!")
            end
        else
            setStatus("Set a room ID before saving")
        end
    end

    -- Ctrl+N for new room
    if key == "n" and love.keyboard.isDown("lctrl", "rctrl") then
        room = newRoom()
        selectedIndex = nil
        selectedType = nil
        setStatus("New room created")
    end

    -- Ctrl+L to load
    if key == "l" and love.keyboard.isDown("lctrl", "rctrl") then
        fileBrowserOpen = true
        fileBrowserRooms = RoomLoader.getAllRooms()
        fileBrowserScroll = 0
        fileBrowserHover = nil
    end

    -- Ctrl+T to test play
    if key == "t" and love.keyboard.isDown("lctrl", "rctrl") then
        if room and room.playerSpawn and room.exitDoor and #room.platforms > 0 then
            editor._testRoom = room
            local game = require("src.states.game")
            Gamestate.switch(game, { editorRoom = room, worldId = room.world or DEFAULT_WORLD_ID })
        else
            setStatus("Room needs platforms, player spawn, and door to test")
        end
    end
end

function editor:mousepressed(x, y, button)
    if button ~= 1 then return end

    local gx, gy = x, y

    -- File browser click
    if fileBrowserOpen then
        local screenW, screenH = GAME_WIDTH, GAME_HEIGHT
        local bw, bh = 400, 300
        local bx = (screenW - bw) / 2
        local by = (screenH - bh) / 2
        -- Close button
        if pointInRect(gx, gy, bx + bw - 30, by, 30, 24) then
            fileBrowserOpen = false
            return
        end
        -- Room entries
        local entryH = 28
        local listY = by + 32
        for i, r in ipairs(fileBrowserRooms) do
            local ey = listY + (i - 1) * entryH - fileBrowserScroll
            if ey >= listY and ey + entryH <= by + bh then
                if pointInRect(gx, gy, bx + 8, ey, bw - 16, entryH) then
                    room = r
                    room._source = nil
                    fileBrowserOpen = false
                    selectedIndex = nil
                    selectedType = nil
                    camX = 0
                    camY = (room.height or 800) / 2 - 300
                    setStatus("Loaded: " .. (r.id or "unknown"))
                    return
                end
            end
        end
        return
    end

    -- Top bar buttons
    if gy < TOPBAR_H then
        -- New
        if pointInRect(gx, gy, TOOLBAR_W, 0, 60, TOPBAR_H) then
            room = newRoom()
            selectedIndex = nil
            selectedType = nil
            setStatus("New room")
            return
        end
        -- Save
        if pointInRect(gx, gy, TOOLBAR_W + 64, 0, 60, TOPBAR_H) then
            local ok, path = RoomSerializer.save(room)
            if ok then setStatus("Saved: " .. path) else setStatus("Save failed!") end
            return
        end
        -- Load
        if pointInRect(gx, gy, TOOLBAR_W + 128, 0, 60, TOPBAR_H) then
            fileBrowserOpen = true
            fileBrowserRooms = RoomLoader.getAllRooms()
            fileBrowserScroll = 0
            return
        end
        -- Test
        if pointInRect(gx, gy, TOOLBAR_W + 192, 0, 60, TOPBAR_H) then
            if room and room.playerSpawn and room.exitDoor and #room.platforms > 0 then
                editor._testRoom = room
                local game = require("src.states.game")
                Gamestate.switch(game, { editorRoom = room, worldId = room.world or DEFAULT_WORLD_ID })
            else
                setStatus("Need platforms + spawn + door to test")
            end
            return
        end
        return
    end

    -- Left toolbar clicks
    if gx < TOOLBAR_W then
        local toolY = TOPBAR_H + 10
        for _, t in ipairs(TOOLS) do
            if pointInRect(gx, gy, 4, toolY, TOOLBAR_W - 8, 26) then
                currentTool = t.id
                selectedIndex = nil
                selectedType = nil
                return
            end
            toolY = toolY + 30
        end
        return
    end

    -- Right panel clicks
    local screenW = GAME_WIDTH
    if gx > screenW - PANEL_W then
        -- World selector button
        local panelX = screenW - PANEL_W + 8
        if pointInRect(gx, gy, panelX, TOPBAR_H + 70, PANEL_W - 16, 22) then
            -- Cycle world
            local idx = 1
            for i, opt in ipairs(worldOptions) do
                if opt.id == room.world then idx = i break end
            end
            idx = (idx % #worldOptions) + 1
            room.world = worldOptions[idx].id
            setStatus("World: " .. worldOptions[idx].name)
            return
        end

        -- Room dimension buttons
        if pointInRect(gx, gy, panelX, TOPBAR_H + 100, PANEL_W - 16, 20) then
            room.width = room.width + 200
            setStatus("Width: " .. room.width)
            return
        end
        if pointInRect(gx, gy, panelX, TOPBAR_H + 124, PANEL_W - 16, 20) then
            room.width = math.max(400, room.width - 200)
            setStatus("Width: " .. room.width)
            return
        end
        if pointInRect(gx, gy, panelX, TOPBAR_H + 150, PANEL_W - 16, 20) then
            room.height = room.height + 100
            setStatus("Height: " .. room.height)
            return
        end
        if pointInRect(gx, gy, panelX, TOPBAR_H + 174, PANEL_W - 16, 20) then
            room.height = math.max(200, room.height - 100)
            setStatus("Height: " .. room.height)
            return
        end
        return
    end

    -- Canvas area — tool actions
    local wx, wy = screenToWorld(gx, gy)

    if currentTool == "select" then
        -- Check resize handles first
        local handle = hitResizeHandle(gx, gy)
        if handle and selectedType == "platform" and selectedIndex then
            resizeHandle = handle
            local p = room.platforms[selectedIndex]
            resizeOrigRect = {x = p.x, y = p.y, w = p.w, h = p.h}
            dragging = true
            dragStartX, dragStartY = wx, wy
            return
        end

        local hitType, hitIdx = hitTest(wx, wy)
        if hitType then
            selectedType = hitType
            selectedIndex = hitIdx
            dragging = true
            dragStartX, dragStartY = wx, wy
            if hitType == "platform" then
                local p = room.platforms[hitIdx]
                dragOffX = wx - p.x
                dragOffY = wy - p.y
            elseif hitType == "enemy" then
                local s = room.spawns[hitIdx]
                dragOffX = wx - s.x
                dragOffY = wy - s.y
            elseif hitType == "spawn" then
                dragOffX = wx - room.playerSpawn.x
                dragOffY = wy - room.playerSpawn.y
            elseif hitType == "door" then
                dragOffX = wx - room.exitDoor.x
                dragOffY = wy - room.exitDoor.y
            end
        else
            selectedIndex = nil
            selectedType = nil
        end

    elseif currentTool == "platform" then
        drawingPlatform = true
        dragStartX, dragStartY = snap(wx), snap(wy)
        drawRect = {x = dragStartX, y = dragStartY, w = GRID, h = GRID}

    elseif currentTool == "spawn" then
        room.playerSpawn = {x = snap(wx), y = snap(wy)}
        setStatus("Player spawn placed")

    elseif currentTool == "door" then
        room.exitDoor = {x = snap(wx), y = snap(wy), w = 32, h = 32}
        setStatus("Exit door placed")

    elseif currentTool == "enemy" then
        local etype = ENEMY_TYPES[enemyTypeIndex]
        table.insert(room.spawns, {x = snap(wx), y = snap(wy), type = etype})
        setStatus("Enemy spawn: " .. etype)

    elseif currentTool == "eraser" then
        local hitType, hitIdx = hitTest(wx, wy)
        if hitType == "platform" then
            table.remove(room.platforms, hitIdx)
            setStatus("Platform deleted")
        elseif hitType == "enemy" then
            table.remove(room.spawns, hitIdx)
            setStatus("Enemy spawn deleted")
        end
    end
end

function editor:mousemoved(x, y, dx, dy)
    if not room then return end
    local wx, wy = screenToWorld(x, y)

    -- Middle mouse drag to pan camera
    if love.mouse.isDown(3) then
        camX = camX - dx / camZoom
        camY = camY - dy / camZoom
        return
    end

    if drawingPlatform and drawRect then
        local ex, ey = snap(wx), snap(wy)
        local rx = math.min(dragStartX, ex)
        local ry = math.min(dragStartY, ey)
        local rw = math.max(GRID, math.abs(ex - dragStartX))
        local rh = math.max(GRID, math.abs(ey - dragStartY))
        drawRect = {x = rx, y = ry, w = rw, h = rh}
        return
    end

    if dragging and currentTool == "select" then
        if resizeHandle and resizeOrigRect and selectedType == "platform" then
            -- Resize
            local p = room.platforms[selectedIndex]
            local o = resizeOrigRect
            local snx, sny = snap(wx), snap(wy)
            if resizeHandle == "br" then
                p.w = math.max(MIN_PLAT_SIZE, snx - o.x)
                p.h = math.max(MIN_PLAT_SIZE, sny - o.y)
            elseif resizeHandle == "bl" then
                local newX = math.min(snx, o.x + o.w - MIN_PLAT_SIZE)
                p.w = o.x + o.w - newX
                p.x = newX
                p.h = math.max(MIN_PLAT_SIZE, sny - o.y)
            elseif resizeHandle == "tr" then
                p.w = math.max(MIN_PLAT_SIZE, snx - o.x)
                local newY = math.min(sny, o.y + o.h - MIN_PLAT_SIZE)
                p.h = o.y + o.h - newY
                p.y = newY
            elseif resizeHandle == "tl" then
                local newX = math.min(snx, o.x + o.w - MIN_PLAT_SIZE)
                local newY = math.min(sny, o.y + o.h - MIN_PLAT_SIZE)
                p.w = o.x + o.w - newX
                p.h = o.y + o.h - newY
                p.x = newX
                p.y = newY
            end
        elseif selectedType == "platform" and selectedIndex then
            local p = room.platforms[selectedIndex]
            p.x = snap(wx - dragOffX)
            p.y = snap(wy - dragOffY)
        elseif selectedType == "enemy" and selectedIndex then
            local s = room.spawns[selectedIndex]
            s.x = snap(wx - dragOffX)
            s.y = snap(wy - dragOffY)
        elseif selectedType == "spawn" then
            room.playerSpawn.x = snap(wx - dragOffX)
            room.playerSpawn.y = snap(wy - dragOffY)
        elseif selectedType == "door" then
            room.exitDoor.x = snap(wx - dragOffX)
            room.exitDoor.y = snap(wy - dragOffY)
        end
    end
end

function editor:mousereleased(x, y, button)
    if button == 1 then
        if drawingPlatform and drawRect then
            if drawRect.w >= MIN_PLAT_SIZE and drawRect.h >= MIN_PLAT_SIZE then
                table.insert(room.platforms, {
                    x = drawRect.x, y = drawRect.y,
                    w = drawRect.w, h = drawRect.h,
                })
                setStatus("Platform placed (" .. drawRect.w .. "x" .. drawRect.h .. ")")
            end
            drawingPlatform = false
            drawRect = nil
        end
        dragging = false
        resizeHandle = nil
        resizeOrigRect = nil
    end
end

function editor:wheelmoved(x, y)
    if fileBrowserOpen then
        fileBrowserScroll = math.max(0, fileBrowserScroll - y * 28)
        return
    end
    -- Zoom
    local oldZoom = camZoom
    if y > 0 then
        camZoom = math.min(4, camZoom * 1.15)
    elseif y < 0 then
        camZoom = math.max(0.25, camZoom / 1.15)
    end
end

function editor:draw()
    local screenW, screenH = GAME_WIDTH, GAME_HEIGHT
    local theme = getTheme()

    -- Canvas background
    love.graphics.setColor(0.12, 0.1, 0.08)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)

    -- Clipping for canvas area
    love.graphics.setScissor(TOOLBAR_W, TOPBAR_H, screenW - TOOLBAR_W - PANEL_W, screenH - TOPBAR_H)

    -- Draw room bounds
    local rx, ry = worldToScreen(0, 0)
    local rw = room.width * camZoom
    local rh = room.height * camZoom
    love.graphics.setColor(0.18, 0.15, 0.12)
    love.graphics.rectangle("fill", rx, ry, rw, rh)

    -- Grid
    if showGrid then
        love.graphics.setColor(0.25, 0.22, 0.18, 0.4)
        local gridStep = GRID * camZoom
        if gridStep >= 4 then
            local startWX = math.floor(camX / GRID) * GRID
            local startWY = math.floor(camY / GRID) * GRID
            local viewW = (screenW - TOOLBAR_W - PANEL_W) / camZoom
            local viewH = (screenH - TOPBAR_H) / camZoom
            for gx = startWX, camX + viewW, GRID do
                local sx = worldToScreen(gx, 0)
                love.graphics.line(sx, TOPBAR_H, sx, screenH)
            end
            for gy = startWY, camY + viewH, GRID do
                local _, sy = worldToScreen(0, gy)
                love.graphics.line(TOOLBAR_W, sy, screenW - PANEL_W, sy)
            end
        end
    end

    -- Room boundary outline
    love.graphics.setColor(0.6, 0.45, 0.25, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", rx, ry, rw, rh)
    love.graphics.setLineWidth(1)

    -- Platforms (rendered with tile renderer via transform)
    love.graphics.push()
    love.graphics.translate(TOOLBAR_W - camX * camZoom, TOPBAR_H - camY * camZoom)
    love.graphics.scale(camZoom)
    for i, plat in ipairs(room.platforms) do
        if plat.h >= 32 then
            TileRenderer.drawWall(plat.x, plat.y, plat.w, plat.h, theme)
        else
            TileRenderer.drawPlatform(plat.x, plat.y, plat.w, plat.h, theme)
        end
        -- Selection highlight
        if selectedType == "platform" and selectedIndex == i then
            love.graphics.setColor(1, 1, 0, 0.5)
            love.graphics.setLineWidth(2 / camZoom)
            love.graphics.rectangle("line", plat.x, plat.y, plat.w, plat.h)
            love.graphics.setLineWidth(1 / camZoom)
            -- Resize handles
            local hs = HANDLE_SIZE / camZoom
            love.graphics.setColor(1, 1, 0, 0.9)
            love.graphics.rectangle("fill", plat.x - hs/2, plat.y - hs/2, hs, hs)
            love.graphics.rectangle("fill", plat.x + plat.w - hs/2, plat.y - hs/2, hs, hs)
            love.graphics.rectangle("fill", plat.x - hs/2, plat.y + plat.h - hs/2, hs, hs)
            love.graphics.rectangle("fill", plat.x + plat.w - hs/2, plat.y + plat.h - hs/2, hs, hs)
        end
    end

    -- Drawing preview
    if drawingPlatform and drawRect then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.rectangle("fill", drawRect.x, drawRect.y, drawRect.w, drawRect.h)
        love.graphics.setColor(1, 1, 0, 0.8)
        love.graphics.rectangle("line", drawRect.x, drawRect.y, drawRect.w, drawRect.h)
    end

    -- Player spawn
    if room.playerSpawn then
        love.graphics.setColor(0.2, 0.9, 0.3, 0.9)
        love.graphics.circle("fill", room.playerSpawn.x, room.playerSpawn.y, 8)
        love.graphics.setColor(1, 1, 1)
        love.graphics.setFont(fonts.small)
        love.graphics.print("P", room.playerSpawn.x - 4, room.playerSpawn.y - 6)
    end

    -- Exit door
    if room.exitDoor then
        local d = room.exitDoor
        love.graphics.setColor(0.9, 0.7, 0.2, 0.8)
        love.graphics.rectangle("fill", d.x, d.y, d.w, d.h)
        love.graphics.setColor(1, 1, 1)
        love.graphics.setFont(fonts.small)
        love.graphics.print("D", d.x + d.w/2 - 4, d.y + d.h/2 - 6)
    end

    -- Enemy spawns
    for i, spawn in ipairs(room.spawns) do
        local col = ENEMY_COLORS[spawn.type] or {0.8, 0.8, 0.8}
        love.graphics.setColor(col[1], col[2], col[3], 0.9)
        love.graphics.circle("fill", spawn.x, spawn.y, 7)
        love.graphics.setColor(1, 1, 1)
        love.graphics.setFont(fonts.small)
        local label = (spawn.type or "?"):sub(1, 1):upper()
        love.graphics.print(label, spawn.x - 3, spawn.y - 6)
        if selectedType == "enemy" and selectedIndex == i then
            love.graphics.setColor(1, 1, 0, 0.7)
            love.graphics.setLineWidth(2 / camZoom)
            love.graphics.circle("line", spawn.x, spawn.y, 10)
            love.graphics.setLineWidth(1 / camZoom)
        end
    end

    love.graphics.pop()
    love.graphics.setScissor()

    -- === UI Overlays ===

    -- Top bar
    love.graphics.setColor(0.08, 0.06, 0.05, 0.95)
    love.graphics.rectangle("fill", 0, 0, screenW, TOPBAR_H)
    love.graphics.setFont(fonts.body)
    local topBtns = { "New", "Save", "Load", "Test" }
    for i, label in ipairs(topBtns) do
        local bx = TOOLBAR_W + (i - 1) * 64
        love.graphics.setColor(0.2, 0.15, 0.1)
        love.graphics.rectangle("fill", bx + 2, 4, 56, TOPBAR_H - 8, 4, 4)
        love.graphics.setColor(0.85, 0.65, 0.35)
        love.graphics.rectangle("line", bx + 2, 4, 56, TOPBAR_H - 8, 4, 4)
        love.graphics.setColor(1, 0.95, 0.82)
        love.graphics.printf(label, bx + 2, 8, 56, "center")
    end

    -- Room ID in top bar
    love.graphics.setColor(0.7, 0.65, 0.55)
    love.graphics.print("ID: " .. (room.id or "?"), TOOLBAR_W + 280, 8)

    -- Status message
    if statusTimer > 0 then
        love.graphics.setColor(1, 0.9, 0.5, math.min(1, statusTimer))
        love.graphics.print(statusMsg, TOOLBAR_W + 450, 8)
    end

    -- Left toolbar
    love.graphics.setColor(0.1, 0.08, 0.06, 0.95)
    love.graphics.rectangle("fill", 0, 0, TOOLBAR_W, screenH)
    love.graphics.setFont(fonts.body)
    love.graphics.setColor(1, 0.85, 0.3)
    love.graphics.print("Tools", 8, TOPBAR_H + 2)

    local toolY = TOPBAR_H + 20
    for _, t in ipairs(TOOLS) do
        local selected = (currentTool == t.id)
        if selected then
            love.graphics.setColor(0.25, 0.18, 0.1)
        else
            love.graphics.setColor(0.15, 0.12, 0.08)
        end
        love.graphics.rectangle("fill", 4, toolY, TOOLBAR_W - 8, 24, 3, 3)
        if selected then
            love.graphics.setColor(0.85, 0.65, 0.35)
            love.graphics.rectangle("line", 4, toolY, TOOLBAR_W - 8, 24, 3, 3)
        end
        love.graphics.setColor(selected and {1, 0.95, 0.82} or {0.6, 0.55, 0.48})
        love.graphics.setFont(fonts.small)
        love.graphics.print(t.label, 10, toolY + 5)
        toolY = toolY + 28
    end

    -- Enemy type indicator
    if currentTool == "enemy" then
        toolY = toolY + 8
        love.graphics.setColor(0.7, 0.65, 0.55)
        love.graphics.setFont(fonts.small)
        love.graphics.print("Type (1/2/3):", 8, toolY)
        toolY = toolY + 16
        for i, etype in ipairs(ENEMY_TYPES) do
            local col = ENEMY_COLORS[etype]
            if i == enemyTypeIndex then
                love.graphics.setColor(col[1], col[2], col[3])
                love.graphics.print("> " .. etype, 10, toolY)
            else
                love.graphics.setColor(col[1] * 0.5, col[2] * 0.5, col[3] * 0.5)
                love.graphics.print("  " .. etype, 10, toolY)
            end
            toolY = toolY + 14
        end
    end

    -- Grid toggle hint
    toolY = screenH - 40
    love.graphics.setColor(0.5, 0.45, 0.4)
    love.graphics.setFont(fonts.small)
    love.graphics.print("G: grid " .. (showGrid and "ON" or "OFF"), 8, toolY)
    love.graphics.print("MMB: pan  Scroll: zoom", 8, toolY + 14)

    -- Right panel
    local panelX = screenW - PANEL_W
    love.graphics.setColor(0.1, 0.08, 0.06, 0.95)
    love.graphics.rectangle("fill", panelX, TOPBAR_H, PANEL_W, screenH - TOPBAR_H)
    love.graphics.setFont(fonts.body)
    love.graphics.setColor(1, 0.85, 0.3)
    love.graphics.print("Properties", panelX + 8, TOPBAR_H + 4)

    love.graphics.setFont(fonts.small)
    local py = TOPBAR_H + 28

    -- Room info
    love.graphics.setColor(0.7, 0.65, 0.55)
    love.graphics.print("Room: " .. (room.id or "?"), panelX + 8, py)
    py = py + 16
    love.graphics.print("World:", panelX + 8, py)
    py = py + 16

    -- World button
    local worldDef = Worlds.get(room.world or DEFAULT_WORLD_ID)
    love.graphics.setColor(0.2, 0.15, 0.1)
    love.graphics.rectangle("fill", panelX + 8, py, PANEL_W - 16, 20, 3, 3)
    love.graphics.setColor(0.85, 0.65, 0.35)
    love.graphics.rectangle("line", panelX + 8, py, PANEL_W - 16, 20, 3, 3)
    love.graphics.setColor(1, 0.95, 0.82)
    love.graphics.print(worldDef and worldDef.name or room.world, panelX + 12, py + 3)
    py = py + 28

    -- Dimensions
    love.graphics.setColor(0.7, 0.65, 0.55)
    love.graphics.print("Width: " .. room.width, panelX + 8, py)
    love.graphics.setColor(0.2, 0.15, 0.1)
    love.graphics.rectangle("fill", panelX + 8, py + 14, PANEL_W - 16, 18, 3, 3)
    love.graphics.setColor(0.6, 0.8, 0.5)
    love.graphics.print("[+200]", panelX + 12, py + 15)
    py = py + 36
    love.graphics.setColor(0.2, 0.15, 0.1)
    love.graphics.rectangle("fill", panelX + 8, py, PANEL_W - 16, 18, 3, 3)
    love.graphics.setColor(0.8, 0.5, 0.5)
    love.graphics.print("[-200]", panelX + 12, py + 1)
    py = py + 26

    love.graphics.setColor(0.7, 0.65, 0.55)
    love.graphics.print("Height: " .. room.height, panelX + 8, py)
    love.graphics.setColor(0.2, 0.15, 0.1)
    love.graphics.rectangle("fill", panelX + 8, py + 14, PANEL_W - 16, 18, 3, 3)
    love.graphics.setColor(0.6, 0.8, 0.5)
    love.graphics.print("[+100]", panelX + 12, py + 15)
    py = py + 36
    love.graphics.setColor(0.2, 0.15, 0.1)
    love.graphics.rectangle("fill", panelX + 8, py, PANEL_W - 16, 18, 3, 3)
    love.graphics.setColor(0.8, 0.5, 0.5)
    love.graphics.print("[-100]", panelX + 12, py + 1)
    py = py + 30

    -- Stats
    love.graphics.setColor(0.7, 0.65, 0.55)
    love.graphics.print("Platforms: " .. #room.platforms, panelX + 8, py)
    py = py + 14
    love.graphics.print("Enemies: " .. #room.spawns, panelX + 8, py)
    py = py + 14
    love.graphics.print("Has spawn: " .. (room.playerSpawn and "yes" or "no"), panelX + 8, py)
    py = py + 14
    love.graphics.print("Has door: " .. (room.exitDoor and "yes" or "no"), panelX + 8, py)
    py = py + 20

    -- Selected element info
    if selectedType == "platform" and selectedIndex then
        local p = room.platforms[selectedIndex]
        if p then
            love.graphics.setColor(1, 0.85, 0.3)
            love.graphics.print("Selected Platform", panelX + 8, py)
            py = py + 16
            love.graphics.setColor(0.8, 0.75, 0.65)
            love.graphics.print(string.format("x:%d y:%d", p.x, p.y), panelX + 8, py)
            py = py + 14
            love.graphics.print(string.format("w:%d h:%d", p.w, p.h), panelX + 8, py)
            py = py + 14
            love.graphics.print("Type: " .. (p.h <= 24 and "one-way" or "solid"), panelX + 8, py)
        end
    elseif selectedType == "enemy" and selectedIndex then
        local s = room.spawns[selectedIndex]
        if s then
            love.graphics.setColor(1, 0.85, 0.3)
            love.graphics.print("Selected Enemy", panelX + 8, py)
            py = py + 16
            love.graphics.setColor(0.8, 0.75, 0.65)
            love.graphics.print("Type: " .. (s.type or "?"), panelX + 8, py)
            py = py + 14
            love.graphics.print(string.format("x:%d y:%d", s.x, s.y), panelX + 8, py)
        end
    end

    -- File browser overlay
    if fileBrowserOpen then
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)

        local bw, bh = 400, 300
        local bx = (screenW - bw) / 2
        local by = (screenH - bh) / 2

        love.graphics.setColor(0.12, 0.1, 0.08)
        love.graphics.rectangle("fill", bx, by, bw, bh, 6, 6)
        love.graphics.setColor(0.85, 0.65, 0.35)
        love.graphics.rectangle("line", bx, by, bw, bh, 6, 6)

        love.graphics.setFont(fonts.body)
        love.graphics.setColor(1, 0.85, 0.3)
        love.graphics.print("Load Room", bx + 12, by + 8)

        -- Close button
        love.graphics.setColor(0.8, 0.4, 0.3)
        love.graphics.print("X", bx + bw - 22, by + 6)

        -- Room list
        love.graphics.setScissor(bx, by + 30, bw, bh - 30)
        love.graphics.setFont(fonts.small)
        local entryH = 28
        local listY = by + 32
        for i, r in ipairs(fileBrowserRooms) do
            local ey = listY + (i - 1) * entryH - fileBrowserScroll
            if ey + entryH >= by + 30 and ey <= by + bh then
                love.graphics.setColor(0.18, 0.15, 0.12)
                love.graphics.rectangle("fill", bx + 8, ey, bw - 16, entryH - 2, 3, 3)
                love.graphics.setColor(0.85, 0.78, 0.65)
                local src = r._source == "user" and " (user)" or ""
                love.graphics.print(
                    string.format("[%s] %s%s", r.world or "?", r.id or "unnamed", src),
                    bx + 14, ey + 6
                )
            end
        end
        love.graphics.setScissor()
    end

    -- Keyboard shortcuts hint
    love.graphics.setColor(0.4, 0.38, 0.35, 0.8)
    love.graphics.setFont(fonts.small)
    love.graphics.print("Ctrl+S: Save  Ctrl+L: Load  Ctrl+N: New  Ctrl+T: Test  Esc: Menu",
        TOOLBAR_W + 4, screenH - 16)

    love.graphics.setColor(1, 1, 1)
end

--- Called when returning from test play
function editor:resume()
    Cursor.setDefault()
    setStatus("Returned from test play")
end

--- Get the room being tested (for game state to use)
function editor.getTestRoom()
    return editor._testRoom
end

return editor
