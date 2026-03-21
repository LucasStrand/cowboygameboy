--[[
  Fullscreen multiply lighting: ambient + point lights (screen-space, matches camera + shake).
]]
local Vision = require("src.data.vision")

local WorldLighting = {}

local worldCanvas
local lightingShader

-- Tune: dark fog outside vision; warm pool at player; weak sky fill
local AMBIENT_RGB = { 0.07, 0.075, 0.095 }
local PLAYER_LIGHT_RGB = { 1.12, 0.98, 0.82 }
local PLAYER_LIGHT_RADIUS = Vision.VISION_SCREEN_RADIUS
local FILL_LIGHT_RGB = { 0.28, 0.38, 0.55 }
local FILL_LIGHT_RADIUS = 520
local FILL_LIGHT_STRENGTH = 0.09
--- World Y offset above camera center for soft “sky” fill
local FILL_WORLD_OFFSET_Y = -260

--- Max map-placed point lights (lanterns, campfires); positions normalized 0–1.
local MAX_STATIC_LIGHTS = 4

local shaderCode = [[
    extern vec3 ambientRgb;
    extern number screenWidth;
    extern number screenHeight;
    extern vec2 lightPos0;
    extern vec3 lightColor0;
    extern number lightRadius0;
    extern vec2 lightForward0;
    extern vec2 lightPos1;
    extern vec3 lightColor1;
    extern number lightRadius1;
    extern number fillStrength;
    extern number staticCount;
    extern vec2 staticPos0;
    extern vec2 staticPos1;
    extern vec2 staticPos2;
    extern vec2 staticPos3;
    extern vec3 staticRgb0;
    extern vec3 staticRgb1;
    extern vec3 staticRgb2;
    extern vec3 staticRgb3;
    extern number staticRad0;
    extern number staticRad1;
    extern number staticRad2;
    extern number staticRad3;

    /* Sharp falloff: stays bright near the player, dark quickly outside “vision” */
    float attenVision(vec2 pixel, vec2 lp, float r)
    {
        float d = length(pixel - lp);
        r = max(r, 1.0);
        float t = d / r;
        return 1.0 / (1.0 + pow(t * 1.9, 2.75));
    }

    /* Ellipse: longer along lightForward0 (aim), tighter across — matches Vision.playerLightMetric */
    float attenPlayerEllipse(vec2 pixel, vec2 lp, float r, vec2 lightFwd)
    {
        vec2 d = pixel - lp;
        float lenF = length(lightFwd);
        if (lenF < 0.02) {
            return attenVision(pixel, lp, r);
        }
        vec2 f = lightFwd / lenF;
        vec2 u = vec2(-f.y, f.x);
        float ax = dot(d, f);
        float ay = dot(d, u);
        float rx = r * 1.38;
        float ry = r * 0.82;
        float te = length(vec2(ax / rx, ay / ry));
        return 1.0 / (1.0 + pow(te * 1.9, 2.75));
    }

    float attenSoft(vec2 pixel, vec2 lp, float r)
    {
        float d = length(pixel - lp);
        r = max(r, 1.0);
        return 1.0 / (1.0 + pow(d / r, 2.0));
    }

    float attenStatic(vec2 pixel, vec2 lp, float r)
    {
        float d = length(pixel - lp);
        r = max(r, 1.0);
        float t = d / r;
        return 1.0 / (1.0 + pow(t * 1.65, 2.4));
    }

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
    {
        vec4 texel = Texel(tex, tc);
        vec2 pixel = tc * vec2(screenWidth, screenHeight);
        vec2 lp0 = lightPos0 * vec2(screenWidth, screenHeight);
        vec2 lp1 = lightPos1 * vec2(screenWidth, screenHeight);
        float a0 = attenPlayerEllipse(pixel, lp0, lightRadius0, lightForward0);
        float a1 = attenSoft(pixel, lp1, lightRadius1);
        vec3 rgb = ambientRgb;
        rgb = rgb + lightColor0 * a0;
        rgb = rgb + lightColor1 * fillStrength * a1;
        vec2 sp0 = staticPos0 * vec2(screenWidth, screenHeight);
        vec2 sp1 = staticPos1 * vec2(screenWidth, screenHeight);
        vec2 sp2 = staticPos2 * vec2(screenWidth, screenHeight);
        vec2 sp3 = staticPos3 * vec2(screenWidth, screenHeight);
        if (staticCount > 0.5) rgb = rgb + staticRgb0 * attenStatic(pixel, sp0, staticRad0);
        if (staticCount > 1.5) rgb = rgb + staticRgb1 * attenStatic(pixel, sp1, staticRad1);
        if (staticCount > 2.5) rgb = rgb + staticRgb2 * attenStatic(pixel, sp2, staticRad2);
        if (staticCount > 3.5) rgb = rgb + staticRgb3 * attenStatic(pixel, sp3, staticRad3);
        rgb.r = min(rgb.r, 1.5);
        rgb.g = min(rgb.g, 1.5);
        rgb.b = min(rgb.b, 1.5);
        vec3 lit = texel.rgb * rgb;
        /* Cool dusty fog when total light is low (outside vision) */
        float bright = dot(rgb, vec3(0.299, 0.587, 0.114));
        float fog = 1.0 - smoothstep(0.06, 0.32, bright);
        vec3 fogTint = vec3(0.68, 0.74, 1.0);
        lit = mix(lit, lit * fogTint, fog * 0.38);
        return vec4(lit, texel.a);
    }
]]

local function ensureShader()
    if lightingShader then return true end
    local ok, sh = pcall(love.graphics.newShader, shaderCode)
    if ok and sh then
        lightingShader = sh
        return true
    end
    return false
end

function WorldLighting.invalidate()
    if worldCanvas then
        worldCanvas:release()
        worldCanvas = nil
    end
    if lightingShader then
        lightingShader:release()
        lightingShader = nil
    end
end

function WorldLighting.ensure()
    if worldCanvas
        and worldCanvas:getWidth() == GAME_WIDTH
        and worldCanvas:getHeight() == GAME_HEIGHT then
        return
    end
    WorldLighting.invalidate()
    worldCanvas = love.graphics.newCanvas(GAME_WIDTH, GAME_HEIGHT)
    worldCanvas:setFilter("linear", "linear")
end

function WorldLighting.getWorldCanvas()
    WorldLighting.ensure()
    return worldCanvas
end

--- Draw `worldCanvas` to the active canvas with lighting. Falls back to untextured draw if shader fails.
--- World-space map lights → screen-normalized pack for the shader (max MAX_STATIC_LIGHTS).
function WorldLighting.computeStaticLightPack(camera, staticLights, shakeX, shakeY)
    shakeX = shakeX or 0
    shakeY = shakeY or 0
    local pack = {}
    for _, L in ipairs(staticLights or {}) do
        if #pack >= MAX_STATIC_LIGHTS then
            break
        end
        local wx = L.x or 0
        local wy = L.y or 0
        local lsx, lsy = camera:cameraCoords(wx, wy, 0, 0, GAME_WIDTH, GAME_HEIGHT)
        lsx = lsx + shakeX
        lsy = lsy + shakeY
        local rgb = L.rgb or { 0.92, 0.75, 0.48 }
        local rad = L.radius or 210
        table.insert(pack, {
            pos = { lsx / GAME_WIDTH, lsy / GAME_HEIGHT },
            rgb = rgb,
            radius = rad,
        })
    end
    return pack
end

local function sendStaticLightsUniforms(pack)
    local n = math.min(MAX_STATIC_LIGHTS, #pack)
    lightingShader:send("staticCount", n)
    for i = 1, MAX_STATIC_LIGHTS do
        local L = pack[i]
        local suffix = i - 1
        if L then
            lightingShader:send("staticPos" .. suffix, L.pos)
            lightingShader:send("staticRgb" .. suffix, { L.rgb[1], L.rgb[2], L.rgb[3] })
            lightingShader:send("staticRad" .. suffix, L.radius)
        else
            lightingShader:send("staticPos" .. suffix, { -1, -1 })
            lightingShader:send("staticRgb" .. suffix, { 0, 0, 0 })
            lightingShader:send("staticRad" .. suffix, 1)
        end
    end
end

function WorldLighting.apply(worldTex, opts)
    opts = opts or {}
    local amb = opts.ambientRgb or AMBIENT_RGB
    local pRgb = opts.playerRgb or PLAYER_LIGHT_RGB
    local pRad = opts.playerRadius or PLAYER_LIGHT_RADIUS
    local fRgb = opts.fillRgb or FILL_LIGHT_RGB
    local fRad = opts.fillRadius or FILL_LIGHT_RADIUS
    local fStr = opts.fillStrength or FILL_LIGHT_STRENGTH

    local lp0 = opts.lightPos0 or { 0.5, 0.55 }
    local lp1 = opts.lightPos1 or { 0.5, 0.2 }
    local lf0 = opts.lightForward0 or { 1, 0 }
    local staticPack = opts.staticLightPack or {}

    if ensureShader() then
        lightingShader:send("ambientRgb", { amb[1], amb[2], amb[3] })
        lightingShader:send("screenWidth", GAME_WIDTH)
        lightingShader:send("screenHeight", GAME_HEIGHT)
        lightingShader:send("lightPos0", lp0)
        lightingShader:send("lightColor0", { pRgb[1], pRgb[2], pRgb[3] })
        lightingShader:send("lightRadius0", pRad)
        lightingShader:send("lightForward0", lf0)
        lightingShader:send("lightPos1", lp1)
        lightingShader:send("lightColor1", { fRgb[1], fRgb[2], fRgb[3] })
        lightingShader:send("lightRadius1", fRad)
        lightingShader:send("fillStrength", fStr)
        sendStaticLightsUniforms(staticPack)
        love.graphics.setShader(lightingShader)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(worldTex, 0, 0)
    love.graphics.setShader()
end

--- Screen-space light positions (normalized 0–1) from camera + optional screen shake.
function WorldLighting.computeLightPositions(camera, player, shakeX, shakeY)
    shakeX = shakeX or 0
    shakeY = shakeY or 0
    local px = player.x + player.w * 0.5
    local py = player.y + player.h * 0.5
    local lsx, lsy = camera:cameraCoords(px, py, 0, 0, GAME_WIDTH, GAME_HEIGHT)
    lsx = lsx + shakeX
    lsy = lsy + shakeY
    local camX, camY = camera:position()
    local mx, my = camera:cameraCoords(camX, camY + FILL_WORLD_OFFSET_Y, 0, 0, GAME_WIDTH, GAME_HEIGHT)
    mx = mx + shakeX
    my = my + shakeY
    local fx, fy = Vision.computeScreenForward(player, camera, shakeX, shakeY)
    return {
        lightPos0 = { lsx / GAME_WIDTH, lsy / GAME_HEIGHT },
        lightPos1 = { mx / GAME_WIDTH, my / GAME_HEIGHT },
        lightForward0 = { fx, fy },
    }
end

WorldLighting.MAX_STATIC_LIGHTS = MAX_STATIC_LIGHTS

return WorldLighting
