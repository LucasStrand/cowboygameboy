-- Transition: enters at ground (360), exits at mid (300) — climbs one tier
return {
    id = "transition_up_a",
    world = "forest",
    chunkType = "traversal",
    width = 400, height = 400,
    edges = { left = 360, right = 300, top = false, bottom = false },
    platforms = {
        {x = 0,   y = 360, w = 160, h = 40},   -- ground entry
        {x = 140, y = 330, w = 80,  h = 16},   -- step
        {x = 240, y = 300, w = 160, h = 40},   -- mid exit
    },
}
