-- Impact visual effects: sheet-driven one-shot animations with named effect ids.

local Settings = require("src.systems.settings")

local ImpactFX = {}

local DEFAULT_FRAME_SIZE = 64
local DEFAULT_COLS = 8
local DEFAULT_BLEND_MODE = "add"
local DEFAULT_ALPHA_MODE = "alphamultiply"

local SHEETS = {
    pack1a = {
        path = "assets/Retro Impact Effect Pack ALL/RetroImpactEffectPack1A.png",
        frame_size = DEFAULT_FRAME_SIZE,
        cols = DEFAULT_COLS,
    },
    pack3a = {
        path = "assets/Retro Impact Effect Pack ALL/RetroImpactEffectPack3A.png",
        frame_size = DEFAULT_FRAME_SIZE,
        cols = DEFAULT_COLS,
    },
}

local EFFECTS = {
    hit_enemy = {
        sheet_id = "pack1a",
        row = 1,
        start_frame = 1,
        end_frame = 8,
        fps = 18,
        scale = 0.5,
        blend_mode = DEFAULT_BLEND_MODE,
        alpha_mode = DEFAULT_ALPHA_MODE,
    },
    hit_wall = {
        sheet_id = "pack1a",
        row = 4,
        start_frame = 1,
        end_frame = 8,
        fps = 18,
        scale = 0.5,
        blend_mode = DEFAULT_BLEND_MODE,
        alpha_mode = DEFAULT_ALPHA_MODE,
    },
    melee = {
        sheet_id = "pack1a",
        row = 8,
        start_frame = 1,
        end_frame = 8,
        fps = 18,
        scale = 0.95,
        blend_mode = DEFAULT_BLEND_MODE,
        alpha_mode = DEFAULT_ALPHA_MODE,
        rotation_mode = "follow_angle",
    },
    explosion_small = {
        sheet_id = "pack3a",
        row = 9,
        start_frame = 1,
        end_frame = 5,
        fps = 18,
        scale = 0.98,
        blend_mode = DEFAULT_BLEND_MODE,
        alpha_mode = DEFAULT_ALPHA_MODE,
        recommended_radius = 44,
        recommended_sfx = "explosion",
        recommended_shake = { duration = 0.09, intensity = 2.0 },
    },
    explosion_medium = {
        sheet_id = "pack3a",
        row = 10,
        start_frame = 1,
        end_frame = 6,
        fps = 17,
        scale = 1.18,
        blend_mode = DEFAULT_BLEND_MODE,
        alpha_mode = DEFAULT_ALPHA_MODE,
        recommended_radius = 60,
        recommended_sfx = "explosion",
        recommended_shake = { duration = 0.13, intensity = 2.8 },
    },
    explosion_large = {
        sheet_id = "pack3a",
        row = 11,
        start_frame = 1,
        end_frame = 6,
        fps = 16,
        scale = 1.42,
        blend_mode = DEFAULT_BLEND_MODE,
        alpha_mode = DEFAULT_ALPHA_MODE,
        recommended_radius = 78,
        recommended_sfx = "ult_explosion",
        recommended_shake = { duration = 0.18, intensity = 3.8 },
    },
    muzzle_explosive_shotgun = {
        sheet_id = "pack3a",
        row = 7,
        start_frame = 1,
        end_frame = 6,
        fps = 22,
        scale = 1.05,
        blend_mode = DEFAULT_BLEND_MODE,
        alpha_mode = DEFAULT_ALPHA_MODE,
        rotation_mode = "follow_angle",
        lifetime_jitter = 0.015,
    },
    --- Single PNG (e.g. commission muzzle); origin toward grip so flash extends along aim.
    muzzle_colt45 = {
        image_path = "assets/vfx/muzzle_colt45.png",
        start_frame = 1,
        end_frame = 1,
        fps = 20,
        scale = 0.44,
        blend_mode = DEFAULT_BLEND_MODE,
        alpha_mode = DEFAULT_ALPHA_MODE,
        rotation_mode = "follow_angle",
        origin_x_frac = 0.2,
        origin_y_frac = 0.5,
        lifetime_jitter = 0.02,
    },
}

local sheetCache = {}
local standaloneImageCache = {}
local active = {}

local function loadStandaloneImage(path)
    local cached = standaloneImageCache[path]
    if cached then
        return cached
    end
    local image = love.graphics.newImage(path)
    image:setFilter("nearest", "nearest")
    standaloneImageCache[path] = image
    return image
end

local function loadSheet(sheet_id)
    local cached = sheetCache[sheet_id]
    if cached then
        return cached
    end

    local spec = SHEETS[sheet_id]
    if not spec then
        error("Unknown impact FX sheet id: " .. tostring(sheet_id))
    end

    local image = love.graphics.newImage(spec.path)
    image:setFilter("nearest", "nearest")
    local sw, sh = image:getDimensions()
    local rows = math.floor(sh / spec.frame_size)
    local quads = {}
    for row = 1, rows do
        quads[row] = {}
        for col = 1, spec.cols do
            quads[row][col] = love.graphics.newQuad(
                (col - 1) * spec.frame_size,
                (row - 1) * spec.frame_size,
                spec.frame_size,
                spec.frame_size,
                sw,
                sh
            )
        end
    end

    cached = {
        image = image,
        frame_size = spec.frame_size,
        cols = spec.cols,
        quads = quads,
    }
    sheetCache[sheet_id] = cached
    return cached
end

function ImpactFX.getDefinition(effect_id)
    return EFFECTS[effect_id or "hit_enemy"] or EFFECTS.hit_enemy
end

function ImpactFX.spawn(cx, cy, effect_id, opts, legacy_angle)
    local effect = ImpactFX.getDefinition(effect_id)
    local options = opts
    if type(options) ~= "table" then
        options = {
            scale_mul = opts,
            angle = legacy_angle,
        }
    end

    local scale_mul = options.scale_mul or 1
    local jitter = effect.lifetime_jitter or 0
    local lifetime_offset = 0
    if jitter > 0 then
        lifetime_offset = (love.math.random() * 2 - 1) * jitter
    end

    local frame_end = effect.end_frame or 1
    if effect.sheet_id and not effect.image_path then
        frame_end = effect.end_frame or loadSheet(effect.sheet_id).cols
    end

    active[#active + 1] = {
        x = cx,
        y = cy,
        effect_id = effect_id or "hit_enemy",
        frame = effect.start_frame or 1,
        timer = 0,
        fps = effect.fps or 18,
        scale = (effect.scale or 1) * scale_mul,
        angle = options.angle or 0,
        flip_x = options.flip_x and -1 or 1,
        flip_y = options.flip_y and -1 or 1,
        tint = options.tint,
        frame_start = effect.start_frame or 1,
        frame_end = frame_end,
        blend_mode = effect.blend_mode or DEFAULT_BLEND_MODE,
        alpha_mode = effect.alpha_mode or DEFAULT_ALPHA_MODE,
        sheet_id = effect.sheet_id,
        rotation_mode = effect.rotation_mode,
        lifetime_offset = lifetime_offset,
        origin_x_frac = effect.origin_x_frac,
        origin_y_frac = effect.origin_y_frac,
    }
end

function ImpactFX.update(dt)
    local i = 1
    while i <= #active do
        local fx = active[i]
        local interval = 1 / math.max(1, fx.fps)
        fx.timer = fx.timer + dt + fx.lifetime_offset
        fx.lifetime_offset = 0
        while fx.timer >= interval do
            fx.timer = fx.timer - interval
            fx.frame = fx.frame + 1
        end
        if fx.frame > fx.frame_end then
            table.remove(active, i)
        else
            i = i + 1
        end
    end
end

function ImpactFX.draw()
    if #active == 0 then
        return
    end

    local vfxMul = Settings.getVfxMul()
    if vfxMul <= 0.001 then
        return
    end

    local prevBlendMode, prevAlphaMode = love.graphics.getBlendMode()
    local currentBlendMode = nil
    local currentAlphaMode = nil

    for _, fx in ipairs(active) do
        local def = ImpactFX.getDefinition(fx.effect_id)
        if def.image_path then
            local img = loadStandaloneImage(def.image_path)
            local iw, ih = img:getDimensions()
            local oxf = fx.origin_x_frac ~= nil and fx.origin_x_frac or (def.origin_x_frac or 0.5)
            local oyf = fx.origin_y_frac ~= nil and fx.origin_y_frac or (def.origin_y_frac or 0.5)
            local ox = iw * oxf
            local oy = ih * oyf
            if currentBlendMode ~= fx.blend_mode or currentAlphaMode ~= fx.alpha_mode then
                love.graphics.setBlendMode(fx.blend_mode, fx.alpha_mode)
                currentBlendMode = fx.blend_mode
                currentAlphaMode = fx.alpha_mode
            end
            local tint = fx.tint
            if tint then
                love.graphics.setColor(tint[1] or 1, tint[2] or 1, tint[3] or 1, (tint[4] or 1) * vfxMul)
            else
                love.graphics.setColor(1, 1, 1, vfxMul)
            end
            local sx = fx.scale * fx.flip_x
            local sy = fx.scale * fx.flip_y
            love.graphics.draw(
                img,
                fx.x,
                fx.y,
                fx.rotation_mode == "follow_angle" and fx.angle or 0,
                sx,
                sy,
                ox,
                oy
            )
        else
            local sheet = loadSheet(fx.sheet_id)
            local q = sheet.quads[def.row] and sheet.quads[def.row][fx.frame]
            if q then
                if currentBlendMode ~= fx.blend_mode or currentAlphaMode ~= fx.alpha_mode then
                    love.graphics.setBlendMode(fx.blend_mode, fx.alpha_mode)
                    currentBlendMode = fx.blend_mode
                    currentAlphaMode = fx.alpha_mode
                end

                local tint = fx.tint
                if tint then
                    love.graphics.setColor(tint[1] or 1, tint[2] or 1, tint[3] or 1, (tint[4] or 1) * vfxMul)
                else
                    love.graphics.setColor(1, 1, 1, vfxMul)
                end

                local sx = fx.scale * fx.flip_x
                local sy = fx.scale * fx.flip_y
                love.graphics.draw(
                    sheet.image,
                    q,
                    fx.x,
                    fx.y,
                    fx.rotation_mode == "follow_angle" and fx.angle or 0,
                    sx,
                    sy,
                    sheet.frame_size / 2,
                    sheet.frame_size / 2
                )
            end
        end
    end

    love.graphics.setBlendMode(prevBlendMode, prevAlphaMode)
    love.graphics.setColor(1, 1, 1)
end

function ImpactFX.clear()
    active = {}
end

return ImpactFX
