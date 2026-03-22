-- Transition: enters at mid (300), exits at ground (360) — drops one tier
return {
    id = "transition_down_a",
    world = "forest",
    chunkType = "traversal",
    width = 400, height = 400,
    edges = { left = 300, right = 360, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 300, w = 180, h = 40},
        {x = 180, y = 330, w = 80,  h = 16},   -- step down
        {x = 220, y = 360, w = 180, h = 40},
    },
}
