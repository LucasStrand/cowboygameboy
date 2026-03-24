# Phase 11: Actor parity baseline (offense profiles + defense/proc seams)

## Mål

- Ett gemensamt **CombatActor**-kontrakt för resolver och proc-runtime (duck typing, se [actor_combat_contract.md](../actor_combat_contract.md)).
- **Attack profiles** som förstklassigt fiende-offense-content med validator och tooltips.
- **Defense-paritet**: fiender läser armor/MR/incoming multipliers från data + statusmods via `get_defense_state`.
- **Proc-paritet**: samma motor för spelare (perks) och fiender (profilregler); guardrails oförändrade.
- Spelaren använder **inte** `WeaponRuntime` delat med fiender i denna slice.

## Status

- **Slice 1 implemented in code** (defense `get_defense_state`, attack profiles + builder, validator/tooltips, generalized `proc_runtime`, equipment stub, `--phase11-actor-regression`).

## Uttryckligen utanför scope (follow-ups i roadmap)

- **Sets** — nästa content-fas; bygger på equipment capability + samma stat/proc-sömmar.
- **Ultimates** — senare; välj actor-attacks vs special actions vs hybrid.
- **Consumables** — senare; koppla till inventory capability när baseline är stabil.

## Legacy-policy

- `enemy.damage` behålls på instansen och används som runtime skadebas när paket byggs från profiler (behåller difficulty- och elite-skalning).
- Profiler bär kanoniska `base_min`/`base_max` för authoring/validator mot `enemies.lua` vid svårighet 1.

## Elite-skalning

- **Låst val för slice 1**: elite (och difficulty) fortsätter modifiera `self.damage` i `Enemy.new` / `getScaled`; attack-byggaren sätter alltid `base_min`/`base_max` från `enemy.damage`.

## Acceptance checklist

### Defense

- [x] Resolver använder `get_defense_state` när metoden finns på målet.
- [x] Spelarens mitigation/block beteende oförändrat.
- [x] Fiende kan få armor/MR från data; status `statMods` som påverkar försvar slår igenom där det är rimligt (t.ex. armor).

### Offense

- [x] Melee-, ranged- och flying-fiender skadar via attack profile + gemensam packet-byggare.
- [x] `SourceRef.owner_source_id` är **profil-id** (inte enbart `typeId`).
- [x] `liveEnemyContext` läser profil + `enemy.damage` för bas; fallback om profil saknas.

### Authoring

- [x] Ogiltig attack profile ger load-time-fel med tydlig path/id.
- [x] Saknad `tooltip_key`/`tooltip_override` failar validatorn.
- [x] Okänd tooltip-template failar validatorn.

### Proc

- [x] Befintliga perk-procs oförändrade för spelaren.
- [x] Fiende-regler från attack profile utvärderas i samma motor; `MAX_PROC_DEPTH` respekteras.
- [x] `OnHit`-payload `source_actor` används för källägda regler.

### Equipment capability

- [x] `getEquipmentState` finns som stub (`nil`) på vanliga fiender; ingen kravkedja i resolver.

### Verifiering

- [x] `love . --phase11-actor-regression` passerar.
- [x] `love . --phase10-regression` oförändrat OK.

## Debug / dev

- Tooltips för attack profiles används primärt för dev/editor/inspektion i slice 1; spelar-HUD kan kopplas senare.
