-- Decorative world props: only `Worlds.definitions[worldId].decorPropPaths` (World Editor).
-- Array of image paths under `assets/`. When nil or missing → no decor. `{}` → none.
-- Spawn density uses `WorldProps.spawn` (desert defaults for worlds without their own block).

local Worlds = require("src.data.worlds")
local WorldProps = {}

--- Spawn tuning per world (density, spacing — editor can override later).
WorldProps.spawn = {
    desert = {
        --- Rough attempts per 100px of usable platform top (after margins).
        slotWidth = 88,
        placeChance = 0.42,
        minSpacing = 34,
        marginX = 28,
        --- Clearance from player spawn / exit door (world pixels).
        spawnClearR = 88,
        doorClearR = 72,
        --- Push props down so opaque pixels sit on the platform (PNG bottom padding is transparent).
        --- In unscaled texture pixels; multiplied by each prop's `scale` at draw time.
        defaultSink = 8,
    },
}

function WorldProps.getDecorDefinitions(worldId)
    local def = Worlds.definitions[worldId]
    if not def or def.decorPropPaths == nil then
        return {}
    end
    if #def.decorPropPaths == 0 then
        return {}
    end
    local out = {}
    for _, entry in ipairs(def.decorPropPaths) do
        local path = type(entry) == "string" and entry or (entry and entry.path)
        if type(path) == "string" and path ~= "" then
            out[#out + 1] = {
                id = path,
                path = path,
                weight = 1,
                scale = 1,
                minPlatformW = 32,
                sink = 0,
            }
        end
    end
    return out
end

return WorldProps
