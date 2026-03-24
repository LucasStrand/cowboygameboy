# Authoring readiness — kodgrindar innan nytt content

Kort checklista: innan du låser design eller skriver stora content-mängder, verifiera att **fundamentet i kod** stödjer idén. Annars blir det workarounds i gameplay-lager.

Se även: [unified_actor_and_content_vision.md](./unified_actor_and_content_vision.md) (målbild: samma actor-kontrakt för HP/skada/armor/inventory där det ska gälla), [content_authoring_spec.md](./content_authoring_spec.md), [stat_registry.md](./stat_registry.md), [damage_rules_matrix.md](./damage_rules_matrix.md).

---

## 1. Ny stat eller modifierare (t.ex. `% armor`, HP-skalad `move_speed`)

**Innan** gear/perk/set/boon refererar staten:

- [ ] Finns stat-id (eller tydlig legacy-mappning) i **stat registry** / er faktiska stat-pipeline?
- [ ] `StatRuntime` (eller motsvarande) **summerar** den med rätt ordning: flat → add_pct → mul → override → clamp?
- [ ] **Mitigation / combat** som ska läsa staten gör det från **resolved** stats, inte från rå `player.stats` om det är spelaren?

*Annars:* content ser ut att “finnas” men beter sig noll eller dubbelräknas.

---

## 2. Ny gear-slot eller equipment-yta (t.ex. `legs`)

**Innan** items auktoriseras i data:

- [ ] Slot finns i **player-modell** (`gear[...]`), loadout-UI, ev. shop/reward filters?
- [ ] **Validering** känner igen slot-namnet vid load?
- [ ] Stats från slotten **ingår** i samma beräkningsväg som övrig gear?

---

## 3. Set bonus / kollektion (2/2, “räkna bara en gång”)

**Innan** set copy finns i flera items:

- [ ] Finns **datakontrakt** (`set_id`, krav på antal delar, unika slots)?
- [ ] Finns **en** runtime som räknar equipped set och applicerar **en** modifier (inte per-item dublett)?
- [ ] Set-effekten uttrycks som **stats eller triggers** som redan stöds — inte dold logik i tooltip-only?

*Nuvarande läge (repo):* ingen generisk set-runtime — detta är en **feature-slice**, inte bara content.

---

## 4. Proc / “var N:te träff” / extra skada / AoE från proc

**Innan** perk beskriver beteende:

- [ ] Trigger finns i **`proc_rules`** + `proc_runtime` matchar `trigger`, `packet_kind`, `source_*`?
- [ ] För **räknare per mål**: använd befintligt läge (t.ex. `source_target_hits` + `every_n`) eller utöka runtime **först**?
- [ ] För **splash / explosion**: finns en **authorad effekt-typ** som köar resolver-jobb med radie — eller är det idag bara vapen/metadata-vägen?

*Poäng:* “extra skada på samma target” är nära befintligt mönster; “proc som stor AoE” kräver ofta **ny effect-type** eller återanvändning av explosion-secondary med tydlig data.

---

## 5. Ny damage-familj eller “unik typ” (t.ex. shadow)

**Innan** vapen/perk säger `family = "shadow"`:

- [ ] **Resolver:** hur påverkar den armor/MR/true bypass? (Ny gren i mitigation eller medvetet alias till `physical`/`magical`/`true`.)
- [ ] **Mottagare:** har fiende/spelare fält för resist mot den typen om den *inte* ska bete sig som befintlig familj?
- [ ] **Recap / metadata:** finns bucket eller tagg så breakdown och UX inte ljuger?

*Smal väg:* samma `family` som befintlig + **`tags` / metadata** för smak (UI, SFX) om gameplay ska följa physical/magical/true.

---

## 6. Boss eller fiende med “samma djup” som spelaren

**Innan** boss designas som mini-spelare:

- [ ] **Inkrement:** fienden har faktiskt ifyllda **defense-fält** som resolvern läser (`armor`, `magic_resist`, incoming-mul …)?
- [ ] **Utgående:** ska använda **samma** källa som spelaren (`WeaponRuntime`, crit, pen) eller acceptera du **enklare** fiende-pipeline med tydlig dokumentation?

*Nuvarande läge (repo):* spelare och fiende delar **resolver för träff**, men **bygger stats och attacker olika** — paritet är arkitektur, inte en rad i `enemies.lua`.

---

## Snabb “stop”-fråga

Om du inte kan säga **vilken modul** som äger beteendet (`damage_resolver`, `proc_runtime`, `weapon_runtime`, `stat_runtime`, `buffs`, `run_metadata`, …) med **en mening**, är risken hög att det blir specialfall i `game.lua` / combat — bra signal att göra feature-slice först.
