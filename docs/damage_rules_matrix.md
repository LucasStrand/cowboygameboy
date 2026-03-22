# Six Chambers Damage Rules Matrix

Det här dokumentet låser standardreglerna för olika damage-kategorier.

Tanken är:

- stark default
- tydliga undantag
- lätta regelbrott via uttryckliga perks / augments

## Huvudprincip

Standardregler gäller alltid först.

Sedan får specifika skills, perks, relics eller temporary states bryta reglerna uttryckligen.

Specific beats general.

## Förklaring av kolumner

- `Can Crit?`
  Får träffen rolla crit som default.
- `Snapshots?`
  Låser styrkan när effekten appliceras i stället för att läsa om live stats varje tick.
- `Counts as Hit?`
  Räknas som riktig hit i systemet.
- `Full On-Hit?`
  Får trigga full on-hit-kedja.
- `Can Trigger Proc?`
  Får trigga andra proc-baserade effekter.
- `Uses Armor/MR?`
  Går genom vanlig mitigation för `physical` / `magical`.
- `Can Lifesteal?`
  Får ge vanlig lifesteal som default.

## Standardmatris

| Damage kind | Can Crit? | Snapshots? | Counts as Hit? | Full On-Hit? | Can Trigger Proc? | Uses Armor/MR? | Can Lifesteal? | Kommentar |
|---|---|---|---|---|---|---|---|---|
| `direct_hit` | yes | no | yes | yes | yes | yes, if `physical` or `magical` | yes | Huvudträffen |
| `burn_tick` | no | yes | no | no | no | yes, if family says so | no | Förlänger oftast duration, inte full proc-källa |
| `bleed_tick` | no | yes | no | no | no | yes, if family says so | no | Stabil DoT-default |
| `poison_tick` | no | yes | no | no | no | yes, if family says so | no | Samma filosofi som annan DoT |
| `beam_tick` | no by default | usually yes | no by default | no by default | no by default | yes, if `physical` or `magical` | no by default | Perfekt kandidat för rule-breaking perks |
| `aura_tick` | no | yes | no | no | no | yes, if `physical` or `magical` | no | Hålls lugn som default |
| `proc_damage` | no by default | yes or source-defined | no | no | no | yes, if `physical` or `magical` | no | Triggar inte nya proc-kedjor som default |
| `reflected_damage` | no | no | no | no | no | yes, if `physical` or `magical` | no | Separat och triggarlös som default |
| `true_damage_hit` | no by default | source-defined | yes if direct, no if secondary | direct only by default | no by default | no | no by default | True damage är payoff/spice-system |
| `delayed_secondary_hit` | source-defined | yes | no by default | no by default | no by default | depends on family | no by default | Exempel: efterping från passive |

## Tydliga defaults

### Direct hit

- kan critta
- kan trigga full on-hit
- kan använda penetration
- känns som huvudträffen

### DoT / secondary effects

- mer begränsade
- snapshotade som default
- triggar inte allt
- kan få bakdörrar via perks / augments

### True damage

- får finnas
- ska vara särskild payoff eller identitet
- ska inte bli så vanligt att armor och MR känns meningslösa

## Exempel på uttryckliga regelbrott

- `Bleed can Crit using 50% of your Crit Damage`
- `Burn no longer snapshots. It updates dynamically from your current damage`
- `Secondary proc damage can trigger other procs, but at 25% chance`
- `Beam ticks now count as hits`
- `Aura ticks apply on-hit effects at 20% efficiency`

## Varför detta är viktigt

Den här matrisen gör att:

- spelet känns konsekvent
- broken builds fortfarande går att förstå
- tooltips kan vara ärliga
- debugging blir mycket enklare
