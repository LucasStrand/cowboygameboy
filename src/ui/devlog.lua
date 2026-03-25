-- Developer log: persistent circular buffer shown in the F1 overlay.
-- Usage:  DevLog.push("sys",      "Room 3 loaded")
--         DevLog.push("combat",   "Took 12 dmg")
--         DevLog.push("progress", "Level up → 4")

local Font = require("src.ui.font")

local DevLog = {}

local MAX_ENTRIES = 800

-- Category display config
local CAT = {
    sys      = { tag = "SYS",  r = 0.4, g = 0.9, b = 1.0 },
    combat   = { tag = "CMB",  r = 1.0, g = 0.45, b = 0.3 },
    progress = { tag = "PRG",  r = 0.4, g = 1.0, b = 0.55 },
}

local entries = {}   -- { t, cat, msg, noOverlay? } — noOverlay: omit from bottom-right overlay (still in F1 console)
local sessionStart = 0

-- Bottom-right overlay: brief toast after each overlay-visible line; hidden until the next one.
local overlayVisibleUntil = nil -- wall-clock seconds; draw while love.timer.getTime() < this
local OVERLAY_DURATION_SEC = 4.5
local OVERLAY_FADE_SEC = 0.45
local consoleState = {
    follow = true,
    topIndex = 1,
}

local function consoleVisibleLines(h)
    local lineH = 13
    local headerH = 18
    local innerH = math.max(lineH, h - headerH - 8)
    return math.max(1, math.floor(innerH / lineH))
end

local function clampConsoleState(visibleLines)
    local total = #entries
    if total <= 0 then
        consoleState.follow = true
        consoleState.topIndex = 1
        return
    end

    local maxTop = math.max(1, total - visibleLines + 1)
    if consoleState.follow then
        consoleState.topIndex = maxTop
    else
        consoleState.topIndex = math.max(1, math.min(maxTop, consoleState.topIndex))
        if consoleState.topIndex >= maxTop then
            consoleState.topIndex = maxTop
            consoleState.follow = true
        end
    end
end

local function fitSingleLine(font, text, maxWidth)
    text = tostring(text or "")
    if font:getWidth(text) <= maxWidth then
        return text
    end

    local suffix = "..."
    local suffixW = font:getWidth(suffix)
    local out = {}
    for i = 1, #text do
        local nextPart = table.concat(out) .. text:sub(i, i)
        if font:getWidth(nextPart) + suffixW > maxWidth then
            break
        end
        out[#out + 1] = text:sub(i, i)
    end
    return table.concat(out) .. suffix
end

function DevLog.init()
    entries = {}
    sessionStart = love.timer.getTime()
    overlayVisibleUntil = nil
    consoleState.follow = true
    consoleState.topIndex = 1
end

--- opts.noOverlay: if true, line is stored but does not open/refresh the bottom-right overlay.
function DevLog.push(category, msg, opts)
    opts = opts or {}
    local t = love.timer.getTime() - sessionStart
    table.insert(entries, {
        t = t,
        cat = category or "sys",
        msg = tostring(msg),
        noOverlay = opts.noOverlay and true or nil,
    })
    if not opts.noOverlay then
        overlayVisibleUntil = love.timer.getTime() + OVERLAY_DURATION_SEC
    end
    if #entries > MAX_ENTRIES then
        table.remove(entries, 1)
        if not consoleState.follow then
            consoleState.topIndex = math.max(1, consoleState.topIndex - 1)
        end
    end
end

-- Draw the log panel into an already-positioned coordinate space.
-- x, y: top-left of the panel. w: panel width. font: current debug font.
-- Returns the Y position after the last line drawn.
function DevLog.draw(x, y, w)
    local lineH = 13

    -- Background
    local panelH = #entries * lineH + 22
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", x - 4, y - 4, w + 8, panelH)

    -- Header
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.print(string.format("-- DEV LOG  (%d entries) --", #entries), x, y)
    y = y + 18

    -- Entries (newest at bottom → iterate forward)
    for i, e in ipairs(entries) do
        local cfg = CAT[e.cat] or CAT.sys
        -- Fade older entries slightly
        local age = #entries - i          -- 0 = newest
        local alpha = math.max(0.35, 1 - age * 0.018)

        -- Timestamp
        love.graphics.setColor(0.55, 0.55, 0.6, alpha * 0.85)
        love.graphics.print(string.format("[%6.1fs]", e.t), x, y)

        -- Category badge
        love.graphics.setColor(cfg.r, cfg.g, cfg.b, alpha)
        love.graphics.print(cfg.tag, x + 58, y)

        -- Message
        love.graphics.setColor(0.92, 0.92, 0.92, alpha)
        love.graphics.print(e.msg, x + 90, y)

        y = y + lineH
    end

    return y
end

function DevLog.drawConsole(x, y, w, h)
    if #entries == 0 then
        return y
    end

    local lineH = 13
    local headerH = 18
    local visibleLines = consoleVisibleLines(h)
    clampConsoleState(visibleLines)
    local start = consoleState.topIndex
    local stop = math.min(#entries, start + visibleLines - 1)
    local count = math.max(0, stop - start + 1)

    love.graphics.setColor(0, 0, 0, 0.76)
    love.graphics.rectangle("fill", x - 4, y - 4, w + 8, h)

    love.graphics.setColor(0.7, 0.7, 0.7)
    local modeLabel = consoleState.follow and "LIVE" or "SCROLLED"
    love.graphics.print(string.format("-- DEV LOG  (%d/%d)  [%s] --", count, #entries, modeLabel), x, y)
    y = y + headerH

    local timeW = 48
    local tagW = 32
    local msgX = x + timeW + tagW + 10
    local msgW = math.max(32, w - (msgX - x) - 2)
    local font = love.graphics.getFont()

    for i = start, stop do
        local e = entries[i]
        local cfg = CAT[e.cat] or CAT.sys
        local age = stop - i
        local alpha = math.max(0.4, 1 - age * 0.08)

        love.graphics.setColor(0.55, 0.55, 0.6, alpha * 0.85)
        love.graphics.print(string.format("[%4.1f]", e.t), x, y)

        love.graphics.setColor(cfg.r, cfg.g, cfg.b, alpha)
        love.graphics.print(cfg.tag, x + timeW, y)

        love.graphics.setColor(0.92, 0.92, 0.92, alpha)
        love.graphics.print(fitSingleLine(font, e.msg, msgW), msgX, y)

        y = y + lineH
    end

    if #entries > visibleLines then
        local trackX = x + w - 4
        local trackY = y - count * lineH
        local trackH = visibleLines * lineH
        local thumbH = math.max(12, trackH * (visibleLines / #entries))
        local maxTop = math.max(1, #entries - visibleLines + 1)
        local progress = maxTop > 1 and ((start - 1) / (maxTop - 1)) or 0
        local thumbY = trackY + (trackH - thumbH) * progress

        love.graphics.setColor(0.2, 0.2, 0.24, 0.8)
        love.graphics.rectangle("fill", trackX, trackY, 3, trackH)
        love.graphics.setColor(0.7, 0.7, 0.75, 0.9)
        love.graphics.rectangle("fill", trackX, thumbY, 3, thumbH)
    end

    return y
end

function DevLog.scrollConsole(lines, h)
    if #entries == 0 then
        return
    end

    local visibleLines = consoleVisibleLines(h)
    clampConsoleState(visibleLines)
    local maxTop = math.max(1, #entries - visibleLines + 1)
    local currentTop = consoleState.topIndex
    local nextTop = math.max(1, math.min(maxTop, currentTop - lines))
    consoleState.topIndex = nextTop
    consoleState.follow = nextTop >= maxTop
end

function DevLog.followConsole()
    consoleState.follow = true
end

-- Transient overlay: last N entries, bottom-right; only for a few seconds after each overlay-visible line.
-- Call every frame from game:draw() without needing F1.
local OVERLAY_LINES = 8
local OVERLAY_W     = 420

function DevLog.drawOverlay(screenW, screenH)
    local now = love.timer.getTime()
    if not overlayVisibleUntil or now >= overlayVisibleUntil then
        return
    end

    local fadeMul = 1
    local left = overlayVisibleUntil - now
    if left < OVERLAY_FADE_SEC and OVERLAY_FADE_SEC > 0 then
        fadeMul = math.max(0, left / OVERLAY_FADE_SEC)
    end

    local visible = {}
    for i = 1, #entries do
        local e = entries[i]
        if not e.noOverlay then
            visible[#visible + 1] = e
        end
    end
    if #visible == 0 then return end

    if not DevLog._overlayFont then
        DevLog._overlayFont = Font.new(10)
    end

    local lineH  = 13
    local count  = math.min(OVERLAY_LINES, #visible)
    local panelH = count * lineH + 6
    local x      = screenW - OVERLAY_W - 6
    local y      = screenH - panelH - 100   -- sit above the loadout row

    local prevFont = love.graphics.getFont()
    love.graphics.setFont(DevLog._overlayFont)

    -- Background
    love.graphics.setColor(0, 0, 0, 0.52 * fadeMul)
    love.graphics.rectangle("fill", x - 4, y - 2, OVERLAY_W + 8, panelH)

    -- Last N overlay-visible entries, newest at bottom
    local start = #visible - count + 1
    for i = start, #visible do
        local e   = visible[i]
        local cfg = CAT[e.cat] or CAT.sys
        local age = #visible - i   -- 0 = newest
        local alpha = math.max(0.3, 1 - age * 0.1) * fadeMul

        love.graphics.setColor(0.5, 0.5, 0.55, alpha * 0.75)
        love.graphics.print(string.format("[%.1fs]", e.t), x, y)

        love.graphics.setColor(cfg.r, cfg.g, cfg.b, alpha)
        love.graphics.print(cfg.tag, x + 42, y)

        love.graphics.setColor(0.95, 0.95, 0.95, alpha)
        love.graphics.print(e.msg, x + 76, y)

        y = y + lineH
    end

    love.graphics.setFont(prevFont)
    love.graphics.setColor(1, 1, 1)
end

return DevLog
