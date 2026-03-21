--- Tabbed settings UI (Video / Audio / Gameplay). Shared by main menu and pause menu.
local Settings = require("src.systems.settings")
local TextLayout = require("src.ui.text_layout")

local SettingsPanel = {}

local BASE_TABS = {
    { id = "video", label = "Video" },
    { id = "audio", label = "Audio" },
    { id = "gameplay", label = "Gameplay" },
}

local function buildTabList()
    local tabs = {}
    for _, t in ipairs(BASE_TABS) do
        tabs[#tabs + 1] = t
    end
    return tabs
end

local function tabBarLayout(screenW, y0, tabFont, tabs)
    local gap = 10
    local n = #tabs
    local pad = 24 -- horizontal padding inside each tab (keeps label on one line)
    local widths = {}
    local total = 0
    for _, t in ipairs(tabs) do
        local w = tabFont:getWidth(t.label) + pad
        widths[#widths + 1] = w
        total = total + w
    end
    total = total + gap * (n - 1)

    local margin = 40
    local maxRow = screenW - 2 * margin
    if total > maxRow then
        local avail = maxRow - gap * (n - 1)
        local sumText = 0
        for _, t in ipairs(tabs) do
            sumText = sumText + tabFont:getWidth(t.label)
        end
        local padEach = (avail - sumText) / (2 * n)
        padEach = math.max(4, padEach)
        total = 0
        for i, t in ipairs(tabs) do
            widths[i] = tabFont:getWidth(t.label) + 2 * padEach
            total = total + widths[i]
        end
        total = total + gap * (n - 1)
    end

    local x0 = (screenW - total) * 0.5
    local x = x0
    local tabs = {}
    for i, t in ipairs(tabs) do
        tabs[i] = {
            id = t.id,
            label = t.label,
            x = x,
            y = y0,
            w = widths[i],
            h = 36,
        }
        x = x + widths[i] + gap
    end
    return tabs
end

-- Centered column so rows aren’t stretched edge-to-edge on ultrawide / large windows.
local CONTENT_PANEL_MAX_W = 500

local function rowRect(screenW, y, h)
    local w = math.min(CONTENT_PANEL_MAX_W, screenW - 96)
    w = math.max(280, w)
    local x = (screenW - w) * 0.5
    return { x = x, y = y, w = w, h = h or 40 }
end

local function sliderTrack(r, labelW)
    local trackW = math.min(200, math.max(80, r.w - labelW - 28))
    local tx = r.x + r.w - trackW - 8
    return { x = tx, y = r.y + (r.h - 14) * 0.5, w = trackW, h = 14 }
end

--- Build interactive layout for hit-testing and drawing.
--- tabFont: used to measure labels so tab widths fit text (avoids "Gameplay" wrapping).
function SettingsPanel.build(screenW, screenH, activeTabId, tabFont)
    local titleY = screenH * 0.12
    -- Extra gap below title so tabs aren’t cramped under “Settings”
    local tabY = titleY + 82
    local tabsList = buildTabList()
    local tabs = tabBarLayout(screenW, tabY, tabFont, tabsList)
    local contentTop = tabY + 46
    local rowH = 44
    local rows = {}

    if activeTabId == "video" then
        rows[1] = { key = "fullscreen", kind = "toggle", label = "Fullscreen", rect = rowRect(screenW, contentTop, rowH) }
        rows[2] = { key = "vsync", kind = "toggle", label = "VSync", rect = rowRect(screenW, contentTop + rowH + 6, rowH) }
        rows[3] = { key = "debug_saloon", kind = "action", label = "Debug: enter saloon", value = "Go >", rect = rowRect(screenW, contentTop + (rowH + 6) * 2, rowH) }
        rows[4] = { key = "debug_add_gold", kind = "action", label = "Debug: add gold", value = "+10", rect = rowRect(screenW, contentTop + (rowH + 6) * 3, rowH) }
        rows[5] = { key = "debug_sub_gold", kind = "action", label = "Debug: subtract gold", value = "-10", rect = rowRect(screenW, contentTop + (rowH + 6) * 4, rowH) }
    elseif activeTabId == "audio" then
        local y = contentTop
        for i, spec in ipairs({
            { key = "masterVolume", label = "Master volume" },
            { key = "musicVolume", label = "Music" },
            { key = "sfxVolume", label = "Sound effects" },
        }) do
            local r = rowRect(screenW, y, rowH)
            local labelReserve = math.min(210, math.floor(r.w * 0.48))
            rows[i] = {
                key = spec.key,
                kind = "slider",
                label = spec.label,
                rect = r,
                track = sliderTrack(r, labelReserve),
            }
            y = y + rowH + 6
        end
    elseif activeTabId == "gameplay" then
        -- Taller rows: long labels + value used to wrap/clamp in 44px; avoid Unicode arrows (font may show tofu).
        local gh = 50
        local gap = 8
        rows[1] = { key = "screenShake", kind = "cycle", label = "Screen shake", rect = rowRect(screenW, contentTop, gh) }
        rows[2] = { key = "defaultAutoGun", kind = "toggle", label = "Auto gun (new runs)", rect = rowRect(screenW, contentTop + gh + gap, gh) }
        rows[3] = {
            key = "mouseAimIdle",
            kind = "cycle",
            -- Short label: was "Mouse idle → keyboard aim" (wrapped/clipped in narrow column)
            label = "Mouse idle delay",
            rect = rowRect(screenW, contentTop + (gh + gap) * 2, gh),
        }
    end

    local backY = screenH * 0.72
    local bw, bh = 280, 48
    local back = {
        x = (screenW - bw) * 0.5,
        y = backY,
        w = bw,
        h = bh,
        label = "Back",
    }

    return {
        tabs = tabs,
        rows = rows,
        back = back,
        titleY = titleY,
        tabY = tabY,
        contentTop = contentTop,
    }
end

function SettingsPanel.hitTest(screenW, screenH, activeTabId, gx, gy, tabFont)
    local L = SettingsPanel.build(screenW, screenH, activeTabId, tabFont)
    if gx >= L.back.x and gx <= L.back.x + L.back.w and gy >= L.back.y and gy <= L.back.y + L.back.h then
        return { kind = "back" }
    end
    for _, t in ipairs(L.tabs) do
        if gx >= t.x and gx <= t.x + t.w and gy >= t.y and gy <= t.y + t.h then
            return { kind = "tab", id = t.id }
        end
    end
    for i, row in ipairs(L.rows) do
        local r = row.rect
        if gx >= r.x and gx <= r.x + r.w and gy >= r.y and gy <= r.y + r.h then
            if row.kind == "slider" and row.track then
                local tr = row.track
                local u = (gx - tr.x) / tr.w
                u = math.max(0, math.min(1, u))
                return { kind = "slider", key = row.key, value = u, index = i }
            end
            return { kind = "row", index = i, row = row }
        end
    end
    return nil
end

local function toggleLabel(key)
    local d = Settings.data
    if key == "fullscreen" then return d.fullscreen and "On" or "Off" end
    if key == "vsync" then return d.vsync == 1 and "On" or "Off" end
    if key == "defaultAutoGun" then return d.defaultAutoGun and "On" or "Off" end
    return "?"
end

local function drawRowLabelValue(font, row, valueText)
    local r = row.rect
    local y = TextLayout.printfYCenteredInRect(font, r.y, r.h)
    local split = r.w * 0.56
    love.graphics.setColor(0.88, 0.82, 0.72)
    love.graphics.setFont(font)
    love.graphics.printf(row.label, r.x + 10, y, split - 14, "left")
    love.graphics.setColor(0.95, 0.78, 0.42)
    love.graphics.printf(valueText, r.x + split, y, r.w - split - 12, "right")
end

function SettingsPanel.draw(screenW, screenH, activeTabId, fonts, hover)
    -- fonts: { title, tab, row, hint }
    local L = SettingsPanel.build(screenW, screenH, activeTabId, fonts.tab)
    local d = Settings.data

    love.graphics.setColor(1, 0.88, 0.35)
    love.graphics.setFont(fonts.title)
    love.graphics.printf("Settings", 0, L.titleY, screenW, "center")

    for _, t in ipairs(L.tabs) do
        local on = t.id == activeTabId
        local hov = hover and hover.kind == "tab" and hover.id == t.id
        if on then
            love.graphics.setColor(0.28, 0.18, 0.1, 0.95)
        elseif hov then
            love.graphics.setColor(0.22, 0.14, 0.08, 0.92)
        else
            love.graphics.setColor(0.14, 0.1, 0.07, 0.85)
        end
        love.graphics.rectangle("fill", t.x, t.y, t.w, t.h, 6, 6)
        love.graphics.setColor(0.85, 0.65, 0.35, on and 1 or 0.55)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", t.x, t.y, t.w, t.h, 6, 6)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 0.95, 0.82)
        love.graphics.setFont(fonts.tab)
        love.graphics.printf(t.label, t.x, TextLayout.printfYCenteredInRect(fonts.tab, t.y, t.h), t.w, "center")
    end

    for i, row in ipairs(L.rows) do
        local hovRow = hover and (
            (hover.kind == "row" and hover.index == i)
            or (hover.kind == "slider" and hover.index == i)
        )
        if hovRow then
            love.graphics.setColor(0.18, 0.12, 0.08, 0.35)
            love.graphics.rectangle("fill", row.rect.x, row.rect.y, row.rect.w, row.rect.h, 4, 4)
        end

        if row.kind == "toggle" then
            drawRowLabelValue(fonts.row, row, toggleLabel(row.key))
        elseif row.kind == "cycle" then
            local vt
            if row.key == "screenShake" then vt = Settings.labelScreenShake()
            elseif row.key == "mouseAimIdle" then vt = Settings.labelMouseAimIdle()
            else vt = "?" end
            drawRowLabelValue(fonts.row, row, vt .. "  >")
        elseif row.kind == "action" then
            drawRowLabelValue(fonts.row, row, row.value or "Run >")
        elseif row.kind == "slider" then
            local v = d[row.key] or 0
            local r = row.rect
            local tr = row.track
            local y = TextLayout.printfYCenteredInRect(fonts.row, r.y, r.h)
            love.graphics.setFont(fonts.row)
            love.graphics.setColor(0.88, 0.82, 0.72)
            love.graphics.printf(row.label, r.x + 10, y, math.max(80, tr.x - r.x - 44), "left")
            love.graphics.setColor(0.95, 0.78, 0.42)
            do
                local pct = string.format("%d%%", math.floor(v * 100 + 0.5))
                local pw = fonts.row:getWidth(pct)
                -- Don’t use printf with a tiny wrap width — it breaks "100%" across lines
                love.graphics.print(pct, tr.x - 8 - pw, y)
            end
            love.graphics.setColor(0.1, 0.08, 0.06, 0.9)
            love.graphics.rectangle("fill", tr.x, tr.y, tr.w, tr.h, 4, 4)
            love.graphics.setColor(0.55, 0.42, 0.22, 1)
            love.graphics.rectangle("fill", tr.x, tr.y, tr.w * v, tr.h, 4, 4)
            love.graphics.setColor(0.85, 0.65, 0.35, 0.75)
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", tr.x, tr.y, tr.w, tr.h, 4, 4)
        end
    end

    local br = L.back
    local backHov = hover and hover.kind == "back"
    if backHov then
        love.graphics.setColor(0.22, 0.14, 0.08, 0.92)
    else
        love.graphics.setColor(0.12, 0.08, 0.06, 0.75)
    end
    love.graphics.rectangle("fill", br.x, br.y, br.w, br.h, 6, 6)
    love.graphics.setColor(0.85, 0.65, 0.35, backHov and 1 or 0.65)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", br.x, br.y, br.w, br.h, 6, 6)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 0.95, 0.82)
    love.graphics.setFont(fonts.tab)
    love.graphics.printf(br.label, br.x, TextLayout.printfYCenteredInRect(fonts.tab, br.y, br.h), br.w, "center")

    love.graphics.setFont(fonts.hint)
    love.graphics.setColor(0.45, 0.45, 0.48)
    love.graphics.printf("Click rows to change  ·  [ / ] switch tabs  ·  ESC or Back", 0, screenH * 0.88, screenW, "center")
end

function SettingsPanel.applyHit(hit, player)
    if not hit then return nil end
    if hit.kind == "tab" then
        return { setTab = hit.id }
    end
    if hit.kind == "back" then
        return { goBack = true }
    end
    if hit.kind == "slider" then
        Settings.setVolumeKey(hit.key, hit.value)
        Settings.save()
        Settings.apply()
        return {}
    end
    if hit.kind == "row" then
        local row = hit.row
        if row.kind == "action" then
            return { action = row.key }
        elseif row.kind == "toggle" then
            if row.key == "fullscreen" then Settings.toggleFullscreen()
            elseif row.key == "vsync" then Settings.toggleVsync()
            elseif row.key == "defaultAutoGun" then Settings.toggleDefaultAutoGun()
            end
        elseif row.kind == "cycle" then
            if row.key == "screenShake" then Settings.cycleScreenShake()
            elseif row.key == "mouseAimIdle" then Settings.cycleMouseAimIdle()
            end
        end
        Settings.save()
        Settings.apply()
        if player and row.key == "defaultAutoGun" then
            player.autoGun = Settings.getDefaultAutoGun()
        end
        return {}
    end
    return {}
end

function SettingsPanel.cycleTab(activeTabId, dir)
    local order = {}
    for _, t in ipairs(buildTabList()) do
        order[#order + 1] = t.id
    end
    local idx = 1
    for i, id in ipairs(order) do
        if id == activeTabId then
            idx = i
            break
        end
    end
    idx = idx + dir
    if idx < 1 then idx = #order end
    if idx > #order then idx = 1 end
    return order[idx]
end

return SettingsPanel
