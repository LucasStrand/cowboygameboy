-- Room serializer — converts room tables to/from Lua source files.
-- Used by the level editor for saving and loading user-created rooms.

local RoomSerializer = {}

--- Indent helper
local function indent(level)
    return string.rep("    ", level)
end

--- Serialize a simple value (number, string, boolean) to a Lua literal.
local function serializeValue(v)
    if type(v) == "number" then
        if v == math.floor(v) then
            return tostring(math.floor(v))
        end
        return tostring(v)
    elseif type(v) == "string" then
        return string.format("%q", v)
    elseif type(v) == "boolean" then
        return tostring(v)
    end
    return "nil"
end

--- Serialize a flat table like {x = 10, y = 20, w = 100, h = 64}.
local function serializeFlatTable(t, keys)
    local parts = {}
    for _, k in ipairs(keys) do
        if t[k] ~= nil then
            parts[#parts + 1] = k .. " = " .. serializeValue(t[k])
        end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

--- Serialize a room table to a valid Lua source string.
function RoomSerializer.serialize(room)
    local lines = {}
    lines[#lines + 1] = "return {"
    lines[#lines + 1] = indent(1) .. "id = " .. serializeValue(room.id) .. ","
    lines[#lines + 1] = indent(1) .. "world = " .. serializeValue(room.world or "forest") .. ","
    lines[#lines + 1] = indent(1) .. "width = " .. serializeValue(room.width) .. ","
    lines[#lines + 1] = indent(1) .. "height = " .. serializeValue(room.height) .. ","

    -- Platforms
    lines[#lines + 1] = indent(1) .. "platforms = {"
    for _, plat in ipairs(room.platforms or {}) do
        lines[#lines + 1] = indent(2) .. serializeFlatTable(plat, {"x", "y", "w", "h"}) .. ","
    end
    lines[#lines + 1] = indent(1) .. "},"

    -- Spawns
    lines[#lines + 1] = indent(1) .. "spawns = {"
    for _, spawn in ipairs(room.spawns or {}) do
        lines[#lines + 1] = indent(2) .. serializeFlatTable(spawn, {"x", "y", "type"}) .. ","
    end
    lines[#lines + 1] = indent(1) .. "},"

    -- Player spawn
    if room.playerSpawn then
        lines[#lines + 1] = indent(1) .. "playerSpawn = "
            .. serializeFlatTable(room.playerSpawn, {"x", "y"}) .. ","
    end

    -- Exit door
    if room.exitDoor then
        lines[#lines + 1] = indent(1) .. "exitDoor = "
            .. serializeFlatTable(room.exitDoor, {"x", "y", "w", "h"}) .. ","
    end

    lines[#lines + 1] = "}"
    return table.concat(lines, "\n") .. "\n"
end

--- Save a room to the LÖVE2D save directory.
function RoomSerializer.save(room)
    local worldId = room.world or "forest"
    local dir = "rooms/" .. worldId
    love.filesystem.createDirectory(dir)
    local path = dir .. "/" .. room.id .. ".lua"
    local source = RoomSerializer.serialize(room)
    local ok, err = love.filesystem.write(path, source)
    if not ok then
        print("[RoomSerializer] Save failed: " .. tostring(err))
    end
    return ok, path
end

--- Load a room from a path (works with both source and save directories).
function RoomSerializer.load(path)
    local chunk, err = love.filesystem.load(path)
    if not chunk then
        print("[RoomSerializer] Load failed: " .. tostring(err))
        return nil
    end
    local ok, room = pcall(chunk)
    if not ok then
        print("[RoomSerializer] Parse failed: " .. tostring(room))
        return nil
    end
    return room
end

return RoomSerializer
