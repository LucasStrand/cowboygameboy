# Six Chambers Damage Rules Matrix

This document locks the default rules for common damage categories.

Design intent:

- strong defaults
- clear exceptions
- explicit rule breaks via perks, augments, relics, or temporary states

## Main principle

Standard rules apply first. Specific skills, perks, relics, or states may break them only when stated explicitly. **Specific beats general.**

## Column reference

- **Can Crit?** — Whether the hit rolls crit by default.
- **Snapshots?** — Locks strength when the effect applies instead of re-reading live stats every tick.
- **Counts as Hit?** — Counts as a real hit in the system.
- **Full On-Hit?** — May trigger the full on-hit chain.
- **Can Trigger Proc?** — May trigger other proc-driven effects.
- **Uses Armor/MR?** — Goes through normal mitigation for `physical` / `magical`.
- **Can Lifesteal?** — May grant normal lifesteal by default.

## Standard matrix

| Damage kind | Can Crit? | Snapshots? | Counts as Hit? | Full On-Hit? | Can Trigger Proc? | Uses Armor/MR? | Can Lifesteal? | Notes |
|---|---|---|---|---|---|---|---|---|
| `direct_hit` | yes | no | yes | yes | yes | yes, if `physical` or `magical` | yes | Primary hit. |
| `burn_tick` | no | yes | no | no | no | yes, if family says so | no | Usually extends duration; not a full proc source. |
| `bleed_tick` | no | yes | no | no | no | yes, if family says so | no | Stable DoT default. |
| `poison_tick` | no | yes | no | no | no | yes, if family says so | no | Same philosophy as other DoTs. |
| `beam_tick` | no by default | usually yes | no by default | no by default | no by default | yes, if `physical` or `magical` | no by default | Strong candidate for rule-breaking perks. |
| `aura_tick` | no | yes | no | no | no | yes, if `physical` or `magical` | no | Kept conservative by default. |
| `proc_damage` | no by default | yes or source-defined | no | no | no | yes, if `physical` or `magical` | no | Does not start new proc chains by default. |
| `reflected_damage` | no | no | no | no | no | yes, if `physical` or `magical` | no | Separate and non-triggering by default. |
| `true_damage_hit` | no by default | source-defined | yes if direct, no if secondary | direct only by default | no by default | no | no by default | Payoff / spice, not baseline mitigation gameplay. |
| `delayed_secondary_hit` | source-defined | yes | no by default | no by default | no by default | depends on family | no by default | Example: follow-up ping from a passive. |

## Reading guide

- `direct_hit` is the main strike.
- DoTs and secondary effects are snapshot-limited by default.
- `true_damage` is payoff/spice, not the baseline.
- Rule-breaking content may open explicit back doors.

## Clear defaults

### Direct hit

- may crit
- may trigger full on-hit
- may use penetration
- reads as the primary hit

### DoT / secondary effects

- more restricted
- snapshot by default
- do not trigger everything
- may gain back doors via perks / augments

### True damage

- allowed
- should be special payoff or identity
- must not become so common that armor and MR feel meaningless

## Rule-break examples

- `Bleed can Crit using 50% of your Crit Damage`
- `Burn no longer snapshots; it updates dynamically from your current damage`
- `Secondary proc damage can trigger other procs, but at 25% chance`
- `Beam ticks count as hits`
- `Aura ticks apply on-hit effects at 20% efficiency`
- `Every 3rd hit on the same target triggers a delayed true-damage ping`

## Why this matrix matters

It keeps the game feeling consistent, makes broken builds explainable, keeps tooltips honest, and simplifies debugging.
