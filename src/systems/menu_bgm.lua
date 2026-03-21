--[[
  Shared menu / boot music: one looping Source from BootIntro.menuMusicPath.
  Started from boot_intro; menu only updates volume. Stopped when leaving menu for gameplay.
]]

local Settings = require("src.systems.settings")

local MenuBgm = {}
local source = nil
local currentPath = nil

function MenuBgm.play(path)
    if not path or path == "" then
        return
    end
    if currentPath == path and source and source:isPlaying() then
        MenuBgm.updateVolume()
        return
    end
    MenuBgm.stop()
    local ok, src = pcall(love.audio.newSource, path, "stream")
    if not ok or not src then
        return
    end
    src:setLooping(true)
    src:setVolume(Settings.getMusicVolumeMul())
    src:play()
    source = src
    currentPath = path
end

function MenuBgm.updateVolume()
    if source then
        source:setVolume(Settings.getMusicVolumeMul())
    end
end

function MenuBgm.stop()
    if source then
        source:stop()
        source = nil
    end
    currentPath = nil
end

function MenuBgm.isPlaying()
    return source and source:isPlaying()
end

return MenuBgm
