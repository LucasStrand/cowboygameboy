local Gamestate = require("lib.hump.gamestate")
local Camera = require("lib.hump.camera")
local bump = require("lib.bump")
local Font = require("src.ui.font")
local Cursor = require("src.ui.cursor")
local Player = require("src.entities.player")
local RoomManager = require("src.systems.room_manager")
local MenuRoomDraw = require("src.ui.menu_room_draw")
local TextLayout = require("src.ui.text_layout")
local Settings = require("src.systems.settings")
local Keybinds = require("src.systems.keybinds")
local SettingsPanel = require("src.ui.settings_panel")
local BootIntroData = require("src.data.boot_intro")
local MenuBgm = require("src.systems.menu_bgm")

local menu = {}

local CAM_ZOOM = 2

local world
local camera
local player
local roomManager
local currentRoom
local bgImage
--- Cached from BootIntroData.titleBackgroundImage (same art as boot title); nil = use room preview
local menuBgImg = nil
local menuBgLoadAttempted = false
local fonts = {}
local view = "main" -- "main" | "settings"
local selectedIndex = 1
local hoverIndex = nil
local settingsTab = "video"
local settingsHover = nil
local settingsBindCapture = nil
--- While LMB is held on a volume slider (enables drag)
local settingsSliderDragKey = nil

--- 1 = full black overlay; lerps to 0 after boot handoff
local introFadeAlpha = 0

local function beginGameWithIntroCountdown()
    MenuBgm.stop()
    local game = require("src.states.game")
    Gamestate.switch(game, { introCountdown = true })
end

local function beginDevArena()
    MenuBgm.stop()
    local game = require("src.states.game")
    Gamestate.switch(game, { devArena = true, introCountdown = false })
end

local function menuButtons()
    local list = {
        { id = "start", label = "Start game" },
    }
    if DEV_TOOLS_ENABLED or DEBUG then
        list[#list + 1] = { id = "dev_arena", label = "Dev arena" }
    end
    list[#list + 1] = { id = "settings", label = "Settings" }
    list[#list + 1] = { id = "quit", label = "Quit" }
    return list
end

local function clearPreview()
    if world then
        while world:countItems() > 0 do
            local items, n = world:getItems()
            if n < 1 then break end
            world:remove(items[1])
        end
    end
    world = nil
    camera = nil
    player = nil
    roomManager = nil
    currentRoom = nil
end

function menu:enter(_, opts)
    if opts and opts.fromIntro then
        introFadeAlpha = 1
    else
        introFadeAlpha = 0
        MenuBgm.play(BootIntroData.menuMusicPath)
    end

    view = "main"
    selectedIndex = 1
    hoverIndex = nil
    settingsTab = "video"
    settingsHover = nil
    settingsBindCapture = nil
    fonts.title = Font.new(48)
    fonts.subtitle = Font.new(16)
    fonts.button = Font.new(22)
    fonts.hint = Font.new(14)
    fonts.default = Font.new(12)
    fonts.settingsBody = Font.new(16)
    Cursor.setDefault()

    clearPreview()

    if not menuBgLoadAttempted then
        menuBgLoadAttempted = true
        local path = BootIntroData.titleBackgroundImage
        if path and path ~= "" then
            local ok, img = pcall(love.graphics.newImage, path)
            if ok and img then
                img:setFilter("nearest", "nearest")
                menuBgImg = img
            end
        end
    end

    if menuBgImg then
        -- Static backdrop (matches boot); no room preview — settings still need a Player instance.
        player = Player.new(50, 300)
        world = nil
        camera = nil
        roomManager = nil
        currentRoom = nil
    else
        world = bump.newWorld(32)
        camera = Camera(400, 200)
        camera.scale = CAM_ZOOM
        player = Player.new(50, 300)
        world:add(player, player.x, player.y, player.w, player.h)
        player.isPlayer = true
        player.keyboardAimMode = true

        roomManager = RoomManager.new()
        roomManager:generateSequence()
        local roomData = roomManager:nextRoom()
        if roomData then
            currentRoom = roomManager:loadRoom(roomData, world, player, { skipEnemies = true })
        end

        if not bgImage then
            bgImage = love.graphics.newImage("assets/backgrounds/forest.png")
            bgImage:setWrap("repeat", "clampzero")
        end
    end
end

function menu:leave()
    clearPreview()
end

local function updateCamera()
    if not currentRoom or not camera or not player then return end
    local viewW = GAME_WIDTH / CAM_ZOOM
    local viewH = GAME_HEIGHT / CAM_ZOOM
    local px = player.x + player.w / 2
    local py = player.y + player.h / 2
    local cx = math.max(viewW / 2, math.min(currentRoom.width - viewW / 2, px))
    local cy = math.max(viewH / 2, math.min(currentRoom.height - viewH / 2, py))
    camera:lookAt(cx, cy)
end

function menu:update(dt)
    MenuBgm.updateVolume()
    if introFadeAlpha > 0 then
        introFadeAlpha = math.max(
            0,
            introFadeAlpha - dt / math.max(0.05, BootIntroData.menuFadeInDuration)
        )
    end
    if world and player and currentRoom then
        player:update(dt, world, {})
        updateCamera()
    end
end

local function buttonLayout()
    local screenW = GAME_WIDTH
    local screenH = GAME_HEIGHT
    local bw, bh = 340, 52
    local gap = 10
    local list = menuButtons()
    local totalH = #list * bh + (#list - 1) * gap
    local startY = screenH * 0.48 - totalH * 0.5
    local rects = {}
    for i, b in ipairs(list) do
        local y = startY + (i - 1) * (bh + gap)
        rects[i] = {
            id = b.id,
            label = b.label,
            x = (screenW - bw) * 0.5,
            y = y,
            w = bw,
            h = bh,
        }
    end
    return rects
end

local function hitRect(mx, my, r)
    return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

function menu:mousemoved(x, y, dx, dy)
    local gx, gy = windowToGame(x, y)
    if view == "main" then
        hoverIndex = nil
        for i, r in ipairs(buttonLayout()) do
            if hitRect(gx, gy, r) then
                hoverIndex = i
                selectedIndex = i
                break
            end
        end
    elseif view == "settings" then
        if settingsSliderDragKey and fonts.button then
            local v = SettingsPanel.sliderValueFromPointerX(
                GAME_WIDTH, GAME_HEIGHT, settingsTab, fonts.button, settingsSliderDragKey, gx
            )
            if v then
                Settings.setVolumeKey(settingsSliderDragKey, v)
                Settings.save()
                Settings.apply()
            end
            return
        end
        local h = SettingsPanel.hitTest(GAME_WIDTH, GAME_HEIGHT, settingsTab, gx, gy, fonts.button)
        if h then
            if h.kind == "tab" then
                settingsHover = { kind = "tab", id = h.id }
            elseif h.kind == "back" then
                settingsHover = { kind = "back" }
            elseif h.kind == "row" then
                settingsHover = { kind = "row", index = h.index }
            elseif h.kind == "slider" then
                settingsHover = { kind = "slider", index = h.index, key = h.key }
            end
        else
            settingsHover = nil
        end
    end
end

function menu:mousepressed(x, y, button)
    if button ~= 1 then return end
    local gx, gy = windowToGame(x, y)
    if view == "main" then
        for i, r in ipairs(buttonLayout()) do
            if hitRect(gx, gy, r) then
                if r.id == "start" then
                    beginGameWithIntroCountdown()
                elseif r.id == "dev_arena" then
                    beginDevArena()
                elseif r.id == "settings" then
                    view = "settings"
                elseif r.id == "quit" then
                    love.event.quit()
                end
                return
            end
        end
    elseif view == "settings" then
        local h = SettingsPanel.hitTest(GAME_WIDTH, GAME_HEIGHT, settingsTab, gx, gy, fonts.button)
        local r = SettingsPanel.applyHit(h, player)
        if h and h.kind == "slider" then
            settingsSliderDragKey = h.key
        end
        if r then
            if r.setTab then settingsTab = r.setTab end
            if r.goBack then
                view = "main"
                settingsBindCapture = nil
                settingsSliderDragKey = nil
            end
            if r.startBind then settingsBindCapture = r.startBind end
        end
    end
end

function menu:mousereleased(x, y, button)
    if button == 1 then
        settingsSliderDragKey = nil
    end
end

function menu:keypressed(key)
    if view == "settings" then
        if settingsBindCapture then
            if key == "escape" then
                settingsBindCapture = nil
            else
                local normalized = Keybinds.normalizeCapturedKey(key)
                Settings.setKeybind(settingsBindCapture, normalized)
                Settings.save()
                settingsBindCapture = nil
            end
            return
        end
        if key == "escape" or key == "backspace" then
            view = "main"
            settingsBindCapture = nil
            settingsSliderDragKey = nil
        elseif key == "[" then
            settingsTab = SettingsPanel.cycleTab(settingsTab, -1)
        elseif key == "]" then
            settingsTab = SettingsPanel.cycleTab(settingsTab, 1)
        end
        return
    end

    local list = menuButtons()
    if key == "up" or key == "w" then
        selectedIndex = selectedIndex - 1
        if selectedIndex < 1 then selectedIndex = #list end
    elseif key == "down" or key == "s" then
        selectedIndex = selectedIndex + 1
        if selectedIndex > #list then selectedIndex = 1 end
    elseif key == "return" or key == "space" or key == "kpenter" then
        local id = list[selectedIndex].id
        if id == "start" then
            beginGameWithIntroCountdown()
        elseif id == "dev_arena" then
            beginDevArena()
        elseif id == "settings" then
            view = "settings"
        elseif id == "quit" then
            love.event.quit()
        end
    end
end

function menu:draw()
    local screenW = GAME_WIDTH
    local screenH = GAME_HEIGHT

    -- Same full-screen art as boot title when configured; otherwise first-room preview.
    if menuBgImg then
        local iw, ih = menuBgImg:getDimensions()
        local scale = math.max(screenW / iw, screenH / ih)
        local sw, sh = iw * scale, ih * scale
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(menuBgImg, (screenW - sw) * 0.5, (screenH - sh) * 0.5, 0, scale, scale)
    elseif camera and currentRoom and player then
        camera:attach(0, 0, GAME_WIDTH, GAME_HEIGHT)
        MenuRoomDraw.draw(camera, currentRoom, bgImage, false, false)
        player:draw()
        camera:detach()
    else
        love.graphics.setColor(0.08, 0.05, 0.03)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)
    end

    love.graphics.setColor(0.02, 0.02, 0.04, 0.52)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)

    if view == "main" then
        love.graphics.setColor(1, 0.85, 0.2)
        love.graphics.setFont(fonts.title)
        love.graphics.printf("SIX CHAMBERS", 0, screenH * 0.14, screenW, "center")

        love.graphics.setColor(0.72, 0.55, 0.38)
        love.graphics.setFont(fonts.subtitle)
        love.graphics.printf("A cowboy roguelike", 0, screenH * 0.14 + 58, screenW, "center")

        local rects = buttonLayout()
        for i, r in ipairs(rects) do
            local hover = (hoverIndex == i) or (hoverIndex == nil and selectedIndex == i)
            if hover then
                love.graphics.setColor(0.22, 0.14, 0.08, 0.92)
            else
                love.graphics.setColor(0.12, 0.08, 0.06, 0.75)
            end
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6, 6)
            love.graphics.setColor(0.85, 0.65, 0.35, hover and 1 or 0.65)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 6, 6)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(1, 0.95, 0.82)
            love.graphics.setFont(fonts.button)
            love.graphics.printf(
                r.label,
                r.x,
                TextLayout.printfYCenteredInRect(fonts.button, r.y, r.h),
                r.w,
                "center"
            )
        end

        love.graphics.setColor(0.45, 0.45, 0.48)
        love.graphics.setFont(fonts.hint)
        love.graphics.printf("Arrows / mouse  ·  Enter to select  ·  Quit to exit", 0, screenH * 0.88, screenW, "center")
    elseif view == "settings" then
        SettingsPanel.draw(screenW, screenH, settingsTab, {
            title = fonts.title,
            tab = fonts.button,
            row = fonts.settingsBody,
            hint = fonts.hint,
        }, settingsHover, settingsBindCapture)
    end

    if introFadeAlpha > 0 then
        love.graphics.setColor(0, 0, 0, introFadeAlpha)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(fonts.default)
end

return menu
