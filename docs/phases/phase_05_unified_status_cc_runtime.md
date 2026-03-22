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

## Content Hooks Landed

- Guns and enemy projectiles can now declare `status_applications`.
- Current live hooks:
  - `blunderbuss` -> `bleed`
  - `ak47` -> `shock`
  - `necromancer` projectile -> `burn`
  - `gunslinger` projectile -> `slow`
  - ultimate barrage -> `wet`
  - explosive rounds perk path -> `burn`

## Acceptance Notes

- Phase 5 lands the shared runtime and live status hooks in code.
- Phase 4 direct-hit behavior remains the base damage path and is not reopened here.
- Manual gameplay verification is still required for:
  - bleed / burn tick pacing
  - shock overload + stun DR
  - status HUD ordering
  - enemy badge readability
  - player stun gating
