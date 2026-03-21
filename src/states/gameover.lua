local Gamestate = require("lib.hump.gamestate")
local Font = require("src.ui.font")
local Cursor = require("src.ui.cursor")
local Settings = require("src.systems.settings")

local gameover = {}

--- Outro BGM (replace path if you change the cue).
local FIN_MUSIC = "assets/music/saloon/Tipsy Tumbleweed Rag - Honky Tonk.wav"

local grayscaleCode = [[
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
    {
        vec4 c = Texel(tex, tc) * color;
        float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
        return vec4(g, g, g, c.a);
    }
]]

local stats = {}
local timer = 0
local fonts = {}
local musicSource = nil
local scratchXs = {}
local bgSnapshot = nil
local grayscaleShader = nil

local function getGrayscaleShader()
    if not grayscaleShader then
        local ok, sh = pcall(love.graphics.newShader, grayscaleCode)
        if ok then
            grayscaleShader = sh
        end
    end
    return grayscaleShader
end

local function computeScore(s)
    local gold = s.gold or 0
    local rooms = s.roomsCleared or 0
    local level = s.level or 1
    local perks = s.perksCount or 0
    return gold + rooms * 100 + level * 50 + perks * 75
end

--- Map 0–1 brightness to monochrome foreground (slightly warm “silver” nitrate).
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

function gameover:enter(_, playerStats)
    playerStats = playerStats or {}
    releaseSnapshot()
    bgSnapshot = playerStats.backgroundImage

    stats = {
        level = playerStats.level,
        roomsCleared = playerStats.roomsCleared,
        gold = playerStats.gold,
        perksCount = playerStats.perksCount,
    }

    timer = 0
    fonts.title = Font.new(72)
    fonts.score = Font.new(28)
    fonts.detail = Font.new(18)
    fonts.prompt = Font.new(18)
    fonts.default = Font.new(12)
    Cursor.setDefault()

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
end

function gameover:keypressed(key)
    if timer > 1 then
        if key == "return" or key == "space" then
            local game = require("src.states.game")
            -- Same 3→2→1 intro as “Start game” from the menu (not instant gameplay).
            Gamestate.switch(game, { introCountdown = true })
        end
        if key == "escape" then
            local menu = require("src.states.menu")
            Gamestate.switch(menu)
        end
    end
end

function gameover:draw()
    local screenW = GAME_WIDTH
    local screenH = GAME_HEIGHT

    local flick = 0.78 + 0.1 * math.sin(timer * 11.3) + 0.06 * math.sin(timer * 23.7 + 1.7)
    if love.math.random() < 0.04 then
        flick = flick * love.math.random(0.45, 0.92)
    end
    if love.math.random() < 0.012 then
        flick = flick * 0.35
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
        local bg = 0.02 * flick
        love.graphics.setColor(bg, bg * 0.98, bg * 0.96, 1)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)
    end

    -- Light global dim so text reads; still see the level
    love.graphics.setColor(0, 0, 0, 0.12 * (0.5 + 0.5 * flick))
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)

    local weave = 0.5 + 0.5 * math.sin(timer * 6.1)
    love.graphics.setColor(0, 0, 0, 0.14 * weave)
    love.graphics.rectangle("fill", 0, 0, screenW, 12)
    love.graphics.rectangle("fill", 0, screenH - 16, screenW, 16)

    local score = computeScore(stats)

    local titleBright = 0.88 * flick
    local tr, tg, tb = mono(titleBright)
    love.graphics.setColor(tr, tg, tb)
    love.graphics.setFont(fonts.title)
    love.graphics.printf("FIN", 0, screenH * 0.26, screenW, "center")

    local sr, sg, sb = mono(0.72 * flick)
    love.graphics.setColor(sr, sg, sb)
    love.graphics.setFont(fonts.score)
    love.graphics.printf(string.format("Score: %d", score), 0, screenH * 0.42, screenW, "center")

    local dr, dg, db = mono(0.48 * flick)
    love.graphics.setColor(dr, dg, db)
    love.graphics.setFont(fonts.detail)
    local y = screenH * 0.52
    love.graphics.printf(
        string.format("Lv %d  ·  Rooms %d  ·  $%d  ·  Perks %d",
            stats.level or 1, stats.roomsCleared or 0, stats.gold or 0, stats.perksCount or 0),
        0, y, screenW, "center")

    love.graphics.setLineWidth(1)
    for i = 1, #scratchXs do
        local x = scratchXs[i]
        local a = (0.04 + 0.05 * (i % 3)) * flick
        love.graphics.setColor(0.85, 0.85, 0.82, a)
        love.graphics.line(x, 0, x + (i % 2 == 0 and 1.5 or -1), screenH)
    end

    for _ = 1, 55 do
        local gx = love.math.random(0, screenW)
        local gy = love.math.random(0, screenH)
        local g = love.math.random() < 0.5 and 0.12 or -0.1
        local br = math.max(0, math.min(1, flick + g))
        local r, gcol, b = mono(br * 0.25)
        love.graphics.setColor(r, gcol, b, 0.35)
        love.graphics.rectangle("fill", gx, gy, 1, 1)
    end

    if timer > 1 then
        local pulse = math.floor(timer * 2.4) % 2 == 0
        local pr, pg, pb = mono((pulse and 0.75 or 0.5) * flick)
        love.graphics.setColor(pr, pg, pb)
        love.graphics.setFont(fonts.prompt)
        love.graphics.printf("Press ENTER to try again  |  ESC for menu", 0, screenH * 0.82, screenW, "center")
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(fonts.default)
end

return gameover
