return {
    id = "train_entrance_01",
    world = "train",
    chunkType = "entrance",
    width = 400,
    height = 400,
    edges = {
        left = false,
        right = 360,
        top = false,
        bottom = false,
    },
    platforms = {
        -- Car floor — flat wooden deck
        {x = 0, y = 360, w = 400, h = 40},
        -- Crate stack / cover
        {x = 260, y = 290, w = 80, h = 16},
    },
    playerSpawn = {x = 60, y = 310},
}
