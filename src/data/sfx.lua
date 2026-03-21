--[[
  Sound effect paths (relative to assets/sounds/). Used by src/systems/sfx.lua.
]]
local SfxData = {}

SfxData.paths = {
    shoot = "SoundPack/Weapons/shot_muffled.wav",
    reload = "SoundPack/Weapons/weapon_equip_short.wav",
    melee_swing = "SoundPack/Combat and Gore/swipe.wav",
    melee_hit = "SoundPack/Combat and Gore/punch.wav",
    dash = "SoundPack/Other/whoosh_1.wav",
    jump = "SoundPack/Retro/jump_short.wav",
    hit_enemy = "Impact/impactMetal_light_002.ogg",
    hit_wall = "Impact/impactGeneric_light_001.ogg",
    ricochet = "Impact/impactMetal_light_001.ogg",
    explosion = "SoundPack/Retro/explosion_small.wav",
    hurt = "SoundPack/Retro/hurt.wav",
    pickup_gold = "SoundPack/Items/coin_collect.wav",
    pickup_xp = "SoundPack/Items/coins_gather_small.wav",
    pickup_health = "Impact/impactGeneric_light_002.ogg",
    door_open = "RPG/doorOpen_1.ogg",
    level_up = "SoundPack/Musical Effects/grand_piano_chime_positive.wav",
    ui_confirm = "Interface/toggle_001.ogg",
    -- Ultimate
    ult_activate = "SoundPack/Musical Effects/brass_mystery.wav",
    ult_shot = "SoundPack/Weapons/shot_muffled.wav",
    ult_explosion = "SoundPack/Retro/explosion_large.wav",
    ult_ready = "SoundPack/Musical Effects/brass_chime_positive.wav",
    -- Saloon / shop (optional hooks)
    casino_shuffle = "Casino/card-shuffle.ogg",
    shop_buy = "Casino/chip-lay-1.ogg",
}

return SfxData
