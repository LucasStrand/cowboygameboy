local Gamestate = require("lib.hump.gamestate")
local Font = require("src.ui.font")
local Cursor = require("src.ui.cursor")
local Settings = require("src.systems.settings")

local gameover = {}

local FIN_MUSIC = "assets/music/saloon/Tipsy Tumbleweed Rag - Honky Tonk.wav"
local AUTO_ADVANCE_DELAY = 1.35

local grayscaleCode = [[
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
    {
        vec4 c = Texel(tex, tc) * color;
        float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
        return vec4(g, g, g, c.a);
    }
]]

local timer = 0
local fonts = {}
local musicSource = nil
local scratchXs = {}
local bgSnapshot = nil
local grayscaleShader = nil
local nextArgs = nil
local sequenceDuration = 0

local function getGrayscaleShader()
    if not grayscaleShader then
        local ok, shader = pcall(love.graphics.newShader, grayscaleCode)
        if ok then
            grayscaleShader = shader
        end
    end
    return grayscaleShader
end

local function ensureFonts()
    if next(fonts) then
        return
    end
    fonts = {
        title = Font.new(48),
        subtitle = Font.new(18),
        prompt = Font.new(12),
        default = Font.new(12),
    }
end

local function mono(v)
    v = math.max(0, math.min(1, v))
    return v * 0.94, v * 0.92, v * 0.88
end

local function stopFinMusic()
    if musicSource then
        musicSource:stop()
        musicSource = nil
    end
end

local function releaseSnapshot()
    if bgSnapshot then
        bgSnapshot:release()
        bgSnapshot = nil
    end
end

local function goToRecap()
    if not nextArgs then
        return
    end
    local args = nextArgs
    nextArgs = nil
    local recap = require("src.states.run_recap")
    Gamestate.switch(recap, args)
end

function gameover:enter(_, playerStats)
    ensureFonts()
    Cursor.setDefault()
    playerStats = playerStats or {}

    releaseSnapshot()
    bgSnapshot = playerStats.backgroundImage
    nextArgs = playerStats
    timer = 0
    sequenceDuration = 2.8

    for i = 1, 6 do
        scratchXs[i] = love.math.random() * GAME_WIDTH
    end

    stopFinMusic()
    local ok, src = pcall(love.audio.newSource, FIN_MUSIC, "stream")
    if ok and src then
        src:setLooping(true)
        src:setVolume(Settings.getMusicVolumeMul())
        musicSource = src
        musicSource:play()
    end
end

function gameover:leave()
    stopFinMusic()
    releaseSnapshot()
    nextArgs = nil
end

function gameover:update(dt)
    timer = timer + dt
    if musicSource then
        musicSource:setVolume(Settings.getMusicVolumeMul())
    end

    for i = 1, #scratchXs do
        scratchXs[i] = scratchXs[i] + (i % 2 == 0 and 18 or -12) * dt
        if scratchXs[i] < -4 then scratchXs[i] = GAME_WIDTH + 4 end
        if scratchXs[i] > GAME_WIDTH + 4 then scratchXs[i] = -4 end
    end

    if timer >= sequenceDuration + AUTO_ADVANCE_DELAY then
        goToRecap()
    end
end

function gameover:keypressed(key)
    if key == "escape" then
        local menu = require("src.states.menu")
        Gamestate.switch(menu)
        return
    end

    if key == "return" or key == "space" then
        if timer < sequenceDuration then
            timer = sequenceDuration
            return
        end
        goToRecap()
    end
end

function gameover:draw()
    ensureFonts()

    local screenW = GAME_WIDTH
    local screenH = GAME_HEIGHT
    local flick = 0.78 + 0.1 * math.sin(timer * 11.3) + 0.06 * math.sin(timer * 23.7 + 1.7)
    if love.math.random() < 0.04 then
        flick = flick * love.math.random(0.45, 0.92)
    end

    local sh = getGrayscaleShader()
    if bgSnapshot and sh then
        love.graphics.setShader(sh)
        love.graphics.setColor(flick, flick, flick, 1)
        love.graphics.draw(bgSnapshot, 0, 0, 0, screenW / bgSnapshot:getWidth(), screenH / bgSnapshot:getHeight())
        love.graphics.setShader()
    elseif bgSnapshot then
        love.graphics.setColor(flick * 0.85, flick * 0.83, flick * 0.8, 1)
        love.graphics.draw(bgSnapshot, 0, 0, 0, screenW / bgSnapshot:getWidth(), screenH / bgSnapshot:getHeight())
    else
        love.graphics.setColor(0.03, 0.03, 0.03, 1)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)
    end

    love.graphics.setColor(0, 0, 0, 0.38)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)

    local titleAlpha = math.min(1, timer / 1.2)
    love.graphics.setFont(fonts.title)
    love.graphics.setColor(mono(0.92 * titleAlpha))
    love.graphics.printf("THE END", 0, screenH * 0.24, screenW, "center")

    local subtitleAlpha = math.max(0, math.min(1, (timer - 0.35) / 1.0))
    love.graphics.setFont(fonts.subtitle)
    love.graphics.setColor(mono(0.72 * subtitleAlpha))
    love.graphics.printf("A SIX CHAMBERS TRAGEDY", 0, screenH * 0.24 + 58, screenW, "center")

    for i = 1, #scratchXs do
        local x = scratchXs[i]
        local a = (0.04 + 0.05 * (i % 3)) * flick
        love.graphics.setColor(0.85, 0.85, 0.82, a)
        love.graphics.line(x, 0, x + (i % 2 == 0 and 1.5 or -1), screenH)
    end

    if timer >= sequenceDuration then
        love.graphics.setFont(fonts.prompt)
        love.graphics.setColor(mono(0.66))
        love.graphics.printf("PRESS ENTER FOR RECAP   |   ESC FOR MENU", 0, screenH * 0.9, screenW, "center")
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(fonts.default)
end

return gameover
