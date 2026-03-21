--- Persisted user settings (save dir: settings.lua). Apply after load and on change.
local Settings = {}

local defaults = {
    fullscreen = false,
    vsync = 1,
    masterVolume = 1,
    musicVolume = 1,
    sfxVolume = 1,
    screenShake = 1,
    defaultAutoGun = true,
    mouseAimIdleSec = 1.0,
}

Settings.data = {}
for k, v in pairs(defaults) do
    Settings.data[k] = v
end

local function mergeLoaded(t)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do
        if defaults[k] ~= nil and type(v) == type(defaults[k]) then
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

function Settings.save()
    local d = Settings.data
    local lines = {
        "return {",
        string.format("  fullscreen = %s,", d.fullscreen and "true" or "false"),
        string.format("  vsync = %d,", d.vsync),
        string.format("  masterVolume = %.4f,", d.masterVolume),
        string.format("  musicVolume = %.4f,", d.musicVolume),
        string.format("  sfxVolume = %.4f,", d.sfxVolume),
        string.format("  screenShake = %.4f,", d.screenShake),
        string.format("  defaultAutoGun = %s,", d.defaultAutoGun and "true" or "false"),
        string.format("  mouseAimIdleSec = %.4f,", d.mouseAimIdleSec),
        "}",
    }
    love.filesystem.write("settings.lua", table.concat(lines, "\n"))
end

function Settings.apply()
    local d = Settings.data
    love.window.setFullscreen(d.fullscreen, "desktop")
    love.window.setVSync(d.vsync)
    love.audio.setVolume(d.masterVolume)
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
    if key == "masterVolume" or key == "musicVolume" or key == "sfxVolume" then
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
