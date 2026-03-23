# Combat actor, attack profile och equipment (runtime-kontrakt)

Detta dokument låser **offentliga Lua-kontrakt** för Phase 11 actor-paritet. Spelaren behåller `WeaponRuntime` som auktoritativ offense för slice 1; fiender använder **attack profiles** som kanonisk offense-data.

## CombatActor (duck typing)

**Obligatoriskt** för entiteter som resolvern och proc-motorn ska behandla enhetligt:

| Medlem | Beskrivning |
|--------|-------------|
| `actorId` | Stabil sträng per instans. |
| `statuses` | Buff/status-tracker (`Buffs`-baserad) där relevant. |
| `get_defense_state(packet)` | Returnerar tabell med nycklar: `armor`, `magic_resist`, `armor_shred`, `magic_shred`, `incoming_damage_mul`, `incoming_physical_mul`, `incoming_magical_mul`, `block_damage_mul` (1 om ej block). |
| `applyResolvedDamage(result, world, packet)` | Befintlig apply efter resolver-pipeline. |

**Valfritt** (nil / saknad metod = capability saknas):

| Medlem | Beskrivning |
|--------|-------------|
| `getProcRules()` | Lista av normaliserade proc-regler (se `proc_runtime`). Spelare: härleds från perks. Vanlig fiende: oftast tom; regler kan ligga på attackprofil. |
| `getEquipmentState()` | Framtida gear-liknande state; ska inte krävas för skada. |
| `getAttackProfile(id)` | Lookup mot data (t.ex. `AttackProfiles.get`); valfri convenience. |

## AttackProfile (data i `src/data/attack_profiles.lua`)

Minimikontrakt:

| Fält | Krav |
|------|------|
| `id` | Unik sträng; används som `SourceRef.owner_source_id` för fiende-anfall. |
| `kind` | Paketets `kind` (slice 1: `direct_hit`). |
| `family` | `physical`, `magical` eller `true`. |
| `base_min`, `base_max` | Kanoniska värden vid svårighet 1 (validering); **runtime** använder `enemy.damage` på instansen för att behålla befintlig skalning (difficult + elite). |

Valfritt: `offensive_stats` (stat-id → värde, via `StatRegistry`), `status_applications`, `proc_rules`, `presentation_hooks`, `tags`, `keywords`, `tooltip_key` / `tooltip_override` / `tooltip_tokens`, flaggor som `can_crit`, `counts_as_hit`, `can_trigger_proc`, leveranstyp (`contact` vs `projectile` internt i byggaren).

## EquipmentCapability

- Endast kontrakt i denna fas: `getEquipmentState()` får returnera `nil`.
- Offense och defense får **inte** kräva inventory.

## Legacy / fallback

1. Om `get_defense_state` saknas på mål använder resolvern en minimal fallback (bakåtkompatibilitet).
2. Om attackprofil saknas för ett `owner_source_id` använder `liveEnemyContext` `enemy.damage` som idag.
3. `enemy.damage` på instansen förblir sanningskälla för **numerisk** skala (difficulty `getScaled` + elite-multiplikator i `Enemy.new`).

## Relaterat

- [phases/phase_11_actor_parity_baseline.md](./phases/phase_11_actor_parity_baseline.md)
- [unified_actor_and_content_vision.md](./unified_actor_and_content_vision.md)
