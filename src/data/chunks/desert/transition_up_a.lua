-- Transition: ground (360) to mesa top (300) — ascending left to right
return {
    id = "desert_transition_up_a",
    world = "desert",
    chunkType = "traversal",
    width = 400, height = 400,
    edges = { left = 360, right = 300, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 360, w = 160, h = 40},
        {x = 140, y = 330, w = 80,  h = 16},
        {x = 240, y = 300, w = 160, h = 40},
    },
}
