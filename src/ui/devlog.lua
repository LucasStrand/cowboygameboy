-- Developer log: persistent circular buffer shown in the F1 overlay.
-- Usage:  DevLog.push("sys",      "Room 3 loaded")
--         DevLog.push("combat",   "Took 12 dmg")
--         DevLog.push("progress", "Level up → 4")

local Font = require("src.ui.font")

local DevLog = {}

local MAX_ENTRIES = 40

-- Category display config
local CAT = {
    sys      = { tag = "SYS",  r = 0.4, g = 0.9, b = 1.0 },
    combat   = { tag = "CMB",  r = 1.0, g = 0.45, b = 0.3 },
    progress = { tag = "PRG",  r = 0.4, g = 1.0, b = 0.55 },
}

local entries = {}   -- { t, cat, msg }
local sessionStart = 0

function DevLog.init()
    entries = {}
    sessionStart = love.timer.getTime()
end

function DevLog.push(category, msg)
    local t = love.timer.getTime() - sessionStart
    table.insert(entries, { t = t, cat = category or "sys", msg = tostring(msg) })
    if #entries > MAX_ENTRIES then
        table.remove(entries, 1)
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

-- Always-visible overlay: last N entries, anchored to bottom-right of the screen.
-- Call every frame from game:draw() without needing F1.
local OVERLAY_LINES = 8
local OVERLAY_W     = 420

function DevLog.drawOverlay(screenW, screenH)
    if #entries == 0 then return end

    if not DevLog._overlayFont then
        DevLog._overlayFont = Font.new(10)
    end

    local lineH  = 13
    local count  = math.min(OVERLAY_LINES, #entries)
    local panelH = count * lineH + 6
    local x      = screenW - OVERLAY_W - 6
    local y      = screenH - panelH - 100   -- sit above the loadout row

    local prevFont = love.graphics.getFont()
    love.graphics.setFont(DevLog._overlayFont)

    -- Background
    love.graphics.setColor(0, 0, 0, 0.52)
    love.graphics.rectangle("fill", x - 4, y - 2, OVERLAY_W + 8, panelH)

    -- Last N entries, newest at bottom
    local start = #entries - count + 1
    for i = start, #entries do
        local e   = entries[i]
        local cfg = CAT[e.cat] or CAT.sys
        local age = #entries - i   -- 0 = newest
        local alpha = math.max(0.3, 1 - age * 0.1)

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
