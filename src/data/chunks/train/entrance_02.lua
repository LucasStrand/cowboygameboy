-- Entrance 2: two cars already separated, introducing the gap concept early.
-- Safe gap (35 px) to warn the player that gaps exist before combat pressure.
return {
    id = "train_entrance_02",
    world = "train",
    chunkType = "entrance",
    width = 400,
    height = 400,
    edges = {
        left  = false,
        right = 340,
        top   = false,
        bottom = false,
    },
    platforms = {
        -- Car 1 — wide boxcar, player starts here
        {x = 0,   y = 340, w = 220, h = 60, trainCar = true, carType = "boxcar",    noFill = true},
        -- Gap (35 px void) — clearly visible, generous for first encounter
        -- Car 2 — flatcar to the right
        {x = 255, y = 340, w = 145, h = 60, trainCar = true, carType = "flatcar",   noFill = true},
        -- Small crate on car 2
        {x = 310, y = 316, w = 40,  h = 24},
    },
    playerSpawn = {x = 40, y = 290},
}
