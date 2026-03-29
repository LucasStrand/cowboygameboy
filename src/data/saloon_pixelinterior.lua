-- Pixel Interior LRK v1.1 — quads for saloon decoration.
-- Sheet-relative pixel rects; tweak here if a crop looks off.
-- doorswindowsstairs_LRK.png 736×256 — rows ~85+85+86; columns are NOT uniform 92px:
-- after the four door variants come window → book stacks → stair tiles (see sheet).
-- floorswalls_LRK.png 224×256 — warm wood plank sample from top panel grid
-- decorations_LRK.png 192×160 — lamps top row; potted plants below (separate quads).
-- Floor lamps: each is ~16px wide in its own column. w=44 from x=16 wrongly includes lamp #2’s pixels
-- (gap 32–47 is empty), which looks like a “cut” shade / two bases spliced together.

local BASE = "assets/pixelinterior_LRK_v1.1/"

return {
    sheets = {
        doors = BASE .. "doorswindowsstairs_LRK.png",
        floors = BASE .. "floorswalls_LRK.png",
        decor = BASE .. "decorations_LRK.png",
        cabinets = BASE .. "cabinets_LRK.png",
    },

    --- @type table<string, { sheet: string, x: number, y: number, w: number, h: number }>
    quads = {
        -- Top row (y=0): warm wood — double-height window stack + both book columns (272–415).
        window = { sheet = "doors", x = 208, y = 0, w = 48, h = 85 },
        bookshelf = { sheet = "doors", x = 272, y = 0, w = 144, h = 85 },
        -- Warm panel: bottom-row center plank (tilable floor accent)
        floor_plank_warm = { sheet = "floors", x = 76, y = 84, w = 72, h = 36 },
        floor_lamp = { sheet = "decor", x = 16, y = 16, w = 16, h = 46 },
        floor_lamp_b = { sheet = "decor", x = 48, y = 15, w = 16, h = 47 },
        floor_lamp_c = { sheet = "decor", x = 80, y = 16, w = 16, h = 46 },
        -- Potted plants (LRK middle/bottom row), feet at bottom of quad
        plant_potted_small = { sheet = "decor", x = 16, y = 81, w = 15, h = 30 },
        plant_potted_mid_a = { sheet = "decor", x = 48, y = 80, w = 16, h = 31 },
        plant_potted_mid_b = { sheet = "decor", x = 80, y = 80, w = 16, h = 31 },
        plant_potted_low = { sheet = "decor", x = 48, y = 124, w = 23, h = 16 },
        -- Warm brown wall cabinets from cabinets_LRK.png, used to fill the back-bar wall gap.
        backbar_bookcase_warm = { sheet = "cabinets", x = 16, y = 16, w = 48, h = 48 },
        backbar_display_warm = { sheet = "cabinets", x = 80, y = 16, w = 48, h = 48 },
        backbar_bookcase_dark = { sheet = "cabinets", x = 16, y = 144, w = 48, h = 48 },
        backbar_display_dark = { sheet = "cabinets", x = 80, y = 144, w = 48, h = 48 },
        wall_cabinet_upper = { sheet = "cabinets", x = 208, y = 19, w = 48, h = 45 },
        wall_cabinet_compact = { sheet = "cabinets", x = 336, y = 30, w = 48, h = 34 },
        wall_cabinet_short = { sheet = "cabinets", x = 528, y = 32, w = 48, h = 25 },
        wall_cabinet_short_b = { sheet = "cabinets", x = 624, y = 32, w = 48, h = 25 },
    },
}
