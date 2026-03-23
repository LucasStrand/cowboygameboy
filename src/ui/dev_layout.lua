-- Shared screen layout when dev panel, character sheet, and DEBUG overlay coexist.

local DevLayout = {}

local GAP = 12
local DEV_X, DEV_Y = 10, 18
local CHAR_W, CHAR_H = 332, 452
local CHAR_DEFAULT_X, CHAR_DEFAULT_Y = 18, 56
-- Matches game/saloon DEBUG HUD: text at screenW-260, backdrop x-5 width 255
local DEBUG_STATS_TEXT_X = -260
local DEBUG_CONSOLE_GAP = 12

--- @param opts { devPanelOpen: boolean?, characterSheetOpen: boolean?, debugOverlay: boolean? }
function DevLayout.compute(screenW, screenH, opts)
    opts = opts or {}
    local devOpen = opts.devPanelOpen == true
    local charOpen = opts.characterSheetOpen == true
    local debugOn = opts.debugOverlay == true

    local statsTextX = screenW + DEBUG_STATS_TEXT_X
    local statsBlockLeft = statsTextX - 5
    local statsBlockW = 255
    local consoleMaxRight = statsTextX - DEBUG_CONSOLE_GAP

    local compact = devOpen and (charOpen or debugOn)
    local desiredW = compact and math.min(420, math.max(280, math.floor(screenW * 0.36)))
        or math.min(760, math.max(620, math.floor(screenW * 0.66)))
    local desiredH = math.min(820, math.floor(screenH * 0.88))
    local pw = math.min(desiredW, screenW - 20)
    local ph = math.min(desiredH, screenH - 24)
    local devRight = DEV_X + pw

    local cx, cy = CHAR_DEFAULT_X, CHAR_DEFAULT_Y
    if devOpen and charOpen then
        cx = devRight + GAP
    end
    if charOpen then
        local maxCx = (debugOn and (consoleMaxRight - GAP) or (screenW - 12)) - CHAR_W
        if cx > maxCx then
            cx = math.max(DEV_X, maxCx)
        end
    end

    local midLeft = 12
    if devOpen and charOpen then
        midLeft = math.max(devRight + GAP, cx + CHAR_W + GAP)
    elseif devOpen then
        midLeft = devRight + GAP
    elseif charOpen then
        midLeft = CHAR_DEFAULT_X + CHAR_W + GAP
    end

    local consoleY = 60
    local consoleH = 240
    local consoleW
    if debugOn then
        consoleW = math.max(120, math.min(720, consoleMaxRight - midLeft))
    else
        consoleW = math.max(120, math.min(720, screenW - 12 - midLeft))
    end

    return {
        devPanel = { x = DEV_X, y = DEV_Y, w = pw, h = ph },
        character = { x = cx, y = cy, w = CHAR_W, h = CHAR_H },
        debugConsole = { x = midLeft, y = consoleY, w = consoleW, h = consoleH },
        debugStats = { textX = statsTextX, blockX = statsBlockLeft, blockW = statsBlockW, y = 60 },
    }
end

function DevLayout.devPanelRect(screenW, screenH, opts)
    local L = DevLayout.compute(screenW, screenH, opts)
    local d = L.devPanel
    return d.x, d.y, d.w, d.h
end

function DevLayout.debugConsoleRect(screenW, screenH, opts)
    local L = DevLayout.compute(screenW, screenH, opts)
    local c = L.debugConsole
    return c.x, c.y, c.w, c.h
end

return DevLayout
