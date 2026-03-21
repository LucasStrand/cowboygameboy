--[[
  Gameplay adaptive music: one looping file per intensity tier (horizontal adaptation).
  Tune paths without touching MusicDirector logic.
]]
local Layers = {}

Layers.levels = {
    "explore",
    "combat",
    "combat_high",
    "elite",
    "boss",
}

--- logical id -> asset path (streaming WAV/OGG)
--- Do not use `assets/music/main/` here — that track is reserved for menu/boot (see src/data/boot_intro.lua).
Layers.paths = {
    explore = "assets/music/relax/Last Sunset in 16 Bits.wav",
    combat = "assets/music/tempo/dust.wav",
    combat_high = "assets/music/tempo/Dead Man's Reload.wav",
    elite = "assets/music/tempo/Dead Man's Reload.wav",
    boss = "assets/music/boss/Iron Dust Showdown.wav",
}

--- Enemies alive + pending spawns at or above this → combat_high (extreme pressure only).
Layers.combatHighEnemyCount = 20

--- Hysteresis: seconds the instant tier must stay stable before we actually switch tracks.
--- High values = fewer crossfades, more time on each loop before stepping up/down.
Layers.hysteresisUp = 1.6
Layers.hysteresisDown = 4.25

--- Crossfade when switching loops.
Layers.crossfadeDuration = 1.5

--- Extra music attenuation when HP fraction is below this (danger zone).
Layers.dangerHpThreshold = 0.25

--- Heartbeat SFX interval at max stress (seconds); scales up toward threshold HP.
Layers.heartbeatIntervalMin = 0.55
Layers.heartbeatIntervalMax = 0.95

return Layers
