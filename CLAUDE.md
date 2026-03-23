# CLAUDE.md

This file gives current repository guidance for coding agents working in this project.

## Running the Game

Requirement: LOVE2D 11.5

```text
love .
```

Phase 10 regression (metadata/recap/persist/export seams): `love . --phase10-regression`

Phase 10 dev: metadata snapshot + stress sample workflow — [docs/phases/phase_10_hardening.md](docs/phases/phase_10_hardening.md).

Phase 11 regression (actor defense, attack profiles, enemy proc path): `love . --phase11-actor-regression`

On Windows you can also drag the repo folder onto `love.exe`.

## Debug and Development Tools

- `F1` toggles the gameplay debug overlay.
- `F2` opens the in-run dev panel when debug tools are enabled.
- The main menu exposes `World Editor` and `Dev arena`.

## State Flow

```text
boot_intro -> menu -> game
menu -> editor
game -> levelup -> game
game -> saloon -> game
game -> gameover
```

`src/states/game.lua` is still the main runtime owner for the active run and wires together combat, rewards, metadata, presentation, and dev tooling.

## Key Runtime Owners

| File | Responsibility |
|---|---|
| `src/systems/weapon_runtime.lua` | Authoritative weapon slot state, ammo, reload, cooldown, resolved weapon stats |
| `src/systems/damage_resolver.lua` | Direct-hit resolution, crit/mitigation ordering, delayed secondary hits |
| `src/systems/buffs.lua` | Shared status runtime for player and enemies |
| `src/systems/proc_runtime.lua` | Canonical proc evaluation and delayed proc packets |
| `src/systems/presentation_runtime.lua` | Event-driven payoff and status presentation hooks |
| `src/systems/reward_runtime.lua` | Level-up rewards, shop offers, rerolls, build profiling |
| `src/systems/run_metadata.lua` | Canonical run history |
| `src/systems/meta_runtime.lua` | Read-only recap/debug summaries |
| `src/systems/room_manager.lua` | World progression, room sequencing, checkpoint cadence |

## Current Data Shape

- `src/data/guns.lua`: current gun definitions and attack-profile metadata
- `src/data/perks.lua`: current perk pool, tags, tooltip metadata, proc rules
- `src/data/gear.lua`: gear pool and tags
- `src/data/statuses.lua`: canonical status definitions and lifecycle hook metadata
- `src/data/presentation_hooks.lua`: payoff/status presentation hooks
- `src/data/tooltip_templates.lua`: content tooltip text templates
- `src/data/worlds.lua`: combat world ordering and world definitions
- `src/data/chunks/`: chunk-authored room content by world

## Current High-Level Status

- Combat/build overhaul is implemented through Phase 8, with **Phase 9 slice 1** (readability) and **Phase 10 slice 1** (retention/hardening harness) landed in code.
- Mid-run save/load of full run metadata remains a future hardening slice.

## Rendering Notes

- The game renders to a canvas matching the window size.
- Larger windows show more world.
- The project now uses both authored sprite assets and procedural drawing.
