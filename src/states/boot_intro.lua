--[[
  Boot sequence: studio splash → title + chamber “loading” → fade to black → main menu.
  Timings and copy: src/data/boot_intro.lua
]]

local Gamestate = require("lib.hump.gamestate")
local Font = require("src.ui.font")
local C = require("src.data.boot_intro")
local BootFx = require("src.ui.boot_fx")
local MenuBgm = require("src.systems.menu_bgm")

local boot_intro = {}

local PHASE = {
    studio = 1,
    title = 2,
    fade_out = 3,
}

local phase = PHASE.studio
local phaseTime = 0
local totalTime = 0
local dust = {}
local fonts = {}
--- Rolling hay bale (title phase)
local hay = { x = 0, rot = 0, bob = 0 }
--- Cached studio logo (optional PNG from C.studioLogoImage)
local studioLogoImg = nil
--- Title phase backdrop (optional PNG from C.titleBackgroundImage)
local titleBgImg = nil

local function setPhase(p)
    phase = p
    phaseTime = 0
    if p == PHASE.title then
        hay.x = GAME_WIDTH + (C.hayBaleRadius or 24) * 5
        hay.rot = love.math.random() * math.pi * 2
    end
end

local function goToMenu()
    local m = require("src.states.menu")
    Gamestate.switch(m, { fromIntro = true })
end

function boot_intro:enter()
    phase = PHASE.studio
    phaseTime = 0
    totalTime = 0
    fonts.studioLarge = Font.new(36)
    fonts.studioSmall = Font.new(15)
    -- Match src/states/menu.lua (title / subtitle / hint)
    fonts.title = Font.new(48)
    fonts.subtitle = Font.new(16)
    fonts.hint = Font.new(14)
    BootFx.initDust(dust, 48, GAME_WIDTH, GAME_HEIGHT, 42)
    studioLogoImg = nil
    if C.studioLogoImage and C.studioLogoImage ~= "" then
        local ok, img = pcall(love.graphics.newImage, C.studioLogoImage)
        if ok and img then
            img:setFilter("nearest", "nearest")
            studioLogoImg = img
        end
    end
    titleBgImg = nil
    local bgPath = C.titleBackgroundImage
    if bgPath and bgPath ~= "" then
        local ok, img = pcall(love.graphics.newImage, bgPath)
        if ok and img then
            img:setFilter("nearest", "nearest")
            titleBgImg = img
        end
    end
    hay.x = GAME_WIDTH + 80
    hay.rot = 0
    hay.bob = 0
    MenuBgm.play(C.menuMusicPath)
end

function boot_intro:leave()
    -- Music continues on menu; do not stop here.
end

local function advanceSkip()
    if not C.skipEnabled then
        return
    end
    if C.skipAdvancesPhase then
        if phase == PHASE.studio then
            setPhase(PHASE.title)
        elseif phase == PHASE.title then
            setPhase(PHASE.fade_out)
        else
            goToMenu()
        end
    else
        phase = PHASE.fade_out
        phaseTime = C.fadeToBlackDuration -- next update() switches to menu immediately
    end
end

function boot_intro:keypressed(key)
    advanceSkip()
end

function boot_intro:mousepressed(x, y, button)
    if button == 1 then
        advanceSkip()
    end
end

function boot_intro:update(dt)
    totalTime = totalTime + dt
    MenuBgm.updateVolume()
    if C.enableDustMotes then
        BootFx.updateDust(dust, dt, GAME_WIDTH, GAME_HEIGHT)
    end

    if phase == PHASE.title and not titleBgImg then
        local hr = C.hayBaleRadius or 24
        local sp = C.hayBaleSpeed or 78
        hay.x = hay.x - sp * dt
        hay.rot = hay.rot + (sp / hr) * dt
        hay.bob = math.sin(totalTime * 2.4) * 2.8
        if hay.x < -hr * 5 then
            hay.x = GAME_WIDTH + hr * 6
        end
    end

    phaseTime = phaseTime + dt

    if phase == PHASE.studio then
        if phaseTime >= C.studioDuration then
            setPhase(PHASE.title)
        end
    elseif phase == PHASE.title then
        if phaseTime >= C.titleDuration then
            setPhase(PHASE.fade_out)
        end
    elseif phase == PHASE.fade_out then
        if phaseTime >= C.fadeToBlackDuration then
            goToMenu()
        end
    end
end

--- Cross-fade alpha: ramps in over `fadeInTime`, ramps out during last `crossFade` of `duration`.
local function contentAlpha(pt, duration, fadeInTime, crossFade)
    local fadeIn = math.min(1, pt / math.max(0.01, fadeInTime))
    local tailStart = duration - crossFade
    local fadeOut = (pt < tailStart) and 1 or math.max(0, 1 - (pt - tailStart) / math.max(0.01, crossFade))
    return fadeIn * fadeOut
end

--- Staggered element alpha: delayed start relative to base contentAlpha.
local function staggerAlpha(pt, offset, fadeInTime)
    return math.min(1, math.max(0, (pt - offset) / math.max(0.01, fadeInTime)))
end

local function drawTitleScene(w, h, t)
    if titleBgImg then
        local iw, ih = titleBgImg:getDimensions()
        local scale = math.max(w / iw, h / ih)
        local sw, sh = iw * scale, ih * scale
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(titleBgImg, (w - sw) * 0.5, (h - sh) * 0.5, 0, scale, scale)
        return
    end
    local bandY = h * 0.42
    local bandH = h * 0.38
    BootFx.drawSkyBackdrop(w, bandY, t)
    BootFx.drawHorizonHero(w, h, bandY, bandH, t)
    local hk = C.hayGroundK or 0.68
    local hr = C.hayBaleRadius or 24
    local groundY = bandY + bandH * hk + hay.bob
    BootFx.drawHayBale(hay.x, groundY, hay.rot, hr, t)
end

function boot_intro:draw()
    local w, h = GAME_WIDTH, GAME_HEIGHT
    local cf = C.crossFadeDuration or 0.55
    local stag = C.studioStagger or 0.25

    if phase == PHASE.studio then
        local a = contentAlpha(phaseTime, C.studioDuration, 0.5, cf)

        -- Parchment background (always full; content fades over it)
        BootFx.drawParchmentBg(w, h, C.bgStudio, totalTime)
        BootFx.drawEdgeVignette(w, h, C.studioVignetteColor)

        -- Staggered elements
        local aLines = staggerAlpha(phaseTime, stag * 0.5, 0.4) * a
        BootFx.drawAccentLines(w, h, h * 0.28, h * 0.72, C.studioAccent, aLines)

        local aLogo = staggerAlpha(phaseTime, 0, 0.45) * a
        if studioLogoImg then
            local iw, ih = studioLogoImg:getDimensions()
            local maxW = C.studioLogoMaxWidth or 420
            local scale = math.min(maxW / iw, (h * 0.2) / ih, 1.5)
            local sw = iw * scale
            love.graphics.setColor(1, 1, 1, aLogo)
            love.graphics.draw(studioLogoImg, (w - sw) * 0.5, h * (C.studioLogoY or 0.22), 0, scale, scale)
        end

        local aTitle = staggerAlpha(phaseTime, stag, 0.45) * a
        local sg = C.studioGold
        love.graphics.setColor(sg[1], sg[2], sg[3], aTitle)
        love.graphics.setFont(fonts.studioLarge)
        love.graphics.printf(C.studioTitle, 0, h * 0.4, w, "center")

        local aSub = staggerAlpha(phaseTime, stag * 2, 0.4) * a
        local sc = C.studioSubtitleColor
        love.graphics.setColor(sc[1], sc[2], sc[3], aSub * 0.95)
        love.graphics.setFont(fonts.studioSmall)
        love.graphics.printf(C.studioSubtitle, 0, h * 0.4 + 52, w, "center")

        if C.enableDustMotes then
            BootFx.drawDust(dust, a, C.studioDustColor)
        end

    elseif phase == PHASE.title then
        local a = contentAlpha(phaseTime, C.titleDuration, 0.6, cf)
        local bg = C.bgDark
        love.graphics.setColor(bg[1], bg[2], bg[3], 1)
        love.graphics.rectangle("fill", 0, 0, w, h)

        drawTitleScene(w, h, totalTime)

        -- Gradient dim behind title copy (full-art backdrop: darken top band)
        local td = (C.titleHeroTextDim or 0.1) * a
        if titleBgImg then
            BootFx.drawGradientDim(w, 0, h * 0.36, td * 1.15)
        else
            BootFx.drawGradientDim(w, 0, h * 0.44, td)
        end

        local gold = C.goldTitle
        love.graphics.setColor(gold[1], gold[2], gold[3], a)
        love.graphics.setFont(fonts.title)
        love.graphics.printf("SIX CHAMBERS", 0, h * 0.14, w, "center")

        local sub = C.subtitleWarm
        local aSub = staggerAlpha(phaseTime, 0.2, 0.5) * a
        love.graphics.setColor(sub[1], sub[2], sub[3], aSub)
        love.graphics.setFont(fonts.subtitle)
        love.graphics.printf(C.gameTagline, 0, h * 0.14 + 58, w, "center")

        BootFx.drawAccentLines(w, h, h * 0.02, h * 0.97, C.accentLine, a)

        local filled = math.min(
            6,
            math.max(0, math.ceil(6 * phaseTime / math.max(0.001, C.titleDuration) - 1e-6))
        )
        BootFx.drawRevolverCylinder(w * 0.5, h * 0.82, filled, gold)

        love.graphics.setColor(sub[1], sub[2], sub[3], a * 0.9)
        love.graphics.setFont(fonts.hint)
        love.graphics.printf("Loading chambers…", 0, h * 0.82 + 50, w, "center")

        if C.skipEnabled and C.skipHint then
            local mh = C.hintMuted
            love.graphics.setColor(mh[1], mh[2], mh[3], a * 0.85)
            love.graphics.printf(C.skipHint, 0, h * 0.91, w, "center")
        end

        if C.enableDustMotes then
            BootFx.drawDust(dust, a)
        end

        -- Title-phase vignette
        local v = C.overlayVignetteTitle
        love.graphics.setColor(v[1], v[2], v[3], v[4])
        love.graphics.rectangle("fill", 0, 0, w, h)

    elseif phase == PHASE.fade_out then
        -- Freeze title hero scene underneath the fade
        local bg = C.bgDark
        love.graphics.setColor(bg[1], bg[2], bg[3], 1)
        love.graphics.rectangle("fill", 0, 0, w, h)
        drawTitleScene(w, h, totalTime)

        local t = math.min(1, phaseTime / math.max(0.0001, C.fadeToBlackDuration))
        love.graphics.setColor(0, 0, 0, t)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end

    -- Post-processing (skip during fade-out — black overlay handles it)
    if phase ~= PHASE.fade_out then
        if C.enableFilmFlicker then
            BootFx.drawFilmFlicker(w, h, C.flickerStrength, totalTime)
        end
        if C.enableScanlines then
            love.graphics.setColor(1, 1, 1, 1)
            BootFx.drawScanlines(w, h, C.scanlineAlpha)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return boot_intro
