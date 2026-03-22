# Phase 04: Direct-Hit Damage Migration

## Goals

- Introduce one authoritative direct-hit resolver.
- Migrate both player-to-enemy and enemy-to-player direct hits in the same phase.
- Make `DamagePacket` canonical enough that combat code no longer rebuilds damage meaning at impact time.
- Preserve current gameplay feel where possible while locking resolver ownership, telemetry, and future-facing secondary-hit scaffolding.

## Modules Added

### `src/systems/damage_resolver.lua`

- Owns direct-hit resolution order for `direct_hit` and Phase 4 `delayed_secondary_hit`.
- Emits authoritative `OnDamageTaken`, `OnHit`, and `OnKill` payloads from resolver-owned values.
- Applies the locked family rules for `physical`, `magical`, and `true`.
- Handles crit before mitigation.
- Queues and processes minimal delayed secondary jobs for explosion splash.

## Integration Points Touched

- `src/systems/damage_packet.lua`
  - packet shape expanded to canonical fields with `amount` retained as a legacy adapter
- `src/entities/player.lua`
  - `takeDamage` becomes a resolver wrapper
  - `applyResolvedDamage` now owns only player HP/iframe/death side effects
- `src/entities/enemy.lua`
  - enemy defense adapter fields added with zeroed defaults
  - `takeDamage` becomes a resolver wrapper
  - `applyResolvedDamage` now owns only enemy HP/death/hurt side effects
- `src/systems/combat.lua`
  - bullets, melee, enemy contact, and enemy projectile hits all route through `damage_resolver`
  - combat no longer emits its own hit/kill events for direct-hit paths
- `src/systems/weapon_runtime.lua`
  - projectile attack profiles now create canonical packets instead of only raw damage fragments
- `src/systems/enemy_ai.lua`
  - enemy projectile spawn now builds canonical packets
- `src/states/game.lua`
  - ultimate projectile spawn now builds a canonical packet
- `src/data/stat_registry.lua`
  - `crit_damage` default aligned to locked docs at `1.5`

## Decisions Landed

### Projectile live resolution with guarded fallback

- Weapon projectiles attempt to bind back to live source context on impact.
- Live binding is accepted only when the source actor and the originating weapon source still match packet metadata.
- If the source no longer matches, the resolver falls back to packet snapshot data instead of reading the wrong live gun.

### Block moved after mitigation

- Blocking is now treated as a target-side incoming modifier.
- Armor or magic resist resolve first.
- Block reduction applies after that mitigation step.

### Explosion splash standardized as delayed secondary hit

- Explosive splash now routes through resolver-owned secondary jobs.
- Splash packets are `delayed_secondary_hit`.
- Splash does not count as hit by default and does not open proc/on-hit recursion in Phase 4.

## Debug And Telemetry

- Resolver debug lines now report:
  - packet kind
  - family
  - source
  - target
  - rolled base damage
  - crit result
  - effective defense
  - final damage
- Resolver-owned event payloads now include:
  - `family`
  - `rolled_base_damage`
  - `pre_defense_damage`
  - `effective_defense`
  - `final_applied_damage`
  - `was_crit`
  - `target_killed`
  - `applied_minimum_damage`

## Acceptance Checklist

- [ ] Player projectiles hit enemies through `damage_resolver`.
- [ ] Enemy projectiles hit player through `damage_resolver`.
- [ ] Player melee hit damage comes from resolver output, not combat-local math.
- [ ] Enemy contact damage comes from resolver output, not player-local armor math.
- [ ] `DamagePacket` canonical fields are present on migrated direct-hit paths.
- [ ] Crit resolves before mitigation.
- [ ] `physical`, `magical`, and `true` family branches all exist in the resolver.
- [ ] Explosive splash routes through delayed-secondary jobs.
- [ ] Resolver owns `OnDamageTaken`, `OnHit`, and `OnKill` emissions for migrated direct-hit paths.
- [ ] Player/enemy apply helpers are thin and no longer own mitigation math.

## Remaining Adapters / Follow-Up

- Some compatibility fallbacks still allow bullets or wrappers to normalize legacy packet fragments if a caller has not been upgraded.
- The old unused ranged helper in `enemy.lua` still reflects pre-resolver projectile metadata style and should be cleaned when dead-code cleanup is convenient.
- Phase 4 does not yet introduce status application, proc recursion, or rule-breaking overrides.

## Verification Status

- Static repo search used to confirm direct-hit event ownership moved to `damage_resolver`.
- Static repo search used to confirm direct direct-hit call sites in combat no longer call `target:takeDamage(raw_amount)` for live paths.
- Manual gameplay verification is still required for:
  - revolver/blunderbuss/AK-47 behavior
  - enemy projectile mitigation
  - block ordering
  - explosion splash
  - projectile live-resolution fallback after weapon swap
