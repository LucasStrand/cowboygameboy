-- Room loader — scans per-world directories for room files and builds a pool.
-- Checks both bundled source rooms (src/data/rooms/<worldId>/) and
-- user-created rooms in the save directory (rooms/<worldId>/).

local RoomLoader = {}

--- Validate that a room table has the required fields.
local function isValidRoom(room)
    if type(room) ~= "table" then return false end
    if not room.id or not room.width or not room.height then return false end
    if not room.platforms or #room.platforms == 0 then return false end
    if not room.playerSpawn then return false end
    if not room.exitDoor then return false end
    return true
end

--- Load all .lua room files from a directory path.
local function loadRoomsFromDir(dir)
    local rooms = {}
    local items = love.filesystem.getDirectoryItems(dir)
    for _, filename in ipairs(items) do
        if filename:match("%.lua$") then
            local path = dir .. "/" .. filename
            local chunk, err = love.filesystem.load(path)
            if chunk then
                local ok, room = pcall(chunk)
                if ok and isValidRoom(room) then
                    rooms[#rooms + 1] = room
                else
                    print("[RoomLoader] Invalid room: " .. path)
                end
            else
                print("[RoomLoader] Failed to load: " .. path .. " — " .. tostring(err))
            end
        end
    end
    return rooms
end

--- Get the room pool for a given world.
--- Returns a list of room tables compatible with RoomData.pool.
function RoomLoader.getPool(worldId)
    local pool = {}

    -- Bundled rooms (in source tree)
    local bundledDir = "src/data/rooms/" .. worldId
    local bundled = loadRoomsFromDir(bundledDir)
    for _, room in ipairs(bundled) do
        pool[#pool + 1] = room
    end

    -- User-created rooms (in save directory)
    local userDir = "rooms/" .. worldId
    local userRooms = loadRoomsFromDir(userDir)
    for _, room in ipairs(userRooms) do
        pool[#pool + 1] = room
    end

    return pool
end

--- Get all rooms across all worlds (for the editor file browser).
function RoomLoader.getAllRooms()
    local all = {}
    -- Check bundled directories
    local worldDirs = love.filesystem.getDirectoryItems("src/data/rooms")
    for _, worldId in ipairs(worldDirs) do
        local info = love.filesystem.getInfo("src/data/rooms/" .. worldId)
        if info and info.type == "directory" then
            local rooms = loadRoomsFromDir("src/data/rooms/" .. worldId)
            for _, room in ipairs(rooms) do
                room.world = room.world or worldId
                room._source = "bundled"
                all[#all + 1] = room
            end
        end
    end
    -- Check user directories
    local userWorldDirs = love.filesystem.getDirectoryItems("rooms")
    for _, worldId in ipairs(userWorldDirs) do
        local info = love.filesystem.getInfo("rooms/" .. worldId)
        if info and info.type == "directory" then
            local rooms = loadRoomsFromDir("rooms/" .. worldId)
            for _, room in ipairs(rooms) do
                room.world = room.world or worldId
                room._source = "user"
                all[#all + 1] = room
            end
        end
    end
    return all
end

return RoomLoader
