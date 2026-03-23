# Six Chambers: Combat, Progression, and Build Architecture

Detta dokument är ett diskussionsunderlag för nästa stora omtag av:

- vapen
- perks / skills
- armor / set bonuses
- player stats
- buffs / debuffs / procs
- meta-progression utanför själva runnen

Målet är inte att låsa exakt implementation direkt, utan att definiera en arkitektur som:

- skalar när fler system tillkommer
- är enkel att balansera
- är enkel att underhålla
- gör det lätt att lägga till helt nya idéer utan att riva upp kärnan

## Designmål

Vi vill ha ett system där:

- vissa builds kan bli väldigt starka eller till och med "broken"
- dåliga runs fortfarande känns spelbara
- starka kombinationer uppstår genom synergier, inte genom spaghettilogik
- meta-progression ger små, tydliga och permanenta förbättringar
- nya effekt-typer som aura, chain lightning, bleed, thorns, summons eller orbitals kan läggas till utan att specialfalla sönder allt

## Problem i nuvarande implementation

Nuvarande kod fungerar för ett litet spel, men den kommer bli dyr att växa vidare på.

### 1. Perks muterar `player.stats` direkt

Det betyder att:

- effekter blir permanenta mutationer i state
- det blir svårt att förstå "varför" en stat har ett visst värde
- stacking-regler blir otydliga
- det är svårt att ta bort, inaktivera eller recomputea effekter

### 2. Vapenstats och playerstats är ihopkopplade på ett skört sätt

Just nu ersätter vapen vissa stats och ärver andra via en delta-modell från revolvern.

Det fungerar för:

- `bulletDamage`
- `reloadSpeed`
- `cylinderSize`

Men det blir svårt att resonera om:

- procentbonusar
- flat bonuses
- overrides
- statusbaserade effekter
- nya attacktyper som inte är vanliga kulor

### 3. Okända stats ignoreras tyst

Det gör att content kan se korrekt ut i data men inte göra något i spelet.

Exempel:

- gear eller buffs kan skriva en stat som inte finns i `player.stats`
- systemet accepterar datan, men effekten används aldrig

### 4. Effektlogik är spridd

Det finns ingen tydlig enhetlig modell för:

- on hit
- on kill
- on reload
- aura tick
- projectile bounce
- chain / fork / split
- status application

Det gör framtida content dyrt att implementera.

## Rekommenderad target-arkitektur

Vi bör dela upp systemet i fem lager.

### 1. Meta Profile

Permanent progression utanför runnen.

Exempel:

- `+5% max HP` från en upplåst relik
- starta med extra guld
- högre chans för viss item-klass
- ett nytt startvapen
- unlocks som bara lägger content i poolen

Meta Profile ska vara liten, tydlig och defensiv.

Den ska främst ge:

- små permanenta basbonusar
- unlocks
- startmodifierare

Den ska inte ge enorm power creep.

### 2. Run State

Allt som gäller för den pågående runnen.

Exempel:

- level
- XP
- valda perks
- tillfälliga buffs / debuffs
- run-specifika currencies
- events och blessings under runnen

Run State ska vara separat från Meta Profile.

### 3. Loadout

Det spelaren faktiskt bär eller använder just nu.

Exempel:

- weapon slot 1
- weapon slot 2
- fler framtida weapon slots om spelet låser upp det
- hat
- vest
- boots
- amulet / charm / relic i framtiden
- armor set pieces

Loadout ska beskriva vad spelaren har equipat, inte direkt skriva slutstats.

### Flera vapenslots i arkitekturen, två aktiva i spelet just nu

Det här är en viktig constraint för hela systemsdesignen:

- arkitekturen ska kunna stödja fler än två vapenslots
- spelet använder just nu två aktiva vapenslots
- spelaren kan inte kasta bort sina vapen fritt
- valet av secondary ska därför vara ett riktigt buildbeslut

Det betyder att systemet bör stödja:

- tydlig identitet per vapen
- tydliga tradeoffs mellan de slots som är aktiva i runnen
- synergier mellan vapen, inte bara "starkaste två DPS-valen"
- content som bryr sig om `active weapon`, `offhand weapon` och `loadout tags`
- att max aktiva slots är en game-rule, inte ett hårdkodat arkitekturval

Det betyder också att vi inte ska designa alla stats som om de vore globala.

Vissa bonuses ska vara:

- globala för spelaren
- lokala till ett visst vapen
- lokala till attackprofilen för ett visst vapen
- låsta till en viss vapentyp

### 4. Stat System

Ett centralt system som räknar ut final stats från flera lager.

Det ska bygga stats från:

1. actor base
2. meta bonuses
3. loadout modifiers
4. perks / skills
5. temporary buffs / debuffs
6. conditional effects

Final stats ska alltid vara recomputed från källor, inte bäras runt som muterad sanning.

### 5. Ability / Effect System

Allt som faktiskt gör något i combat ska beskrivas som abilities och effects.

Exempel:

- vanlig pistolskott
- shotgun volley
- aura damage
- chain lightning
- bleed on hit
- thorns
- explosion on kill
- spawn orbiting knife

Detta lager ska vara frikopplat från hur stats räknas fram.

## Statmodell

Alla stats bör definieras centralt i ett registry.

Exempel på stats:

- `max_hp`
- `move_speed`
- `armor`
- `crit_chance`
- `crit_damage`
- `attack_speed`
- `reload_time`
- `magazine_size`
- `projectile_count`
- `projectile_speed`
- `projectile_bounce`
- `chain_targets`
- `bleed_chance`
- `bleed_damage`
- `aura_radius`
- `aura_damage`

Varje stat bör ha:

- id
- default value
- min / max clamp om relevant
- display label
- eventuell rounding-regel

Det ska inte vara möjligt att lägga content på en stat som inte finns i registryt.

## Stat-katalog för vanliga bonuses

Här är en bred lista på stats och bonus-typer som ofta är relevanta i roguelites med builds, gear och proc-system.

Det betyder inte att allt måste in direkt.

Det betyder att vi bör designa arkitekturen så att dessa typer passar naturligt.

### A. Core survivability

- `max_hp`
- `flat_damage_reduction`
- `armor`
- `magic_resist`
- `block_chance`
- `block_value`
- `barrier_hp`
- `barrier_regen`
- `dodge_chance`
- `iframes_duration`
- `healing_received`
- `life_regen`
- `life_on_kill`
- `life_on_hit`
- `revive_count`
- `revive_hp_pct`

### B. Movement and control

- `move_speed`
- `air_move_speed`
- `acceleration`
- `friction`
- `jump_force`
- `extra_jumps`
- `dash_speed`
- `dash_distance`
- `dash_charges`
- `dash_cooldown`
- `coyote_time`
- `jump_buffer_time`
- `fall_speed_max`
- `gravity_scale`

### C. General offense

- `damage`
- `physical_damage`
- `magical_damage`
- `damage_vs_elites`
- `damage_vs_bosses`
- `damage_while_close`
- `damage_while_far`
- `damage_while_moving`
- `damage_while_stationary`
- `execute_threshold`
- `attack_speed`
- `cooldown_reduction`
- `crit_chance`
- `crit_damage`
- `weakspot_damage`

### D. Gun and projectile stats

- `reload_time`
- `magazine_size`
- `reserve_ammo`
- `projectile_damage`
- `projectile_speed`
- `projectile_size`
- `projectile_lifetime`
- `projectile_count`
- `projectile_spread`
- `projectile_pierce`
- `projectile_bounce`
- `projectile_split_count`
- `projectile_homing`
- `projectile_acceleration`
- `projectile_knockback`
- `recoil`
- `recoil_reduction`
- `accuracy`
- `inaccuracy`

### E. Element and damage family stats

- `bleed_chance`
- `bleed_duration`
- `bleed_damage`
- `burn_chance`
- `burn_duration`
- `burn_damage`
- `shock_chance`
- `shock_duration`
- `shock_damage`
- `poison_chance`
- `poison_duration`
- `poison_damage`
- `explosion_damage`
- `explosion_radius`
- `aoe_damage`
- `aoe_radius`

### F. Chain, bounce, proc, and secondary-hit stats

- `chain_targets`
- `chain_range`
- `chain_falloff`
- `proc_chance`
- `on_hit_damage`
- `on_crit_damage`
- `on_kill_explosion_damage`
- `thorns_damage`
- `thorns_reflect_pct`
- `retaliation_cooldown`
- `status_spread_targets`
- `status_spread_range`

### G. Aura, orbitals, summons, and autonomous damage

- `aura_damage`
- `aura_radius`
- `aura_tick_rate`
- `orbital_count`
- `orbital_damage`
- `orbital_speed`
- `summon_count`
- `summon_damage`
- `summon_duration`
- `trap_damage`
- `trap_duration`

### H. Utility and economy

- `luck`
- `gold_gain`
- `xp_gain`
- `pickup_radius`
- `shop_price_mult`
- `reroll_count`
- `banish_count`
- `offer_count`
- `healing_orb_drop_chance`
- `ammo_drop_chance`

### I. Risk / reward and build-shaping negatives

De här är också viktiga, eftersom bra armor och starka items ofta ska kunna ge tydliga nackdelar.

- `max_hp_pct_down`
- `move_speed_pct_down`
- `reload_time_up`
- `dash_disabled`
- `extra_jumps_down`
- `crit_chance_down`
- `healing_received_down`
- `incoming_damage_up`
- `shop_price_up`

## Rekommenderade statfamiljer

Alla stats bör inte behandlas lika i balans.

Vi bör redan nu tänka i kategorier.

### 1. Basstats

Det här är trygga, vanligt förekommande stats som nästan alltid känns bra:

- `max_hp`
- `move_speed`
- `armor`
- `magic_resist`
- `damage`
- `reload_time`
- `magazine_size`

## Damage Families

Detta är nu låst för v1:

- `physical` är en riktig damage family
- `magical` är en riktig damage family
- `true` är en riktig damage family

Mitigation:

- `armor` skyddar mot `physical`
- `magic_resist` skyddar mot `magical`
- `true damage` ignorerar båda helt

Element som:

- fire
- shock

ska i första hand uttryckas som tags, statuses och effect-identiteter ovanpå family-lagret.

`true damage` ska fortfarande kunna ha en damage range.

Det viktiga är att intervallet resolved först och sedan inte reduceras av `armor` eller `magic_resist`.

### 2. Build-defining stats

Det här är stats som kan forma hela runs:

- `crit_chance`
- `crit_damage`
- `projectile_count`
- `projectile_bounce`
- `chain_targets`
- `aura_damage`
- `thorns_damage`

### 3. Specialiststats

Det här är stats som kräver andra delar av bygget för att kännas bra:

- `bleed_damage`
- `shock_damage`
- `burn_duration`
- `on_kill_explosion_damage`
- `orbital_damage`
- `summon_damage`

### 4. Riskstats

Det här är stats som lätt spräcker balansen eller gör runs frustrerande om de används vårdslöst:

- `cooldown_reduction`
- `attack_speed`
- `projectile_count`
- `chain_targets`
- `proc_chance`
- `crit_chance`
- `dodge_chance`

## Armorfilosofi

Armor ska inte vara en enda axel "mer defense = bättre".

Armor bör delas in i tydliga familjer så att spelaren förstår vad ett set försöker göra.

### 1. Heavy armor

Känsla:

- långsam
- stabil
- förlåtande

Typiska bonuses:

- `max_hp`
- `armor`
- `flat_damage_reduction`
- `thorns_damage`
- `barrier_hp`

Typiska nackdelar:

- `move_speed_pct_down`
- `dash_distance_down`
- `extra_jumps_down`
- `attack_speed_down`

### 2. Light armor

Känsla:

- snabb
- aggressiv
- riskfylld

Typiska bonuses:

- `move_speed`
- `dash_charges`
- `attack_speed`
- `crit_chance`
- `reload_time` reduction

Typiska nackdelar:

- lägre `max_hp`
- lägre `armor`
- mindre crowd safety

### 3. Tactical / utility armor

Känsla:

- kontroll
- uptime
- consistency

Typiska bonuses:

- `cooldown_reduction`
- `reload_time`
- `pickup_radius`
- `luck`
- `status_chance`

### 4. Offensive set armor

Känsla:

- färre rena basstats
- starkare synergies

Typiska themes:

- bleed set
- shock set
- crit set
- thorns / retaliation set
- explosion / aoe set

Poängen är att armor ska kunna vara en primär build-motor, inte bara ett skyddslager.

## Modifier-modell

Allt som ändrar stats bör vara modifiers med tydlig typ.

Föreslagna modifier-typer:

- `flat`
- `add_pct`
- `mul`
- `override`

Exempel:

- `+10 max_hp` -> `flat`
- `+15% damage` -> `add_pct`
- `x1.25 attack speed` -> `mul`
- `set projectile_count = 3` -> `override`

### Rekommenderad beräkningsordning

För varje stat:

1. börja med base value
2. applicera alla `flat`
3. applicera summerad `add_pct`
4. applicera alla `mul`
5. applicera sista giltiga `override` om sådan finns
6. clamp / round

Det gör systemet tydligt och balanserbart.

## Skill / Perk / Item / Set Bonus som samma språk

En viktig princip:

Perks, gear, meta bonuses, buffs och set bonuses ska inte ha egna specialsystem för stats om det går att undvika.

Istället bör de alla uttryckas som en kombination av:

- stat modifiers
- granted effects
- triggers
- tags

Exempel:

### Perk: Sharpshooter

- `damage add_pct +0.15`
- `crit_chance flat +0.05`

### Armor set: Bloodletter 2-piece

- grant effect: `apply_bleed_on_hit`

### Meta relic: Old Family Flask

- `max_hp add_pct +0.05`

### Buff: Frenzy

- `attack_speed mul 1.25`
- `move_speed add_pct +0.10`

## Vapenarkitektur

Vapen bör inte vara "stats som råkar skjuta kulor".

Vapen bör bestå av:

- `weapon definition`
- `attack profile`
- `tags`
- `base modifiers`
- eventuella special-effects

Exempel:

### Weapon definition

- id
- rarity
- slot type
- attack id
- visuals / audio hooks
- stat modifiers
- tags
- capability flags
- modifier rules

### Capability flags

Vissa egenskaper är inte vanliga stats, utan regler för vad ett vapen får och inte får göra.

Exempel:

- `allow_magazine_size_bonus = false`
- `allow_reload_time_bonus = true`
- `allow_recoil_scaling = true`
- `allow_projectile_bounce = false`
- `allow_pierce_bonus = true`

Det här behövs för att vissa vapen uttryckligen ska kunna bryta mot normala buildregler.

Exempel:

- 2-round shotgun kan ha hög recoil-skalning och traversalidentitet
- samma shotgun kan uttryckligen ignorera ammo-size bonuses
- crossbow kan ha native piercing som sin identitet

### Modifier rules

Utöver capability flags bör ett vapen kunna deklarera hur vissa stats tolkas.

Exempel:

- shotgun power ökar även recoil
- recoil kan ge traversal om spelaren skjuter mot mark eller motsatt riktning
- vissa vapen kan mappa `attack_speed` till annan cadence än vanliga guns

Detta ska inte vara en hemlig special-case i player-koden, utan en del av vapnets data eller attackprofil.

### Attack profile

Beskriver vad som händer när vapnet används.

Exempel:

- fire one projectile
- fire cone volley
- beam tick
- spawn aura pulse
- launch chain bolt
- fire piercing bolt
- apply recoil impulse to player
- spawn secondary shards on impact

Det betyder att framtida content som elshockar eller flamethrower passar naturligt i samma modell.

### Exempel: traversal shotgun

En 2-round shotgun bör kunna uttryckas ungefär så här:

- låg magazine size
- hög base recoil
- power-skalning som också ökar recoil impulse
- explicit regel att `magazine_size` inte får skalas av generella bonuses

Poängen här är att vapnet inte bara är damage output, utan också movement tech.

### Exempel: crossbow

Crossbow bör kunna uttryckas ungefär så här:

- låg fire rate
- hög projectile damage
- native pierce
- eventuellt hög weakspot/crit-synergi

Crossbow ska inte behöva "låtsas vara pistol" för att passa in i systemet.

## Ability / Effect / Trigger-system

Det här är den viktiga delen för skalbarheten.

### Damage Instances

Om vi vill stödja "items kan critta", "DoTs kan critta" och andra galna synergier måste all skada i spelet representeras som samma typ av runtime-objekt.

Jag rekommenderar att varje skadeträff modelleras som en `damage instance` eller `damage packet`.

Den bör minst innehålla:

- source id
- source type
  exempel: weapon, status, item_effect, ultimate, aura
- base damage
- damage tags
- `can_crit`
- crit profile
- `can_apply_on_hit`
- `can_trigger_procs`
- `proc_depth`
- snapshot data

Poängen är att:

- ett vanligt skott är en damage instance
- burn-tick är en damage instance
- bleed-tick är en damage instance
- overload-smäll från shock är en damage instance
- item/passive damage är en damage instance

Om allt går genom samma pipeline blir det möjligt att skriva absurda men begripliga synergier.

### Delayed Secondary Hits

En viktig följd av detta är att en träff får skapa en senare, separat träff.

Exempel:

- vanligt skott gör `damage:physical`
- vapnets passive räknar hit count
- var tredje träff på samma target triggar en extra true-damage-hit
- den extra träffen kommer som en egen `damage instance`, inte som en mutation av originalträffen

Det här behövs för idéer som:

- "var tredje skott gör 110-135 true damage"
- "var tredje skott gör 15% av min physical som extra true damage"
- "träffen kommer lite senare som en liten proc eller ping"

Arkitekturregeln bör vara:

- huvudträffen resolved först
- sedan kan ett effect eller passive schedula en ny secondary hit
- secondary hit får egen family, egna tags och egen crit/proc policy
- secondary hit använder snapshot data från den träff som skapade den

Det betyder att en attack mycket väl kan göra:

1. en vanlig physical hit nu
2. en separat true-damage-ping strax efteråt

utan att de två behöver dela mitigation-regler eller crit-regler

### Critable Secondary Damage

Vi bör uttryckligen stödja att sekundär skada kan få critta när en perk/augment tillåter det.

Exempel på sekundär skada:

- burn ticks
- bleed ticks
- aura damage
- item/passive damage
- overload-smällar
- on-hit bonus damage

Detta ska inte vara default för allt.

Det ska vara opt-in via effect-regler eller globala build-rules.

Exempel:

- normal regel: burn kan inte critta
- special perk/augment: `damage_over_time_can_crit = true`
- special perk/augment: `item_effects_can_crit = true`

Det här är exakt typen av regel som kan göra en build groteskt stark på ett roligt sätt.

### Proc Safety Rules

När vi öppnar för crit på item damage och DoTs måste vi samtidigt skydda systemet mot oändliga loops.

Hårda rekommendationer:

- varje damage instance får bara göra ett crit-roll
- DoT-ticks ska inte automatiskt trigga `on_hit` om inte effekten uttryckligen säger det
- secondary damage bör som default ha `can_trigger_procs = false`
- använd `proc_depth` eller liknande för att kapa kedjor
- vissa effekter bör ha `can_recurse = false`

Annars får vi snabbt problem som:

- crit -> bleed -> crit -> on-hit -> ny bleed -> crit
- aura tick -> proc -> chain -> proc -> chain -> proc

Vi vill tillåta broken synergy.

Vi vill inte tillåta oändlig eller obegriplig synergy.

### Triggers

Exempel:

- `on_attack`
- `on_projectile_spawn`
- `on_hit`
- `on_nth_hit`
- `on_crit`
- `on_kill`
- `on_reload`
- `on_dash`
- `on_damage_taken`
- `on_room_start`
- `every_n_seconds`

### Effects

Exempel:

- deal damage
- apply status
- spawn projectile
- schedule delayed damage
- bounce projectile
- chain to nearby enemy
- heal
- grant shield
- explode
- knockback
- spawn aura pulse
- apply recoil impulse
- spawn chained secondary hit
- trigger on projectile pierce

### Conditional rules

Exempel:

- only if target has tag `bleeding`
- only if weapon has tag `pistol`
- only on every 3rd hit from this source
- only if player hp below 50%
- only if wearing set `storm_caller`

Detta är det som gör att "konstiga" idéer kan bli vanliga content-data istället för specialfall i core code.

### Projektiltung framtid

Systemet måste designas för att tåla många samtidiga saker:

- många projektiler
- många träffar per sekund
- secondary hits
- chain reactions
- aura ticks
- explosions
- ljus och impact FX

Det betyder att vi redan nu bör tänka på:

- tydlig ownership mellan combat logic och visuals
- att projectiles kan trigga andra effects utan att kedjan blir ogenomskinlig
- att samma build kan skapa många samtidiga objekt och procs
- att det ska gå att sätta rimliga limits eller budgets utan att spelkänslan dör

Gameplaymässigt vill vi tillåta kaos.

Tekniskt måste kaoset vara organiserat.

## Status-system

Statuses bör vara first-class citizens.

Exempel:

- bleed
- burn
- shock
- slow
- weak
- vulnerable
- regen
- barrier

Varje status bör definiera:

- stacking rule
- duration rule
- tick behavior
- visual hook
- tag output

Shock bör till exempel kunna användas av chain lightning-systemet.

Bleed bör kunna användas av armor sets eller perks som triggar extra effekter på blödande mål.

## Tags som lim

Tags kommer göra systemet mycket enklare att expandera.

Exempel på tags:

- `weapon:pistol`
- `weapon:shotgun`
- `weapon:crossbow`
- `damage:projectile`
- `damage:aoe`
- `damage:shock`
- `damage:bleed`
- `attack:piercing`
- `attack:recoil_mobility`
- `set:bloodletter`
- `status:bleeding`

Med tags kan vi skriva content som:

- `+20% damage with weapon:pistol`
- `shock effects gain +1 chain_targets`
- `on_hit with damage:projectile apply bleed`
- `+1 pierce with weapon:crossbow`
- `recoil impulse +25% with attack:recoil_mobility`

## Set bonus-arkitektur

Armor pieces bör ha:

- vanliga stat modifiers
- set id
- piece count contribution

Set bonuses bör definieras separat:

- 2-piece
- 3-piece
- 4-piece

Exempel:

### Bloodletter set

2-piece:

- `bleed_chance flat +0.15`

3-piece:

- grant effect `bleed_on_hit`

4-piece:

- `on_hit vs status:bleeding -> deal bonus damage`

Detta är bättre än att baka in setlogik direkt i varje armor piece.

## Meta-progression

Meta-systemet bör vara begränsat och tydligt uppdelat i tre kategorier.

### 1. Unlocks

Lägger till nytt content i pools.

Exempel:

- nytt vapen
- nytt armor set
- ny perk-familj

### 2. Start bonuses

Små permanenta bonuses.

Exempel:

- `+5% max_hp`
- `+10 starting gold`
- `+2% move_speed`

### 3. Start choices

Ger fler build-paths utan ren power inflation.

Exempel:

- välj startrevolver
- välj shotgun-start
- välj en svag charm från början

## Balanseringsprinciper

Vi bör medvetet tillåta spikes i power, men skydda golvet.

### Build ceiling

Det ska gå att bli väldigt stark.

Det är en del av charmen.

### Run floor

Spelaren ska inte känna att runnen är död för att tre offers i rad var dåliga.

Det kan lösas med:

- bättre baseline-vapen
- garanterad utility i vissa perk pools
- rerolls / banish / shop control
- fler neutralt bra stats i meta-progression

### Controlled randomness

RNG ska skapa variation, inte bara frustration.

Vi bör kunna styra:

- hur ofta rena power-perks dyker upp
- hur ofta utility dyker upp
- hur mycket en build får "hintas" av tidigare picks

### Praktisk balans-target

Vi siktar inte på att alla runs ska kännas "fair" i exakt samma grad.

Vi siktar på att en typisk fördelning över tid ungefär känns så här:

- 6 till 8 runs av 10: mediokra, stabila, spelbara
- 1 run av 10: tydligt stark och minnesvärd
- 1 run av 10: tydligt svag eller obekväm

Konsekvensen av detta är:

- baseline-power måste vara tillräcklig för att mediokra runs ska bära
- recovery-tools måste finnas för dåliga runs
- high-roll builds får gärna vara lite för starka så länge de inte blir normen
- meta-progression ska främst höja golvet, inte kapa taket

## Rekommenderad content-struktur i Lua

Data bör vara deklarativ så långt det går.

Exempel på framtida form:

```lua
return {
  id = "stormcaller_vest",
  slot = "vest",
  tags = { "set:stormcaller" },
  modifiers = {
    { stat = "armor", op = "flat", value = 2 },
    { stat = "shock_damage", op = "add_pct", value = 0.20 },
  },
  grants = {
    { effect = "shock_on_hit", chance = 0.15 },
  },
}
```

Och:

```lua
return {
  id = "shock_on_hit",
  trigger = "on_hit",
  conditions = {
    { target_has_not_status = "shock" },
  },
  effects = {
    { type = "apply_status", status = "shock", duration = 2.5 },
  },
}
```

## Rekommenderade hårda regler

För att hålla systemet sunt bör vi låsa några regler tidigt.

### Regel 1

Slutstats räknas alltid fram från källor.

Inga perks ska direkt mutera slutvärden permanent i `player.stats`.

### Regel 2

Alla stats måste finnas i ett centralt registry.

Okända stats ska ge fel i dev mode.

### Regel 3

Vapen, perks, gear, buffs och meta bonuses använder samma modifier-språk.

### Regel 4

Specialbeteenden ska i första hand implementeras som abilities/effects/triggers, inte som ad hoc `if perk then`.

### Regel 5

Set bonuses definieras separat från items.

### Regel 6

Vissa vapens beteenden ska vara weapon-locked och inte kunna brytas av generella stats.

Exempel:

- shotgun som inte får extra ammo
- crossbow som alltid är piercing-baserad
- traversal-vapen där recoil är del av identiteten

### Regel 7

Combat logic och VFX logic måste vara separerade, men kopplade via tydliga events.

Vi vill kunna ha mycket projektiler, ljus och effekter samtidigt utan att content-systemet blir oöverskådligt.

## Föreslagen implementation i etapper

Vi bör inte försöka göra allt i en patch.

### Etapp 1: Stat foundation

- inför stat registry
- inför modifier-objekt
- inför recompute av effective stats
- sluta mutera permanenta final stats direkt

### Etapp 2: Loadout and perk refactor

- gör om gear och perks till datakällor som ger modifiers
- gör vapen till tydliga attack profiles + modifiers

### Etapp 3: Trigger/effect framework

- bygg ett litet event-system för combat triggers
- lägg till on-hit, on-kill, on-reload, timed effects

### Etapp 4: Statuses and sets

- bleed
- shock
- burn
- armor sets

### Etapp 5: Meta progression

- unlocks
- start bonuses
- persistent relics

## Öppna frågor att diskutera

Det här är frågorna vi bör låsa innan implementation:

1. Hur mycket power ska meta-progression få ge innan runs tappar sin roguelike-känsla?
2. Ska perks huvudsakligen vara generella stat boosts, eller ska de mestadels vara build-defining mechanics?
3. Ska vapen kunna ha egna affix eller upgrades, eller ska all variation komma från perks och gear?
4. Hur mycket kontroll ska spelaren ha över RNG?
5. Ska armor främst vara defensivt, eller vara en viktig källa till offensiva synergies och set bonuses?
6. Ska varje damage-typ ha egen identitet, till exempel bleed, fire, shock, explosive?
7. Hur långt vill vi gå med tags och condition-system innan datan blir för tung?
8. Hur hårt ska vi låsa weapon-specific rules som ammo lock, recoil traversal och native piercing?

## Min rekommendation just nu

Om vi ska fatta ett första stort beslut redan nu så är detta mitt förslag:

- bygg om allt kring `stat registry + modifier pipeline + effect/trigger system`
- håll meta-progression liten men meningsfull
- låt gear och set bonuses vara viktiga build-enablers, inte bara defensiva siffror
- låt vapen definiera attackmönster och identitet
- låt perks främst förstärka eller vrida om en build, inte bara vara tråkiga plus-siffror

Det ger bäst chans att få ett system som både känns roligt och går att leva med i kodbasen.

## Låsta beslut hittills

Det här är beslut från diskussionen som vi tills vidare behandlar som riktning, inte bara idéer.

### 1. Run-kvalitet ska vara ojämn med flit

Målbild:

- cirka 6 till 8 runs av 10 ska kännas mediokra men spelbara
- cirka 1 run av 10 ska kännas riktigt stark
- cirka 1 run av 10 ska kännas tydligt dålig

Det betyder att vi inte ska försöka jämna ut all RNG.

Det vi ska skydda är inte att alla runs känns lika starka, utan att:

- mediokra runs fortfarande känns värda att spela
- dåliga runs fortfarande har en väg tillbaka
- starka runs får existera utan att bli standard

### 2. Armor ska gå i båda riktningar

Armor är inte bara defensivt gear.

Armor ska kunna representera:

- tung, defensiv bulk
- mobilitet och evasiveness
- hybridbyggen
- offensiva set bonuses
- utility-fokuserade set

Exempel på tradeoffs vi uttryckligen vill tillåta:

- väldigt tung armor som tar bort dubbelhopp
- lätt armor som ger move speed men mindre skydd
- set som fokuserar på cooldown reduction
- set som fokuserar på attack speed
- set som fokuserar på crit / crit damage
- set som fokuserar på thorns, bleed, shock eller andra procs

### 3. Bow och crossbow är samma family i v1

För enkelhet och tydlighet behandlas bow och crossbow som samma weapon family.

Skillnader mellan enskilda vapen i familjen uttrycks via:

- base stats
- attack profile
- capability rules

inte via helt separata families.

### 4. Staves är rena ranged weapons

Staves ska inte vara hybrid melee/ranged i v1.

Låsta identiteter:

- fire staff: burn som skalar med level
- lightning staff: shock + chain-identitet

### 5. Den stora yxan är en legendary ultimate

Den stora yxan ska inte ta vanlig weapon slot.

Istället är den första tydliga `legendary ultimate`-designen:

- när den hittas eller unlockas under runnen får spelaren en `Q`-ability
- abilityn snurrar yxan runt spelaren
- den gör hög physical AOE damage

Det innebär att vanliga weapons och ultimates bör dela teknik, men inte loadout-regler.

### 6. Supersoaker får vara usel men med nischad wet utility

Supersoakern ska få existera som ett låg-power eller smått drygt vapen.

Låst riktning:

- extremt låg damage
- extremt kort range
- kan applicera `wet`
- kan därför få nischad synergi, särskilt med shock
- wet ökar bara chansen att chaina vidare till ännu ett target
- wet släcker inte burn i v1

Men den ska inte automatiskt bli bra bara för att wet finns i systemet.

### 7. HP potions är separat sustain-system

Detta är låst för v1:

- HP potions har max stack `3`
- HP potions har `60s` cooldown
- när de är slut måste spelaren hitta sätt att fylla på igen

Detta ska vara ett eget sustain-spår, inte bara ännu en timed boon.

### 8. Vanliga mob drops ute i runnen är korta boosts

Vanliga drops från mobs ute i gameplay ska främst vara kortlivade boosts.

Exempel:

- rage
- berserk
- heal
- magnet collect all xp

Längre drycker som Monster är i nuläget främst:

- rewards
- shop-items
- event-belöningar

### 9. True damage finns som egen huvudfamily

Detta är nu låst:

- `true damage` finns som separat damage family i v1
- den går inte genom `armor`
- den går inte genom `magic_resist`
- den ska göra exakt den resolved damage instancen landar på
- den får fortfarande använda damage range, crit och vanliga source/tags-regler

Det betyder i praktiken att:

- physical damage testar targetens `armor`
- magical damage testar targetens `magic_resist`
- true damage hoppar över mitigation-steget helt

## Nästa steg

När vi är redo kan vi ta detta dokument och bryta ut det i:

1. beslut som vi vill låsa
2. konkret datamodell
3. implementation plan per subsystem
4. migration från nuvarande kod

Det konkreta registry-utkastet finns nu i [stat_registry.md](./stat_registry.md).

Den konkreta vapenmodellen finns nu i [weapon_architecture.md](./weapon_architecture.md).

Den konkreta statusmodellen finns nu i [status_architecture.md](./status_architecture.md).

Modellen för consumables och temporära boons finns nu i [consumables_architecture.md](./consumables_architecture.md).
