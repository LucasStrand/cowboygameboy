# Enhetlig actor-modell och content — mål, nuläge, riktning

Det här dokumentet **låser intent**: du vill kunna lägga till stats, effekter, procs, sets, perks, items och vapen **data-nära**, och du vill att **alla karaktärtyper** (spelare, NPC, monster) ska bete sig **konsekvent** kring HP, skada, armor, inventory där det är rimligt.

Det är **inte** en lögn om att spelet redan är där — det är en **north star** plus en ärlig **gap-lista** så du kan verifiera att refaktorer pekar rätt.

---

## Mål (vad “framtidssäkrat” betyder här)

1. **En skada-pipeline** för alla: samma packet, resolver, ordning, ownership och (där möjligt) recap-metadata.
2. **En stat-modell** för försvar och (på sikt) anfall: samma registry, samma beräkningsordning, samma ställe att lägga till nya stats.
3. **Content som data**: perks/procs/gear/vapen definieras så att **nytt beteende** helst landar i **befintliga runtime-ägare** (`proc_runtime`, `weapon_runtime`, `buffs`, …) — inte nya grenar i `game.lua`.
4. **Actor-typer** delar **samma kontrakt** där designen kräver paritet (t.ex. boss med riktig armor/MR och ev. samma proc-regler), men får **olika capabilities** (spelaren har UI och meta; en enkel gris har inte inventory).

---

## Vad som redan är gemensamt (bra grund)

| Område | Gemensamt idag |
|--------|----------------|
| Direkt skada | `DamageResolver` + `DamagePacket` för träffar mot spelare och fiende |
| Status / CC | `Buffs` med `owner_kind` / `cc_profile` |
| Käll-ownership | `SourceRef` och events för recap/proc |
| Spelar-content | `StatRuntime` + `WeaponRuntime`, perks med `proc_rules`, gear med `stats` |
| Authoring-regler | Load-time validation, tooltips, checklista för kodgrindar |

Det här **är** framtidssäkring för **skadans och statusens kärna**.

---

## Var du *inte* har full paritet än (ärlig gap)

| Område | Spelare | Fiende / NPC (typiskt) |
|--------|---------|-------------------------|
| **HP / maxHP** | Dynamisk `maxHP` från resolved stats | `hp` / `maxHP` från fiendedata + elite |
| **Armor / MR** | Via `getEffectiveStats()` i resolver | Fält finns i resolver-vägen men fylls oftast inte från data; enklare defaults |
| **Utgående skada** | Vapen + perks + snapshot-kontext i resolver | `liveEnemyContext`: i princip `damage`-fält, begränsad crit/pen-pipeline |
| **Inventory / gear / vapen-slots** | Ja (`gear`, `weapons`, `WeaponRuntime`) | Nej som samma system — fienden *är* sin attackprofil |
| **Proc rules** | Perk-lista på spelaren → `proc_runtime` (via `getProcRules`) | **Phase 11:** samma motor; regler kan ligga på **attack profile** eller framtida `getProcRules` på NPC |

Alltså: **inkommande** skada kan redan vara “samma spelregler”; **utgående** och **equipment** är medvetet **olika implementationer** idag.

---

## North-star-arkitektur (riktning, inte allt på en gång)

Tänk **tre lager** i stället för “Player” och “Enemy” som två helt skilda världar:

### Lager A — Combat actor (minimum alla som kan ta skada / ha status)

Gemensamt kontrakt (begrepp, inte nödvändigtvis ett enda Lua-interface än):

- `actor_id`, `hp`, `max_hp` (läst via samma accessor om möjligt)
- `get_defense_state(packet)` → samma form som `getTargetDefenseState` behöver (armor, MR, shred, incoming mul, block om relevant)
- `apply_resolved_damage(...)` (du har redan `applyResolvedDamage` på actorer)
- `statuses` tracker

### Lager B — Offense / vapen (valfritt per actor-typ)

- Spelare: `WeaponRuntime` + perks.
- “Elit bandit med revolver”: **samma** `WeaponRuntime` instans per fiende *eller* en **data-driven attack profile** som matar samma packet-form som spelaren.
- Enkla djur: en **minimal** offense-profil (nuvarande `damage` + ev. familj) — fortfarande via **samma resolver-ingångar** där det går.

### Lager C — Inventory / meta (bara där det behövs)

- Spelare + vissa NPC: equipment slots, gold, meta.
- Monster: ofta tomt — men **inte** ett specialfall i resolvern, bara “inga slots”.

---

## Hur det kopplar till “nya stats / procs / sets”

- **Nya stats:** ska in i **registry + beräkning** först; sedan consumas av resolver/HUD (se [authoring_readiness_checklist.md](./authoring_readiness_checklist.md)).
- **Nya procs:** ska vara **regler + effekt-typer** i `proc_runtime` (eller delad “rule engine”) — *om* fiender ska proc:a, måste de **äga** samma typ av regellista eller en fiende-specifik lista med samma motor.
- **Sets:** egen liten runtime som läser equipment och applicerar **en** bonus — oberoende av om bäraren är spelare eller (sikt) NPC med samma slot-modell.

---

## Verifiering: “har jag gjort det jag tänkte?”

Du **har** gjort rätt på **skada + status + data-validering + spelar-build**.

Du **har inte** (ännu) full **actor-paritet** för offense/equipment — och det är **okej** om du medvetet prioriterat spelar-upplevelsen först. Nästa steg för att **matcha din vision ordagrant** är:

1. **Försvar på fiender:** armor/MR/incoming mul från **data** + ev. buffs — samma fält resolvern redan läser.
2. **Offense:** antingen utöka `liveEnemyContext` med rikare stats **eller** börja ge utvalda fiender **weapon-liknande** kontext (större refaktor).
3. **Proc på fiender:** dela proc-motorn med en `rules`-lista på actor, inte hårdkopplat till `player.perks` endast.
4. **Inventory:** introducera bara när en NPC faktiskt behöver samma slot-modell — annars håll “ingen inventory” som **B-lager** utan specialfall i skada.

---

## Relaterade dokument

- [authoring_readiness_checklist.md](./authoring_readiness_checklist.md) — praktiska kodgrindar per feature-typ  
- [stat_registry.md](./stat_registry.md) — gemensamt stat-språk  
- [content_authoring_spec.md](./content_authoring_spec.md) — validering och presentation  

Uppdatera detta dokument när en fas landar (t.ex. “fiender läser armor från data”) så din **verifiering** förblir spårbar.
