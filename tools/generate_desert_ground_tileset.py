from pathlib import Path
import struct
import zlib

TILE = 16
ATLAS_COLS = 6
ATLAS_ROWS = 3

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "terrain" / "desert" / "generated_ground"
ATLAS_PATH = OUT_DIR / "desert_ground_manual_atlas.png"
ATLAS_PREVIEW_PATH = OUT_DIR / "desert_ground_manual_atlas_preview.png"
SCENE_PREVIEW_PATH = OUT_DIR / "desert_ground_manual_scene_preview.png"

TRANSPARENT = (0, 0, 0, 0)
SKY = (215, 183, 129, 255)
SKY_DARK = (169, 126, 82, 255)
SAND_LIGHT = (250, 231, 172, 255)
SAND_BASE = (236, 198, 121, 255)
SAND_SHADE = (212, 167, 92, 255)
DIRT_LIGHT = (197, 140, 80, 255)
DIRT_MID = (159, 107, 59, 255)
DIRT_DARK = (120, 75, 42, 255)
DIRT_DEEP = (86, 52, 31, 255)
STONE = (204, 157, 107, 255)
WOOD_LIGHT = (173, 121, 73, 255)
WOOD_MID = (132, 88, 51, 255)
WOOD_DARK = (93, 58, 36, 255)
ACCENT = (103, 62, 36, 255)

TILE_LAYOUT = {
    "grass_l": (0, 0),
    "grass_m": (1, 0),
    "grass_r": (2, 0),
    "grass_bl": (3, 0),
    "grass_bm": (4, 0),
    "grass_br": (5, 0),
    "dirt_l": (0, 1),
    "dirt": (1, 1),
    "dirt2": (2, 1),
    "dirt3": (3, 1),
    "dirt_r": (4, 1),
    "dirt_bm": (5, 1),
    "dirt_bl": (0, 2),
    "dirt_br": (1, 2),
    "plank_l": (2, 2),
    "plank_m": (3, 2),
    "plank_r": (4, 2),
    "spare": (5, 2),
}


def make_image(width, height, color=TRANSPARENT):
    return [color] * (width * height)


def index(width, x, y):
    return y * width + x


def set_px(img, width, x, y, color):
    if 0 <= x < width:
        height = len(img) // width
        if 0 <= y < height:
            img[index(width, x, y)] = color


def get_px(img, width, x, y):
    if 0 <= x < width:
        height = len(img) // width
        if 0 <= y < height:
            return img[index(width, x, y)]
    return TRANSPARENT


def fill_rect(img, width, x0, y0, rect_w, rect_h, color):
    for y in range(y0, y0 + rect_h):
        for x in range(x0, x0 + rect_w):
            set_px(img, width, x, y, color)


def paste(src, src_w, dst, dst_w, ox, oy):
    src_h = len(src) // src_w
    for y in range(src_h):
        for x in range(src_w):
            px = get_px(src, src_w, x, y)
            if px[3]:
                set_px(dst, dst_w, ox + x, oy + y, px)


def scale_nearest(src, src_w, scale):
    src_h = len(src) // src_w
    dst_w = src_w * scale
    dst_h = src_h * scale
    dst = make_image(dst_w, dst_h)
    for y in range(src_h):
        for x in range(src_w):
            color = get_px(src, src_w, x, y)
            if not color[3]:
                continue
            for sy in range(scale):
                for sx in range(scale):
                    set_px(dst, dst_w, x * scale + sx, y * scale + sy, color)
    return dst, dst_w, dst_h


def write_chunk(handle, chunk_type, data):
    handle.write(struct.pack(">I", len(data)))
    handle.write(chunk_type)
    handle.write(data)
    crc = zlib.crc32(chunk_type)
    crc = zlib.crc32(data, crc)
    handle.write(struct.pack(">I", crc & 0xFFFFFFFF))


def write_png(path, width, height, pixels):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        row_start = y * width
        for x in range(width):
            raw.extend(bytes(pixels[row_start + x]))
    compressed = zlib.compress(bytes(raw), level=9)
    with path.open("wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        write_chunk(handle, b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        write_chunk(handle, b"IDAT", compressed)
        write_chunk(handle, b"IEND", b"")


def darken(color, amount):
    return (
        max(0, color[0] - amount),
        max(0, color[1] - amount),
        max(0, color[2] - amount),
        color[3],
    )


def lighten(color, amount):
    return (
        min(255, color[0] + amount),
        min(255, color[1] + amount),
        min(255, color[2] + amount),
        color[3],
    )


def ground_profile(kind):
    profiles = {
        "left": [2, 2, 1, 1, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1, 1],
        "mid": [1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1],
        "right": [1, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 2, 2],
        "heavy_left": [3, 2, 2, 1, 1, 1, 0, 0, 1, 1, 1, 0, 1, 1, 2, 2],
        "heavy_mid": [2, 1, 1, 1, 0, 0, 1, 1, 0, 1, 1, 0, 0, 1, 1, 2],
        "heavy_right": [2, 2, 1, 1, 0, 1, 1, 1, 0, 0, 1, 1, 1, 2, 2, 3],
    }
    return profiles[kind]


def dirt_color(y, seed):
    if y <= 5:
        base = DIRT_LIGHT
    elif y <= 8:
        base = DIRT_MID
    elif y <= 12:
        base = DIRT_DARK
    else:
        base = DIRT_DEEP
    if (y + seed) % 5 == 0:
        return darken(base, 4)
    if (y + seed) % 7 == 0:
        return lighten(base, 4)
    return base


def add_pebbles(tile, variant):
    pebble_sets = {
        0: [(3, 6), (10, 7), (6, 11), (12, 12)],
        1: [(5, 5), (11, 8), (3, 10), (8, 13)],
        2: [(2, 7), (8, 6), (12, 10), (5, 13)],
        3: [(4, 6), (10, 9), (6, 12), (13, 13)],
        4: [(3, 8), (12, 7), (7, 11), (9, 13)],
    }
    for x, y in pebble_sets[variant]:
        tile[index(TILE, x, y)] = STONE
        if y + 1 < TILE:
            tile[index(TILE, x, y + 1)] = darken(STONE, 20)


def add_crack(tile, points):
    for x, y in points:
        if 0 <= x < TILE and 0 <= y < TILE:
            tile[index(TILE, x, y)] = ACCENT


def draw_ground_tile(profile_kind, variant_seed=0, side="mid", heavy_lip=False):
    tile = make_image(TILE, TILE)
    profile = ground_profile(profile_kind)
    for x, top in enumerate(profile):
        for y in range(top, TILE):
            if y == top:
                color = SAND_LIGHT if (x + variant_seed) % 4 else lighten(SAND_LIGHT, 6)
            elif y <= top + 1:
                color = SAND_BASE
            elif y <= top + (4 if heavy_lip else 3):
                color = SAND_SHADE if (x + y + variant_seed) % 3 else SAND_BASE
            else:
                color = dirt_color(y, variant_seed + x)
            tile[index(TILE, x, y)] = color

        lip_y = min(TILE - 1, top + (4 if heavy_lip else 3))
        tile[index(TILE, x, lip_y)] = darken(SAND_SHADE, 10)

    add_pebbles(tile, variant_seed % 5)

    if side == "left":
        for y in range(2, TILE):
            tile[index(TILE, 0, y)] = DIRT_DEEP
            tile[index(TILE, 1, y)] = DIRT_DARK
        for y in range(0, 5):
            tile[index(TILE, 0, y)] = TRANSPARENT
    elif side == "right":
        for y in range(2, TILE):
            tile[index(TILE, TILE - 1, y)] = DIRT_DEEP
            tile[index(TILE, TILE - 2, y)] = DIRT_DARK
        for y in range(0, 5):
            tile[index(TILE, TILE - 1, y)] = TRANSPARENT

    if variant_seed % 2 == 0:
        add_crack(tile, [(5, 8), (6, 9), (6, 10), (7, 11)])
    else:
        add_crack(tile, [(10, 7), (9, 8), (9, 9), (8, 10)])
    return tile


def draw_dirt_tile(variant_name):
    tile = make_image(TILE, TILE)
    seed_map = {
        "dirt_l": 1,
        "dirt": 2,
        "dirt2": 3,
        "dirt3": 4,
        "dirt_r": 5,
        "dirt_bm": 6,
        "dirt_bl": 7,
        "dirt_br": 8,
        "spare": 9,
    }
    seed = seed_map[variant_name]
    for y in range(TILE):
        for x in range(TILE):
            color = dirt_color(y, seed + x)
            if y in (4, 9) and (x + seed) % 5 == 0:
                color = lighten(color, 7)
            tile[index(TILE, x, y)] = color

    add_pebbles(tile, seed % 5)

    if variant_name in ("dirt_l", "dirt_bl"):
        for y in range(TILE):
            tile[index(TILE, 0, y)] = DIRT_DEEP
            tile[index(TILE, 1, y)] = DIRT_DARK
    if variant_name in ("dirt_r", "dirt_br"):
        for y in range(TILE):
            tile[index(TILE, TILE - 1, y)] = DIRT_DEEP
            tile[index(TILE, TILE - 2, y)] = DIRT_DARK
    if variant_name in ("dirt_bm", "dirt_bl", "dirt_br"):
        for y in range(13, TILE):
            for x in range(TILE):
                tile[index(TILE, x, y)] = darken(tile[index(TILE, x, y)], 18)
        for x in range(0, TILE, 4):
            tile[index(TILE, x, 12)] = STONE

    if variant_name == "dirt2":
        add_crack(tile, [(4, 5), (5, 5), (6, 6), (7, 7), (8, 7)])
    elif variant_name == "dirt3":
        add_crack(tile, [(10, 4), (9, 5), (8, 6), (8, 7), (7, 8), (7, 9)])
    elif variant_name == "spare":
        add_crack(tile, [(3, 6), (4, 7), (5, 8), (6, 8), (7, 9)])
    return tile


def draw_plank_tile(kind):
    tile = make_image(TILE, TILE)
    board_top = 2
    board_bottom = 7

    for y in range(board_top, board_bottom + 1):
        for x in range(TILE):
            if y == board_top:
                color = lighten(WOOD_LIGHT, 10) if x % 5 == 0 else WOOD_LIGHT
            elif y == board_bottom:
                color = WOOD_DARK
            elif y == board_top + 1:
                color = SAND_BASE if (x + y) % 6 else SAND_LIGHT
            else:
                color = WOOD_MID if (x + y) % 4 else WOOD_LIGHT
            tile[index(TILE, x, y)] = color

    for x in (5, 10):
        for y in range(board_top + 1, board_bottom):
            tile[index(TILE, x, y)] = WOOD_DARK

    for x in range(1, TILE - 1):
        if x % 4 == 1:
            tile[index(TILE, x, board_top + 1)] = SAND_LIGHT

    if kind == "left":
        for y in range(board_top + 1, board_bottom):
            tile[index(TILE, 0, y)] = WOOD_DARK
            tile[index(TILE, 1, y)] = WOOD_MID
        tile[index(TILE, 0, board_top)] = TRANSPARENT
        tile[index(TILE, 0, board_top + 1)] = TRANSPARENT
    elif kind == "right":
        for y in range(board_top + 1, board_bottom):
            tile[index(TILE, TILE - 1, y)] = WOOD_DARK
            tile[index(TILE, TILE - 2, y)] = WOOD_MID
        tile[index(TILE, TILE - 1, board_top)] = TRANSPARENT
        tile[index(TILE, TILE - 1, board_top + 1)] = TRANSPARENT

    return tile


def build_atlas():
    atlas_w = TILE * ATLAS_COLS
    atlas_h = TILE * ATLAS_ROWS
    atlas = make_image(atlas_w, atlas_h)

    tiles = {
        "grass_l": draw_ground_tile("left", variant_seed=1, side="left"),
        "grass_m": draw_ground_tile("mid", variant_seed=2),
        "grass_r": draw_ground_tile("right", variant_seed=3, side="right"),
        "grass_bl": draw_ground_tile("heavy_left", variant_seed=4, side="left", heavy_lip=True),
        "grass_bm": draw_ground_tile("heavy_mid", variant_seed=5, heavy_lip=True),
        "grass_br": draw_ground_tile("heavy_right", variant_seed=6, side="right", heavy_lip=True),
        "dirt_l": draw_dirt_tile("dirt_l"),
        "dirt": draw_dirt_tile("dirt"),
        "dirt2": draw_dirt_tile("dirt2"),
        "dirt3": draw_dirt_tile("dirt3"),
        "dirt_r": draw_dirt_tile("dirt_r"),
        "dirt_bm": draw_dirt_tile("dirt_bm"),
        "dirt_bl": draw_dirt_tile("dirt_bl"),
        "dirt_br": draw_dirt_tile("dirt_br"),
        "plank_l": draw_plank_tile("left"),
        "plank_m": draw_plank_tile("mid"),
        "plank_r": draw_plank_tile("right"),
        "spare": draw_dirt_tile("spare"),
    }

    for name, (col, row) in TILE_LAYOUT.items():
        paste(tiles[name], TILE, atlas, atlas_w, col * TILE, row * TILE)
    return atlas, atlas_w, atlas_h


def build_atlas_preview(atlas, atlas_w, atlas_h):
    scale = 8
    scaled, scaled_w, scaled_h = scale_nearest(atlas, atlas_w, scale)
    canvas_w = scaled_w + 32
    canvas_h = scaled_h + 32
    preview = make_image(canvas_w, canvas_h, SKY)

    for y in range(canvas_h):
        band = y / max(1, canvas_h - 1)
        row_color = (
            int(SKY[0] * (1 - band) + SKY_DARK[0] * band),
            int(SKY[1] * (1 - band) + SKY_DARK[1] * band),
            int(SKY[2] * (1 - band) + SKY_DARK[2] * band),
            255,
        )
        for x in range(canvas_w):
            preview[index(canvas_w, x, y)] = row_color

    paste(scaled, scaled_w, preview, canvas_w, 16, 16)

    for col in range(ATLAS_COLS + 1):
        x = 16 + col * TILE * scale
        for y in range(16, 16 + scaled_h):
            if 0 <= x < canvas_w:
                preview[index(canvas_w, x, y)] = darken(SKY_DARK, 20)
    for row in range(ATLAS_ROWS + 1):
        y = 16 + row * TILE * scale
        for x in range(16, 16 + scaled_w):
            if 0 <= y < canvas_h:
                preview[index(canvas_w, x, y)] = darken(SKY_DARK, 20)
    return preview, canvas_w, canvas_h


def pick_tile(name, atlas, atlas_w):
    col, row = TILE_LAYOUT[name]
    tile = make_image(TILE, TILE)
    for y in range(TILE):
        for x in range(TILE):
            tile[index(TILE, x, y)] = get_px(atlas, atlas_w, col * TILE + x, row * TILE + y)
    return tile


def build_scene_preview(atlas, atlas_w):
    scene_w = 224
    scene_h = 112
    scene = make_image(scene_w, scene_h, SKY)

    for y in range(scene_h):
        band = y / max(1, scene_h - 1)
        row_color = (
            int(SKY[0] * (1 - band) + SKY_DARK[0] * band),
            int(SKY[1] * (1 - band) + SKY_DARK[1] * band),
            int(SKY[2] * (1 - band) + SKY_DARK[2] * band),
            255,
        )
        for x in range(scene_w):
            scene[index(scene_w, x, y)] = row_color

    dune_y = 70
    for x in range(scene_w):
        curve = ((x // 16) % 3) - 1
        for y in range(dune_y + curve, scene_h):
            scene[index(scene_w, x, y)] = (194, 147, 88, 255)

    wall_tiles = [
        ["grass_l"] + ["grass_m"] * 7 + ["grass_r"],
        ["dirt_l"] + ["dirt", "dirt2", "dirt3", "dirt", "dirt2", "dirt3"] + ["dirt_r"],
        ["dirt_bl"] + ["dirt_bm"] * 7 + ["dirt_br"],
    ]
    start_x = 24
    start_y = 40
    for row_idx, row in enumerate(wall_tiles):
        for col_idx, name in enumerate(row):
            paste(pick_tile(name, atlas, atlas_w), TILE, scene, scene_w, start_x + col_idx * TILE, start_y + row_idx * TILE)

    platform_y = 24
    platform_x = 120
    platform_names = ["plank_l", "plank_m", "plank_m", "plank_r"]
    for col_idx, name in enumerate(platform_names):
        paste(pick_tile(name, atlas, atlas_w), TILE, scene, scene_w, platform_x + col_idx * TILE, platform_y)

    scaled, scaled_w, scaled_h = scale_nearest(scene, scene_w, 4)
    return scaled, scaled_w, scaled_h


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    atlas, atlas_w, atlas_h = build_atlas()
    atlas_preview, atlas_preview_w, atlas_preview_h = build_atlas_preview(atlas, atlas_w, atlas_h)
    scene_preview, scene_preview_w, scene_preview_h = build_scene_preview(atlas, atlas_w)

    write_png(ATLAS_PATH, atlas_w, atlas_h, atlas)
    write_png(ATLAS_PREVIEW_PATH, atlas_preview_w, atlas_preview_h, atlas_preview)
    write_png(SCENE_PREVIEW_PATH, scene_preview_w, scene_preview_h, scene_preview)

    print(f"Wrote atlas: {ATLAS_PATH}")
    print(f"Wrote atlas preview: {ATLAS_PREVIEW_PATH}")
    print(f"Wrote scene preview: {SCENE_PREVIEW_PATH}")


if __name__ == "__main__":
    main()
