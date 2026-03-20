local Gamestate = require("lib.hump.gamestate")

local menu = require("src.states.menu")
local game = require("src.states.game")
local gameover = require("src.states.gameover")
local levelup = require("src.states.levelup")
local saloon = require("src.states.saloon")

GAME_WIDTH = 1280
GAME_HEIGHT = 720
DEBUG = false

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    math.randomseed(os.time())
    Gamestate.registerEvents()
    Gamestate.switch(menu)
end

function love.keypressed(key)
    if key == "f1" then
        DEBUG = not DEBUG
    end
end
