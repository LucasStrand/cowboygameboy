# Phase 02: Shared Foundations

## Goals

- Add the shared runtime foundations for the combat/build overhaul without replacing the live resolver yet.
- Keep current gameplay behavior intact while introducing:
  - stat registry runtime
  - content validation
  - damage packet normalization
  - combat events
  - run-seeded gameplay RNG
  - source ownership metadata
- Create clean seams for:
  - Phase 3 weapon/runtime refactor
  - Phase 4 direct-hit resolver migration

## Modules Added

### `src/data/stat_registry.lua`

- Central stat registry in `snake_case`.
- Declares defaults, groups, accepted ops, rounding, clamps, and legacy aliases.
- Includes current legacy stats so validation and adapters can work before live migration.

### `src/systems/stat_runtime.lua`

- Computes normalized actor stats from a context object.
- Produces a modifier trace for debugging and later telemetry work.
- Exports a legacy camelCase adapter table so existing code can be compared safely.

### `src/systems/content_validator.lua`

- Validates Phase 2 combat/build content at load-time.
- Fails loudly with actionable error messages.
- Scope is intentionally limited to current combat/build files.

### `src/systems/damage_packet.lua`

- Normalizes attack and damage metadata into a stable packet shape.
- Does not resolve damage yet.
- Exists so Phase 4 can migrate to a real resolver without redoing source metadata.

### `src/systems/combat_events.lua`

- Tiny event bus for core combat runtime events.
- Added now so gameplay code can start emitting stable events before presentation listeners are migrated.

### `src/systems/game_rng.lua`

- Run-seeded gameplay RNG wrapper with stable named channels.
- Supports deterministic gameplay rolls while leaving cosmetic randomness alone.
- Exposes a current run RNG so existing systems can migrate incrementally.

### `src/systems/source_ref.lua`

- Normalizes source ownership metadata for:
  - player attacks
  - enemy attacks
  - future perks/statuses/procs

## Integration Points Touched

- `main.lua`
  - load-time content validation
- `src/states/game.lua`
  - run seed creation
  - current gameplay RNG ownership
- `src/entities/player.lua`
  - stat runtime debug comparison path
  - shot metadata
  - reload events
  - incoming damage packet/source metadata
- `src/entities/bullet.lua`
  - bullet metadata carriage
- `src/entities/enemy.lua`
  - optional packet/source metadata intake
- `src/systems/combat.lua`
  - packet creation before legacy damage application
  - source-aware `OnHit`, `OnKill`, `OnDamageTaken`
- gameplay-affecting RNG call sites migrated away from direct `math.random`

## Blockers Hit

### Current combat data is only partially data-driven

- `perks.lua` still mutates `player.stats` directly via functions.
- This means the validator can only validate shape and required fields there, not semantic stat usage inside arbitrary Lua logic.

### Current stat names are mixed and inconsistent

- Live code still uses camelCase.
- Some content already references dead or unofficial keys such as `damage` and `critChance`.
- Phase 2 preserves those keys as aliases or known validation targets so boot does not explode before migration work begins.

### Gameplay randomness was spread everywhere

- Some gameplay rolls live in data modules.
- Some live in states.
- Some live in systems.
- Phase 2 therefore needed a current-run RNG singleton seam so migration could happen without threading a new parameter through the whole game yet.

## Decisions Made

### Validation scope stays intentionally narrow in Phase 2

- Only combat/build content is hard-validated now:
  - guns
  - perks
  - gear
  - weapons
  - buffs
- Wider world/content validation is deferred until later phases.

### Phase 2 RNG only replaces gameplay-affecting randomness

- Deterministic gameplay now covers reward/run/combat-affecting rolls.
- Cosmetic randomness is still allowed to use legacy randomness for now.

### Stat runtime remains advisory in Phase 2

- Live gameplay still trusts the existing player stat path.
- New stat runtime exists to prove the registry model can represent current state and to highlight mismatches before it becomes authoritative.

## Compromises / Temporary Adapters

### Legacy stat adapter

- `stat_runtime.export_legacy_stats(...)` exists purely as a migration adapter.
- It should disappear once live systems fully consume normalized stats.

### Current RNG singleton

- `GameRng.setCurrent(...)` is a temporary bridge.
- Long term, systems should receive the runtime explicitly instead of reaching for a global current instance.

### Metadata-only damage packet use

- Damage packets are created now but do not drive damage math yet.
- Current live damage numbers still come from legacy resolver code.

## Debug Hooks Added

- Stat runtime comparison hook in `player.lua`.
- Packet/source creation at the legacy hit seams.
- Core combat events emitted even before listeners migrate.

## Telemetry Fields Introduced

- `source_ref.owner_actor_id`
- `source_ref.owner_source_type`
- `source_ref.owner_source_id`
- `source_ref.parent_source_id`
- `damage_packet.kind`
- `damage_packet.family`
- `damage_packet.tags`
- `damage_packet.counts_as_hit`
- `damage_packet.can_trigger_proc`

## Acceptance Checklist

- [ ] Boot fails loudly on intentionally broken combat/build content.
- [ ] Boot succeeds with current valid combat/build content.
- [ ] Same run seed produces repeatable gameplay outcomes in migrated RNG paths.
- [ ] Bullet and melee paths create packet/source metadata without changing visible damage.
- [ ] Core combat events emit ownership data.
- [ ] Stat runtime comparison runs without breaking gameplay.

## Verification Status

- Code and docs are implemented.
- Runtime/manual verification is still pending.
- No local Lua/Love syntax runner was available in this pass, so verification was limited to code inspection and seam checks.

## Problems Encountered

- The current codebase has many `math.random` call sites mixed between gameplay and presentation.
- Some content files are already relying on unofficial stat names that should eventually be removed or migrated.
- The current player stat flow contains several hidden rules inside `player.lua`, so the new stat runtime currently mirrors behavior instead of replacing it.

## Solutions Chosen

- Introduce explicit adapters rather than force-rewriting live systems too early.
- Use packet/source metadata now so later resolver work has a clean seam.
- Normalize RNG ownership at the run level while still allowing cosmetic randomness to stay separate.

## Prepared For Next Phase

- Weapon runtime can now move into explicit slot/state structures without also inventing RNG, validation, packet, or source foundations at the same time.
- Phase 3 can focus on:
  - slot collection
  - active slot set
  - resolved weapon stats
  - moving ammo/reload/cooldown/counters into explicit weapon runtime state

## Phase 3 Readiness

Phase 3 is ready once the team accepts these remaining legacy seams:

- player stat truth still lives in the old player stat path
- live weapon runtime truth still lives in `player.lua`
- live damage resolver truth still lives in current combat/enemy/player damage code

That is expected. Phase 2 was only meant to add the shared foundations under those seams.
