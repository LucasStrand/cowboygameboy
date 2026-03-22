local Gamestate = require("lib.hump.gamestate")
local Settings = require("src.systems.settings")
local ContentValidator = require("src.systems.content_validator")
local Worlds = require("src.data.worlds")

local boot_intro = require("src.states.boot_intro")
local game = require("src.states.game")
local gameover = require("src.states.gameover")
local levelup = require("src.states.levelup")
local saloon = require("src.states.saloon")

-- Logical render size = drawable window size (see syncGameDimensions). Larger window ⇒ more world visible;
-- HUD uses fixed pixel sizes in this space (does not scale up with resolution).
GAME_WIDTH = 1280
GAME_HEIGHT = 720
DEBUG = false
DEV_TOOLS_ENABLED = true

local function hasCliFlag(...)
    local wanted = {}
    for i = 1, select("#", ...) do
        wanted[select(i, ...)] = true
    end
    for _, value in ipairs(arg or {}) do
        if wanted[value] then
            return true
        end
    end
    return false
end

local CLI_DEV_BOOT = hasCliFlag("dev", "--dev", "--debug", "--dev-arena")

local gameCanvas
local canvasScale = 1
local canvasOffsetX = 0
local canvasOffsetY = 0

local function syncGameDimensions()
    local winW, winH = love.graphics.getDimensions()
    local w = math.max(640, math.floor(winW))
    local h = math.max(360, math.floor(winH))
    if w == GAME_WIDTH and h == GAME_HEIGHT and gameCanvas then
        return
    end
    GAME_WIDTH = w
    GAME_HEIGHT = h
    if gameCanvas then
        gameCanvas:release()
        gameCanvas = nil
    end
    gameCanvas = love.graphics.newCanvas(GAME_WIDTH, GAME_HEIGHT)
    gameCanvas:setFilter("linear", "linear")

    local ok, BlurBG = pcall(require, "src.ui.blur_bg")
    if ok and BlurBG and BlurBG.invalidate then
        BlurBG.invalidate()
    end
    local okWL, WorldLighting = pcall(require, "src.systems.world_lighting")
    if okWL and WorldLighting and WorldLighting.invalidate then
        WorldLighting.invalidate()
    end
end

local function updateCanvasScale()
    -- 1:1 blit: canvas fills the window; mouse coords match canvas pixels
    canvasScale = 1
    canvasOffsetX = 0
    canvasOffsetY = 0
end

function love.load()
    love.graphics.setDefaultFilter("linear", "linear")
    math.randomseed(os.time())

    local Settings = require("src.systems.settings")
    Settings.load()
    Settings.apply()
    ContentValidator.validate_all()

    syncGameDimensions()
    updateCanvasScale()
    
    -- Register all events except draw (we render to canvas and blit manually)
    local callbacks = {'update'}
    for k in pairs(love.handlers) do
        callbacks[#callbacks+1] = k
    end
    Gamestate.registerEvents(callbacks)
    if CLI_DEV_BOOT then
        Gamestate.switch(game, {
            devArena = true,
            introCountdown = false,
            openDevPanel = true,
            devBoot = true,
            worldId = Worlds.order[1],
        })
    else
        Gamestate.switch(boot_intro)
    end
end

function love.resize(w, h)
    syncGameDimensions()
    updateCanvasScale()
end

function love.draw()
    -- Render to a canvas matching the window; larger window ⇒ larger canvas ⇒ more world (see camera view).
    -- Table form: temporary stencil buffer for love.graphics.stencil (roulette wheel clip); LOVE 11+.
    love.graphics.setCanvas({ gameCanvas, stencil = true })
    love.graphics.clear(0, 0, 0, 1)
    
    local current = Gamestate.current()
    if current and current.draw then
        current.draw(current)
    end
    
    love.graphics.setCanvas()

    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(gameCanvas, canvasOffsetX, canvasOffsetY, 0, canvasScale, canvasScale)
end

function love.keypressed(key)
    if key == "f1" then
        DEBUG = not DEBUG
    end
end

-- Transform window coordinates to game / canvas coordinates (for mouse input)
function windowToGame(x, y)
    return (x - canvasOffsetX) / canvasScale, (y - canvasOffsetY) / canvasScale
end
