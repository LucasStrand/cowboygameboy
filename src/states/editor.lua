-- World Editor — tune world properties, map generation, and enemy rosters.
-- Accessible from the main menu. Changes save to the LÖVE save directory
-- and are loaded automatically on next launch.

local Gamestate = require("lib.hump.gamestate")
local Font = require("src.ui.font")
local Worlds = require("src.data.worlds")
local EnemyData = require("src.data.enemies")
local ChunkLoader = require("src.systems.chunk_loader")
local ChunkAssembler = require("src.systems.chunk_assembler")

local editor = {}

-- ─── Constants ─────────────────────────────────────────────────────
local NAV_H = 56
local ROW_H = 34
local SECTION_PAD = 10
local FORM_MAX_W = 660
local LABEL_W = 180
local SLIDER_H = 14
local SLIDER_W = 220
local BTN_H = 34
local BTN_W = 110
local BOTTOM_BAR_H = 54

local BG = {0.10, 0.10, 0.12}
local SECTION_BG = {0.16, 0.16, 0.20}
local TRACK = {0.22, 0.22, 0.28}
local DIM = {0.55, 0.55, 0.6}
local LIGHT = {0.85, 0.85, 0.9}
local WHITE = {1, 1, 1}
local ACCENT = {0.4, 0.7, 1.0}

local WORLD_ACCENTS = {
    desert = {0.92, 0.68, 0.28},
    forest = {0.28, 0.78, 0.38},
    train  = {0.65, 0.38, 0.22},
}

local ENEMY_ORDER = {"bandit", "gunslinger", "buzzard", "nightborne", "necromancer"}

-- ─── State ─────────────────────────────────────────────────────────
local currentIdx = 1
local scrollY = 0
local maxScroll = 0
local rows = {}
local fonts = {}
local dragging = nil   -- {row=row} when slider is being dragged
local dirty = false
local statusMsg = ""
local statusTimer = 0
local returnFromPreview = false
local defaults = {}   -- deep copy of world definitions taken on first enter

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = deepCopy(v) end
    return copy
end

-- ─── Helpers ───────────────────────────────────────────────────────
local function worldId()   return Worlds.order[currentIdx] end
local function world()     return Worlds.definitions[worldId()] end
local function accent()    return WORLD_ACCENTS[worldId()] or ACCENT end

local function formBounds()
    local w = love.graphics.getWidth()
    local fw = math.min(w - 40, FORM_MAX_W)
    return math.floor((w - fw) / 2), fw
end

local function setStatus(msg)
    statusMsg = msg
    statusTimer = 3
end

-- ─── Layout ────────────────────────────────────────────────────────
local function buildRows()
    rows = {}
    local wd = world()
    if not wd then return end
    local y = 12

    local function section(label)
        rows[#rows+1] = {type="section", y=y, h=ROW_H+SECTION_PAD, label=label}
        y = y + ROW_H + SECTION_PAD
    end

    local function label(lbl, val)
        rows[#rows+1] = {type="label", y=y, h=ROW_H, label=lbl, value=val}
        y = y + ROW_H
    end

    local function slider(lbl, lo, hi, step, get, set, fmt)
        rows[#rows+1] = {
            type="slider", y=y, h=ROW_H, label=lbl,
            min=lo, max=hi, step=step, get=get, set=set, fmt=fmt or "%.2f",
        }
        y = y + ROW_H
    end

    local function stepper(lbl, lo, hi, step, get, set)
        rows[#rows+1] = {
            type="stepper", y=y, h=ROW_H, label=lbl,
            min=lo, max=hi, step=step, get=get, set=set,
        }
        y = y + ROW_H
    end

    local function enemy(typeId)
        local data = EnemyData.types[typeId]
        if not data then return end
        rows[#rows+1] = {
            type="enemy", y=y, h=ROW_H, label=data.name,
            typeId=typeId, color=data.color,
        }
        y = y + ROW_H
    end

    -- ── Visual ──
    section("VISUAL")
    label("Background", wd.background or "(none)")
    label("Tile Atlas", wd.tileAtlas or "(none)")
    slider("Parallax Speed", 0, 1, 0.05,
        function() return wd.parallaxSpeed or 0.3 end,
        function(v) wd.parallaxSpeed = v; dirty = true end)
    slider("Sky Red", 0, 1, 0.01,
        function() return wd.skyColor[1] end,
        function(v) wd.skyColor[1] = v; dirty = true end)
    slider("Sky Green", 0, 1, 0.01,
        function() return wd.skyColor[2] end,
        function(v) wd.skyColor[2] = v; dirty = true end)
    slider("Sky Blue", 0, 1, 0.01,
        function() return wd.skyColor[3] end,
        function(v) wd.skyColor[3] = v; dirty = true end)

    -- ── Map Generation ──
    local cg = wd.chunkGen
    if cg then
        section("MAP GENERATION")
        stepper("Grid Columns", 2, 20, 1,
            function() return cg.cols end,
            function(v) cg.cols = v; dirty = true end)
        stepper("Grid Rows", 1, 8, 1,
            function() return cg.rows end,
            function(v) cg.rows = v; dirty = true end)
        slider("Horizontal Bias", 1, 10, 1,
            function() return cg.rightWeight end,
            function(v) cg.rightWeight = v; dirty = true end, "%.0f")
        slider("Vertical Bias", 1, 10, 1,
            function() return cg.verticalWeight end,
            function(v) cg.verticalWeight = v; dirty = true end, "%.0f")
        slider("Branch Chance", 0, 1, 0.05,
            function() return cg.branchChance end,
            function(v) cg.branchChance = v; dirty = true end)
    end
    stepper("Rooms / Checkpoint", 1, 15, 1,
        function() return wd.roomsPerCheckpoint or 5 end,
        function(v) wd.roomsPerCheckpoint = v; dirty = true end)

    -- ── Enemies ──
    section("ENEMIES")
    for _, tid in ipairs(ENEMY_ORDER) do
        enemy(tid)
    end

    y = y + ROW_H  -- bottom padding
    maxScroll = math.max(0, y + NAV_H + BOTTOM_BAR_H - love.graphics.getHeight())
end

-- ─── Widget Drawing ────────────────────────────────────────────────
local function drawSection(row, fx, fw)
    local sy = row.y - scrollY + NAV_H
    love.graphics.setColor(SECTION_BG)
    love.graphics.rectangle("fill", fx - 4, sy, fw + 8, row.h - SECTION_PAD + 4, 4, 4)
    love.graphics.setColor(accent())
    love.graphics.setFont(fonts.med)
    love.graphics.print(row.label, fx + 8, sy + 4)
end

local function drawLabel(row, fx, fw)
    local sy = row.y - scrollY + NAV_H
    love.graphics.setFont(fonts.sm)
    love.graphics.setColor(DIM)
    love.graphics.print(row.label, fx + 8, sy + 8)
    love.graphics.setColor(LIGHT)
    local val = row.value or ""
    if #val > 42 then val = "..." .. val:sub(-39) end
    love.graphics.print(val, fx + LABEL_W, sy + 8)
end

local function sliderW(fw)
    return math.min(SLIDER_W, fw - LABEL_W - 80)
end

local function drawSlider(row, fx, fw)
    local sy = row.y - scrollY + NAV_H
    local val = row.get()
    local t = (val - row.min) / math.max(0.001, row.max - row.min)
    local sx = fx + LABEL_W
    local sw = sliderW(fw)
    local ty = sy + math.floor((ROW_H - SLIDER_H) / 2)

    love.graphics.setFont(fonts.sm)
    love.graphics.setColor(DIM)
    love.graphics.print(row.label, fx + 8, sy + 8)

    love.graphics.setColor(TRACK)
    love.graphics.rectangle("fill", sx, ty, sw, SLIDER_H, 4, 4)
    love.graphics.setColor(accent())
    love.graphics.rectangle("fill", sx, ty, math.max(4, t * sw), SLIDER_H, 4, 4)

    love.graphics.setColor(WHITE)
    love.graphics.print(string.format(row.fmt, val), sx + sw + 10, sy + 8)
end

local function drawStepper(row, fx, fw)
    local sy = row.y - scrollY + NAV_H
    local val = row.get()
    local sx = fx + LABEL_W
    local a = accent()

    love.graphics.setFont(fonts.sm)
    love.graphics.setColor(DIM)
    love.graphics.print(row.label, fx + 8, sy + 8)

    -- < button
    love.graphics.setColor(a)
    love.graphics.rectangle("fill", sx, sy + 6, 22, 20, 3, 3)
    love.graphics.setColor(WHITE)
    love.graphics.print("<", sx + 6, sy + 7)

    -- value
    love.graphics.setColor(WHITE)
    local vs = tostring(val)
    love.graphics.print(vs, sx + 30, sy + 8)

    -- > button
    local rx = sx + 30 + fonts.sm:getWidth(vs) + 6
    love.graphics.setColor(a)
    love.graphics.rectangle("fill", rx, sy + 6, 22, 20, 3, 3)
    love.graphics.setColor(WHITE)
    love.graphics.print(">", rx + 6, sy + 7)
end

local function drawEnemy(row, fx, fw)
    local sy = row.y - scrollY + NAV_H
    local roster = world().enemyRoster or {}
    local weight = roster[row.typeId] or 0
    local on = weight > 0
    local sx = fx + LABEL_W
    local sw = sliderW(fw)
    local c = row.color or DIM

    -- checkbox
    love.graphics.setColor(c)
    if on then
        love.graphics.rectangle("fill", fx + 8, sy + 9, 14, 14, 2, 2)
    else
        love.graphics.rectangle("line", fx + 8, sy + 9, 14, 14, 2, 2)
    end

    -- name
    love.graphics.setFont(fonts.sm)
    love.graphics.setColor(on and LIGHT or DIM)
    love.graphics.print(row.label, fx + 30, sy + 8)

    if on then
        -- weight slider
        local t = math.min(1, weight / 50)
        local ty = sy + math.floor((ROW_H - SLIDER_H) / 2)
        love.graphics.setColor(TRACK)
        love.graphics.rectangle("fill", sx, ty, sw, SLIDER_H, 4, 4)
        love.graphics.setColor(c)
        love.graphics.rectangle("fill", sx, ty, math.max(4, t * sw), SLIDER_H, 4, 4)
        love.graphics.setColor(WHITE)
        love.graphics.print(tostring(weight), sx + sw + 10, sy + 8)
    else
        love.graphics.setColor(DIM)
        love.graphics.print("(click to enable)", sx, sy + 8)
    end
end

-- ─── Nav Bar ───────────────────────────────────────────────────────
local function drawNav()
    local w = love.graphics.getWidth()
    local a = accent()

    love.graphics.setColor(a[1]*0.3, a[2]*0.3, a[3]*0.3)
    love.graphics.rectangle("fill", 0, 0, w, NAV_H)

    -- title
    local wd = world()
    local title = string.format("WORLD %d:  %s", currentIdx, (wd.name or worldId()):upper())
    love.graphics.setFont(fonts.big)
    love.graphics.setColor(WHITE)
    local tw = fonts.big:getWidth(title)
    love.graphics.print(title, math.floor((w - tw) / 2), 6)

    -- arrows
    love.graphics.setFont(fonts.big)
    love.graphics.setColor(a)
    if currentIdx > 1 then
        love.graphics.print("<", 20, 6)
    end
    if currentIdx < #Worlds.order then
        love.graphics.print(">", w - 36, 6)
    end

    -- subtitle
    love.graphics.setFont(fonts.sm)
    love.graphics.setColor(DIM)
    local nChunks = #ChunkLoader.getPool(worldId())
    local sub = string.format("%d chunks  |  %s", nChunks,
        dirty and "UNSAVED CHANGES" or "saved")
    local sw = fonts.sm:getWidth(sub)
    love.graphics.print(sub, math.floor((w - sw) / 2), 34)
end

-- ─── Bottom Buttons ────────────────────────────────────────────────
local BUTTONS = {
    {label = "Preview (F5)"},
    {label = "Save (Ctrl+S)"},
    {label = "Reset"},
    {label = "Menu (Esc)"},
}

local function buttonBounds()
    local w = love.graphics.getWidth()
    local totalW = #BUTTONS * BTN_W + (#BUTTONS - 1) * 16
    local bx = math.floor((w - totalW) / 2)
    local by = love.graphics.getHeight() - BTN_H - 12
    return bx, by, totalW
end

local function drawButtons()
    local w = love.graphics.getWidth()
    local bx, by = buttonBounds()
    local a = accent()

    -- bar bg
    love.graphics.setColor(0.08, 0.08, 0.10, 0.92)
    love.graphics.rectangle("fill", 0, by - 10, w, BOTTOM_BAR_H + 10)

    local colors = {
        a,
        dirty and {0.9, 0.8, 0.2} or {0.4, 0.4, 0.45},
        {0.7, 0.45, 0.2},
        {0.6, 0.3, 0.3},
    }

    love.graphics.setFont(fonts.med)
    for i, btn in ipairs(BUTTONS) do
        local x = bx + (i - 1) * (BTN_W + 16)
        local c = colors[i]
        love.graphics.setColor(c[1]*0.25, c[2]*0.25, c[3]*0.25)
        love.graphics.rectangle("fill", x, by, BTN_W, BTN_H, 6, 6)
        love.graphics.setColor(c)
        love.graphics.rectangle("line", x, by, BTN_W, BTN_H, 6, 6)
        local lw = fonts.med:getWidth(btn.label)
        love.graphics.setColor(WHITE)
        love.graphics.print(btn.label, x + math.floor((BTN_W - lw)/2), by + 8)
    end
end

-- ─── Sky Color Preview ─────────────────────────────────────────────
local function drawSkyPreview(fx, fw)
    local wd = world()
    if not wd or not wd.skyColor then return end
    -- Find the Sky Red row to position the preview next to it
    for _, row in ipairs(rows) do
        if row.type == "slider" and row.label == "Sky Red" then
            local sy = row.y - scrollY + NAV_H
            local sw = sliderW(fw)
            local px = fx + LABEL_W + sw + 60
            love.graphics.setColor(wd.skyColor)
            love.graphics.rectangle("fill", px, sy, 40, ROW_H * 3 - 4, 4, 4)
            love.graphics.setColor(DIM)
            love.graphics.rectangle("line", px, sy, 40, ROW_H * 3 - 4, 4, 4)
            break
        end
    end
end

-- ─── Gamestate Callbacks ───────────────────────────────────────────
function editor:enter()
    if returnFromPreview then
        returnFromPreview = false
        buildRows()  -- refresh in case window resized
        return
    end
    fonts.big = Font.new(20)
    fonts.med = Font.new(14)
    fonts.sm  = Font.new(11)
    currentIdx = 1
    scrollY = 0
    dirty = false
    dragging = nil
    statusMsg = ""
    statusTimer = 0
    -- Snapshot defaults so Reset can always restore them
    if not next(defaults) then
        for wid, def in pairs(Worlds.definitions) do
            defaults[wid] = deepCopy(def)
        end
    end
    buildRows()
end

function editor:update(dt)
    if statusTimer > 0 then statusTimer = statusTimer - dt end

    if dragging then
        local mx = love.mouse.getX()
        local fx, fw = formBounds()
        local sx = fx + LABEL_W
        local sw = sliderW(fw)
        local row = dragging.row

        if row.type == "slider" then
            local t = math.max(0, math.min(1, (mx - sx) / sw))
            local val = row.min + t * (row.max - row.min)
            val = math.floor(val / row.step + 0.5) * row.step
            val = math.max(row.min, math.min(row.max, val))
            row.set(val)
        elseif row.type == "enemy" then
            local t = math.max(0, math.min(1, (mx - sx) / sw))
            local val = math.max(1, math.floor(t * 50 + 0.5))
            local wd = world()
            wd.enemyRoster = wd.enemyRoster or {}
            wd.enemyRoster[row.typeId] = val
            dirty = true
        end
    end
end

function editor:draw()
    love.graphics.clear(BG)
    local fx, fw = formBounds()

    -- clip content area
    local winH = love.graphics.getHeight()
    love.graphics.setScissor(0, NAV_H, love.graphics.getWidth(), winH - NAV_H - BOTTOM_BAR_H)
    for _, row in ipairs(rows) do
        local sy = row.y - scrollY + NAV_H
        if sy + row.h > NAV_H and sy < winH then
            if row.type == "section" then     drawSection(row, fx, fw)
            elseif row.type == "label" then   drawLabel(row, fx, fw)
            elseif row.type == "slider" then  drawSlider(row, fx, fw)
            elseif row.type == "stepper" then drawStepper(row, fx, fw)
            elseif row.type == "enemy" then   drawEnemy(row, fx, fw)
            end
        end
    end
    drawSkyPreview(fx, fw)
    love.graphics.setScissor()

    drawNav()
    drawButtons()

    -- status toast
    if statusTimer > 0 and statusMsg ~= "" then
        love.graphics.setFont(fonts.sm)
        local tw = fonts.sm:getWidth(statusMsg)
        local w = love.graphics.getWidth()
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", (w - tw)/2 - 12, NAV_H + 6, tw + 24, 24, 4, 4)
        love.graphics.setColor(1, 1, 0.7)
        love.graphics.print(statusMsg, (w - tw)/2, NAV_H + 10)
    end
end

-- ─── Mouse ─────────────────────────────────────────────────────────
function editor:mousepressed(mx, my, button)
    if button ~= 1 then return end
    local w = love.graphics.getWidth()
    local fx, fw = formBounds()

    -- nav arrows
    if my < NAV_H then
        if mx < 50 and currentIdx > 1 then
            currentIdx = currentIdx - 1; scrollY = 0; buildRows()
        elseif mx > w - 50 and currentIdx < #Worlds.order then
            currentIdx = currentIdx + 1; scrollY = 0; buildRows()
        end
        return
    end

    -- bottom buttons
    local bx, by = buttonBounds()
    if my >= by and my <= by + BTN_H then
        for i = 0, #BUTTONS - 1 do
            local x = bx + i * (BTN_W + 16)
            if mx >= x and mx <= x + BTN_W then
                if i == 0 then self:doPreview()
                elseif i == 1 then self:doSave()
                elseif i == 2 then self:doReset()
                elseif i == 3 then self:doBack()
                end
                return
            end
        end
        return
    end

    -- row hit testing
    local cy = my - NAV_H + scrollY
    for _, row in ipairs(rows) do
        if cy >= row.y and cy < row.y + row.h then
            local sx = fx + LABEL_W
            local sw = sliderW(fw)

            if row.type == "slider" then
                if mx >= sx and mx <= sx + sw then
                    dragging = {row = row}
                    local t = math.max(0, math.min(1, (mx - sx) / sw))
                    local val = row.min + t * (row.max - row.min)
                    val = math.floor(val / row.step + 0.5) * row.step
                    val = math.max(row.min, math.min(row.max, val))
                    row.set(val)
                end

            elseif row.type == "stepper" then
                local val = row.get()
                if mx >= sx and mx < sx + 22 then
                    row.set(math.max(row.min, val - row.step))
                    dirty = true
                elseif mx >= sx + 30 + fonts.sm:getWidth(tostring(val)) + 6
                   and mx < sx + 30 + fonts.sm:getWidth(tostring(val)) + 28 then
                    row.set(math.min(row.max, val + row.step))
                    dirty = true
                end

            elseif row.type == "enemy" then
                local wd = world()
                wd.enemyRoster = wd.enemyRoster or {}
                local weight = wd.enemyRoster[row.typeId] or 0
                -- checkbox
                if mx >= fx + 4 and mx <= fx + 26 then
                    if weight > 0 then
                        wd.enemyRoster[row.typeId] = 0
                    else
                        wd.enemyRoster[row.typeId] = 20
                    end
                    dirty = true
                -- weight slider
                elseif weight > 0 and mx >= sx and mx <= sx + sw then
                    dragging = {row = row}
                    local t = math.max(0, math.min(1, (mx - sx) / sw))
                    wd.enemyRoster[row.typeId] = math.max(1, math.floor(t * 50 + 0.5))
                    dirty = true
                end
            end
            return
        end
    end
end

function editor:mousereleased(mx, my, button)
    if button == 1 then dragging = nil end
end

function editor:wheelmoved(wx, wy)
    scrollY = math.max(0, math.min(maxScroll, scrollY - wy * 36))
end

function editor:resize(w, h)
    buildRows()
end

-- ─── Keys ──────────────────────────────────────────────────────────
function editor:keypressed(key)
    if key == "left" and currentIdx > 1 then
        currentIdx = currentIdx - 1; scrollY = 0; buildRows()
    elseif key == "right" and currentIdx < #Worlds.order then
        currentIdx = currentIdx + 1; scrollY = 0; buildRows()
    elseif key == "escape" then
        self:doBack()
    elseif key == "f5" then
        self:doPreview()
    elseif key == "s" and love.keyboard.isDown("lctrl", "rctrl") then
        self:doSave()
    end
end

-- ─── Actions ───────────────────────────────────────────────────────
function editor:doPreview()
    local wid = worldId()
    local room = ChunkAssembler.generate(wid, 1)
    if room then
        returnFromPreview = true
        local game = require("src.states.game")
        Gamestate.switch(game, { editorRoom = room, worldId = wid })
    else
        setStatus("Failed to generate — check chunks for " .. wid)
    end
end

function editor:doSave()
    local lines = {"-- World overrides (generated by World Editor)", "return {"}
    for _, wid in ipairs(Worlds.order) do
        local wd = Worlds.definitions[wid]
        if wd then
            lines[#lines+1] = string.format("    %s = {", wid)
            lines[#lines+1] = string.format("        roomsPerCheckpoint = %d,", wd.roomsPerCheckpoint or 5)
            lines[#lines+1] = string.format("        parallaxSpeed = %.2f,", wd.parallaxSpeed or 0.3)
            if wd.skyColor then
                lines[#lines+1] = string.format("        skyColor = {%.3f, %.3f, %.3f},",
                    wd.skyColor[1], wd.skyColor[2], wd.skyColor[3])
            end
            if wd.chunkGen then
                local cg = wd.chunkGen
                lines[#lines+1] = "        chunkGen = {"
                lines[#lines+1] = string.format("            cols = %d, rows = %d,", cg.cols, cg.rows)
                lines[#lines+1] = string.format("            rightWeight = %d, verticalWeight = %d,", cg.rightWeight, cg.verticalWeight)
                lines[#lines+1] = string.format("            branchChance = %.2f,", cg.branchChance)
                lines[#lines+1] = "        },"
            end
            if wd.enemyRoster then
                lines[#lines+1] = "        enemyRoster = {"
                for _, tid in ipairs(ENEMY_ORDER) do
                    local wt = wd.enemyRoster[tid]
                    if wt and wt > 0 then
                        lines[#lines+1] = string.format("            %s = %d,", tid, wt)
                    end
                end
                lines[#lines+1] = "        },"
            end
            lines[#lines+1] = "    },"
        end
    end
    lines[#lines+1] = "}"
    lines[#lines+1] = ""

    love.filesystem.write("world_overrides.lua", table.concat(lines, "\n"))
    dirty = false
    setStatus("Saved! Overrides written to save directory.")
end

function editor:doReset()
    local wid = worldId()
    local src = defaults[wid]
    if not src then
        setStatus("No defaults stored — restart game and try again.")
        return
    end
    -- Restore a deep copy so the default stays pristine for future resets
    Worlds.definitions[wid] = deepCopy(src)
    dirty = true
    buildRows()
    setStatus("Reset " .. wid .. " to defaults. Save to persist.")
end

function editor:doBack()
    local menu = require("src.states.menu")
    Gamestate.switch(menu)
end

return editor
