# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Game

**Requirement:** LOVE2D 11.5 installed ([love2d.org](https://love2d.org/))

```bash
love .
```

On Windows you can also drag the project folder onto `love.exe`. No compilation step — it's pure Lua.

**Debug mode:** Press `F1` during gameplay to toggle the debug overlay (hitboxes, effective stats, active perks, event log).

## Architecture

**Six Chambers** is a 2D cowboy roguelike platformer. The stack is LOVE2D + Lua with these third-party libs in `/lib/`:
- **bump.lua** — AABB collision detection for all dynamic entities
- **hump/gamestate.lua** — State machine managing all screen transitions
- **hump/camera.lua**, **hump/vector.lua**, **hump/timer.lua** — Utilities

### State Machine Flow

```
menu → game ──(every 5 rooms)──→ saloon → game
              ↓ level up                   ↑
           levelup ──────────────────────→
              ↓ death
           gameover
```

All states live in `src/states/`. The `game` state is the main loop — it owns the room, player, enemies, bullets, and pickups, and delegates to systems for processing.

### Key Systems (`src/systems/`)

| File | Responsibility |
|---|---|
| `combat.lua` | Bullet updates, collision, AOE explosions, loot drops, pickup collection |
| `room_manager.lua` | Generates 5-room sequences, loads room layouts, scales difficulty, spawns enemies |
| `progression.lua` | XP tracking, leveling, perk rolling and application |
| `inventory.lua` | Gear equipping (hat/vest/boots slots), stat bonuses |
| `blackjack.lua` | Full blackjack card game for saloon gambling |
| `shop.lua` | Bartender shop (healing, gear, ammo) |

### Entities (`src/entities/`)

- **player.lua** — AABB movement with gravity, coyote time, jump buffering, double jump, dash; revolver reload mechanic; perk stat application
- **enemy.lua** — Three AI types: Bandit (melee), Gunslinger (ranged), Buzzard (flying); simple behavior trees
- **bullet.lua** — Projectiles supporting ricochet and explosive rounds
- **pickup.lua** — Loot drops (XP/gold/health) with gravity and bob animation

### Data (`src/data/`)

All game content is defined as plain Lua tables — easy to tune without touching logic:
- `perks.lua` — 12 perks
- `enemies.lua` — 3 enemy type definitions with scaling formula
- `gear.lua` — 9 gear items across 3 tiers
- `rooms.lua` — 4 hand-crafted room layouts (platforms, spawn points, door positions)

### Difficulty Scaling

`difficulty = 1 + (rooms_cleared × 0.3)` — multiplied into all enemy HP, damage, XP, and gold values.

### Rendering

`main.lua` renders to a canvas matching the **window size** (resizable); the camera sees **more world** when the window is larger. HUD stays fixed-size in canvas pixels. Linear filtering on the canvas and `src/ui/font.lua` for UI text. The parallax background scrolls at 30% camera speed. All graphics are procedural shapes (no sprite sheets); audio is placeholder.
