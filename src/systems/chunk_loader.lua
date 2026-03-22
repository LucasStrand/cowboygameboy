-- Chunk loader — scans per-world directories for chunk files and builds pools.
-- Checks both bundled source chunks (src/data/chunks/<worldId>/) and
-- user-created chunks in the save directory (chunks/<worldId>/).

local ChunkLoader = {}
local RoomSerializer = require("src.systems.room_serializer")

--- Validate that a chunk table has the required fields.
local function isValidChunk(chunk)
    if type(chunk) ~= "table" then return false end
    if not chunk.id or not chunk.width or not chunk.height then return false end
    if not chunk.platforms or #chunk.platforms == 0 then return false end
    if not chunk.chunkType then return false end
    if not chunk.edges or type(chunk.edges) ~= "table" then return false end
    return true
end

--- Load all .lua chunk files from a directory path.
local function loadChunksFromDir(dir)
    local chunks = {}
    local items = love.filesystem.getDirectoryItems(dir)
    for _, filename in ipairs(items) do
        if filename:match("%.lua$") then
            local path = dir .. "/" .. filename
            local fn, err = love.filesystem.load(path)
            if fn then
                local ok, chunk = pcall(fn)
                if ok and isValidChunk(chunk) then
                    chunks[#chunks + 1] = RoomSerializer.normalize(chunk)
                else
                    print("[ChunkLoader] Invalid chunk: " .. path)
                end
            else
                print("[ChunkLoader] Failed to load: " .. path .. " — " .. tostring(err))
            end
        end
    end
    return chunks
end

--- Get all chunks for a given world as a flat list.
function ChunkLoader.getPool(worldId)
    local pool = {}

    -- Bundled chunks (in source tree)
    local bundledDir = "src/data/chunks/" .. worldId
    local bundled = loadChunksFromDir(bundledDir)
    for _, chunk in ipairs(bundled) do
        pool[#pool + 1] = chunk
    end

    -- User-created chunks (in save directory)
    local userDir = "chunks/" .. worldId
    local userChunks = loadChunksFromDir(userDir)
    for _, chunk in ipairs(userChunks) do
        pool[#pool + 1] = chunk
    end

    return pool
end

--- Get chunks for a world grouped by chunkType.
--- Returns a table: { entrance = {...}, exit = {...}, combat = {...}, ... }
function ChunkLoader.getPoolByType(worldId)
    local pool = ChunkLoader.getPool(worldId)
    local byType = {}
    for _, chunk in ipairs(pool) do
        local t = chunk.chunkType
        if not byType[t] then
            byType[t] = {}
        end
        byType[t][#byType[t] + 1] = chunk
    end
    return byType
end

--- Get all chunks across all worlds (for the editor file browser).
function ChunkLoader.getAllChunks()
    local all = {}
    -- Check bundled directories
    local worldDirs = love.filesystem.getDirectoryItems("src/data/chunks")
    for _, worldId in ipairs(worldDirs) do
        local info = love.filesystem.getInfo("src/data/chunks/" .. worldId)
        if info and info.type == "directory" then
            local chunks = loadChunksFromDir("src/data/chunks/" .. worldId)
            for _, chunk in ipairs(chunks) do
                chunk.world = chunk.world or worldId
                chunk._source = "bundled"
                all[#all + 1] = chunk
            end
        end
    end
    -- Check user directories
    local userWorldDirs = love.filesystem.getDirectoryItems("chunks")
    for _, worldId in ipairs(userWorldDirs) do
        local info = love.filesystem.getInfo("chunks/" .. worldId)
        if info and info.type == "directory" then
            local chunks = loadChunksFromDir("chunks/" .. worldId)
            for _, chunk in ipairs(chunks) do
                chunk.world = chunk.world or worldId
                chunk._source = "user"
                all[#all + 1] = chunk
            end
        end
    end
    return all
end

return ChunkLoader
