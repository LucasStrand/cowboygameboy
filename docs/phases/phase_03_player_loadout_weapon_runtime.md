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

## Acceptance Checklist

- [ ] Boot succeeds with existing gun content and no schema rewrite requirement.
- [ ] Revolver behavior still matches pre-refactor baseline.
- [ ] Blunderbuss recoil hop still works through attack-profile bridge.
- [ ] AK-47 still respects rapid fire and inaccuracy.
- [ ] Slot 2 melee stance exists as explicit runtime state, not missing backend data.
- [ ] Reload persists on a slot while the player switches to another slot.
- [ ] Akimbo slots tick cooldown and reload independently.
- [ ] Ammo perk and ammo shop upgrade hit authoritative runtime state instead of writing to compatibility mirrors.
- [ ] HUD ammo capacity can read resolved slot stats.

## Remaining Adapters / Follow-Up

- Some legacy readers still consume derived compatibility mirrors in `player`.
- `player:getEffectiveStatsForGun` still exists as a compatibility seam and should be deleted once all runtime stat reads come through slot/runtime helpers.
- Full attack profiles, capability enforcement, and rule transforms are still deferred to later phases.

## Verification Status

- Implementation completed.
- Static verification still required.
- Manual gameplay verification is still required for reload persistence, akimbo, HUD ammo readout, and weapon swapping in live Love runtime.
