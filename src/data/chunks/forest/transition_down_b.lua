-- Transition: enters at high (240), exits at mid (300) — drops one tier
return {
    id = "transition_down_b",
    world = "forest",
    chunkType = "traversal",
    width = 400, height = 400,
    edges = { left = 240, right = 300, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 240, w = 180, h = 40},
        {x = 180, y = 270, w = 80,  h = 16},
        {x = 220, y = 300, w = 180, h = 40},
    },
}
