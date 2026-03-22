# Phase 06: Proc Runtime + Rule-Breaking Framework

## Goals

- Finish the Phase 6 runtime layer on top of the Phase 4 resolver and Phase 5 status foundations.
- Preserve the already-landed explosive bullet kickoff slice.
- Add one real generic proc/runtime seam driven by canonical packets and resolver-owned events.
- Ship one showcase rule-breaker through that seam:
  - every third weapon hit on the same target schedules a delayed true-damage ping

## Modules Touched

### `src/systems/impact_fx.lua`

- Refactored from a tiny row switcher into a definition-driven effect runtime.
- Effect definitions now carry:
  - sheet path indirection
  - row
  - start / end frame
  - fps
  - scale
  - blend mode
  - optional rotation mode
  - optional lifetime jitter
- Existing effects kept on the same API surface:
  - `hit_enemy`
  - `hit_wall`
  - `melee`
- Added new effect ids:
  - `explosion_small`
  - `explosion_medium`
  - `explosion_large`
  - `muzzle_explosive_shotgun`

### `src/systems/weapon_runtime.lua`

- Resolved weapon stats now apply the locked exclusivity rule:
  - `explosiveRounds => ricochetCount = 0`
- Projectile authoring now adds VFX metadata:
  - `impact_fx_id`
  - `muzzle_fx_id`
  - `explosion_tier`
  - tier-specific `explosion_radius`
  - tier-specific `explosion_damage_scale`
  - tier-specific explosion SFX id
- Current tier mapping in the kickoff slice:
  - revolver / pistol-style weapons: `small`
  - AK / rifle-style weapons: `medium`
  - blunderbuss / 2-gauge feel: `large`

### `src/systems/proc_runtime.lua`

- New Phase 6 runtime owner for generic proc evaluation.
- Subscribes to resolver-owned `CombatEvents`.
- Evaluates authored proc rules instead of hardcoding proc behavior in combat-local code.
- Owns:
  - per-source + per-target hit counters
  - proc-depth guardrails
  - delayed proc-packet scheduling through `DamageResolver.enqueueSecondaryJob`

### `src/systems/damage_packet.lua`

- Packet shape now carries `proc_depth`.
- Direct hits default to `0`.
- Proc-generated delayed packets increment depth and are blocked from further recursion by default.

### `src/data/perks.lua`

- Adds the first real Phase 6 showcase perk:
  - `phantom_third`
- The perk is authored with `proc_rules` rather than direct combat-side branching.
- Current authored showcase behavior:
  - `OnHit`
  - weapon-slot direct hits only
  - counter ownership by source + target
  - every third hit queues a delayed `true`-family ping

### `src/systems/damage_resolver.lua`

- Resolver-owned event payloads now carry the original packet and proc-policy fields needed by Phase 6 runtime consumers.
- Secondary-job processing now supports actor-id targeting so proc-generated delayed hits can strike one explicit target instead of only radius splash.

### `src/entities/player.lua`

- Projectile fire now spawns muzzle FX via effect ids.
- `blunderbuss + explosiveRounds` uses `muzzle_explosive_shotgun` for a Dragon's Breath-style fire read.

### `src/entities/bullet.lua`

- Bullets now carry visual metadata directly.
- Explosive bullets suppress ricochet even if stale data somehow still provides bounce count.
- Wall collision now uses explosive impact VFX + explosive SFX for explosive bullets instead of wall sparks.

### `src/systems/combat.lua`

- Enemy-hit impact now chooses between standard hit VFX and explosive tier VFX from projectile metadata.
- Explosive hits use explosion SFX buckets instead of regular enemy-hit SFX.
- Direct-hit resolver ownership remains unchanged.

## Decisions Landed

### Three explosive tiers only

- Phase 6 kickoff ships exactly three explosive presentation tiers:
  - `small`
  - `medium`
  - `large`
- The goal is enough variation for current weapons without turning the kickoff slice into a VFX catalog pass.

### Blunderbuss gets the Dragon's Breath identity

- No full flame trail system yet.
- The identity comes from:
  - flame-like muzzle VFX
  - larger explosive impact
  - the existing shotgun spread behavior

### Explosive beats ricochet

- If both perks or flags exist, explosive behavior wins.
- Runtime suppresses bounce count instead of leaving a hidden collision-order rule.
- F1 readouts now surface the lock with `Ricochet: 0 (LOCKED)` when explosive is active.

### First real rule-breaker ships through runtime, not combat-local code

- The first official Phase 6 showcase is not baked into bullets, combat, or resolver special cases.
- Instead:
  - resolver emits canonical `OnHit`
  - proc runtime evaluates authored perk rules
  - proc runtime schedules a canonical delayed packet
  - resolver owns the delayed hit when it lands

### Proc recursion is explicitly guarded

- Direct hits may open proc evaluation.
- Proc-generated delayed packets carry `proc_depth = 1`.
- Proc-generated delayed packets do not recurse further by default.
- The showcase ping does not:
  - count as hit
  - trigger on-hit
  - trigger more procs
  - lifesteal

## Debug / Verification Hooks

- F1 effective stats panel now reflects the explosive-vs-ricochet lock.
- DevLog still captures projectile runtime/debug output through the existing debug seams.
- No new dev panel section was added for this kickoff slice; live verification should use normal combat plus F1/F2 tools.

## Acceptance Notes

### Verified Good

- Named effect ids now exist for explosive bullets and legacy hit effects.
- Explosive projectile authoring now carries VFX metadata from weapon runtime.
- Ricochet is suppressed in resolved weapon stats when explosive rounds are active.
- Blunderbuss gets a dedicated explosive muzzle effect instead of looking like a normal pellet hit.
- `ImpactFX` now loads the Phase 6 explosive sheet from the real asset path:
  - `assets/Retro Impact Effect Pack ALL/RetroImpactEffectPack3A.png`
- A LOVE smoke run of the Phase 6 preview harness launches cleanly after the asset-path fix and no longer crashes on `pack3a` load.
- A generic Phase 6 proc runtime now exists and subscribes to resolver-owned `CombatEvents`.
- Packet/effect proc flags are now consumed by runtime policy instead of existing only as passive packet metadata.
- The first real authored showcase rule-breaker now exists as perk data:
  - `phantom_third`
  - `third_hit_true_ping`

### Still Unverified In Live Visual Play

- Revolver + explosive: confirm the small tier stays readable at gameplay zoom.
- AK + explosive: confirm the medium tier reads clearly distinct from revolver and blunderbuss.
- Blunderbuss + explosive: confirm the Dragon's Breath-style muzzle read is obvious in real fights.
- Compare enemy-hit vs wall-hit explosive feedback in active combat so wall hits do not feel stronger than enemy hits.
- Final tune pass for row choice, fps, and scale if live combat exposes visual confusion between `small`, `medium`, and `large`.

### Bugs / Balance Problems Found During Closeout

- Confirmed and fixed:
  - `ImpactFX` referenced the wrong `pack3a` filename during closeout verification.
  - The real asset on disk is `RetroImpactEffectPack3A.png`.
  - This caused an immediate runtime crash during draw/load for Phase 6 explosive effects.
- No balance problems confirmed in this pass.

## Verification Status

- Static code inspection confirms:
  - explosive projectile metadata is authored in `weapon_runtime`
  - bullet wall-hit behavior uses explosive VFX/SFX before ricochet logic
  - explosive hits in `combat` use tiered impact FX
  - F1 debug stats reflect ricochet suppression
- Static code inspection also confirms:
  - a dedicated `proc_runtime` now subscribes to resolver-owned combat events
  - `DamagePacket` carries `proc_depth`
  - resolver payloads expose packet/proc fields to runtime subscribers
  - proc-generated delayed hits re-enter combat through canonical packets and secondary jobs
- LOVE smoke verification confirms:
  - `explosion_small`
  - `explosion_medium`
  - `explosion_large`
  - `muzzle_explosive_shotgun`
  - all load through the definition-driven `ImpactFX.spawn(cx, cy, effect_id, opts, legacy_angle)` path without a missing-asset crash
- LOVE runtime harness verifies the real Phase 6 proc path for:
  - hit 1 on target: counter increments, no proc
  - hit 2 on target: counter increments, no proc
  - hit 3 on target: delayed true-damage ping fires
  - source + target ownership keeps counters separated across different sources and different targets
  - proc-generated delayed hits do not emit `OnHit` and do not recurse further by default
- Phase 6 proc harness artifacts live under:
  - `tmp/phase6_proc_harness/`
  - `tmp/phase6_proc_harness_output.txt`
- Manual gameplay verification is still required for:
  - revolver explosive feel
  - AK explosive feel
  - blunderbuss Dragon's Breath read
  - visual tier readability
  - enemy-hit vs wall-hit feel in actual fights
  - explosive-vs-ricochet lock behavior in actual fights
