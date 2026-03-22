-- World definitions — each world has a theme (tile atlas, background, colors)
-- and its own pool of rooms loaded from src/data/rooms/<worldId>/.

local Worlds = {}

-- Ordered list of world IDs for progression
Worlds.order = { "desert", "train", "forest" }

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
        enemyRoster = {
            bandit = 30,
            gunslinger = 20,
            buzzard = 10,
            nightborne = 25,
            necromancer = 15,
        },
        -- Chunk generation config: World 2 is dense forest, more vertical exploration
        chunkGen = {
            cols = 6,           -- narrower grid
            rows = 4,           -- taller (vertical layout)
            rightWeight = 2,    -- still moves right but less dominant
            verticalWeight = 3, -- strongly prefer up/down movement
            branchChance = 0.5, -- more secret branches to discover
        },
    },

    desert = {
        id = "desert",
        name = "Western Desert",
        background = "assets/backgrounds/stage1vertical.jpg",
        tileAtlas = nil,  -- no tile atlas; uses solid-fill rock/sand rendering
        theme = {
            -- Colors sampled from Western/Background1.png canyon terrain
            _solidFill = true,
            _topColor  = {0.87, 0.74, 0.50},  -- sandy top surface
            _faceColor = {0.72, 0.49, 0.30},  -- sandstone rock face
            _baseColor = {0.50, 0.32, 0.18},  -- dark shadow base
        },
        skyColor = {0.85, 0.65, 0.35},
        parallaxSpeed = 0.3,
        roomsPerCheckpoint = 5,
        enemyRoster = {
            bandit = 45,
            gunslinger = 25,
            buzzard = 15,
        },
        -- Chunk generation config: World 1 is flat desert, wide and horizontal
        chunkGen = {
            cols = 10,          -- wide grid
            rows = 2,           -- short (horizontal layout)
            rightWeight = 5,    -- strongly prefer moving right
            verticalWeight = 1, -- rarely go up/down
            branchChance = 0.3, -- fewer branches in early world
        },
        --- Procedural decor (see World Editor / world_props); versioned with the repo.
        decorPropPaths = {
            "assets/wild_west_free_pack/plant_1.png",
            "assets/sprites/props/cacti/barrel_cactus.png",
            "assets/sprites/props/cacti/leaning_cactus.png",
            "assets/sprites/props/cacti/prickly_pear_cluster.png",
            "assets/sprites/props/cacti/short_saguaro_1_arm.png",
            "assets/sprites/props/cacti/tall_saguaro_2_arms.png",
        },
    },

    train = {
        id = "train",
        name = "Iron Horse Express",
        background = "assets/backgrounds/deserttrainworldbackground.jpg",
        tileAtlas = "assets/Tiles/Tiles/Assets/Assets.png",
        theme = {
            -- Planks everywhere for a wooden train-car feel
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
            _atlasPath = "assets/Tiles/Tiles/Assets/Assets.png",
            _tint = {0.70, 0.62, 0.50},  -- aged wood / steel tint
        },
        skyColor = {0.6, 0.35, 0.2},
        parallaxSpeed = 0.5,
        roomsPerCheckpoint = 5,
        enemyRoster = {
            bandit = 25,
            gunslinger = 30,
            buzzard = 15,
            nightborne = 15,
            necromancer = 15,
        },
        -- Chunk generation config: World 3 is a train — long narrow horizontal rush
        chunkGen = {
            cols = 12,          -- very wide
            rows = 2,           -- flat (train cars are horizontal)
            rightWeight = 6,    -- almost always moves right
            verticalWeight = 1, -- very rarely go up/down
            branchChance = 0.2, -- few branches on a train
        },
    },

    saloon = {
        id = "saloon",
        name = "Saloon",
        background = "assets/backgrounds/saloonLobby.png",
        tileAtlas = "assets/Tiles/Tiles/Assets/Assets.png",
        theme = {
            -- Use forest atlas plank tiles for wooden saloon interior
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
        skyColor = {0.12, 0.08, 0.05},
        parallaxSpeed = 0,
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

--- Load editor overrides from save directory (if any).
local ok, chunk = pcall(love.filesystem.load, "world_overrides.lua")
if ok and chunk then
    local success, overrides = pcall(chunk)
    if success and type(overrides) == "table" then
        for worldId, ovr in pairs(overrides) do
            local def = Worlds.definitions[worldId]
            if def then
                for k, v in pairs(ovr) do
                    if type(v) == "table" and type(def[k]) == "table" then
                        for kk, vv in pairs(v) do
                            def[k][kk] = vv
                        end
                    else
                        def[k] = v
                    end
                end
            end
        end
    end
end

return Worlds
