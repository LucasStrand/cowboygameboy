# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Game

Requirement: LOVE2D 11.5

```text
love .
```

Dev/debug boot (enables dev panel and skips intro): `love . --dev` (also accepts `--debug`, `--dev-arena`)

Phase 10 regression (metadata/recap/persist/export seams): `love . --phase10-regression`

Phase 10 dev: metadata snapshot + stress sample workflow — [docs/phases/phase_10_hardening.md](docs/phases/phase_10_hardening.md).

Phase 11 regression (actor defense, attack profiles, enemy proc path): `love . --phase11-actor-regression`

On Windows you can also drag the repo folder onto `love.exe`.

There is no test suite or lint configuration — regression modes above are the primary verification mechanism.

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
game -> gameover -> run_recap
```

`src/states/game.lua` is the main runtime owner for the active run and wires together combat, rewards, metadata, presentation, and dev tooling. It uses a centralized `Mods` table to pass all required modules into the state, working around Lua's 60-upvalue closure limit.

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
- `src/data/chunks/`: chunk-authored room content by world (desert, train, forest)

## Architectural Guidelines

- Put gameplay data in `src/data/` unless it clearly belongs to a runtime owner in `src/systems/`.
- Do not add ad hoc combat logic back into `player.lua` or `combat.lua` — keep new logic aligned with the existing runtime owners above.
- Preserve the western tone: grounded cowboy language, saloon/casino flavor, frontier violence.
- The canonical roadmap for phase status lives in `docs/combat_build_overhaul_roadmap.md`.

## Current High-Level Status

- Combat/build overhaul is implemented through Phase 8, with **Phase 9 slice 1** (readability) and **Phase 10 slice 1** (retention/hardening harness) landed in code.
- Mid-run save/load of full run metadata remains a future hardening slice.

## Content Snapshot

- Guns: revolver, blunderbuss, AK-47
- Perks: 13 (including explosive rounds, ricochet, akimbo, phantom_third)
- Gear: hat, vest, boots slots
- Statuses: bleed, burn, shock, wet, stun, slow
- Enemies: 7 definitions including bosses
- Worlds: desert → train → forest, with saloon checkpoints every 5 rooms

## Rendering Notes

- The game renders to a canvas matching the window size (`GAME_WIDTH`/`GAME_HEIGHT` globals, default 1280×720).
- Larger windows show more world; HUD uses fixed pixel sizes and does not scale.
- The project uses both authored pixel-art assets and procedural drawing.
