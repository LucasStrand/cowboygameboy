-- World Editor — tune world properties, map generation, and enemy rosters.
-- Accessible from the main menu. Changes save to the LÖVE save directory
-- and are loaded automatically on next launch.

local Gamestate = require("lib.hump.gamestate")
local Font = require("src.ui.font")
local Worlds = require("src.data.worlds")
local EnemyData = require("src.data.enemies")
local ChunkLoader = require("src.systems.chunk_loader")
local ChunkAssembler = require("src.systems.chunk_assembler")
local AssetScan = require("src.data.asset_scan")

local editor = {}

-- ─── Constants ─────────────────────────────────────────────────────
local NAV_H = 56
local ROW_H = 34
local SECTION_PAD = 10
local FORM_MAX_W = 920
local LABEL_W = 180
local SLIDER_H = 14
local SLIDER_W = 220
local BTN_H = 34
local BTN_W = 110
local BOTTOM_BAR_H = 54
local ROW_SEARCH_H = 38
--- Thumbnail grid for decor picker
local DECOR_THUMB = 72
local DECOR_PAD = 8
local DECOR_LABEL_H = 26
local MAX_DECOR_GRID = 96

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
local decorSearchFocused = false
--- Per-world: { query = string, folderIdx = number }
local decorUIByWorld = {}
--- Per-world playtest: 0 = random assembled level, 1..N = Nth chunk in sorted pool
local previewChunkChoiceByWorld = {}
--- Loaded Image cache for decor thumbnails (path -> Image|false)
local decorThumbCache = {}

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

local function decorUI()
    local wid = worldId()
    if not decorUIByWorld[wid] then
        decorUIByWorld[wid] = { query = "", folderIdx = 1 }
    end
    return decorUIByWorld[wid]
end

local function getDecorThumb(path)
    local c = decorThumbCache[path]
    if c ~= nil then return c end
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
        img:setFilter("nearest", "nearest")
        decorThumbCache[path] = img
        return img
    end
    decorThumbCache[path] = false
    return nil
end

local function formBounds()
    local w = love.graphics.getWidth()
    local fw = math.min(w - 40, FORM_MAX_W)
    return math.floor((w - fw) / 2), fw
end

local function setStatus(msg)
    statusMsg = msg
    statusTimer = 3
end

local function pathInDecorList(wd, path)
    if not wd or not wd.decorPropPaths then return false end
    for _, p in ipairs(wd.decorPropPaths) do
        local s = type(p) == "string" and p or (p and p.path)
        if s == path then return true end
    end
    return false
end

local function toggleDecorPath(wd, path)
    if not wd then return end
    if wd.decorPropPaths == nil then
        wd.decorPropPaths = { path }
        dirty = true
        return
    end
    local list = wd.decorPropPaths
    local idx = nil
    for i, p in ipairs(list) do
        local s = type(p) == "string" and p or (p and p.path)
        if s == path then idx = i; break end
    end
    if idx then
        table.remove(list, idx)
        if #list == 0 then
            wd.decorPropPaths = {}
        end
    else
        list[#list + 1] = path
    end
    dirty = true
end

local function escapeLuaStr(s)
    return s:gsub("\\", "\\\\"):gsub('"', '\\"')
end

local function folderStepperLabel(folders, idx)
    local prefix = folders[idx]
    local vs = (prefix == "" or prefix == nil) and "(all folders)" or prefix
    if #vs > 36 then
        vs = vs:sub(1, 16) .. "…" .. vs:sub(-16)
    end
    return vs
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

    section("LEVEL PREVIEW")
    do
        local wid = worldId()
        local pool = {}
        for _, c in ipairs(ChunkLoader.getPool(wid)) do
            pool[#pool + 1] = c
        end
        table.sort(pool, function(a, b) return (a.id or "") < (b.id or "") end)
        if previewChunkChoiceByWorld[wid] == nil then
            previewChunkChoiceByWorld[wid] = (#pool > 0) and 1 or 0
        end
        if #pool == 0 then
            previewChunkChoiceByWorld[wid] = 0
        else
            previewChunkChoiceByWorld[wid] = math.max(0, math.min(#pool, previewChunkChoiceByWorld[wid]))
        end
        rows[#rows + 1] = { type = "previewchunk", y = y, h = ROW_H, pool = pool, wid = wid }
        y = y + ROW_H
    end

    -- ── Decor: pick image paths from the project (saved as decorPropPaths) ──
    section("DECOR ASSETS (PROJECT)")
    rows[#rows + 1] = {
        type = "search",
        y = y,
        h = ROW_SEARCH_H,
    }
    y = y + ROW_SEARCH_H

    local _, fw = formBounds()
    local ui = decorUI()
    local folderList = AssetScan.getAssetSubfolders()
    if ui.folderIdx > #folderList then ui.folderIdx = 1 end
    ui.folderIdx = math.max(1, math.min(#folderList, ui.folderIdx))
    local prefix = folderList[ui.folderIdx] or ""

    local allPaths = AssetScan.getImagePaths()
    local qlow = ui.query:lower()
    local filtered = {}
    for _, p in ipairs(allPaths) do
        local ok = true
        if prefix ~= "" then
            if p:sub(1, #prefix) ~= prefix or p:sub(#prefix + 1, #prefix + 1) ~= "/" then
                ok = false
            end
        end
        if ok and qlow ~= "" and not p:lower():find(qlow, 1, true) then
            ok = false
        end
        if ok then
            filtered[#filtered + 1] = p
        end
    end

    rows[#rows + 1] = { type = "folderstepper", y = y, h = ROW_H, folders = folderList }
    y = y + ROW_H

    local totalF = #filtered
    local capped = {}
    local nCap = math.min(totalF, MAX_DECOR_GRID)
    for i = 1, nCap do
        capped[i] = filtered[i]
    end

    local cols = math.max(1, math.floor((fw - 24) / (DECOR_THUMB + DECOR_PAD)))
    local cellW = DECOR_THUMB + DECOR_PAD
    local cellH = DECOR_THUMB + DECOR_LABEL_H + DECOR_PAD
    local gridRows = math.max(1, math.ceil(math.max(nCap, 1) / cols))
    local gridH = gridRows * cellH + 16

    rows[#rows + 1] = {
        type = "decorgrid",
        y = y,
        h = gridH,
        paths = capped,
        cols = cols,
        cellW = cellW,
        cellH = cellH,
        totalFiltered = totalF,
    }
    y = y + gridH

    if totalF > MAX_DECOR_GRID then
        rows[#rows + 1] = {
            type = "label",
            y = y,
            h = ROW_H,
            label = "Showing",
            value = string.format("%d of %d — narrow folder or search", MAX_DECOR_GRID, totalF),
        }
        y = y + ROW_H
    end

    rows[#rows + 1] = { type = "decorclear", y = y, h = ROW_H }
    y = y + ROW_H
    rows[#rows + 1] = { type = "decorrescan", y = y, h = ROW_H }
    y = y + ROW_H

    local custom = wd.decorPropPaths
    if custom == nil then
        label("Selected", "none — no decor props in-game until you pick images above")
    elseif #custom == 0 then
        label("Selected", "0 images — no decor props")
    else
        label("Selected", string.format("%d image(s) used for this world", #custom))
    end

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

local function drawSearchRow(row, fx, fw)
    local sy = row.y - scrollY + NAV_H
    love.graphics.setColor(0.12, 0.12, 0.14)
    love.graphics.rectangle("fill", fx + 8, sy + 4, fw - 16, row.h - 8, 4, 4)
    love.graphics.setColor(decorSearchFocused and accent() or DIM)
    love.graphics.rectangle("line", fx + 8, sy + 4, fw - 16, row.h - 8, 4, 4)
    love.graphics.setFont(fonts.sm)
    love.graphics.setColor(LIGHT)
    local txt = decorUI().query
    if txt == "" then
        love.graphics.setColor(DIM)
        txt = "Search filename or path…"
    end
    love.graphics.print(txt, fx + 16, sy + 10)
end

local function previewChunkLabel(wid, pool)
    local ch = previewChunkChoiceByWorld[wid] or 0
    if #pool == 0 then
        return "(no chunk files)"
    elseif ch == 0 then
        return "Random assembled"
    end
    local c = pool[ch]
    if not c then return "?" end
    return string.format("%s  (%s)", c.id or "?", c.chunkType or "?")
end

local function drawPreviewChunk(row, fx, fw)
    local sy = row.y - scrollY + NAV_H
    local pool = row.pool
    local wid = row.wid
    local ch = previewChunkChoiceByWorld[wid] or 0
    if #pool > 0 then
        ch = math.max(0, math.min(#pool, ch))
        previewChunkChoiceByWorld[wid] = ch
    end
    local vs = previewChunkLabel(wid, pool)
    local sx = fx + LABEL_W
    local a = accent()

    love.graphics.setFont(fonts.sm)
    love.graphics.setColor(DIM)
    love.graphics.print("Playtest", fx + 8, sy + 8)

    if #pool > 0 then
        love.graphics.setColor(a)
        love.graphics.rectangle("fill", sx, sy + 6, 22, 20, 3, 3)
        love.graphics.setColor(WHITE)
        love.graphics.print("<", sx + 6, sy + 7)

        love.graphics.setColor(WHITE)
        love.graphics.print(vs, sx + 30, sy + 8)

        local rx = sx + 30 + fonts.sm:getWidth(vs) + 6
        love.graphics.setColor(a)
        love.graphics.rectangle("fill", rx, sy + 6, 22, 20, 3, 3)
        love.graphics.setColor(WHITE)
        love.graphics.print(">", rx + 6, sy + 7)
    else
        love.graphics.setColor(DIM)
        love.graphics.printf(vs, sx, sy + 8, fw - sx - 8, "left")
    end
end

local function drawFolderStepper(row, fx, fw)
    local sy = row.y - scrollY + NAV_H
    local folders = row.folders
    local idx = decorUI().folderIdx
    idx = math.max(1, math.min(#folders, idx))
    decorUI().folderIdx = idx
    local vs = folderStepperLabel(folders, idx)
    local sx = fx + LABEL_W
    local a = accent()

    love.graphics.setFont(fonts.sm)
    love.graphics.setColor(DIM)
    love.graphics.print("Folder", fx + 8, sy + 8)

    love.graphics.setColor(a)
    love.graphics.rectangle("fill", sx, sy + 6, 22, 20, 3, 3)
    love.graphics.setColor(WHITE)
    love.graphics.print("<", sx + 6, sy + 7)

    love.graphics.setColor(WHITE)
    love.graphics.print(vs, sx + 30, sy + 8)

    local rx = sx + 30 + fonts.sm:getWidth(vs) + 6
    love.graphics.setColor(a)
    love.graphics.rectangle("fill", rx, sy + 6, 22, 20, 3, 3)
    love.graphics.setColor(WHITE)
    love.graphics.print(">", rx + 6, sy + 7)
end

local function drawDecorGrid(row, fx, fw)
    local sy = row.y - scrollY + NAV_H
    local paths = row.paths
    local cols = row.cols
    local cellW = row.cellW
    local cellH = row.cellH
    local wd = world()

    love.graphics.setColor(0.11, 0.11, 0.13)
    love.graphics.rectangle("fill", fx + 4, sy, fw - 8, row.h, 4, 4)

    if not paths or #paths == 0 then
        love.graphics.setFont(fonts.sm)
        love.graphics.setColor(DIM)
        love.graphics.printf(
            "No images match. Change folder or search.",
            fx + 12,
            sy + row.h * 0.5 - 6,
            fw - 24,
            "center"
        )
        return
    end

    for i, path in ipairs(paths) do
        local col = (i - 1) % cols
        local rowIndex = math.floor((i - 1) / cols)
        local cx = fx + 8 + col * cellW
        local cy = sy + 8 + rowIndex * cellH

        love.graphics.setColor(0.16, 0.16, 0.2)
        love.graphics.rectangle("fill", cx, cy, DECOR_THUMB, DECOR_THUMB, 0, 0)

        local img = getDecorThumb(path)
        if img then
            local iw, ih = img:getDimensions()
            local scale = math.min(DECOR_THUMB / iw, DECOR_THUMB / ih) * 0.92
            local dw, dh = iw * scale, ih * scale
            local ox = cx + (DECOR_THUMB - dw) / 2
            local oy = cy + (DECOR_THUMB - dh) / 2
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(img, ox, oy, 0, scale, scale)
        else
            love.graphics.setColor(DIM)
            love.graphics.setFont(fonts.sm)
            love.graphics.print("?", cx + DECOR_THUMB * 0.45, cy + DECOR_THUMB * 0.4)
        end

        local on = pathInDecorList(wd, path)
        love.graphics.setColor(accent())
        if on then
            love.graphics.rectangle("fill", cx + DECOR_THUMB - 18, cy + 4, 14, 14, 2, 2)
        else
            love.graphics.rectangle("line", cx + DECOR_THUMB - 18, cy + 4, 14, 14, 2, 2)
        end

        love.graphics.setFont(fonts.sm)
        love.graphics.setColor(LIGHT)
        local fname = path:match("[^/]+$") or path
        if #fname > 12 then
            fname = fname:sub(1, 10) .. "…"
        end
        love.graphics.printf(fname, cx, cy + DECOR_THUMB + 2, DECOR_THUMB, "center")
    end
end

local function decorGridHitTest(row, fx, mx, cy)
    if cy < row.y or cy >= row.y + row.h then
        return nil
    end
    local relY = cy - row.y - 8
    local relX = mx - fx - 8
    if relX < 0 or relY < 0 then
        return nil
    end
    local cols = row.cols
    local cellW = row.cellW
    local cellH = row.cellH
    local ix = math.floor(relX / cellW)
    local rx = relX - ix * cellW
    local iy = math.floor(relY / cellH)
    local ry = relY - iy * cellH
    if ix < 0 or ix >= cols or rx > DECOR_THUMB then
        return nil
    end
    if ry > DECOR_THUMB + DECOR_LABEL_H then
        return nil
    end
    local idx = iy * cols + ix + 1
    local paths = row.paths
    if not paths or idx < 1 or idx > #paths then
        return nil
    end
    return paths[idx]
end

local function drawDecorClear(row, fx, fw)
    local sy = row.y - scrollY + NAV_H
    love.graphics.setColor(0.7, 0.45, 0.2)
    love.graphics.rectangle("line", fx + 8, sy + 4, fw - 16, row.h - 8, 4, 4)
    love.graphics.setFont(fonts.sm)
    love.graphics.setColor(LIGHT)
    love.graphics.print("Clear selected images (no decor until you pick again)", fx + 16, sy + 8)
end

local function drawDecorRescan(row, fx, fw)
    local sy = row.y - scrollY + NAV_H
    love.graphics.setColor(accent())
    love.graphics.rectangle("line", fx + 8, sy + 4, fw - 16, row.h - 8, 4, 4)
    love.graphics.setFont(fonts.sm)
    love.graphics.setColor(LIGHT)
    love.graphics.print("Rescan assets/ folder (new files)", fx + 16, sy + 8)
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
    AssetScan.invalidateCache()
    decorSearchFocused = false
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
            elseif row.type == "search" then   drawSearchRow(row, fx, fw)
            elseif row.type == "previewchunk" then drawPreviewChunk(row, fx, fw)
            elseif row.type == "folderstepper" then drawFolderStepper(row, fx, fw)
            elseif row.type == "decorgrid" then drawDecorGrid(row, fx, fw)
            elseif row.type == "decorclear" then drawDecorClear(row, fx, fw)
            elseif row.type == "decorrescan" then drawDecorRescan(row, fx, fw)
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
        decorSearchFocused = false
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
        decorSearchFocused = false
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
            if row.type == "search" then
                decorSearchFocused = true
                return
            end
            decorSearchFocused = false

            if row.type == "previewchunk" then
                local pool = row.pool
                local wid = row.wid
                if #pool == 0 then
                    return
                end
                local ch = previewChunkChoiceByWorld[wid] or 0
                ch = math.max(0, math.min(#pool, ch))
                local vs = previewChunkLabel(wid, pool)
                local sx = fx + LABEL_W
                if mx >= sx and mx < sx + 22 then
                    previewChunkChoiceByWorld[wid] = math.max(0, ch - 1)
                    buildRows()
                elseif mx >= sx + 30 + fonts.sm:getWidth(vs) + 6
                    and mx < sx + 30 + fonts.sm:getWidth(vs) + 28 then
                    previewChunkChoiceByWorld[wid] = math.min(#pool, ch + 1)
                    buildRows()
                end
                return
            elseif row.type == "folderstepper" then
                local folders = row.folders
                local idx = decorUI().folderIdx
                local vs = folderStepperLabel(folders, idx)
                local sx = fx + LABEL_W
                if mx >= sx and mx < sx + 22 then
                    decorUI().folderIdx = math.max(1, idx - 1)
                    buildRows()
                elseif mx >= sx + 30 + fonts.sm:getWidth(vs) + 6
                    and mx < sx + 30 + fonts.sm:getWidth(vs) + 28 then
                    decorUI().folderIdx = math.min(#folders, idx + 1)
                    buildRows()
                end
                return
            elseif row.type == "decorgrid" then
                local cy = my - NAV_H + scrollY
                local path = decorGridHitTest(row, fx, mx, cy)
                if path then
                    toggleDecorPath(world(), path)
                end
                return
            elseif row.type == "decorclear" then
                if mx >= fx + 8 and mx <= fx + fw - 8 then
                    world().decorPropPaths = nil
                    dirty = true
                end
                return
            elseif row.type == "decorrescan" then
                if mx >= fx + 8 and mx <= fx + fw - 8 then
                    AssetScan.invalidateCache()
                    decorThumbCache = {}
                    buildRows()
                    setStatus("Rescanned assets/ for images.")
                end
                return
            end

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
    if decorSearchFocused then
        if key == "backspace" then
            decorUI().query = decorUI().query:sub(1, -2)
            buildRows()
            return
        elseif key == "escape" then
            decorSearchFocused = false
            return
        elseif key == "return" or key == "kpenter" then
            decorSearchFocused = false
            return
        end
    end
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

function editor:textinput(t)
    if not decorSearchFocused then return end
    if t:find("%c") then return end
    decorUI().query = decorUI().query .. t
    buildRows()
end

-- ─── Actions ───────────────────────────────────────────────────────
function editor:doPreview()
    local wid = worldId()
    local pool = {}
    for _, c in ipairs(ChunkLoader.getPool(wid)) do
        pool[#pool + 1] = c
    end
    table.sort(pool, function(a, b) return (a.id or "") < (b.id or "") end)
    local ch = previewChunkChoiceByWorld[wid] or 0
    if #pool > 0 then
        ch = math.max(0, math.min(#pool, ch))
        previewChunkChoiceByWorld[wid] = ch
    end
    local room
    if #pool == 0 then
        room = ChunkAssembler.generate(wid, 1)
    elseif ch == 0 then
        room = ChunkAssembler.generate(wid, 1)
    else
        room = ChunkAssembler.chunkToPreviewRoom(pool[ch])
    end
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
            if wd.decorPropPaths ~= nil then
                if #wd.decorPropPaths == 0 then
                    lines[#lines+1] = "        decorPropPaths = {},"
                else
                    lines[#lines+1] = "        decorPropPaths = {"
                    for _, p in ipairs(wd.decorPropPaths) do
                        local path = type(p) == "string" and p or (p and p.path)
                        if type(path) == "string" then
                            lines[#lines+1] = string.format('            "%s",', escapeLuaStr(path))
                        end
                    end
                    lines[#lines+1] = "        },"
                end
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
