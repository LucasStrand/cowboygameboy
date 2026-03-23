# Phase 05: Unified Status/CC Runtime

## Goals

- Replace the old player-only buff tracker with one shared status runtime.
- Make status instances authoritative for both player and enemies.
- Route status ticks and payoff hits through the Phase 4 damage resolver.
- Land v1 combat statuses, CC rules, remove-ops, and runtime-backed UI seams.

## Modules Added / Refactored

### `src/data/statuses.lua`

- Canonical registry for status definitions and legacy aliases.
- Includes v1 combat statuses:
  - `bleed`
  - `burn`
  - `shock`
  - `wet`
  - `stun`
  - `slow`
- Also holds migrated legacy boons/debuffs so `buffs.lua` can stay in place without split ownership.

### `src/systems/buffs.lua`

- Refactored in place into the shared status engine.
- Trackers now carry:
  - owner ref / owner actor
  - status instances
  - aggregated stat mods
  - tag counts
  - hard-CC DR state
  - visual state
- Emits:
  - `status_applied`
  - `status_refreshed`
  - `status_stacked`
  - `status_ticked`
  - `status_expired`
  - `status_removed`
- Keeps compatibility wrappers for old buff callers and HUD code.

## Runtime Changes

- Player now owns `player.statuses` as the authoritative runtime tracker.
- Enemies now own `enemy.statuses` and expose compact status badges in-world.
- `stun` blocks player and enemy action flow through status runtime checks.
- `slow` affects movement through status-driven stat aggregation.
- Status tick damage no longer mutates HP directly and instead resolves as canonical packets.
- Shock overload now:
  - consumes `shock`
  - resolves a payoff hit through the resolver
  - applies `stun`

## Content Hooks

- Runtime and packet support for future `status_applications` remains in place.
- Temporary closeout cleanup removed the hardcoded live examples from:
  - player guns
  - enemy projectile examples
  - ultimate projectile
- Phase 5 now leaves the status runtime content-neutral until future authored content adds explicit hooks.

## Debug Hooks

- Phase 5 now has a dev-only `Status Lab` in the F2 dev panel.
- Trigger method:
  - open F2
  - expand `Status Lab`
  - apply `bleed`, `burn`, `shock`, `wet`, `stun`, or `slow` to the player or the nearest living enemy
  - use `Dump`, `Cleanse`, `Purge`, `Consume`, and `Clear` actions to verify runtime state transitions
- The harness is intentionally content-neutral:
  - it does not add default gun status hooks
  - it does not add default enemy projectile status hooks
  - it does not add default ultimate status hooks
- DevLog output is the authoritative trace for:
  - applied status ids
  - stacks
  - remaining duration
  - control-state and CC timers
  - remove-op results

## Closeout Notes

- Phase 5 lands the shared runtime in code.
- Phase 4 direct-hit behavior remains the base damage path and is not reopened here.
- Temporary hardcoded live status hooks were removed during closeout so the runtime remains content-neutral until future authored content adds explicit `status_applications`.
- Post-closeout cleanup in this pass removed the live `player.buffs` alias dependency from player runtime ownership; HUD/stat-runtime readers now consume `player.statuses` first and only fall back if needed.
- Remaining direct status applications in gameplay code are intentional authored boons/debug paths, not leftover temporary verification hooks.

## Acceptance Notes

### Verified Good

- Shared status runtime exists and is wired to both player and enemies.
- Status ticks/payoff hits route through canonical damage packets instead of direct HP mutation.
- Compatibility path for legacy boons/HUD remains present through `buffs.lua`.
- Temporary authored status hooks have been removed from player guns, enemy projectile examples, and the ultimate projectile.
- bleed / burn tick pacing is verified in the LOVE runtime harness at the authored `0.5s` interval.
- shock overload triggers the payoff hit, consumes `shock`, and applies stun DR / immunity as expected.
- status HUD ordering is verified through runtime output from `Buffs.getTopStatuses`.
- player stun gating is wired across update, jump, dash, shoot, melee, and reload entry points.
- cleanse / purge / consume / expire behavior is verified in the LOVE runtime harness.

### Still Unverified In Live Visual Play

- interactive live-play verification of status feel/readability in real combat remains open in this closeout pass:
  - bleed / burn pacing under real encounter pressure
  - shock overload readability and stun DR feel in motion
  - HUD ordering under normal play
  - enemy badge readability in combat clutter
  - player stun feel while moving / jumping / dashing / reloading

### Bugs / Balance Problems Found During Closeout

- None confirmed in harness/static/boot verification.

## Verification Status

- Static repo search used to confirm no temporary authored `status_applications` remain on guns, enemy projectile examples, or the ultimate path.
- A dev-only verification harness now exists so Phase 5 can be verified without reintroducing permanent status content.
- LOVE runtime harness executed the real `buffs.lua` and Phase 4 resolver paths for:
  - bleed tick pacing
  - burn tick pacing
  - shock overload payoff hit
  - stun DR / hard-CC immunity
  - status ordering from `Buffs.getTopStatuses`
  - cleanse / purge / consume / expire remove-op behavior
- Harness output recorded resolver-owned `[damage_resolver]` lines plus `status_applied`, `status_stacked`, `status_refreshed`, `status_ticked`, `status_removed`, and `status_expired` events.
- Static code review verified player stun gating at the player runtime/action seams and confirmed enemy badges render only the top two statuses with a dark backing plus hard-CC color override.
- Harness artifacts live under `tmp/status_runtime_harness/` with output in `tmp/status_runtime_harness_output.txt`.
- A short LOVE boot smoke was run in this closeout pass and did not immediately crash.
- Interactive manual live-play verification for the Phase 5 closeout items remains open; this phase is harness-verified, not live-play-closed.
