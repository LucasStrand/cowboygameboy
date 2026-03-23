# Six Chambers Combat/Build Overhaul Roadmap

Detta dokument är master-index och exekveringsplan för combat/build-overhaulen.

Syftet är att:

- samla alla designbeslut i en tydlig väg framåt
- låsa rätt implementation-ordning
- visa beroenden mellan faser
- hålla migrationen spårbar
- säkerställa att dokumentation uppdateras tillsammans med kod

## Dokumentindex

| Dokument | Roll | Status |
|---|---|---|
| [combat_progression_architecture.md](./combat_progression_architecture.md) | Övergripande vision och systemriktning | `locked foundation` |
| [stat_registry.md](./stat_registry.md) | Statmodell och registry | `locked foundation` |
| [weapon_architecture.md](./weapon_architecture.md) | Vapenmodell och resolved weapon stats | `locked foundation` |
| [status_architecture.md](./status_architecture.md) | Statusidentiteter och V1-balanstankar | `locked foundation` |
| [consumables_architecture.md](./consumables_architecture.md) | Potions, boons och sustain | `locked foundation` |
| [implementation_foundation.md](./implementation_foundation.md) | Enkel förklaring av tekniska kärnfrågor | `locked foundation` |
| [content_authoring_spec.md](./content_authoring_spec.md) | Validation, tooltips, localization, presentation hooks | `phase 1 spec` |
| [status_system_spec.md](./status_system_spec.md) | Status/CC-system som runtime-subsystem | `phase 1 spec` |
| [ux_meta_systems_spec.md](./ux_meta_systems_spec.md) | UX, rewards, economy, meta och metadata | `phase 1 spec` |
| [damage_rules_matrix.md](./damage_rules_matrix.md) | Standardregler för direct hit, DoT, proc och true damage | `phase 1 spec` |
| [damage_resolution_spec.md](./damage_resolution_spec.md) | Exakt damage order och mitigationmodell | `phase 1 spec` |
| [runtime_rules_spec.md](./runtime_rules_spec.md) | Hit-regler, overrides, slot/runtime-model och proc-defaults | `phase 1 spec` |
| [phases/phase_02_shared_foundations.md](./phases/phase_02_shared_foundations.md) | Phase 2 implementation log | `implemented` |
| [phases/phase_03_player_loadout_weapon_runtime.md](./phases/phase_03_player_loadout_weapon_runtime.md) | Phase 3 implementation log | `implemented + hardened` |
| [phases/phase_04_direct_hit_damage_migration.md](./phases/phase_04_direct_hit_damage_migration.md) | Phase 4 implementation log | `implemented + verified` |
| [phases/phase_05_unified_status_cc_runtime.md](./phases/phase_05_unified_status_cc_runtime.md) | Phase 5 implementation log | `implemented + verified` |
| [phases/phase_06_explosive_bullet_vfx_and_ricochet_exclusivity.md](./phases/phase_06_explosive_bullet_vfx_and_ricochet_exclusivity.md) | Phase 6 implementation log | `implemented + live visual closeout complete` |
| [phases/phase_07_content_tooltips_and_presentation_hooks.md](./phases/phase_07_content_tooltips_and_presentation_hooks.md) | Phase 7 implementation log | `implemented v1 slice` |
| [phases/phase_08_reward_weighting_economy_and_run_metadata.md](./phases/phase_08_reward_weighting_economy_and_run_metadata.md) | Phase 8 implementation log | `implemented + truth gate passed + live recap closeout complete` |
| [phases/phase_09_ux_readability_pass.md](./phases/phase_09_ux_readability_pass.md) | Phase 9 plan / acceptance contract | `slice 1 implemented` |
| [phases/phase_10_hardening.md](./phases/phase_10_hardening.md) | Phase 10 plan / acceptance contract | `slice 1 implemented` |
| [phases/phase_11_actor_parity_baseline.md](./phases/phase_11_actor_parity_baseline.md) | Phase 11 actor / attack profile / proc seams | `baseline slice (see phase doc)` |
| [actor_combat_contract.md](./actor_combat_contract.md) | CombatActor, AttackProfile, equipment stub | `Phase 11 contract` |

Icke-relevanta markdown-filer i `docs/` för denna roadmap ska lämnas utanför indexet.

Just nu gäller det:

- `suno_fight_prompts.md`

## Beslutsbucketar

## Current Repo Position

- Code audit status: Phases 2–8 complete; **Phase 9 slice 1** (readability / recap / HUD) and **Phase 10 slice 1** (metadata retention caps, scoreboard write hardening, recap defensive paths, regression harness, dev stress preset) are implemented in code. **Phase 11 slice 1** adds actor-paritet: `get_defense_state`, attack profiles för fiende-offense, generaliserad `proc_runtime`, equipment stub, `--phase11-actor-regression`.
- Canonical truth remains: `run_metadata` → `MetaRuntime.summarize` → recap/export; damage-event rings and long-run metadata tables are **explicitly capped** (see `RunMetadata.retentionStats` and [phase_10_hardening.md](./phases/phase_10_hardening.md)).
- Regression: run `love . --phase10-regression` and `love . --phase11-actor-regression` from the repo root (prints OK or exits non-zero on failure).

### Locked

- Incrementell, foundation-first migration
- Två aktiva vapenslots i spelet nu, men arkitekturen måste stödja fler
- `physical`, `magical` och `true` är riktiga damage families
- `true damage` bypassar `armor` och `magic_resist`
- Standardregler gäller alltid först
- Specifika perks, augments, relics och states får bryta standardregler uttryckligen
- Direct hits är huvudträffen och går genom full pipeline
- DoTs och secondary effects är snapshotade och begränsade som default
- Rule-breaking perks är en egen viktig content-kategori
- Statusar och CC är ett eget subsystem
- Hard CC får inte kunna chainas obegränsat
- Source ownership måste finnas för damage, healing, shielding och recap
- Documentation must ship with code

### Open

- Exakta tuningvärden för CDR-cap, min reload time, max chain count och max projectile count
- Exakta HUD-prioriteter och hur mycket build-stöd UI ska exponera under run
- Exakta reward weights och hur aggressiv build-detektion ska vara
- Exakta bossprofiler för CC per bossfamilj
- Exakt mängd hjälp för lågroll-runs

### Deferred

- Full content expansion efter V1-foundation
- Större breadth-meta efter att reward/meta-pipelines är stabila
- Mer exotiska summons/orbitals/traps tills core resolver, status och proc-system är färdiga

## Arbetsregler

- Varje implementationfas måste uppdatera relevant `docs/*.md` före eller tillsammans med kod
- Varje fas får ett eget dokument med relevant info om vad som ändrats, problem som uppstod, lösningar som valdes och vad som förberetts inför nästa fas
- Dokumentera mycket i dessa fas-markdownfiler. Det är bättre med för mycket info än för lite
- Blockers och lösningar måste dokumenteras tydligt så framtida arbete kan förstå varför vissa val gjordes och om senare lösningar fortfarande går att implementera som tänkt
- Läs alltid den tidigare fasens md fil efter relevant info som kan påverka utveckling av denna fas. Om måste, kolla längre tillbaka i faserna.
- Varje ny runtime-regel ska ha exakt ett source-of-truth-dokument
- Varje undantag från standardregler ska dokumenteras i en `rule-breaking`-sektion
- Varje migrerad subsystemfas måste lägga till:
  - acceptance checklist
  - debug hooks / commands
  - telemetry fields
- Inga `misc overhaul`-brancher
- En branch eller PR ska motsvara en tydlig subsystemmilstolpe

## Fasstatus

- [x] Phase 0: Freeze the program
- [x] Phase 1: Lock runtime specs
- [x] Phase 2: Shared foundations
- [x] Phase 3: Player/loadout/weapon runtime
- [x] Phase 4: Direct-hit damage migration `implemented + verified`
- [x] Phase 5: Status + CC subsystem `implemented + verified`
- [x] Phase 6: Proc system + rule-breaking overrides `implemented + live visual closeout complete`
- [x] Phase 7: Content pipeline + tooltips + presentation hooks `implemented v1 slice`
- [x] Phase 8: Economy + rewards + meta + run metadata `implemented + truth gate passed + live recap closeout complete`
- [x] Phase 9: UX/readability pass `slice 1`
- [x] Phase 10: Hardening `slice 1`
- [x] Phase 11: Actor parity baseline `slice 1` (attack profiles, defense seam, proc generalization)

## Fasordning

### [x] Phase 0: Freeze the program

Mål:

- skapa exekverbar roadmap
- samla docs
- låsa buckets, trackers och arbetsregler

Output:

- detta dokument
- dokumentindex
- migration trackers

### [x] Phase 1: Lock runtime specs

Mål:

- låsa exakta runtime-regler innan stor refaktor börjar

Output:

- `damage_resolution_spec.md`
- `runtime_rules_spec.md`
- färdiga defaults för mitigation, snapshot/live, proc recursion och slot/runtime-regler

### [x] Phase 2: Shared foundations

Mål:

- bygga gemensam infrastruktur utan att direkt riva ut gammal kod

Delar:

- central stat runtime
- content validation
- damage packet model
- gameplay events
- deterministic gameplay RNG
- source ownership ids
- faslogg: `docs/phases/phase_02_shared_foundations.md`

### [x] Phase 3: Player/loadout/weapon runtime

Mål:

- flytta från nuvarande player-centriskt vapentillstånd till explicit weapon runtime state

Delar:

- slot collection
- active slot set
- resolved weapon stats
- ammo/reload/cooldown/counters i weapon runtime state

### [x] Phase 4: Direct-hit damage migration

Mål:

- route direct hits genom ny resolver före status/proc-heavy content

Delar:

- bullets
- melee
- basic explosions
- basic delayed secondary hits

### [x] Phase 5: Status + CC subsystem

Mål:

- införa riktiga status instances och CC-regler

Delar:

- duration
- stacks
- tags
- cleanse/purge/consume
- DR / boss CC rules
- UI priority

### [x] Phase 6: Proc system + rule-breaking overrides

Mål:

- stödja absurda builds utan att bryta defaultreglerna

Delar:

- proc guardrails
- override flags
- första showcase rule-breakers

### [x] Phase 7: Content pipeline + tooltips + presentation hooks

Mål:

- göra systemet authorable, validerat och förklarbart

Delar:

- load-time validation
- hybrid tooltips
- localization templates
- event-driven presentation ownership

### [x] Phase 8: Economy + rewards + meta + run metadata

Mål:

- se till att non-combat-lagret stödjer builds i stället för att sabotera dem

Delar:

- smart reward weighting
- economy roles
- breadth-first meta
- run metadata capture

### [x] Phase 9: UX/readability pass `slice 1`

Mål:

- få djupet att faktiskt landa hos spelaren

Delar:

- combat readability layers
- ownership feedback
- HUD priority tiers
- build identity support
- recap och summary

### [x] Phase 10: Hardening `slice 1`

Mål:

- få systemet robust nog för större content-expansion

Delar:

- performance budgets
- graceful degradation
- save/load
- telemetry format
- debug toolset

## Beroenden

| Från | Till | Varför |
|---|---|---|
| Phase 0 | Alla | Roadmap, buckets och docsregler måste finnas först |
| Phase 1 | Phase 2-10 | Exakta runtime-regler måste vara låsta före refaktor |
| Phase 2 | Phase 3-10 | Alla senare system behöver shared foundations |
| Phase 3 | Phase 4 | Resolvern behöver riktig weapon runtime state |
| Phase 4 | Phase 5 | Statusar behöver hit-klassificering och source ownership |
| Phase 5 | Phase 6 | Proc-override-systemet måste bygga på riktig statusmodell |
| Phase 2 + 4 | Phase 7 | Tooltips, validation och presentation behöver stabila ids och events |
| Phase 2 + 7 | Phase 8 | Reward/meta kräver tags, validation och content language |
| Phase 4 + 5 + 7 | Phase 9 | UX/readability kräver stabil feedback ownership och UI-data |
| Phase 2-6 | Phase 10 | Hardening måste bygga på verkliga runtime-gränssnitt |

## Safe Parallelism

- Telemetry/debug scaffolding kan börja under Phase 4
- Content validation och tooltiparbete kan börja under Phase 7 när ids och events stabiliserats
- Economy/reward-design kan förberedas under Phase 6 men inte finaliseras före stabil build detection

## Migration Trackers

### Foundation

| Del | Status | Nästa steg |
|---|---|---|
| Stat runtime | `implemented` | använd fortsatt som canonical statseam för senare proc/tooltips/meta |
| Damage packet model | `implemented + expanded` | bygg Phase 6 proc/override-regler ovanpå canonical packet shape |
| Gameplay events | `implemented` | bredda mot proc/presentation/recap utan att bryta ägarskap |
| Gameplay RNG wrapper | `implemented` | verifiera vidare i större gameplay/hardening-pass |

### Damage Pipeline

| Del | Status | Nästa steg |
|---|---|---|
| Damage resolution order | `implemented + verified` | använd som stabil bas för kommande proc-regler i Phase 6 |
| Mitigation model | `implemented + verified` | fortsätt bara med framtida tuning/content ovanpå resolvern |
| Pen/shred | `implemented + verified` | bredda senare via nytt content och fler resolver-paths |
| Direct-hit migration | `implemented + verified` | använd resolver/events som Phase 6-bas |

### Weapon Runtime

| Del | Status | Nästa steg |
|---|---|---|
| N-slot backend model | `spec locked after Phase 1` | ersätt hårdkodade 2-slot-antaganden i runtime |
| Resolved weapon stats | `implemented + hardened` | konsumera direkt från Phase 4 resolver-context |
| Runtime counters | `implemented + hardened` | verifiera live behavior och bygg vidare i Phase 4 |
| Projectile presentation metadata | `implemented` | bygg vidare med fler muzzle/impact/trail ids när Phase 6 breddas |

### Status System

| Del | Status | Nästa steg |
|---|---|---|
| Status definitions | `implemented + verified` | authora framtida content ovanpå content-neutral runtime |
| CC/DR rules | `implemented + verified` | bredda senare med boss-/elite-profiler när sådant content kräver det |
| Remove operations | `implemented + verified` | använd som stabil status-bas för framtida authored remove effects |
| UI priority tiers | `implemented + verified` | bygg vidare i senare readability-pass vid behov |

### Proc / Rule-Breaking

| Del | Status | Nästa steg |
|---|---|---|
| Explosive bullet VFX tiers | `implemented + live visual closeout complete` | tier scales/fps tuned; wall impacts use lower scale than enemy hits; camera shake on player explosive hits |
| Explosive vs ricochet exclusivity | `implemented + live visual closeout complete` | håll kvar som explicit override-regel i framtida content |
| General proc guardrails | `implemented` | återanvänd proc runtime för fler authored passives och overrides |
| Showcase rule-breaker: third-hit true ping | `implemented` | använd som referensmönster för senare proc-content |

### Content Validation

| Del | Status | Nästa steg |
|---|---|---|
| Load-time validation | `implemented + phase 7 breadth` | bredda senare mot fler content-typer och localization breadth |
| Tooltip model | `implemented v1` | bredda efter perks + guns till gear/status/rewards |
| Localization templates | `implemented v1` | fortsätt med fler template keys och språk senare |

### UI / Readability

| Del | Status | Nästa steg |
|---|---|---|
| Ownership feedback | `implemented v1` | bredda från proc payoff-hook till fler event-owned feedback paths |
| HUD tiers | `implemented baseline (slice 1)` | Phase 9 slice 1: Group A/B split + dev clutter preset; full redesign still optional |
| Recap/post-run summary | `implemented v2` | Phase 9 slice 1 landed; export includes format/retention version lines |

### Economy / Rewards / Meta

| Del | Status | Nästa steg |
|---|---|---|
| Reward weighting | `implemented v1` | bredda pool authoring och tuning ovanpå reward runtime |
| Economy roles | `implemented v1` | cursed/refill-bredd och djupare roll-matris |
| Meta breadth-first | `deferred` | real persistent unlocks efter stabil meta/recap-seam |
| Run metadata | `implemented + export seam + retention caps` | Phase 10 slice 1: ring buffers / table caps + `retentionStats`; full mid-run save/load still open |

## Dokumentationskrav när utveckling börjar

För varje subsystemmilstolpe ska implementerande branch:

- uppdatera relevant source-of-truth-doc
- uppdatera detta roadmap-dokument
- markera vad som blev `Locked`, `Open` eller `Deferred`
- lägga till acceptance checklist
- lägga till telemetry fields
- lägga till debug hooks

## Första konkreta implementationsteg

1. Skriv `damage_resolution_spec.md`
2. Skriv `runtime_rules_spec.md`
3. Implementera Phase 2 shared foundations först därefter
