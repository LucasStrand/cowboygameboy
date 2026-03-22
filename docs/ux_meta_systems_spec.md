# Six Chambers UX and Meta Systems Spec

Detta dokument låser riktningen för:

- combat readability
- HUD priority
- build clarity
- economy pressure
- reward pools
- meta unlock philosophy
- run metadata
- performance/debug/runtime support

## Combat Readability

Combat ska kunna läsas i tre lager:

### Primär tydlighet

- vilka attacker är mina
- vilka projektiler är farliga
- när ett payoff-moment händer

### Sekundär tydlighet

- vem som orsakade secondary effects
- om burn eller delayed proc dödade målet i stället för direct hit

### Recap / Debug

- death recap
- last damaging source
- stora senaste procs

Presentation default:

- direct hits starkast feedback
- stora payoffs näst starkast
- background damage svagare

## HUD Priority

### Grupp A: alltid synlig

- HP / shield
- ammo / reload / main resource
- potion charges
- viktigaste cooldowns
- payoff-counters som spelar roll i realtid

### Grupp B: lätt åtkomlig

- buffs/debuffs på spelaren
- boon summary
- vissa passive counters

### Grupp C: inspect/expand

- små modifiers
- full statuslista
- proc-chance breakdown
- exakt source mapping

## Build Clarity

UI ska hjälpa spelaren att förstå:

- core engine
- enablers
- payoff pieces
- finishers

Bra verktyg:

- highlightade keywords
- synliga tags
- build-matching reward hints
- enkel build summary

## Economy Pressure

Ekonomin ska skapa val, inte skatt.

Roller:

- shoppriser = baslinje och tempo
- rerolls = flexibilitet mot kostnad
- refills/repairs = defensiva beslut
- cursed items = risk/reward

Defaultprincip:

- varje shopbesök bör ge minst två rimliga beslut

## Reward Pools

Använd smart weighting, inte ren RNG.

På reward-val default:

- `1` reward stödjer nuvarande build
- `1` reward är neutral/stabil
- `1` reward öppnar pivot eller alternativ

Weighting inputs:

- weapon family
- damage tags
- status themes
- tidigare picks
- build engine
- biome/event context

## Meta Unlock Philosophy

Meta ska främst bredda spelet.

Bra unlocks:

- nya vapen
- nya perks/relics
- nya events/rooms/merchants
- nya risk/reward-loopar

Lite rå power får finnas för onboarding, men ska inte vara huvudspåret.

## Run Metadata

Spara från start:

- run seed
- biome / route
- room history
- reward history
- boss pool candidates
- event pool weights
- modifier flags
- curse/blessing state
- economy milestones

Detta behövs för:

- QA
- balans
- recap
- seed sharing

## Performance Budgets

Sätt hårda tak tidigt för:

- max projectiles
- max chain hops
- max aura ticks per frame
- max on-hit evaluations per frame

När budget nås ska systemet degradera snyggt.

## Determinism

Gameplay-RNG ska vara reproducerbar.

Presentation måste inte vara perfekt deterministisk, men gameplay-runs ska kunna spelas upp eller reproduceras för debugging och balans.

## Save / Load

Mid-run save/load måste spara:

- buff timers
- status stacks
- ammo/reload state
- weapon runtime counters
- delayed hits
- reward pool state
- RNG state

## Telemetry / Debug

Logga minst:

- damage per source
- damage per tag
- proc rate
- overkill
- buff/debuff uptime
- reward picks
- reroll usage
- death points

Debug tools måste kunna:

- ge perks
- applicera statusar
- spawna fiender
- printa damage packet steg för steg
- visa RNG-rolls
- visa source ownership för procs

