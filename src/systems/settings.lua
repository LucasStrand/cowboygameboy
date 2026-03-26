--- Persisted user settings (save dir: settings.lua). Apply after load and on change.
--
--- Audio: `love.audio.setVolume` uses masterVolume globally. musicVolume / sfxVolume are
--- multipliers for future per-Source volume — use `Settings.getMusicVolumeMul()` /
--- `getSfxVolumeMul()` on music vs SFX `Source` instances when audio is added.
local Settings = {}
local DevLog = require("src.ui.devlog")

local defaults = {
    fullscreen = false,
    vsync = 1,
    masterVolume = 1,
    musicVolume = 1,
    sfxVolume = 1,
    --- Impact sprites, damage popups, etc. (0 = off, 1 = full)
    vfxVolume = 1,
    screenShake = 1,
    defaultAutoGun = true,
    mouseAimIdleSec = 1.0,
    showCrosshair = true,
    keybinds = {
        character = "c",
        interact = "e",
        jump = "space",
        drop = "s",
        dash = "shift",
        melee = "f",
        -- Ctrl is used for crouch; shield block uses B (see player.lua crouch vs block resolution).
        block = "b",
        ult = "q",
        reload = "r",
    },
}

Settings.data = {}
for k, v in pairs(defaults) do
    if k == "keybinds" then
        Settings.data.keybinds = {}
        for bk, bv in pairs(v) do
            Settings.data.keybinds[bk] = bv
        end
    else
        Settings.data[k] = v
    end
end

local function mergeKeybinds(t)
    if type(t) ~= "table" then return end
    local kb = Settings.data.keybinds
    for k, v in pairs(t) do
        if defaults.keybinds[k] and type(v) == "string" then
            kb[k] = v
        end
    end
end

local function mergeLoaded(t)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do
        if k == "keybinds" then
            mergeKeybinds(v)
        elseif defaults[k] ~= nil and type(v) == type(defaults[k]) and k ~= "keybinds" then
            Settings.data[k] = v
        end
    end
end

function Settings.load()
    local chunk = love.filesystem.load("settings.lua")
    if chunk then
        local ok, t = pcall(chunk)
        if ok then mergeLoaded(t) end
    end
end

local function escapeStr(s)
    return string.gsub(s, "\\", "\\\\"):gsub('"', '\\"')
end

function Settings.save()
    local d = Settings.data
    local kbOrder = { "character", "interact", "jump", "drop", "dash", "melee", "block", "ult", "reload" }
    local kbLines = { "  keybinds = {" }
    for _, name in ipairs(kbOrder) do
        local v = d.keybinds and d.keybinds[name]
        if v then
            kbLines[#kbLines + 1] = string.format('    %s = "%s",', name, escapeStr(v))
        end
    end
    kbLines[#kbLines + 1] = "  },"
    local lines = {
        "return {",
        string.format("  fullscreen = %s,", d.fullscreen and "true" or "false"),
        string.format("  vsync = %d,", d.vsync),
        string.format("  masterVolume = %.4f,", d.masterVolume),
        string.format("  musicVolume = %.4f,", d.musicVolume),
        string.format("  sfxVolume = %.4f,", d.sfxVolume),
        string.format("  vfxVolume = %.4f,", d.vfxVolume),
        string.format("  screenShake = %.4f,", d.screenShake),
        string.format("  defaultAutoGun = %s,", d.defaultAutoGun and "true" or "false"),
        string.format("  mouseAimIdleSec = %.4f,", d.mouseAimIdleSec),
        string.format("  showCrosshair = %s,", d.showCrosshair and "true" or "false"),
        table.concat(kbLines, "\n"),
        "}",
    }
    love.filesystem.write("settings.lua", table.concat(lines, "\n"))
end

function Settings.setKeybind(action, storedKey)
    if not defaults.keybinds[action] or type(storedKey) ~= "string" then return end
    Settings.data.keybinds[action] = storedKey
end

function Settings.apply()
    local d = Settings.data
    love.window.setFullscreen(d.fullscreen, "desktop")
    love.window.setVSync(d.vsync)
    love.audio.setVolume(d.masterVolume)
end

--- Multiply when setting volume on music `Source` objects (effective level = master × this).
function Settings.getMusicVolumeMul()
    return Settings.data.musicVolume
end

--- Multiply when setting volume on SFX `Source` objects.
function Settings.getSfxVolumeMul()
    return Settings.data.sfxVolume
end

--- Multiply visual effect intensity (particles, floating numbers, etc.).
function Settings.getVfxMul()
    return Settings.data.vfxVolume
end

function Settings.getShowCrosshair()
    return Settings.data.showCrosshair
end

function Settings.resetKeybindsOnly()
    for bk, bv in pairs(defaults.keybinds) do
        Settings.data.keybinds[bk] = bv
    end
end

function Settings.resetAllToDefaults()
    for k, v in pairs(defaults) do
        if k == "keybinds" then
            Settings.data.keybinds = {}
            for bk, bv in pairs(defaults.keybinds) do
                Settings.data.keybinds[bk] = bv
            end
        else
            Settings.data[k] = v
        end
    end
end

function Settings.getScreenShakeScale()
    return Settings.data.screenShake
end

function Settings.getMouseAimIdleSec()
    return Settings.data.mouseAimIdleSec
end

function Settings.getDefaultAutoGun()
    return Settings.data.defaultAutoGun
end

-- Discrete row actions (used by settings UI)
local SHAKE_LEVELS = { 0, 0.4, 0.75, 1 }
local IDLE_LEVELS = { 0.5, 1.0, 1.5 }

local function nearestIndex(levels, v)
    local best, bi = math.huge, 1
    for i, x in ipairs(levels) do
        local d = math.abs(x - v)
        if d < best then best, bi = d, i end
    end
    return bi
end

function Settings.toggleFullscreen()
    Settings.data.fullscreen = not Settings.data.fullscreen
end

function Settings.toggleVsync()
    Settings.data.vsync = Settings.data.vsync == 1 and 0 or 1
end

function Settings.toggleDefaultAutoGun()
    Settings.data.defaultAutoGun = not Settings.data.defaultAutoGun
end

function Settings.toggleShowCrosshair()
    Settings.data.showCrosshair = not Settings.data.showCrosshair
end

function Settings.cycleScreenShake()
    local i = nearestIndex(SHAKE_LEVELS, Settings.data.screenShake)
    Settings.data.screenShake = SHAKE_LEVELS[(i % #SHAKE_LEVELS) + 1]
end

function Settings.cycleMouseAimIdle()
    local i = nearestIndex(IDLE_LEVELS, Settings.data.mouseAimIdleSec)
    Settings.data.mouseAimIdleSec = IDLE_LEVELS[(i % #IDLE_LEVELS) + 1]
end

function Settings.setVolumeKey(key, t)
    t = math.max(0, math.min(1, t))
    if key == "masterVolume" or key == "musicVolume" or key == "sfxVolume" or key == "vfxVolume" then
        Settings.data[key] = t
    end
end

function Settings.labelScreenShake()
    local s = Settings.data.screenShake
    if s <= 0 then return "Off" end
    if s < 0.5 then return "Low" end
    if s < 0.9 then return "Medium" end
    return "Full"
end

function Settings.labelMouseAimIdle()
    return string.format("%.1fs", Settings.data.mouseAimIdleSec)
end

return Settings
