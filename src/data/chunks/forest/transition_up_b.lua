-- Transition: enters at mid (300), exits at high (240) — climbs one tier
return {
    id = "transition_up_b",
    world = "forest",
    chunkType = "traversal",
    width = 400, height = 400,
    edges = { left = 300, right = 240, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 300, w = 160, h = 40},
        {x = 140, y = 270, w = 80,  h = 16},
        {x = 240, y = 240, w = 160, h = 40},
    },
}
