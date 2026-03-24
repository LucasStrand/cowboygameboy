# Six Chambers Content Authoring Spec

This document describes the backbone for data-driven content: validation, tooltips, localization, presentation hooks, and how content stays explainable and maintainable. If combat is the heart, authoring is the skeleton.

## Load-time validation

### Design principle

Content errors should surface at **load time**, not during gameplay. Fail loud, clear, and early.

When content loads, the system should verify that the following exist and are valid:

- stat ids
- effect ids
- trigger ids
- tag names
- status families
- tooltip keys
- localization keys
- target filters
- animation hooks
- VFX / SFX references
- proc rules
- presentation hook ids
- condition operators

Failures should be:

- clear
- early
- path- and content-specific

### Errors to catch immediately

- misspelled stat id
- effect references an unknown trigger
- tooltip references a missing variable
- status claims it is cleanseable but has no cleanse group
- skill tries to apply a buff to a target type it does not support

### Why this matters

The more the game is data-driven, the less you can rely on “we will notice in playtest.” You want to know immediately what is wrong, where it lives, and why. Otherwise bugs look like balance issues but are actually broken data.

## Tooltips

### Strategy (hybrid)

- standardized info is generated from data
- special text may be overridden manually when needed
- `tooltip_key` is the default authoring path
- `tooltip_override` is for rule-breaking or unusually complex copy
- the V1 builder supports `perks`, `guns`, `gear`, `statuses`, **`attack_profile`** (Phase 11 enemy offense), and current shop/reward offers

### V1 contract

- `tooltip_key: string | nil`
- `tooltip_tokens: table | nil`
- `tooltip_override: string | nil`
- the same contract applies to authored shop/reward offers
- legacy `description` may remain for compatibility only; the canonical authoring path from Phase 7 onward is the tooltip model

### Generated automatically

- damage
- duration
- stacks
- chance
- cooldown
- radius
- scaling
- target type
- weapon identity / fire pattern
- reload / ammo language

Example the system should be able to produce on its own:

`Applies Burn for 12 damage over 4s.`

### Manual override

Use override for:

- rule-breaking perks
- complex logic
- flavor text
- arena-style “this effect changes the rules” mechanics

Example that is usually too stiff if fully generated:

`Every third shot ignites the target and refunds 1 ammo if the target is marked.`

### Why hybrid

All manual: time-consuming, easy to forget to update, inconsistent quality. All generated: stiff language, hard-to-explain specials, robotic tooltips.

## Localization

### Design principle

Dynamic **values** are good. Dynamic **grammar** should be minimized.

### Recommended approach

Use full sentences or clear full templates with tokens. Each locale should own its full sentence; the system only fills in values. Otherwise you build something that works for one language (often English) and becomes expensive when you add others.

Avoid runtime-stitched grammar.

### V1

- local template registry in code
- English templates first
- key-based lookup, not free string concatenation

Examples:

- `Applies Burn for {damage} over {duration}s.`
- `Critical hits against Bleeding enemies deal {bonus}% more damage.`

## Presentation hooks

Own presentation through **events**, not per-effect special cases in combat code.

Gameplay emits events; presentation listens and reacts.

Core events include:

- `OnHit`
- `OnCrit`
- `OnDamageTaken`
- `OnStatusApplied`
- `OnStatusRefreshed`
- `OnStatusExpired`
- `OnCleanse`
- `OnPurge`
- `OnShieldBreak`
- `OnKill`

Presentation may then drive VFX, SFX, camera shake, screen flash, hit pause, animation layers, and UI popups.

### Why event ownership matters

If presentation is wired as “only burn plays this sound on this class” or “only this crit runs this animation if the weapon is a bow,” the system becomes unmaintainable. Event-based ownership lets content reuse presentation, change polish without touching gameplay logic, and iterate balance and feel separately.

### Practical principle

Gameplay states **what** happened. Presentation decides **how** it looks and sounds.

### V1 contract

- content may specify `presentation_hooks`
- hook ids are validated at load time
- Phase 7 uses this for proc payoff feedback and status lifecycle feedback without new combat-local one-offs

## Guiding philosophy

- core rules stay explicit
- data stays safe and validated
- UI shows what matters first
- builds can go absurd through luck and synergy
- combinations should feel designed, not random
- tooltips and content must stay maintainable
- VFX, SFX, and animation can grow without exploding gameplay code

Supporting ideas:

1. **Categories** — e.g. `hard_cc`, `soft_cc`, `buff`, `debuff`, `dot`, `mark`, `proc`, `rule_breaking_perk`.
2. **Interactions via tags and rules** — not hundreds of hard-coded special cases.
3. **Defaults plus explicit breaks** — perks and relics state when they override the matrix.
4. **Self-explanation** — tooltips, debug logs, clear status rules, validated data.

### Recommended next implementation steps

- load-time validation for content files
- tooltip schema with generated fields and manual override
- localization tokens and templates
- presentation events gameplay is allowed to emit

## Attack profiles (Phase 11)

- Canonical enemy offense: one row per attack in `src/data/attack_profiles.lua`.
- Same tooltip contract as other content: `tooltip_key` or `tooltip_override` required; validated at load time.
- See [actor_combat_contract.md](./actor_combat_contract.md) for fields and legacy mapping from `enemy.damage`.

## Related

- [authoring_readiness_checklist.md](./authoring_readiness_checklist.md) — code gates before new content (sets, proc AoE, new families, boss parity).
- [unified_actor_and_content_vision.md](./unified_actor_and_content_vision.md) — goals vs current: unified actor model, offense/defense/inventory.
- [actor_combat_contract.md](./actor_combat_contract.md) — CombatActor, AttackProfile, equipment stub.
- [phases/phase_11_actor_parity_baseline.md](./phases/phase_11_actor_parity_baseline.md) — acceptance and scope.
