local PROJECT_ROOT = [[C:\Users\9914k\Dev\Cowboygamejam\cowboygameboy]]
local OUTPUT_LOG = "phase6_vfx_preview_output.txt"

package.path = table.concat({
    PROJECT_ROOT .. [[\?.lua]],
    PROJECT_ROOT .. [[\?\init.lua]],
    package.path,
}, ";")

local ImpactFX = require("src.systems.impact_fx")

local frames = {}
local frame_index = 0
local frame_count = 12
local captured = false

local effects = {
    { id = "explosion_small", x = 120, y = 120 },
    { id = "explosion_medium", x = 320, y = 120 },
    { id = "explosion_large", x = 560, y = 120 },
    { id = "muzzle_explosive_shotgun", x = 320, y = 300, angle = 0 },
}

local function drawLabel(text, x, y)
    love.graphics.setColor(0.95, 0.9, 0.78, 1)
    love.graphics.print(text, x, y)
end

local function writeCaptureLog()
    local fh = assert(io.open(OUTPUT_LOG, "w"))
    fh:write("phase6 preview captured\n")
    fh:write("effects: explosion_small, explosion_medium, explosion_large, muzzle_explosive_shotgun\n")
    fh:close()
end

function love.load()
    love.window.setMode(760, 420, { resizable = false, vsync = 0 })
    love.graphics.setDefaultFilter("nearest", "nearest")
    for _, effect in ipairs(effects) do
        ImpactFX.spawn(effect.x, effect.y, effect.id, { angle = effect.angle or 0 })
    end
end

function love.update(dt)
    if captured then
        return
    end
    ImpactFX.update(dt)
    frame_index = frame_index + 1
    if frame_index >= frame_count then
        captured = true
        writeCaptureLog()
        love.event.quit(0)
    end
end

function love.draw()
    love.graphics.clear(0.07, 0.05, 0.04, 1)

    love.graphics.setColor(0.14, 0.1, 0.08, 1)
    love.graphics.rectangle("fill", 40, 60, 680, 300, 8, 8)
    love.graphics.setColor(0.24, 0.18, 0.14, 1)
    love.graphics.rectangle("line", 40, 60, 680, 300, 8, 8)

    drawLabel("Phase 6 VFX Preview", 48, 20)
    drawLabel("small", 88, 335)
    drawLabel("medium", 276, 335)
    drawLabel("large", 530, 335)
    drawLabel("muzzle_explosive_shotgun", 228, 365)

    love.graphics.setColor(0.2, 0.16, 0.12, 1)
    love.graphics.rectangle("fill", 84, 112, 72, 72, 4, 4)
    love.graphics.rectangle("fill", 284, 112, 72, 72, 4, 4)
    love.graphics.rectangle("fill", 524, 112, 72, 72, 4, 4)
    love.graphics.rectangle("fill", 284, 276, 72, 48, 4, 4)

    ImpactFX.draw()

end
