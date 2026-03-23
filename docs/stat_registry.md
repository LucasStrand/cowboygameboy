# Six Chambers Stat Registry

Detta dokument är source of truth för vilka stats som får existera i systemet.

Målet är att:

- varje stat har ett tydligt namn och ansvar
- content inte kan hitta på egna stats i tysthet
- UI, gear, perks, buffs, sets och meta-progression använder samma språk
- vi vet vilka stats som är v1 och vilka som är framtida

## Regler

### 1. Endast registry-stats är giltiga

Om en perk, item, buff eller set bonus refererar till en stat som inte finns här ska det vara ett dev error.

### 2. IDs använder snake_case

Exempel:

- `max_hp`
- `crit_chance`
- `projectile_bounce`

### 3. Stats beskriver kapacitet, inte content-logik

Bra:

- `bleed_chance`
- `chain_targets`

Inte bra:

- `stormcaller_bonus_damage_if_target_is_shocked`

Sådan logik hör hemma i effect/trigger-systemet.

### 4. Samma stat används överallt

Vi ska inte ha:

- `reload_speed`
- `reload_time`
- `reload_mult`

om de i praktiken försöker uttrycka samma sak.

För v1 använder vi `reload_time`, där lägre är bättre.

## Modifier-ops

Alla stats ska kunna modifieras via samma operationsspråk:

- `flat`
- `add_pct`
- `mul`
- `override`

Beräkningsordning per stat:

1. base
2. sum of `flat`
3. sum of `add_pct`
4. product of `mul`
5. last `override`
6. clamp / round

## V1 Active Registry

Det här är stats som jag rekommenderar att vi verkligen stödjer i första riktiga refaktorn.

| ID | Grupp | Default | Min/Max | Round | Kommentar |
|----|-------|---------|---------|-------|-----------|
| `max_hp` | survivability | `100` | min `1` | integer | Basliv |
| `move_speed` | movement | `200` | min `0` | integer | Markrörelse |
| `jump_force` | movement | `380` | min `0` | integer | Lagra som positiv styrka, inte negativ velocity |
| `extra_jumps` | movement | `1` | min `0` | integer | `1` = dubbelhopp tillåtet |
| `dash_speed` | movement | `520` | min `0` | integer | Om dash blir statdriven |
| `dash_charges` | movement | `1` | min `0` | integer | Framtidssäker men rimlig i v1 |
| `armor` | survivability | `0` | min `0` | integer | Flat mitigation före clamp till minst 1 skada |
| `magic_resist` | survivability | `0` | min `0` | integer | Flat mitigation mot magical damage |
| `block_reduction` | survivability | `0` | `0..0.95` | 2 decimals | Andel reducerad skada vid block |
| `block_mobility` | survivability | `0` | `0..1` | integer | `0` rooted, `1` full mobility |
| `damage` | offense | `1.0` | min `0` | 3 decimals | Global damage multiplier-bas, inte flat damage |
| `physical_damage` | offense | `1.0` | min `0` | 3 decimals | Family multiplier för physical damage |
| `magical_damage` | offense | `1.0` | min `0` | 3 decimals | Family multiplier för magical damage |
| `true_damage` | offense | `1.0` | min `0` | 3 decimals | Family multiplier för true damage |
| `crit_chance` | offense | `0` | `0..1` | 3 decimals | Kritchans |
| `crit_damage` | offense | `1.5` | min `1` | 3 decimals | Total crit multiplier |
| `attack_speed` | offense | `1.0` | min `0.1` | 3 decimals | Global attackspeed multiplier |
| `cooldown_reduction` | offense | `0` | `0..0.75` | 3 decimals | För abilities, inte nödvändigtvis vapeneld |
| `reload_time` | gun | `1.2` | min `0.05` | 3 decimals | Tid, lägre är bättre |
| `magazine_size` | gun | `6` | min `1` | integer | Cylinder / mag size |
| `projectile_speed` | gun | `720` | min `0` | integer | Kulhastighet |
| `projectile_damage` | gun | `10` | min `0` | integer | Basdamage per projektil |
| `projectile_count` | gun | `1` | min `1` | integer | Antal projektiler per skott |
| `projectile_spread` | gun | `0` | min `0` | 3 decimals | Spridningsvinkel |
| `projectile_bounce` | gun | `0` | min `0` | integer | Ricochet / bounce count |
| `projectile_pierce` | gun | `0` | min `0` | integer | För framtida content |
| `chain_targets` | special | `0` | min `0` | integer | Extra targets för electrical chain och liknande effekter |
| `chain_range` | special | `0` | min `0` | integer | Räckvidd för chain / arc jump |
| `accuracy` | gun | `1.0` | `0..1` | 3 decimals | `1` = perfekt accuracy |
| `lifesteal_on_kill` | sustain | `0` | min `0` | integer | Heal per kill |
| `pickup_radius` | utility | `20` | min `0` | integer | Magnet radius |
| `luck` | utility | `0` | min `0` | 3 decimals | Loot / rarity weighting |
| `xp_gain` | utility | `1.0` | min `0` | 3 decimals | För framtida meta / perks |
| `gold_gain` | utility | `1.0` | min `0` | 3 decimals | För drops / economy |
| `bleed_chance` | status | `0` | `0..1` | 3 decimals | V1-ready om vi vill lägga till bleed tidigt |
| `bleed_damage` | status | `0` | min `0` | integer | Per tick eller statusbas beroende på effect-system |
| `bleed_duration` | status | `0` | min `0` | 3 decimals | Sekunder |
| `burn_chance` | status | `0` | `0..1` | 3 decimals | Eldstatus för fire staff och andra fire-paths |
| `burn_damage` | status | `0` | min `0` | integer | Base burn damage innan eventuell level-skalning |
| `burn_duration` | status | `0` | min `0` | 3 decimals | Sekunder |
| `shock_chance` | status | `0` | `0..1` | 3 decimals | För chain lightning-paths |
| `shock_damage` | status | `0` | min `0` | integer | Sekundär shock-skalning |
| `shock_duration` | status | `0` | min `0` | 3 decimals | Sekunder |
| `wet_chance` | status | `0` | `0..1` | 3 decimals | Främst för supersoaker / water effects |
| `wet_duration` | status | `0` | min `0` | 3 decimals | Sekunder |
| `thorns_damage` | reactive | `0` | min `0` | integer | Damage tillbaka på träff |
| `aura_damage` | special | `0` | min `0` | integer | Passiv aura runt spelaren |
| `aura_radius` | special | `0` | min `0` | integer | Aura range |
| `aura_tick_rate` | special | `0` | min `0` | 3 decimals | Tickar per sekund eller period beroende på implementation |

## V1 Registry Notes

### `damage`

`damage` är global damage-skalning och ersätter nuvarande `damageMultiplier`.

Det bör vara en tydlig multiplikativ stat med base `1.0`.

### `physical_damage`, `magical_damage` och `true_damage`

Detta är nu låst som riktiga damage families i v1.

Det betyder:

- outgoing damage instances måste bära family info
- `armor` mitigates `physical`
- `magic_resist` mitigates `magical`
- `true` ignorerar både `armor` och `magic_resist`
- `true` ska göra exakt den resolved damage instancen landar på, bortsett från eventuell range-roll och rounding före mitigation-steget

Element eller themes som:

- fire
- shock

ligger ovanpå detta som tags, statuses eller effects.

Exempel:

- revolver: `damage:physical`
- lightning staff: `damage:magical` + `damage:shock`
- fire staff: `damage:magical` + `damage:fire`
- axe ultimate: `damage:physical`
- cursed proc eller execute-hit: `damage:true`

### `reload_time`

Vi standardiserar på tid, inte "reload speed".

Det gör balans enklare eftersom lägre alltid är bättre och statens betydelse alltid är samma.

### `accuracy`

Nuvarande system använder `inaccuracy`.

För registryt är `accuracy` renare som spelardriven stat:

- `1.0` = perfekt
- lägre värde = sämre

Intern implementation kan fortfarande översätta detta till spread eller inaccuracy.

### `extra_jumps`

Den här behövs för att kunna göra gear som:

- tar bort dubbelhopp
- ger trippelhopp
- byter mobilitet mot bulk

### `aura_*`

Aura är ett bra lackmustest för om arkitekturen verkligen är generaliserad.

Om aura känns naturlig i systemet så har vi troligen valt rätt riktning.

### `burn_*`

Eldstaffens burn ska skala med level.

Det betyder att:

- själva statusfamiljen `burn_chance`, `burn_damage`, `burn_duration` hör hemma i registryt
- men level-skalningen bör uttryckas i effect-data eller attack profile, inte som en egen generell stat

Exempel:

- `apply burn`
- `resolved burn damage = burn_damage * (1 + level_scale_factor * source_level)`

### `wet_*`

`wet` bör behandlas som en riktig statusfamilj trots att supersoakern är ett svagt vapen.

Det viktiga är att wet får existera i systemet utan att vattenrelaterade interactions blir specialfall.

### `chain_*`

Lightning staff gör att chain inte längre är en ren framtidsidé.

Det betyder att `chain_targets` och `chain_range` är rimliga v1-stats för el-paths och andra future arc-effects.

Själva extra chain-chansen från `wet` behöver däremot inte vara en generell stat från dag ett.

Den kan uttryckas som effect-data eller status interaction.

### Weapon-locked behavior är inte samma sak som stats

En viktig skillnad:

Det finns saker som ser ut som stats, men som egentligen är weapon capabilities eller weapon rules.

Exempel:

- om ett vapen får ta emot `magazine_size` bonus eller inte
- om ett vapen får recoil från power-skalning
- om ett vapen har native pierce som identitet
- om ett vapen får använda bounce, split eller chain modifiers

Det här ska inte modelleras som vanliga globala player stats.

Det ska istället ligga i vapendata eller attackprofilens regler.

## Weapon Capability Registry

Utöver stat registryt bör vi ha ett separat registry eller schema för weapon capabilities.

Exempel på capability fields:

- `allow_magazine_size_bonus`
- `allow_reload_time_bonus`
- `allow_attack_speed_bonus`
- `allow_projectile_bounce_bonus`
- `allow_projectile_pierce_bonus`
- `allow_chain_bonus`
- `allow_recoil_scaling`
- `recoil_has_mobility_tech`
- `native_pierce`
- `native_explosive`

Det här gör att vi kan uttrycka saker som:

- 2-round shotgun får mer recoil från power, men ingen extra ammo
- crossbow har native pierce
- vissa vapen får aldrig ricochet även om builden annars stödjer bounce

## Weapon-specific Derived Stats

Vissa stats bör få finnas både globalt och som weapon-resolved resultat.

Exempel:

- global `projectile_damage`
- global `reload_time`
- global `projectile_bounce`

Men när ett vapen används bör systemet räkna fram:

- `resolved_magazine_size`
- `resolved_reload_time`
- `resolved_projectile_damage`
- `resolved_projectile_count`
- `resolved_projectile_pierce`
- `resolved_recoil_impulse`

Poängen är:

- spelaren har ett gemensamt statlager
- varje vapen får sedan ett resolved view av de stats det faktiskt accepterar

Detta är extra viktigt eftersom spelaren alltid bär två vapen och inte kan kasta dem fritt.

## Suggested Loadout Resolution Order

När spelet räknar fram vad ett vapen faktiskt gör bör ordningen ungefär vara:

1. läs global final player stats
2. läs weapon base profile
3. applicera weapon capability rules
4. beräkna resolved weapon stats
5. skicka resolved stats till attack profile / projectile spawn

På så sätt kan vi ha:

- perks som känns globala
- vapen som ändå behåller sin identitet
- secondary weapon som fungerar annorlunda än primary utan specialspaghetti

## Deferred V2 Stats

De här bör inte blockera v1, men registryt ska kunna växa hit utan att brytas.

| ID | Grupp | Varför vänta |
|----|-------|--------------|
| `poison_chance` | status | Inte nödvändigt direkt |
| `poison_damage` | status | Inte nödvändigt direkt |
| `poison_duration` | status | Inte nödvändigt direkt |
| `chain_falloff` | special | Samma skäl |
| `aoe_damage` | special | Kan vänta tills explosionsfamiljen blir större |
| `aoe_radius` | special | Kan vänta tills explosionsfamiljen blir större |
| `barrier_hp` | survivability | Kräver barrier-system |
| `barrier_regen` | survivability | Kräver barrier-system |
| `dodge_chance` | survivability | Riskfylld balansmässigt |
| `life_on_hit` | sustain | Kräver försiktig balans |
| `execute_threshold` | offense | Bygger mer på effect-system än statsystem |
| `orbital_count` | summon | Kräver orbital-system |
| `orbital_damage` | summon | Kräver orbital-system |
| `summon_count` | summon | Kräver summon-system |
| `summon_damage` | summon | Kräver summon-system |
| `shop_price_mult` | utility | Bra senare för ekonomi-paths |
| `offer_count` | utility | Bra senare för progression-control |
| `reroll_count` | utility | Bra senare för RNG control |
| `banish_count` | utility | Bra senare för RNG control |

## Legacy Mapping

Nuvarande kod använder delvis andra namn. När vi migrerar bör vi mappa tydligt.

| Nuvarande | Ny registry-stat |
|----------|-------------------|
| `damageMultiplier` | `damage` |
| `reloadSpeed` | `reload_time` |
| `cylinderSize` | `magazine_size` |
| `bulletSpeed` | `projectile_speed` |
| `bulletDamage` | `projectile_damage` |
| `bulletCount` | `projectile_count` |
| `spreadAngle` | `projectile_spread` |
| `ricochetCount` | `projectile_bounce` |
| `lifestealOnKill` | `lifesteal_on_kill` |
| `explosiveRounds` | effect, inte stat |
| `deadEye` | effect / trigger flag, inte stat |
| `akimbo` | loadout / effect flag, inte stat |

## Effect Flags That Should Not Be Stats

De här ska inte ligga i stat registryt som vanliga numeriska stats.

De hör hemma i effects, grants, tags eller loadout state.

- `explosive_rounds`
- `dead_eye`
- `akimbo`
- `bleed_on_hit`
- `shock_on_hit`
- `double_shot_after_reload`
- `spawn_orbital_knife`
- `chain_lightning_on_crit`
- `every_third_hit_bonus`
- `delayed_true_damage_proc`

Hit hör också weapon rules som:

- `ignore_magazine_size_bonus`
- `power_scales_recoil`
- `native_piercing_bolts`
- `recoil_enables_traversal`

Och build-rules som:

- `damage_over_time_can_crit`
- `item_effects_can_crit`
- `secondary_damage_can_crit`
- `status_ticks_trigger_on_hit`

## Suggested Data Shape

Så här bör registryt ungefär representeras i Lua senare:

```lua
return {
  max_hp = {
    group = "survivability",
    default = 100,
    min = 1,
    round = "floor",
  },
  crit_chance = {
    group = "offense",
    default = 0,
    min = 0,
    max = 1,
    round_digits = 3,
  },
  projectile_count = {
    group = "gun",
    default = 1,
    min = 1,
    round = "floor",
  },
}
```

## Recommended Next Step

När vi är redo bör nästa dokument eller implementation definiera:

1. vilka stats som faktiskt hamnar i första kodversionen
2. vilka som bara finns som framtidsmål
3. vilka effects som ersätter gamla bool-flaggor
4. hur weapon attack profiles läser registryt

Den konkreta modellen för detta finns i [weapon_architecture.md](./weapon_architecture.md).

Statusdefinitionerna och deras regler finns i [status_architecture.md](./status_architecture.md).

Consumables och temporära boons finns i [consumables_architecture.md](./consumables_architecture.md).

## Damage Families

I v1 är dessa riktiga huvudfamilies:

- `physical`
- `magical`
- `true`

Mitigation:

- `armor` reducerar `physical`
- `magic_resist` reducerar `magical`
- `true` reduceras inte av någon av dem

Element och specialidentiteter uttrycks ovanpå detta via tags:

- `damage:fire`
- `damage:shock`
- `damage:bleed`

Det här betyder att samma träff kan vara:

- `damage:magical` + `damage:shock`
- `damage:physical` + `damage:bleed`

`true damage` bör normalt inte kombineras med `physical` eller `magical` på samma damage instance.

En true-damage-instance får däremot fortfarande ha:

- damage range
- crit-resultat om effekten tillåter crit
- tags som beskriver källa eller tema

Exempel:

- `damage:true` + `damage:burn`
- `damage:true` + `source:ultimate`
