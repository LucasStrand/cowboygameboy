-- Pixel Interior LRK v1.1 — quads for saloon decoration.
-- Sheet-relative pixel rects; tweak here if a crop looks off.
-- doorswindowsstairs_LRK.png 736×256 — rows ~85+85+86; columns are NOT uniform 92px:
-- after the four door variants come window → book stacks → stair tiles (see sheet).
-- floorswalls_LRK.png 224×256 — warm wood plank sample from top panel grid
-- decorations_LRK.png 192×160 — floor lamp in the left strip

local BASE = "assets/pixelinterior_LRK_v1.1/"

return {
    sheets = {
        doors = BASE .. "doorswindowsstairs_LRK.png",
        floors = BASE .. "floorswalls_LRK.png",
        decor = BASE .. "decorations_LRK.png",
    },

    --- @type table<string, { sheet: string, x: number, y: number, w: number, h: number }>
    quads = {
        -- Top row (y=0): warm wood — double-height window stack + both book columns (272–415).
        window = { sheet = "doors", x = 208, y = 0, w = 48, h = 85 },
        bookshelf = { sheet = "doors", x = 272, y = 0, w = 144, h = 85 },
        -- Warm panel: bottom-row center plank (tilable floor accent)
        floor_plank_warm = { sheet = "floors", x = 76, y = 84, w = 72, h = 36 },
        -- First column: tallest floor lamp
        floor_lamp = { sheet = "decor", x = 0, y = 0, w = 44, h = 104 },
    },
}
