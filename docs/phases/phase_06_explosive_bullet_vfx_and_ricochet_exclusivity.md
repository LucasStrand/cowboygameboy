# Phase 06 Kickoff: Explosive Bullet VFX + Ricochet Exclusivity

## Goals

- Start Phase 6 with a narrow, runtime-safe slice instead of the full proc/rule-breaking system.
- Give explosive bullets distinct presentation tiers and a stronger identity on existing guns.
- Upgrade `ImpactFX` to named effect definitions so later Phase 6 work can request VFX by id instead of sheet rows.
- Hard-lock `explosiveRounds` and `ricochetCount` as mutually exclusive in live runtime.

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

### Still Unverified In Gameplay

- Exact frame-row selection quality from `Retro Impact Effect Pack 3 A.png` at gameplay zoom.
- Readability difference between `small`, `medium`, and `large` explosion tiers during active fights.
- Whether large blunderbuss explosive impact needs a lower or higher scale after live testing.
- Whether wall-collision explosive VFX feels right relative to enemy-hit explosive VFX.

### Bugs / Balance Problems Found During Closeout

- None confirmed in this pass.

## Verification Status

- Static code inspection confirms:
  - explosive projectile metadata is authored in `weapon_runtime`
  - bullet wall-hit behavior uses explosive VFX/SFX before ricochet logic
  - explosive hits in `combat` use tiered impact FX
  - F1 debug stats reflect ricochet suppression
- Manual gameplay verification is still required for:
  - revolver explosive feel
  - AK explosive feel
  - blunderbuss Dragon's Breath read
  - visual tier readability
  - explosive-vs-ricochet lock behavior in actual fights
