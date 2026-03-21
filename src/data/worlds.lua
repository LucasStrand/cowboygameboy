-- World definitions — each world has a theme (tile atlas, background, colors)
-- and its own pool of rooms loaded from src/data/rooms/<worldId>/.

local Worlds = {}

-- Ordered list of world IDs for progression
Worlds.order = { "desert", "forest", "train" }
Worlds.default = Worlds.order[1]

Worlds.definitions = {
    forest = {
        id = "forest",
        name = "Greenwood Forest",
        background = "assets/backgrounds/forest.png",
        tileAtlas = "assets/Tiles/Tiles/Assets/Assets.png",
        theme = {
            -- Tile coordinates {col, row} in the atlas (1-indexed, 16x16 grid)
            grass_l   = {3, 1},
            grass_m   = {4, 1},
            grass_r   = {5, 1},
            grass_bl  = {2, 2},
            grass_bm  = {5, 2},
            grass_br  = {6, 2},
            dirt      = {4, 4},
            dirt2     = {3, 4},
            dirt3     = {5, 4},
            dirt_l    = {2, 3},
            dirt_r    = {6, 3},
            dirt_bl   = {3, 6},
            dirt_bm   = {4, 6},
            dirt_br   = {5, 6},
            plank_l   = {7, 9},
            plank_m   = {8, 9},
            plank_r   = {9, 9},
        },
        skyColor = {0.15, 0.1, 0.08},
        parallaxSpeed = 0.3,
        roomsPerCheckpoint = 5,
    },

    desert = {
        id = "desert",
        name = "Western Desert",
        background = "assets/backgrounds/deserttrainworldbackground.jpg",
        tileAtlas = "assets/terrain/desert/generated_ground/desert_ground_manual_atlas.png",
        theme = {
            -- Hand-built side-view desert atlas (16x16 tiles, 1-indexed coordinates).
            grass_l   = {1, 1},
            grass_m   = {2, 1},
            grass_r   = {3, 1},
            grass_bl  = {4, 1},
            grass_bm  = {5, 1},
            grass_br  = {6, 1},
            dirt_l    = {1, 2},
            dirt      = {2, 2},
            dirt2     = {3, 2},
            dirt3     = {4, 2},
            dirt_r    = {5, 2},
            dirt_bl   = {1, 3},
            dirt_bm   = {6, 2},
            dirt_br   = {2, 3},
            plank_l   = {3, 3},
            plank_m   = {4, 3},
            plank_r   = {5, 3},
        },
        skyColor = {0.85, 0.65, 0.35},
        parallaxSpeed = 0.3,
        roomsPerCheckpoint = 5,
    },

    train = {
        id = "train",
        name = "Iron Horse Express",
        background = "assets/backgrounds/sunsetmesa.png",
        tileAtlas = "assets/Tiles/Tiles/Assets/Assets.png",
        theme = {
            -- Reuse forest atlas with different tile selections for now
            grass_l   = {7, 9},
            grass_m   = {8, 9},
            grass_r   = {9, 9},
            grass_bl  = {7, 9},
            grass_bm  = {8, 9},
            grass_br  = {9, 9},
            dirt      = {4, 4},
            dirt2     = {3, 4},
            dirt3     = {5, 4},
            dirt_l    = {2, 3},
            dirt_r    = {6, 3},
            dirt_bl   = {3, 6},
            dirt_bm   = {4, 6},
            dirt_br   = {5, 6},
            plank_l   = {7, 9},
            plank_m   = {8, 9},
            plank_r   = {9, 9},
        },
        skyColor = {0.6, 0.35, 0.2},
        parallaxSpeed = 0.5,
        roomsPerCheckpoint = 5,
    },
}

--- Get the world definition by ID.
function Worlds.get(worldId)
    return Worlds.definitions[worldId]
end

--- Get the next world after the given one, or nil if last.
function Worlds.getNext(worldId)
    for i, id in ipairs(Worlds.order) do
        if id == worldId then
            return Worlds.order[i + 1]
        end
    end
    return nil
end

--- Get the world index (1-based) for display.
function Worlds.getIndex(worldId)
    for i, id in ipairs(Worlds.order) do
        if id == worldId then return i end
    end
    return 0
end

return Worlds
