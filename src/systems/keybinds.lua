--- Reads `Settings.data.keybinds` (set by Settings + keybinding UI).
local Keybinds = {}

local Settings

local function S()
    if not Settings then Settings = require("src.systems.settings") end
    return Settings.data.keybinds
end

--- Human-readable label for a stored binding token.
function Keybinds.formatActionKey(action)
    local kb = S()
    if not kb or not kb[action] then return "?" end
    return Keybinds.formatStoredKey(kb[action])
end

function Keybinds.formatStoredKey(stored)
    if stored == "shift" then return "Shift" end
    if stored == "ctrl" then return "Ctrl" end
    if stored == "alt" then return "Alt" end
    if stored == "escape" then return "Esc" end
    if stored == " " or stored == "space" then return "Space" end
    if #stored == 1 then return string.upper(stored) end
    return stored
end

--- Normalize raw LÖVE key from capture to stored token.
function Keybinds.normalizeCapturedKey(key)
    if key == "lshift" or key == "rshift" then return "shift" end
    if key == "lctrl" or key == "rctrl" then return "ctrl" end
    if key == "lalt" or key == "ralt" then return "alt" end
    return key
end

function Keybinds.blockUsesCtrl()
    return S() and S().block == "ctrl"
end

function Keybinds.isBlockDown()
    local b = S() and S().block
    if not b then return false end
    if b == "ctrl" then
        return love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    end
    return love.keyboard.isDown(b)
end

function Keybinds.isDown(action)
    local kb = S()
    if not kb or not kb[action] then return false end
    local b = kb[action]
    if action == "dash" and b == "shift" then
        return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
    end
    if action == "block" and b == "ctrl" then
        return love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    end
    return love.keyboard.isDown(b)
end

--- For love.keypressed: does this key fire the bound action?
function Keybinds.matches(action, key)
    local kb = S()
    if not kb or not kb[action] then return false end
    local b = kb[action]
    if action == "dash" and b == "shift" then
        return key == "lshift" or key == "rshift"
    end
    if action == "block" and b == "ctrl" then
        return key == "lctrl" or key == "rctrl"
    end
    return key == b
end

return Keybinds
