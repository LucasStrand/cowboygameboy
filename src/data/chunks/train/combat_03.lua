-- Combat 3: cargo chaos — a flatcar fully loaded with crate stacks as cover.
-- No gap on the floor; enemies use crates for elevation and flanking.
return {
    id = "train_combat_03",
    world = "train",
    chunkType = "combat",
    width = 400,
    height = 400,
    edges = {
        left  = 340,
        right = 340,
        top   = false,
        bottom = false,
    },
    platforms = {
        -- One long flatcar
        {x = 0,   y = 340, w = 400, h = 60, trainCar = true, carType = "flatcar", noFill = true},
        -- Crate column left — chest-high cover
        {x = 40,  y = 316, w = 44,  h = 24},
        -- Double-stacked crate mid-left
        {x = 110, y = 292, w = 44,  h = 48},
        -- Low single crate mid
        {x = 190, y = 324, w = 36,  h = 16},
        -- Tall crate right-centre — perch for buzzards/gunslingers
        {x = 260, y = 280, w = 44,  h = 60},
        -- Scattered small crates far right
        {x = 330, y = 316, w = 36,  h = 24},
    },
}
