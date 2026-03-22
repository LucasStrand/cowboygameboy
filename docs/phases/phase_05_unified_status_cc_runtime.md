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

- Player now owns `player.statuses` with `player.buffs` kept as an alias.
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

## Acceptance Notes

### Verified Good

- Shared status runtime exists and is wired to both player and enemies.
- Status ticks/payoff hits route through canonical damage packets instead of direct HP mutation.
- Compatibility path for legacy boons/HUD remains present through `buffs.lua`.
- Temporary authored status hooks have been removed from player guns, enemy projectile examples, and the ultimate projectile.

### Still Unverified In Gameplay

- bleed / burn tick pacing
- shock overload + stun DR
- status HUD ordering
- enemy badge readability
- player stun gating
- broader remove-op behavior in real gameplay

### Bugs / Balance Problems Found During Closeout

- None confirmed in this pass.

## Verification Status

- Static repo search used to confirm no temporary authored `status_applications` remain on guns, enemy projectile examples, or the ultimate path.
- Short LOVE boot smoke test completed without an immediate startup crash.
- A dev-only verification harness now exists so Phase 5 can be verified without reintroducing permanent status content.
- Manual gameplay verification is still required for:
  - bleed / burn tick pacing
  - shock overload + stun DR
  - status HUD ordering
  - enemy badge readability
  - player stun gating
  - cleanse / purge / consume / expire behavior in live gameplay
