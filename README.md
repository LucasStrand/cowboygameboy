# Six Chambers

A 2D cowboy roguelike platformer built with LOVE2D 11.5 and Lua.

The combat/build overhaul is implemented through Phase 8 in code, including the recap/export closeout. Phase 9 exists as a plan only and has not started yet. The source-of-truth roadmap lives in [docs/combat_build_overhaul_roadmap.md](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/docs/combat_build_overhaul_roadmap.md).

## How to Run

1. Install [LOVE2D 11.5](https://love2d.org/).
2. Run from the repo root:

```text
love .
```

On Windows you can also drag the folder onto `love.exe`.

## Debug and Tools

- `F1` toggles the debug overlay during gameplay.
- `F2` opens the in-run dev panel when debug tools are enabled.
- The main menu includes `World Editor` and `Dev arena` entries for fast testing.

## Current Game Loop

1. Start in the first combat world.
2. Fight through chunk-built combat rooms and clear enemies to unlock exits.
3. Every 5 rooms, enter the saloon checkpoint for shop and casino systems.
4. Progress through the current world order: desert -> train -> forest.
5. On death, the run ends on a short cinematic game-over screen followed by a dedicated recap/export flow built from run metadata.

## Current Runtime Focus

- Weapon state is owned by `weapon_runtime`.
- Direct-hit damage is owned by `damage_resolver`.
- Player and enemy statuses share the `buffs` runtime.
- Proc and payoff rules run through `proc_runtime` plus presentation hooks.
- Rewards, rerolls, shop offers, and build profiling run through `reward_runtime`.
- Recap and run tracking are owned by `run_metadata` and `meta_runtime`.
- Local score history/export plumbing currently sits on top of that truth seam.

## Content Snapshot

- 3 player guns: revolver, blunderbuss, AK-47.
- 13 perks, including proc and explosive/ricochet interactions.
- 9 gear items across hat, vest, and boots.
- 7 enemy definitions, including bosses.
- 3 combat worlds plus the saloon hub.
- V1 combat statuses including bleed, burn, shock, wet, stun, and slow.

## Repo Layout

```text
main.lua / conf.lua        LOVE2D entry point and window config
docs/                     Roadmap, specs, and phase logs
src/states/               Menu, game, levelup, saloon, editor, gameover, boot intro
src/entities/             Player, enemies, bullets, pickups, NPCs
src/systems/              Combat, resolver/runtime systems, rewards, metadata, world assembly
src/data/                 Guns, perks, gear, enemies, statuses, worlds, hooks, templates
src/ui/                   HUD, dev panel, perk cards, recap-facing UI helpers
assets/                   Sprites, tiles, backgrounds, music, SFX
tmp/                      Harnesses and verification artifacts
```

## Notes

- The game renders to a resizable canvas and shows more world on larger windows.
- The project now uses a mix of authored pixel-art assets and procedural rendering.
- For collaborator-facing context, see [GAME_CONTEXT.md](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/GAME_CONTEXT.md).
