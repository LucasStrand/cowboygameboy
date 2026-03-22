-- Recursive scan of game assets for editor pickers (png / jpg / jpeg under assets/).
-- Cached until invalidated (e.g. editor re-enter or rescan).

local AssetScan = {}

local cache = nil

local function scanDir(rel, out)
    local ok, items = pcall(love.filesystem.getDirectoryItems, rel)
    if not ok or not items then return end
    for _, name in ipairs(items) do
        if name ~= "." and name ~= ".." and name ~= "__MACOSX" and not name:match("^%.") then
            local path = rel .. "/" .. name
            local info = love.filesystem.getInfo(path)
            if info then
                if info.type == "directory" then
                    scanDir(path, out)
                elseif info.type == "file" then
                    local lower = name:lower()
                    if lower:match("%.png$") or lower:match("%.jpg$") or lower:match("%.jpeg$") then
                        out[#out + 1] = path:gsub("\\", "/")
                    end
                end
            end
        end
    end
end

--- Sorted list of paths relative to game root (forward slashes).
function AssetScan.getImagePaths()
    if cache then return cache end
    local out = {}
    if love.filesystem.getInfo("assets", "directory") then
        scanDir("assets", out)
    end
    table.sort(out)
    cache = out
    return out
end

function AssetScan.invalidateCache()
    cache = nil
end

--- Top-level folders under `assets/` that contain at least one image (e.g. `assets/sprites`).
--- First entry is `""` meaning no folder filter (all images).
function AssetScan.getAssetSubfolders()
    local paths = AssetScan.getImagePaths()
    local set = {}
    for _, p in ipairs(paths) do
        local top = p:match("^(assets/[^/]+)/")
        if top then
            set[top] = true
        end
    end
    local list = {}
    for k in pairs(set) do
        list[#list + 1] = k
    end
    table.sort(list)
    table.insert(list, 1, "")
    return list
end

return AssetScan
