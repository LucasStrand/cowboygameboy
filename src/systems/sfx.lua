local Settings = require("src.systems.settings")
local SfxData = require("src.data.sfx")

local Sfx = {}
local prefix = "assets/sounds/"
--- Global gain so most cues sit lower in the mix (user SFX slider still applies on top).
local SFX_BASE_GAIN = 0.48

--- Play a one-shot by logical id from src/data/sfx.lua. opts.volume multiplies the cue (default 1).
--- opts.pitch sets playback pitch; opts.no_variation skips automatic jitter for ids in SfxData.play_variation.
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
    local pitch = opts.pitch
    if pitch == nil and not opts.no_variation then
        local var = SfxData.play_variation and SfxData.play_variation[id]
        if var then
            local vm = var.volume or 0.08
            local pm = var.pitch or 0.06
            mul = mul * (1 + (love.math.random() - 0.5) * 2 * vm)
            pitch = 1 + (love.math.random() - 0.5) * 2 * pm
        end
    end
    if type(pitch) == "number" and pitch ~= 1 then
        src:setPitch(math.max(0.35, math.min(2.2, pitch)))
    end
    src:setVolume(math.max(0, mul * Settings.getSfxVolumeMul() * SFX_BASE_GAIN))
    src:play()
end

return Sfx
