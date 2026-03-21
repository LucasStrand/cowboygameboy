import struct
import zlib
from pathlib import Path


FRAME_W = 64
FRAME_H = 64
SCALE = 2
LOGICAL_W = FRAME_W // SCALE
LOGICAL_H = FRAME_H // SCALE

ANIMS = {
    "idle": 4,
    "walk": 6,
    "attack": 5,
    "hurt": 2,
}

TRANSPARENT = (0, 0, 0, 0)
OUTLINE = (24, 18, 12, 255)
SKIN_DARK = (52, 96, 49, 255)
SKIN_MID = (86, 150, 78, 255)
SKIN_LIGHT = (134, 204, 114, 255)
SKIN_SHADE = (68, 123, 63, 255)
VEST = (78, 46, 34, 255)
LEATHER = (122, 80, 46, 255)
BELT = (164, 121, 62, 255)
METAL = (214, 198, 142, 255)
EYE = (251, 236, 158, 255)
PANTS = (58, 67, 94, 255)
BOOT = (68, 42, 29, 255)
TOOTH = (239, 225, 195, 255)
NOSE = (84, 128, 67, 255)


def blank_frame():
    return [[TRANSPARENT for _ in range(LOGICAL_W)] for _ in range(LOGICAL_H)]


def put(frame, x, y, color):
    if 0 <= x < LOGICAL_W and 0 <= y < LOGICAL_H:
        frame[y][x] = color


def fill_rect(frame, x, y, w, h, color):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            put(frame, xx, yy, color)


def fill_ellipse(frame, cx, cy, rx, ry, color):
    for yy in range(cy - ry - 1, cy + ry + 2):
        for xx in range(cx - rx - 1, cx + rx + 2):
            dx = (xx - cx) / max(rx, 1)
            dy = (yy - cy) / max(ry, 1)
            if dx * dx + dy * dy <= 1.0:
                put(frame, xx, yy, color)


def draw_line(frame, x0, y0, x1, y1, thickness, color):
    steps = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(steps + 1):
        t = i / steps
        x = round(x0 + (x1 - x0) * t)
        y = round(y0 + (y1 - y0) * t)
        fill_ellipse(frame, x, y, thickness, thickness, color)


def shade_lower(frame, color_from, color_to, y_cutoff):
    for y in range(y_cutoff, LOGICAL_H):
        for x in range(LOGICAL_W):
            if frame[y][x] == color_from:
                frame[y][x] = color_to


def shade_right(frame, color_from, color_to, x_cutoff):
    for y in range(LOGICAL_H):
        for x in range(x_cutoff, LOGICAL_W):
            if frame[y][x] == color_from:
                frame[y][x] = color_to


def add_outline(frame):
    original = [row[:] for row in frame]
    for y in range(LOGICAL_H):
        for x in range(LOGICAL_W):
            if original[y][x][3] != 0:
                continue
            for yy in range(max(0, y - 1), min(LOGICAL_H, y + 2)):
                found = False
                for xx in range(max(0, x - 1), min(LOGICAL_W, x + 2)):
                    if original[yy][xx][3] != 0:
                        frame[y][x] = OUTLINE
                        found = True
                        break
                if found:
                    break


def draw_head(frame, x, y, mouth_open=False, grimace=False):
    fill_ellipse(frame, x, y, 7, 6, SKIN_MID)
    fill_ellipse(frame, x, y + 1, 6, 5, SKIN_LIGHT)
    fill_rect(frame, x - 5, y - 5, 11, 2, LEATHER)
    fill_rect(frame, x - 3, y - 7, 7, 3, LEATHER)
    fill_rect(frame, x - 6, y + 4, 13, 2, SKIN_SHADE)
    put(frame, x - 3, y, EYE)
    put(frame, x + 3, y, EYE)
    put(frame, x - 1, y + 2, NOSE)
    put(frame, x, y + 2, NOSE)
    if mouth_open:
        fill_rect(frame, x - 3, y + 5, 6, 2, OUTLINE)
        put(frame, x - 3, y + 5, TOOTH)
        put(frame, x + 2, y + 5, TOOTH)
    else:
        fill_rect(frame, x - 4, y + 5, 2, 1, TOOTH)
        fill_rect(frame, x + 2, y + 5, 2, 1, TOOTH)
    if grimace:
        put(frame, x - 5, y + 1, TOOTH)
        put(frame, x + 5, y + 1, TOOTH)


def draw_torso(frame, x, y, lean=0, belt_shift=0):
    fill_ellipse(frame, x + lean, y, 10, 8, SKIN_MID)
    fill_ellipse(frame, x + lean, y + 1, 9, 7, SKIN_LIGHT)
    fill_rect(frame, x - 6 + lean, y - 4, 13, 9, VEST)
    fill_rect(frame, x - 5 + lean, y - 2, 3, 5, LEATHER)
    fill_rect(frame, x + 3 + lean, y - 3, 3, 6, LEATHER)
    draw_line(frame, x - 4 + lean, y - 4, x - 1 + lean, y + 4, 0, BELT)
    draw_line(frame, x + 4 + lean, y - 4, x + 1 + lean, y + 4, 0, BELT)
    fill_rect(frame, x - 6 + lean, y + 4, 13, 2, BELT)
    fill_rect(frame, x - 1 + lean + belt_shift, y + 4, 3, 2, METAL)


def draw_arm(frame, shoulder_x, shoulder_y, elbow_x, elbow_y, hand_x, hand_y):
    draw_line(frame, shoulder_x, shoulder_y, elbow_x, elbow_y, 1, SKIN_MID)
    draw_line(frame, elbow_x, elbow_y, hand_x, hand_y, 1, SKIN_SHADE)
    fill_ellipse(frame, hand_x, hand_y, 2, 2, SKIN_LIGHT)


def draw_leg(frame, hip_x, hip_y, foot_x, foot_y):
    draw_line(frame, hip_x, hip_y, foot_x, foot_y - 2, 1, PANTS)
    fill_rect(frame, foot_x - 2, foot_y - 1, 4, 2, BOOT)


def pose_for(anim, frame_idx):
    if anim == "idle":
        return {
            "bob": [0, -1, 0, 1][frame_idx],
            "lean": [0, 0, 1, 0][frame_idx],
            "left_arm": (7, 18, 5, 22, 4, 26),
            "right_arm": (24, 18, 26, 22, 27, 25),
            "left_leg": (12, 26, 12, 31),
            "right_leg": (18, 26, 19, 31),
            "mouth_open": False,
            "grimace": False,
        }
    if anim == "walk":
        return [
            {"bob": 0, "lean": 1, "left_arm": (7, 18, 4, 21, 3, 25), "right_arm": (24, 18, 27, 21, 28, 26), "left_leg": (12, 26, 10, 31), "right_leg": (18, 26, 20, 30)},
            {"bob": 1, "lean": 1, "left_arm": (7, 19, 5, 22, 4, 26), "right_arm": (24, 17, 26, 20, 27, 24), "left_leg": (12, 27, 11, 30), "right_leg": (18, 25, 20, 31)},
            {"bob": 0, "lean": 0, "left_arm": (7, 18, 6, 22, 5, 26), "right_arm": (24, 18, 25, 22, 26, 26), "left_leg": (12, 26, 12, 31), "right_leg": (18, 26, 18, 31)},
            {"bob": 1, "lean": -1, "left_arm": (7, 17, 8, 20, 9, 24), "right_arm": (24, 19, 22, 22, 21, 26), "left_leg": (12, 25, 14, 31), "right_leg": (18, 27, 17, 30)},
            {"bob": 0, "lean": -1, "left_arm": (7, 18, 9, 21, 10, 26), "right_arm": (24, 18, 21, 21, 20, 25), "left_leg": (12, 26, 14, 30), "right_leg": (18, 26, 16, 31)},
            {"bob": 0, "lean": 0, "left_arm": (7, 18, 6, 22, 5, 26), "right_arm": (24, 18, 25, 22, 26, 26), "left_leg": (12, 26, 12, 31), "right_leg": (18, 26, 18, 31)},
        ][frame_idx]
    if anim == "attack":
        return [
            {"bob": 0, "lean": 0, "left_arm": (7, 18, 5, 16, 5, 12), "right_arm": (24, 18, 26, 16, 26, 12), "left_leg": (12, 26, 11, 31), "right_leg": (18, 26, 20, 30), "mouth_open": False, "grimace": False},
            {"bob": -1, "lean": 1, "left_arm": (7, 17, 4, 13, 5, 9), "right_arm": (24, 17, 27, 13, 26, 9), "left_leg": (12, 25, 11, 31), "right_leg": (18, 25, 19, 30), "mouth_open": True, "grimace": False},
            {"bob": 0, "lean": 2, "left_arm": (7, 18, 9, 14, 12, 12), "right_arm": (24, 18, 22, 14, 19, 12), "left_leg": (12, 26, 10, 31), "right_leg": (18, 26, 20, 30), "mouth_open": True, "grimace": True},
            {"bob": 1, "lean": 1, "left_arm": (7, 19, 10, 18, 13, 19), "right_arm": (24, 19, 21, 18, 18, 19), "left_leg": (12, 27, 12, 31), "right_leg": (18, 27, 19, 31), "mouth_open": True, "grimace": False},
            {"bob": 0, "lean": 0, "left_arm": (7, 18, 6, 20, 5, 24), "right_arm": (24, 18, 25, 20, 26, 24), "left_leg": (12, 26, 12, 31), "right_leg": (18, 26, 18, 31), "mouth_open": False, "grimace": False},
        ][frame_idx]
    if anim == "hurt":
        return [
            {"bob": 0, "lean": -2, "left_arm": (7, 18, 5, 20, 3, 23), "right_arm": (24, 18, 22, 16, 20, 13), "left_leg": (12, 26, 11, 31), "right_leg": (18, 26, 17, 30), "mouth_open": True, "grimace": True},
            {"bob": 1, "lean": -1, "left_arm": (7, 19, 6, 22, 4, 26), "right_arm": (24, 19, 21, 18, 19, 16), "left_leg": (12, 27, 11, 31), "right_leg": (18, 27, 18, 31), "mouth_open": False, "grimace": True},
        ][frame_idx]
    raise ValueError(anim)


def build_frame(anim, frame_idx):
    frame = blank_frame()
    pose = pose_for(anim, frame_idx)
    bob = pose["bob"]
    lean = pose["lean"]

    draw_head(frame, 15 + lean, 8 + bob, pose.get("mouth_open", False), pose.get("grimace", False))
    draw_torso(frame, 15, 20 + bob, lean=lean)
    draw_arm(frame, *pose["left_arm"])
    draw_arm(frame, *pose["right_arm"])
    draw_leg(frame, *pose["left_leg"])
    draw_leg(frame, *pose["right_leg"])

    shade_right(frame, SKIN_LIGHT, SKIN_MID, 16 + max(0, lean))
    shade_right(frame, SKIN_MID, SKIN_SHADE, 22)
    shade_right(frame, VEST, LEATHER, 17)
    shade_lower(frame, SKIN_LIGHT, SKIN_MID, 14 + bob)
    shade_lower(frame, SKIN_MID, SKIN_DARK, 24 + bob)
    add_outline(frame)
    return frame


def upscale_and_pack(frames):
    width = FRAME_W * len(frames)
    height = FRAME_H
    rows = []
    for y in range(height):
        logical_y = y // SCALE
        row = bytearray([0])
        for frame in frames:
            for x in range(FRAME_W):
                logical_x = x // SCALE
                row.extend(frame[logical_y][logical_x])
        rows.append(bytes(row))
    return width, height, b"".join(rows)


def png_chunk(tag, data):
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def save_png(path, width, height, raw_rgba):
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    payload = zlib.compress(raw_rgba, 9)
    png = [
        b"\x89PNG\r\n\x1a\n",
        png_chunk(b"IHDR", ihdr),
        png_chunk(b"IDAT", payload),
        png_chunk(b"IEND", b""),
    ]
    path.write_bytes(b"".join(png))


def main():
    out_dir = Path("assets/sprites/ogreboss")
    out_dir.mkdir(parents=True, exist_ok=True)
    for anim, frames_count in ANIMS.items():
        frames = [build_frame(anim, i) for i in range(frames_count)]
        width, height, payload = upscale_and_pack(frames)
        out_path = out_dir / f"{anim}.png"
        save_png(out_path, width, height, payload)
        print(f"wrote {out_path} ({width}x{height})")


if __name__ == "__main__":
    main()
