local Gamestate = require("lib.hump.gamestate")

local menu = require("src.states.menu")
local game = require("src.states.game")
local gameover = require("src.states.gameover")
local levelup = require("src.states.levelup")
local saloon = require("src.states.saloon")

GAME_WIDTH = 1280
GAME_HEIGHT = 720
DEBUG = false

-- Virtual resolution canvas and scaling
-- Reference frame: 1920x1080 (16:9). Window is fitted inside that aspect (ultrawide = pillarbox).
local REF_W, REF_H = 1920, 1080

local gameCanvas
local canvasScale = 1
local canvasOffsetX = 0
local canvasOffsetY = 0

local function updateCanvasScale()
    local winW, winH = love.graphics.getDimensions()
    local s = math.min(winW / REF_W, winH / REF_H)
    local contentW = REF_W * s
    local contentH = REF_H * s
    canvasScale = contentW / GAME_WIDTH
    canvasOffsetX = (winW - contentW) / 2
    canvasOffsetY = (winH - contentH) / 2
end

function love.load()
    -- Linear sampling: smoother text/UI when the canvas is scaled to the window
    love.graphics.setDefaultFilter("linear", "linear")
    math.randomseed(os.time())

    gameCanvas = love.graphics.newCanvas(GAME_WIDTH, GAME_HEIGHT)
    gameCanvas:setFilter("linear", "linear")
    updateCanvasScale()
    
    -- Register all events except draw (we render to canvas and blit manually)
    local callbacks = {'update'}
    for k in pairs(love.handlers) do
        callbacks[#callbacks+1] = k
    end
    Gamestate.registerEvents(callbacks)
    Gamestate.switch(menu)
end

function love.resize(w, h)
    updateCanvasScale()
end

function love.draw()
    -- Render game to fixed-size canvas
    love.graphics.setCanvas(gameCanvas)
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

-- Transform window coordinates to game coordinates (for mouse input)
function windowToGame(x, y)
    local gx = (x - canvasOffsetX) / canvasScale
    local gy = (y - canvasOffsetY) / canvasScale
    return gx, gy
end
