local Settings = require("src.systems.settings")
local SfxData = require("src.data.sfx")

local Sfx = {}
local prefix = "assets/sounds/"
--- Global gain so most cues sit lower in the mix (user SFX slider still applies on top).
local SFX_BASE_GAIN = 0.48

--- Play a one-shot by logical id from src/data/sfx.lua. opts.volume multiplies the cue (default 1).
function Sfx.play(id, opts)
    opts = opts or {}
    local rel = SfxData.paths and SfxData.paths[id]
    if not rel or rel == "" then
        return
    end
    local path = prefix .. rel
    local ok, src = pcall(love.audio.newSource, path, "static")
    if not ok or not src then
        return
    end
    local mul = opts.volume ~= nil and opts.volume or 1
    src:setVolume(mul * Settings.getSfxVolumeMul() * SFX_BASE_GAIN)
    src:play()
end

return Sfx
