# Six Chambers Damage Rules Matrix

Detta dokument låser standardreglerna för vanliga damage-kategorier.

Detta är defaultregler.

Specifika perks, augments, relics eller states får bryta dem uttryckligen.

## Standardmatris

| Damage kind | Can Crit? | Snapshots? | Counts as Hit? | Full On-Hit? | Can Trigger Proc? | Uses Armor/MR? | Can Lifesteal? |
|---|---|---|---|---|---|---|---|
| `direct_hit` | yes | no | yes | yes | yes | yes if `physical` / `magical` | yes |
| `burn_tick` | no | yes | no | no | no | yes if family says so | no |
| `bleed_tick` | no | yes | no | no | no | yes if family says so | no |
| `poison_tick` | no | yes | no | no | no | yes if family says so | no |
| `beam_tick` | no by default | yes by default | no by default | no by default | no by default | yes if `physical` / `magical` | no by default |
| `aura_tick` | no | yes | no | no | no | yes if `physical` / `magical` | no |
| `proc_damage` | no by default | yes or source-defined | no | no | no | yes if `physical` / `magical` | no |
| `reflected_damage` | no | no | no | no | no | yes if `physical` / `magical` | no |
| `true_damage_hit` | no by default | source-defined | yes if direct | direct only | no by default | no | no by default |
| `delayed_secondary_hit` | source-defined | yes | no by default | no by default | no by default | depends on family | no by default |

## Reading Guide

- `direct_hit` är huvudträffen
- DoTs och secondary effects är snapshotade och begränsade som default
- `true damage` är payoff/spice, inte baslinje
- rule-breaking content får öppna bakdörrar

## Common Rule-Break Examples

- `Bleed can Crit using 50% of your Crit Damage`
- `Burn no longer snapshots`
- `Beam ticks count as hits`
- `Secondary proc damage can trigger other procs at reduced chance`
- `Every 3rd hit on the same target triggers a delayed true-damage ping`

