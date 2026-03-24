# Phase 03: Player / Loadout / Weapon Runtime

## Goals

- Make weapon runtime state authoritative without replacing the live damage resolver yet.
- Move slot ownership, active slot, reload/cooldown/ammo, and resolved weapon stats out of ad hoc player mirrors.
- Preserve current combat behavior for existing guns while introducing a bridge to future attack profiles.

## Modules Added

### `src/systems/weapon_runtime.lua`

- Owns canonical player weapon runtime state.
- Stores explicit backend slots for both current active slots.
- Keeps slot 2 alive in backend as `mode = "melee"` when no ranged weapon is equipped.
- Computes resolved weapon stats through the shared stat runtime.
- Ticks reload/cooldown per slot and persists that state across slot switching.
- Adapts current gun definitions into a canonical runtime shape with:
  - `attack_profile_id`
  - `capabilities`
  - `rules`
  - `tags`
- Bridges current projectile firing through attack-profile execution instead of direct player-side bullet assembly.

## Integration Points Touched

- `src/entities/player.lua`
  - player accessors added for weapon runtime and legacy sync
  - active slot and ranged weapon lookup now read runtime state first
  - shoot/reload/switch/equip now route through weapon runtime
  - legacy `player.weapons` and active ammo/reload mirrors remain as derived compatibility state in this phase
- `src/systems/stat_runtime.lua`
  - melee inclusion now checks runtime slot mode instead of relying on `weapons[2] == nil`
- `src/ui/hud.lua`
  - ammo capacity reads can use resolved weapon stats per slot
- `src/states/game.lua`
  - auto-fire path now reads authoritative slot runtime state
- `src/data/perks.lua`
  - ammo perk now uses runtime ammo accessor
- `src/systems/shop.lua`
  - ammo shop upgrade now uses runtime ammo accessor
- `src/data/guns.lua`
  - current guns now expose optional attack-profile metadata explicitly

## Decisions Made

### Hybrid adapter stays in place

- `guns.lua` remains the primary authoring source in this phase.
- Weapon runtime adapts that content into a more canonical internal shape.
- Full weapon-definition replacement is deferred.

### Compatibility mirrors remain temporarily

- `player.weapons`
- `player.ammo`
- `player.reloading`
- `player.reloadTimer`
- `player.shootCooldown`

These fields are still populated so HUD, game loop, and other legacy call sites keep working, but they are no longer authoritative.

## Phase 3 Hardening Revision

- Dead legacy fallback bodies were removed from `player.lua` runtime seams:
  - `getEffectiveStatsForGun`
  - `switchWeapon`
  - `equipWeapon`
- `weapon_runtime` no longer pretends to maintain a resolved-stat cache that was never invalidated correctly.
- Compatibility mirrors are intentionally narrowed to:
  - HUD/presentation reads
  - small glue seams such as reload transition checks
- New gameplay or combat logic should not read from mirrors when runtime accessors exist.
- Runtime slot mode is now the preferred melee/ranged truth. Legacy `weapons[2]` reasoning remains only as one explicit fallback adapter in `stat_runtime` for non-runtime contexts.

### Legacy `gun.onShoot` survives only as a bridge

- Attack execution now flows through `attack_profile_id`.
- Existing weapon-specific callbacks are still called after profile execution so live behavior is preserved.
- No new weapon behavior should be authored by extending ad hoc player-side shooting logic.

## Debug Hooks Added

- Runtime dump helper for weapon slots:
  - mode
  - weapon id
  - ammo
  - reload timer
  - cooldown timer
  - shots since reload
  - attack profile id
- Dumps are emitted at key seams:
  - init
  - equip
  - switch
  - reload start
  - reload finish
  - ammo delta
  - fire

## Telemetry Fields Added To Reload Events

- `weapon_id`
- `slot_mode`
- `attack_profile_id`

## Acceptance Notes

### Verified Good

- Weapon runtime is the authoritative owner for slot state, active slot, ammo, reload, cooldown, and resolved weapon stats.
- Runtime-first player seams no longer contain dead legacy fallback bodies.
- Ammo mutations in perks and shop now route through runtime accessors instead of compatibility mirrors.
- Auto-fire and melee-mode truth read runtime state instead of player mirror state.
- Later direct-hit/status work now consumes weapon runtime as the outgoing player source seam.

### Still Unverified In Gameplay

- Exact feel parity for revolver, blunderbuss, and AK-47 still needs a dedicated manual pass.
- Reload persistence across active slot switching still needs a dedicated manual gameplay confirmation.
- Akimbo live behavior and HUD ammo readout still need a dedicated manual gameplay confirmation.

### Bugs / Balance Problems Found During Closeout

- None confirmed in this pass.

## Hardening Acceptance

- [x] Runtime-first player seams no longer contain unreachable legacy branches.
- [x] Compatibility mirrors are documented as derived projections, not source of truth.
- [x] Weapon runtime debug dumps remain authoritative and do not read mirrors.
- [x] Gameplay-facing ammo mutations in perks/shop use runtime accessors.
- [x] Auto-fire gameplay reads authoritative slot runtime.
- [x] Remaining mirror reads are constrained to HUD/presentation and small glue paths.

## Remaining Adapters / Follow-Up

- HUD still consumes derived compatibility mirrors for slot/ammo presentation.
- Reload transition glue in `game.lua` still reads `player.reloading` as a projection.
- `player:getEffectiveStatsForGun` remains as a compatibility helper for non-slot stat reads and debug comparison.
- `stat_runtime` retains one documented fallback for callers without runtime-backed player accessors.
- Full attack profiles, capability enforcement, and rule transforms are still deferred to later phases.

## Verification Status

- Phase 3 implementation and hardening pass completed.
- Static repo-search verification confirms that remaining mirror reads are limited to approved UI/glue paths.
- Residual live-feel parity checks are explicit in this log instead of hidden in the old checkbox list.
