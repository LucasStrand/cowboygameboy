--[[
  Boot / splash sequence — timings, copy, and asset hooks for src/states/boot_intro.lua.
  Tune durations here; set paths to nil to disable music or future logo/title images.
]]

local BootIntro = {}

-- ---------------------------------------------------------------------------
-- Timings (seconds)
-- ---------------------------------------------------------------------------
BootIntro.studioDuration = 3.5
BootIntro.titleDuration = 5.0
BootIntro.fadeToBlackDuration = 0.65

--- Content fades out during the last N seconds of studio/title before next phase starts.
BootIntro.crossFadeDuration = 0.55

--- After Gamestate.switch(menu, { fromIntro = true }), menu fades from black for this long.
BootIntro.menuFadeInDuration = 0.6

-- ---------------------------------------------------------------------------
-- Skip (any key / mouse button)
-- ---------------------------------------------------------------------------
BootIntro.skipEnabled = true

--- If true: skip jumps to the next phase. If false: skip jumps straight to fade+menu.
BootIntro.skipAdvancesPhase = true

--- Shown when skipEnabled (hint under title phase)
BootIntro.skipHint = "Press any key to continue"

-- ---------------------------------------------------------------------------
-- Studio splash — copy (replace with your real studio name)
-- ---------------------------------------------------------------------------
BootIntro.studioTitle = "DUST & SPUR"
BootIntro.studioSubtitle = "We make games between gunfights."

-- Optional image paths (future): love.graphics.newImage when non-nil
--- Drop your design here (e.g. exported PNG); drawn centered above the studio title.
BootIntro.studioLogoImage = nil -- e.g. "assets/ui/studio_logo.png"
BootIntro.studioLogoMaxWidth = 420
BootIntro.studioLogoY = 0.26 -- fraction of screen height (0 = top)

--- Delay between logo, title, and subtitle appearance (seconds)
BootIntro.studioStagger = 0.25

-- ---------------------------------------------------------------------------
-- Title phase — tagline under main title
-- ---------------------------------------------------------------------------
BootIntro.gameTagline = "A western roguelike — six rounds, no second chances."

-- Full-screen title / loading backdrop (scaled to cover). Also used as main menu backdrop when set.
-- nil = procedural sunset/mesa in boot, and first-room preview + parallax on the menu.
BootIntro.titleBackgroundImage = "assets/backgrounds/sunsetmesa.png"

-- ---------------------------------------------------------------------------
-- Audio (optional — nil disables)
-- ---------------------------------------------------------------------------
--- Menu theme: started at boot, continues on main menu; stopped when leaving menu for gameplay.
BootIntro.menuMusicPath = "assets/music/main/Dust Trail Horizons.wav"

--- Future: one-shot SFX (paths; loaded in state if set)
BootIntro.sfxStudioHit = nil
BootIntro.sfxTitleHit = nil

-- ---------------------------------------------------------------------------
-- Visual flags (procedural FX in src/ui/boot_fx.lua)
-- ---------------------------------------------------------------------------
BootIntro.enableDustMotes = true
BootIntro.enableScanlines = true
BootIntro.enableFilmFlicker = true
BootIntro.scanlineAlpha = 0.06
BootIntro.flickerStrength = 0.035

--- Title / loading screen: lighter vignette than studio so sunset reads clearly
BootIntro.overlayVignetteTitle = { 0.03, 0.02, 0.05, 0.28 }
--- Darken only the hero band for text (0 = none). Keep low so sunset stays vivid.
BootIntro.titleHeroTextDim = 0.1

-- ---------------------------------------------------------------------------
-- Colors (RGBA tables, 0–1) — aligned with src/states/menu.lua
-- ---------------------------------------------------------------------------
BootIntro.bgDark = { 0.08, 0.05, 0.03 }
BootIntro.overlayVignette = { 0.02, 0.02, 0.04, 0.45 }
BootIntro.goldTitle = { 1, 0.85, 0.2 }
BootIntro.subtitleWarm = { 0.72, 0.55, 0.38 }
BootIntro.accentLine = { 0.85, 0.65, 0.35, 0.85 }
BootIntro.hintMuted = { 0.45, 0.45, 0.48 }

-- Studio-specific palette (beige/parchment)
BootIntro.bgStudio = { 0.76, 0.67, 0.50 }
BootIntro.studioGold = { 0.35, 0.24, 0.1 }
BootIntro.studioSubtitleColor = { 0.42, 0.32, 0.18 }
BootIntro.studioAccent = { 0.55, 0.42, 0.25, 0.6 }
BootIntro.studioDustColor = { 0.55, 0.45, 0.3 }
BootIntro.studioVignetteColor = { 0.42, 0.32, 0.18, 0.45 }

-- Hay bale (title phase): rolls along the hero “ground” line
BootIntro.hayBaleSpeed = 78
BootIntro.hayBaleRadius = 24
--- 0 = top of hero band, 1 = bottom — where the bale sits vertically
BootIntro.hayGroundK = 0.68

return BootIntro
