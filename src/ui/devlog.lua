-- Developer log: persistent circular buffer shown in the F1 overlay.
-- Usage:  DevLog.push("sys",      "Room 3 loaded")
--         DevLog.push("combat",   "Took 12 dmg")
--         DevLog.push("progress", "Level up → 4")

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

return DevLog
