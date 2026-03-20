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
local gameCanvas
local canvasScale = 1
local canvasOffsetX = 0
local canvasOffsetY = 0

local function updateCanvasScale()
    local winW, winH = love.graphics.getDimensions()
    -- Scale to cover (fill window, may crop edges on extreme aspect ratios)
    canvasScale = math.max(winW / GAME_WIDTH, winH / GAME_HEIGHT)
    -- Center the scaled canvas
    canvasOffsetX = (winW - GAME_WIDTH * canvasScale) / 2
    canvasOffsetY = (winH - GAME_HEIGHT * canvasScale) / 2
end

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    math.randomseed(os.time())
    
    gameCanvas = love.graphics.newCanvas(GAME_WIDTH, GAME_HEIGHT)
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
    
    -- Draw canvas scaled to fill window
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
