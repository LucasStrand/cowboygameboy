# Six Chambers - Prompt Context

Use this file when writing prompts or briefing collaborators. It reflects the current codebase, not the original prototype scope.

## Identity

Six Chambers is a 2D cowboy roguelike platformer built with LOVE2D 11.5 and Lua. The current game mixes platform combat, weapon/runtime-heavy build systems, casino and shop checkpoints, and run recap metadata.

## Current Project Status

- Combat/build overhaul Phases 2-8 are in code.
- Phase 8 is closed in code and documentation, including the live recap/export closeout.
- Phase 9 readability work is not started in code yet.

## Core Run Structure

- Main menu supports normal play, a world editor, and a dev arena.
- Combat progression currently moves through `desert -> train -> forest`.
- Each combat world uses chunk-authored room content and a 5-room checkpoint cadence.
- After each 5-room segment, the run enters the saloon for shop and casino flows.
- Death routes into a metadata-driven recap/game-over screen.

## Runtime Ownership

- `weapon_runtime.lua`: authoritative weapon slots, ammo, cooldowns, reloads, resolved weapon stats.
- `damage_resolver.lua`: authoritative direct-hit resolution and delayed secondary hits.
- `buffs.lua`: shared player/enemy status runtime.
- `proc_runtime.lua`: perk-driven proc evaluation and delayed proc packets.
- `presentation_runtime.lua`: event-owned payoff and status presentation hooks.
- `reward_runtime.lua`: level-up rewards, shop generation, rerolls, build profiling.
- `run_metadata.lua`: canonical run history.
- `meta_runtime.lua`: read-only summary and recap projection.

## Current Content Snapshot

- Guns: revolver, blunderbuss, AK-47.
- Perks: 13 current perks, including explosive rounds, ricochet, akimbo, and `phantom_third`.
- Gear: hat, vest, boots.
- Statuses: v1 combat statuses plus migrated boon/debuff compatibility paths.
- Enemies: standard combat enemies plus boss definitions.
- Worlds: desert, train, forest, plus saloon support data.

## Player-Facing Systems In Code

- Mouse-aimed shooting, reload, melee, dash, double jump, shielding/blocking, Dead Man's Hand ultimate.
- Resolver-owned direct-hit damage families and proc-safe delayed hits.
- Shared status system for player and enemies with cleanse/purge/consume behavior.
- Tooltip/template pipeline for perks, guns, gear, statuses, and shop offers.
- Build-aware rewards, rerolls, economy tracking, and run recap summaries.
- A two-step death flow with cinematic end screen plus dedicated recap/export screen.
- Dev tooling for reward/meta/status verification plus a dedicated dev arena.

## Prompting Guidance

1. Treat the roadmap docs as canonical for phase status:
   [docs/combat_build_overhaul_roadmap.md](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/docs/combat_build_overhaul_roadmap.md)
2. Put gameplay data in `src/data/` unless a runtime owner clearly belongs in `src/systems/`.
3. Keep new combat logic aligned with the existing runtime ownership instead of adding ad hoc logic back into `player.lua` or `combat.lua`.
4. Preserve the western tone: grounded cowboy language, saloon/casino flavor, frontier violence.
5. Do not describe Phase 9 readability work as implemented unless the code actually lands the planned recap/HUD readability slice beyond the current recap/export baseline.
