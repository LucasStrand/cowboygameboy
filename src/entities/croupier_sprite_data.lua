--- Loads blackjack_dealer_table sprites for the travelling croupier (table-view art; saloon blackjack uses the felt dealer).
local M = {}

local DEALER_DIR = "assets/sprites/blackjack_dealer_table"

local loaded = false
local rot = {} --- @type table<string, love.Image>
local idleSouth = {} --- @type love.Image[]
local dealingSouth = {} --- @type love.Image[]

local function loadAnimSubdir(subdir)
    local frames = {}
    for i = 0, 20 do
        local path = string.format("%s/animations/%s/south/frame_%03d.png", DEALER_DIR, subdir, i)
        local ok, img = pcall(love.graphics.newImage, path)
        if ok then
            img:setFilter("nearest", "nearest")
            frames[#frames + 1] = img
        end
    end
    return frames
end

function M.ensureLoaded()
    if loaded then return end
    loaded = true

    for _, name in ipairs({ "north", "south", "east", "west" }) do
        local path = DEALER_DIR .. "/rotations/" .. name .. ".png"
        local ok, img = pcall(love.graphics.newImage, path)
        if ok then
            img:setFilter("nearest", "nearest")
            rot[name] = img
        end
    end

    idleSouth = loadAnimSubdir("breathing-idle")
    dealingSouth = loadAnimSubdir("dealing-cards")

    -- If idle animation missing, fall back to static south rotation (same folder asset).
    if #idleSouth == 0 and rot.south then
        idleSouth = { rot.south }
    end
end

--- Unit vector from NPC center toward player → cardinal for 4-dir art.
function M.facingTowardPlayer(px, py, cx, cy)
    local dx = px - cx
    local dy = py - cy
    if dx * dx + dy * dy < 1e-6 then
        return "south"
    end
    local a = math.atan2(dy, dx)
    if a >= -math.pi / 4 and a < math.pi / 4 then
        return "east"
    elseif a >= math.pi / 4 and a < 3 * math.pi / 4 then
        return "south"
    elseif a >= 3 * math.pi / 4 or a < -3 * math.pi / 4 then
        return "west"
    else
        return "north"
    end
end

function M.getRotation(name)
    return rot[name]
end

function M.getIdleSouthFrames()
    return idleSouth
end

--- South-facing idle: one loop that uses every south asset (4 breathing frames + rotations/south.png).
function M.getSouthIdleLoop()
    local rs = rot.south
    if #idleSouth >= 4 and rs then
        return { idleSouth[1], idleSouth[2], idleSouth[3], idleSouth[4], rs }
    end
    if #idleSouth > 0 then
        return idleSouth
    end
    if rs then
        return { rs }
    end
    return {}
end

function M.getDealingSouthFrames()
    return dealingSouth
end

function M.hasSprites()
    return rot.north ~= nil or rot.south ~= nil or rot.east ~= nil or rot.west ~= nil
        or #idleSouth > 0 or #dealingSouth > 0
end

return M
