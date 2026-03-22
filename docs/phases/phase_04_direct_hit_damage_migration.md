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

## Debug Hooks

- F1 debug overlay + DevLog receive resolver-owned hit lines from `damage_resolver`.
- Weapon runtime slot dumps remain available through the existing runtime debug hooks and are still the right companion tool when checking projectile live-source fallback.
- Phase 4 does not add a separate new panel flow; direct-hit closeout still requires live combat verification in the Love runtime.

## Acceptance Checklist

### Verified Good

- [x] `DamagePacket` canonical fields are present on migrated direct-hit paths.
- [x] Crit resolves before mitigation in resolver code.
- [x] `physical`, `magical`, and `true` family branches all exist in the resolver.
- [x] Resolver owns `OnDamageTaken`, `OnHit`, and `OnKill` emissions for migrated direct-hit paths.
- [x] Player/enemy apply helpers are thin and no longer own mitigation math.

### Verified In LOVE Runtime Harness

- [x] Player projectiles hit enemies through `damage_resolver`.
- [x] Enemy projectiles hit player through `damage_resolver`.
- [x] Player melee hit damage comes from resolver output, not combat-local math.
- [x] Enemy contact damage comes from resolver output, not player-local armor math.
- [x] Explosive splash routes through delayed-secondary jobs.

### Bugs / Balance Problems Found During Closeout

- None confirmed in this pass.

## Remaining Adapters / Follow-Up

- Some compatibility fallbacks still allow bullets or wrappers to normalize legacy packet fragments if a caller has not been upgraded.
- The old unused ranged helper in `enemy.lua` still reflects pre-resolver projectile metadata style and should be cleaned when dead-code cleanup is convenient.
- Phase 4 does not yet introduce status application, proc recursion, or rule-breaking overrides.

## Verification Status

- Static repo search used to confirm direct-hit event ownership moved to `damage_resolver`.
- Static repo search used to confirm direct direct-hit call sites in combat no longer call `target:takeDamage(raw_amount)` for live paths.
- LOVE runtime harness executed the real `combat.lua` and `damage_resolver.lua` paths for:
  - player projectile direct hit
  - enemy projectile direct hit
  - player melee direct hit
  - enemy contact direct hit
  - explosive delayed-secondary splash
- Harness output recorded resolver-owned debug lines and `CombatEvents` emissions for the migrated paths.
- Repo-local `:takeDamage(` grep only found the thin wrapper definitions on `player.lua` and `enemy.lua`, with no live combat call sites bypassing the resolver.
- Harness artifacts live under `tmp/damage_resolver_harness/` with output in `tmp/damage_resolver_harness_output.txt`.
- Manual gameplay verification for the migrated Phase 4 paths has now been completed during closeout, so resolver wiring and live combat behavior are both considered verified for this phase.
