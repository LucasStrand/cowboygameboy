# Character Skin Template

Reference spec for creating new character skins compatible with the cowboygameboy animation system.

---

## Sprite Format

| Property | Value |
|---|---|
| Frame size | 48 × 48 px per frame |
| Strip orientation | Horizontal (left to right) |
| Strip height | 48 px |
| Strip width | frame_count × 48 px |
| Color mode | RGBA PNG |
| Filtering | Nearest-neighbor (no anti-aliasing) |
| Draw scale | 0.85× (renders at ~41 px) |
| Direction | Right-facing (`east`). Engine mirrors horizontally for left. |
| Pixel art style | Black outline, medium-to-high detail, medium shading |

---

## Required Animation Strips

All strips live in `assets/sprites/<skin_name>/`.

| File | Frames | FPS | Loop | Engine Use | Animation Notes |
|---|---|---|---|---|---|
| `idle.png` | 7 | 6 | yes | Standing still | Subtle breathing/shift |
| `smoking.png` | 9 | 5 | yes | Extended idle (3 s+) | Drink/smoke gesture |
| `run.png` | 8 | 10 | yes | Ground movement | Full run cycle |
| `draw.png` | 6 | 16 | yes | Jump / fall / dash (frames 1-3 used for dash) | Mid-air body tense |
| `shoot.png` | 5 | 14 | no | Fire weapon | Arm-forward recoil, weapon drawn as overlay |
| `holster.png` | 8 | 12 | no | Weapon switch | Reach down to hip |
| `holster_spin.png` | 14 | 14 | no | Akimbo weapon swap | Combat idle spin |
| `quickdraw.png` | 6 | 14 | no | Melee swing (starts frame 1) | Forward punch/jab |

> **Tip:** The `draw.png` strip doubles as jump, fall, and dash. Frames 1-3 are used for dash; the full strip plays for jump/fall.

---

## Weapon Hand Position (Critical)

Weapons are rendered as separate sprite overlays — they are NOT baked into the character frames. The character animation only needs to show the arm/hand in a neutral "ready to grip" position.

- **Hand anchor point**: roughly at `(sprite_width × 0.65, sprite_height × 0.42)` from top-left of the frame
- Keep the right hand open and forward in `idle`, `run`, `shoot`, and `draw` frames
- The engine calculates `aimAngle` and rotates the weapon overlay around the hand anchor
- In `holster` frames the hand drops to the hip — the weapon overlay is hidden during this animation
- Akimbo mode renders two weapon overlays staggered ±4 px on Y from the hand anchor

---

## PixelLab Generation Settings (Baseline)

When generating a new skin with PixelLab, use these settings as a starting point:

```
Tool: create_character
  size: 48
  view: "side"
  n_directions: 8          (generate all; game uses east + mirror)
  mode: "standard"
  shading: "medium shading"
  detail: "high detail"
  outline: "single color black outline"
  proportions: {"type": "preset", "name": "stylized"}
  ai_freedom: 750
```

### Animation jobs to queue (template-based, cheap)

| animation_name | template_animation_id | directions |
|---|---|---|
| idle | `breathing-idle` | `["east"]` |
| smoking | `drinking` | `["east"]` |
| run | `running-8-frames` | `["east"]` |
| draw | `jumping-1` | `["east"]` |
| shoot | `throw-object` | `["east"]` |
| holster | `picking-up` | `["east"]` |
| quickdraw | `lead-jab` | `["east"]` |
| holster_spin | `fight-stance-idle-8-frames` | `["east"]` |

> Use `directions: ["east"]` to stay within the 8-slot job limit. The game engine mirrors east for west.

---

## Registering a New Skin

1. Drop all 8 PNGs into `assets/sprites/<skin_name>/`
2. Open `src/systems/animation.lua` and find the `ANIMATIONS` table at the top
3. Add an entry (or swap the path prefix) pointing to the new skin folder
4. In `src/player.lua` find `animSystem = Animation.new(...)` and update the skin path argument

### Skin path config (player.lua)

```lua
-- Change "cowboy" to your skin folder name:
local SKIN = "cowboy"
animSystem = Animation.new("assets/sprites/" .. SKIN .. "/", ANIMATIONS)
```

---

## Frame Extraction Cheatsheet

If PixelLab returns individual frame PNGs, stitch them into a horizontal strip:

```bash
# ImageMagick — stitch N frames left-to-right:
magick +append frame_0.png frame_1.png ... frame_N.png output_strip.png
```

If PixelLab returns a sprite sheet zip, each animation will have its own sub-folder.
Rename files to match the table above and place them in `assets/sprites/<skin_name>/`.

---

## Existing Skins

| Folder | Status | Notes |
|---|---|---|
| `assets/sprites/cowboy/` | Active (default) | Original hand-authored strips |
| `assets/sprites/cowboy_v2/` | Active (generated) | PixelLab-generated, character_id: `e4dda30e-08d1-4fbe-b4fe-97bb2b46a52e` |
| `assets/sprites/gunslinger/` | Partial | walk + shoot only |
| `assets/sprites/bandit/` | Partial | walk only |

---

## Style Notes (Western Tone)

- Keep the silhouette readable at 41 px rendered height — hat brim and gun holster are key identifiers
- Bandana, duster coat, spurs: iconic western reads even at low res
- Avoid bright neon colors — muted earth tones (tan, brown, dusty red, faded denim)
- Blood/damage tint: the engine applies a red flash on hit — no need to bake hurt frames
- Death animation optional; engine currently fades/flips on death if strip absent
