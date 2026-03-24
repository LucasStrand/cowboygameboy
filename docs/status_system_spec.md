# Six Chambers Status System Spec

This document locks baseline rules for statuses and crowd control. Statuses should be a real subsystem with clear rules for application, duration, stacks, UI, cleanse/purge/consume, CC, and interactions.

## Philosophy

Statuses and CC are not just “extra effects.” They are their own system with explicit rules for how they apply, how long they last, how they stack, how they are shown, how they are removed, and how they interact. If this is not locked early, it becomes unclear what counts as debuff, mark, CC, state, or proc-driven effect.

## Status object

Each status instance should carry at least:

- `id`
- `category`
- `duration`
- `stacks`
- `tags`
- `source`
- `target`
- `cleanse_rules`
- `visual_priority`
- `cc_rules`

## Categories

**V1 categories:**

- `buff`
- `debuff`
- `mark`
- `hard_cc`
- `soft_cc`
- `utility`

**Extended / future:** `environmental` — use only when content needs a distinct bucket; align with data before relying on it in UI or rules.

## Core rules

- One engine should support buffs and debuffs on both player and enemies (prefer one motor over parallel silos).
- Status metadata decides: buff vs debuff, valid targets, cleanse rules, UI visibility, priority, tags.
- Interactions should be built on **tags and families**, not hard-coded name pairs.
- `cleanse`, `purge`, `expire`, and `consume` are **different** operations.
- Hard CC should use **diminishing returns (DR)** or immunity windows.

## Hard CC and DR

Hard CC must not chain forever. Otherwise builds stunlock bosses, encounters collapse, and other strategies stop mattering.

Typical hard CC types: stun, freeze, silence, knockdown, and **root** if root is strong enough in this game to count as hard CC.

### Example DR curve (normal enemies)

- first stun in DR window: `100%` duration
- second: `50%`
- third: `25%`
- fourth: short immunity

CC stays impactful without infinite loops.

### Boss model

Bosses need not mirror trash rules exactly. Prefer: shorter hard CC duration, stagger meter instead of full stun, or temporary immunity to the same CC type after a hit.

Immunity or DR should decay over time so the player can control the boss sometimes, not permanently, and fights keep rhythm — better than permanent blanket immunity.

Exact numbers and defaults live in [runtime_rules_spec.md](./runtime_rules_spec.md).

## CC rules (implementation)

The status system should support:

- DR families
- immunity windows
- boss override profiles
- stagger hooks for future bosses

## UI priority

With many statuses on one target, UI must choose what to show clearly.

### Tier 1 — critical

- stun
- freeze
- silence
- knockdown
- root (if treated as hard CC)
- shield break vulnerability
- death mark
- execute state

### Tier 2 — important combat states

- expose
- armor shred
- major damage amp
- heal block
- unstoppable

### Tier 3 — common DoTs and setup

- burn
- bleed
- poison
- chill
- shock

### Tier 4 — minor / utility

- small stacking debuffs
- light slows
- minor marks
- secondary states

### UI rule

Show the **3–5** most important statuses clearly. Hide the rest behind `+X`, target inspect, debug, or inspect views.

UI should answer: is the target controlled, vulnerable, dangerous, and is this the right moment for my payoff?

## Status families and tags

Build interactions on tags and families, not pairwise effect names.

Example tags: `fire`, `bleed`, `shock`, `wet`, `poison`, `armor_break`, `crit_setup`, `execute_setup`.

The system can then query: wet present, any fire effect, `3+` debuff stacks, `crit_setup` present — without special-casing every combination.

### Combination examples

- `wet + shock` — longer chain range or higher stun chance
- `bleed + crit` — crit vs bleeding targets bonuses or bleed consume
- `burn + execute` — burn detonates below a health threshold
- armor set + status — gear bonuses when several debuff tags are present
- `frost + impact` — chilled targets take bonus stagger damage

### Design rule

Prefer interactions driven by tag, stack count, duration, source type, and target condition — not raw effect names alone.

## Initial families (V1 intent)

### Burn

- DoT
- snapshot damage by default
- refresh/extend duration identity

### Bleed

- DoT
- snapshot damage by default
- strong payoff for crit/consume synergies

### Shock

- buildup status
- overload after enough relevant hits
- payoff as stun or burst damage

### Wet

- utility / setup
- supports shock and chain synergy

## Remove operations

### Cleanse

Removes negative effects from a friendly target.

### Purge

Removes positive effects from an enemy.

### Expire

Natural end when duration reaches `0`.

### Consume

Removed to fuel a payoff or resource use (e.g. detonate burns, consume bleed stacks, remove mark for crit). Prefer explicit consume over a generic “remove status.”

## Illustrative status shape

```lua
return {
  id = "burn",
  category = "debuff",
  tags = { "fire", "dot" },
  duration_seconds = 4.0,
  stack_rule = "extend_duration",
  snapshot_damage = true,
  cleanse_rules = {
    can_cleanse = true,
    can_purge = false,
    can_consume = true,
  },
  visual_priority = 3,
  cc_rules = nil,
}
```

Hard CC example:

```lua
return {
  id = "stun",
  category = "hard_cc",
  tags = { "cc", "stun" },
  duration_seconds = 0.45,
  stack_rule = "refresh_if_stronger",
  cleanse_rules = {
    can_cleanse = true,
    can_purge = false,
    can_consume = false,
  },
  visual_priority = 1,
  cc_rules = {
    uses_dr = true,
    dr_family = "hard_cc",
  },
}
```

These are **illustrative**; field names must match the live definitions in `src/data/statuses.lua` and related loaders.

## Acceptance criteria

- Statuses have clear **source ownership**.
- CC rules are readable per status or per boss profile.
- Tags support interactions without per-name-pair special cases.
- UI can pick top statuses via `visual_priority`.

## Open decisions to lock

- exact DR window length for hard CC
- whether root is hard CC vs strong soft CC
- whether bosses use stagger meter, reduced duration, or both
- how many status icons appear on the default HUD
- which tags are mandatory in V1
