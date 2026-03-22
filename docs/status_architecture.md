# Six Chambers Status Architecture

Detta dokument definierar hur statuses ska fungera som system.

Fokus i v1 är:

- `bleed`
- `burn`
- `shock`
- `wet`

Målet är att statuses ska vara:

- enkla att lägga till i content
- enkla att balansera
- tydliga att läsa i kod
- tydliga att bygga synergier kring

## Designmål

Statuses ska:

- kunna appliceras av vapen, perks, armor, sets, buffs och ultimates
- ha tydliga stacking-regler
- kunna läsas av effect/trigger-systemet
- inte kräva specialfall per status i all combat-kod
- vara visuellt tydliga men tekniskt separerade från gameplay

Consumables och timed boons som påverkar statuses eller outgoing damage finns i [consumables_architecture.md](./consumables_architecture.md).

## Grundmodell

En status består av två delar:

1. `status definition`
2. `status instance`

### Status definition

Det statiska datat för typen.

Exempel:

- id
- tags
- stackregel
- refreshregel
- tick-beteende
- visuals

### Status instance

Den aktiva förekomsten på ett mål.

Exempel:

- source id
- source tags
- stacks
- remaining duration
- resolved damage per tick
- applicerade modifiers om relevant

### Snapshot vs Dynamic Scaling

För DoTs och andra statusbaserade skador behöver vi låsa om skadan snapshotas eller läses om dynamiskt.

Min rekommendation för v1:

- bleed och burn snapshotar sin tick-skada när de appliceras
- duration och stacks lever vidare separat
- ny application kan skapa ny snapshot eller skriva över den beroende på statusregel

Det gör systemet lättare att förstå och lättare att balansera.

Det öppnar också för intressanta "juiced" application moments, till exempel en stor crit som applicerar extra stark bleed.

## Rekommenderat schema

```lua
return {
  id = "burn",
  tags = { "status:burning", "damage:fire" },
  stack_mode = "intensity",
  max_stacks = 5,
  duration_mode = "refresh",
  tick_interval = 0.5,
  on_apply = {
    { type = "emit_event", event = "status_applied" },
  },
  on_tick = {
    { type = "deal_status_damage", damage_from = "instance.tick_damage" },
  },
  visuals = {
    vfx = "burn_flame",
    tint = { 1.0, 0.42, 0.1, 0.18 },
  },
}
```

## Core Concepts

### 1. Stack Mode

Statusen måste uttryckligen säga hur den stackar.

Föreslagna modes:

- `none`
  en instans åt gången
- `duration`
  fler appliceringar ökar bara duration
- `intensity`
  fler appliceringar ökar styrkan
- `independent`
  flera separata instanser kan samexistera

### 2. Duration Mode

När statusen appliceras igen måste systemet veta vad som händer med tiden.

Föreslagna modes:

- `refresh`
  duration återställs till max
- `extend`
  duration ökar med viss mängd
- `keep_longer`
  bara längre duration vinner

### 3. Source Ownership

Varje statusinstans bör veta var den kom ifrån.

Det behövs för:

- loggning
- future scaling
- on-status triggers
- source-specific interactions

Exempel:

- fire staff
- shock staff
- bleed armor set
- supersoaker

## V1 Statuses

## `bleed`

### Roll

Physical attrition-status.

Bra för:

- armor sets
- melee
- bows
- crit/weakspot-synergier

### Rekommenderad identitet

- tickar fysisk skada över tid
- stackar via intensity
- ganska låg direkt impact, högre payoff över tid

### Föreslagna regler

- `stack_mode = intensity`
- `max_stacks = 5`
- `duration_mode = refresh`
- `tick_interval = 0.5`

### Synergier

- bonus damage mot bleeding targets
- execute under X% hp
- spread bleed on kill
- crit mot bleeding targets

## `burn`

### Roll

Ranged fire attrition med level-skalning.

### Rekommenderad identitet

- tickar eldskada
- skalar med level på källan
- stabil och pålitlig damage-over-time
- mer konsekvent än shock, mindre explosiv

### Föreslagna regler

- `stack_mode = intensity`
- `max_stacks = 4`
- `duration_mode = refresh`
- `tick_interval = 0.5`

### Viktig regel

Burn level-skalning ska inte vara en global stat.

Den ska uttryckas i effect-data från källan.

Exempel:

- fire staff applicerar burn
- burn tick damage räknas vid application som:
  `resolved_burn_damage = burn_damage * (1 + level_scale_factor * source_level)`

### Synergier

- längre burn duration
- fler burn stacks
- explosion när burning enemy dör
- extra damage mot wet targets kan vara möjligt senare, men inte nödvändigt i v1

## `shock`

### Roll

Burstig control/status för chain, conductivity och stun payoff.

### Rekommenderad identitet

- ingen vanlig DoT-identitet i v1
- byggs upp av upprepade elträffar
- på tredje elträffen går målet in i overload
- overload ger stun och bonus damage
- fungerar som payoff-status för elvapen

### Föreslagna regler

- `stack_mode = intensity`
- `max_stacks = 3`
- `duration_mode = refresh`
- ingen vanlig damage tick i basversionen
- vid 3 stacks triggas overload
- overload:
  - gör bonus damage
  - applicerar `stun`
  - konsumerar eller resetar shock stacks

### Synergier

- chain till extra targets
- bonus damage mot shocked targets
- wet -> större chans att sprida vidare till ännu ett target
- stun som payoff efter uppbyggnad

### Viktig designpoäng

Elstavens chain är inte samma sak som vanlig `projectile_bounce`.

Vi bör skilja på:

- fysisk bounce / ricochet
- electrical chain / arc jump

Shock är det statuslim som gör electrical chain begriplig.

### Shock overload i v1

Den enklaste tydliga modellen är:

- första elträffen: 1 shock stack
- andra elträffen: 2 shock stacks
- tredje elträffen: overload

När overload triggas:

- målet tar en separat el-smäll
- målet stunnas en kort stund
- shock stacks resetas

Detta gör elvapen lättlästa:

- burn = stabil DoT
- shock = buildup till stun/payoff

## `wet`

### Roll

Svag utility-status som främst finns för setup och interactions.

### Rekommenderad identitet

- gör nästan ingen egen skada
- är lätt att applicera
- ökar payoff från andra system, främst shock chain
- bär Supersoakerens värde utan att göra vapnet allmänt starkt

### Föreslagna regler

- `stack_mode = duration`
- `max_stacks = 1`
- `duration_mode = refresh`
- ingen egen tick damage

### Synergier

- wet ökar chansen att shock sprider till ännu ett target
- wet kan senare användas för andra conductivity interactions

### Viktig balansregel

Wet får inte bli så starkt att supersoakern blir ett självklart top-tier-vapen.

Wet ska vara:

- nischat
- buildberoende
- mest användbart om man redan investerat i shock-paths

### Viktig regel

Wet släcker inte burn i v1.

Det håller systemet enklare och undviker onödig elemental bookkeeping tidigt.

## Status Families vs Effects

Allt ska inte vara en status.

Bra kandidater för status:

- bleed
- burn
- shock
- wet

Bra kandidater för vanliga effects istället:

- explosive rounds
- recoil boost
- on-hit bonus damage
- chain lightning proc
- legendary axe spin

Regel:

Om något behöver duration, stacks och target state är det ofta en status.

Om något bara händer direkt är det oftare en effect.

### Critable DoT and Status Damage

Normalt bör statusdamage inte critta gratis.

Men arkitekturen bör uttryckligen stödja att en buildregel kan slå på detta.

Exempel:

- `damage_over_time_can_crit = true`
- `item_effects_can_crit = true`

Det här gör det möjligt att skapa exakt de sjuka synergier som känns fantastiska när de händer.

Exempel:

- bleed från crit-bygge
- burn-ticks som kan critta
- item/passive damage som kan critta
- shock overload-smäll som kan critta

### Rekommenderad regel för v1

Varje tick eller sekundär träff som får critta ska behandlas som en egen `damage instance`.

Det betyder:

- egen crit roll
- egen damage tag set
- egen proc-behörighet

Men det betyder inte att den automatiskt får trigga hela spelets on-hit-maskineri.

### Proc Guardrails

För att undvika att critbara DoTs spräcker systemet direkt bör v1 ha dessa defaultregler:

- status ticks har `can_apply_on_hit = false`
- status ticks har `can_trigger_procs = false`
- status ticks får critta bara om buildregel eller effectregel säger det
- overload-smällar och andra payoff-effekter kan vara mer generösa än vanliga DoT-ticks

Detta gör att vi kan tillåta "Vulnerability"-liknande effekter utan att allt blir rekursiv spaghetti.

### Om `stun`

I den här v1-modellen är `stun` främst payoff från shock overload.

Det betyder att:

- `shock` är den primära elemental statusen
- `stun` kan behandlas som crowd-control effect eller separat CC-status
- vi behöver inte designa hela systemet runt `stun` som egen elemental family just nu

## Application Flow

När en status appliceras bör flödet vara:

1. source attack/effect försöker applicera status
2. chance och conditions utvärderas
3. status registry hämtas
4. stack- och duration-regler körs
5. instance skapas eller uppdateras
6. `status_applied` eller `status_refreshed` event emittas

## Tick Flow

När aktiva statuses uppdateras bör flödet vara:

1. minska timers
2. ticka instanser vars tick timer gått ut
3. emit `status_ticked`
4. hantera expire
5. emit `status_expired`

## Recommended Combat Events

Status-systemet bör emit:a minst:

- `status_applied`
- `status_refreshed`
- `status_stacked`
- `status_ticked`
- `status_expired`

Och det bör kunna reagera på:

- `projectile_hit`
- `melee_hit`
- `enemy_killed`
- `reload_completed`
- `ability_used`

## Tags

Statuses bör bidra med tags på målet medan de är aktiva.

Exempel:

- `status:bleeding`
- `status:burning`
- `status:shocked`
- `status:wet`

Det gör att content kan skriva:

- bonus damage vs `status:bleeding`
- chain bonus vs `status:wet`
- explosion on kill if `status:burning`

## UI and VFX

Gameplay och visuals ska vara separerade.

Status-definitionen bör kunna peka på:

- icon
- tint
- overlay
- hit spark
- trail modifier

Men själva renderingen ska ske i VFX/HUD-lager, inte i statuslogiken.

## Data Shape Example

### Fire staff applying burn

```lua
{
  effect = "apply_status",
  status = "burn",
  chance_from = "burn_chance",
  duration_from = "burn_duration",
  instance_values = {
    tick_damage_from = "burn_damage",
    level_scale_factor = 0.12,
    level_source = "player_level",
  },
}
```

### Supersoaker applying wet

```lua
{
  effect = "apply_status",
  status = "wet",
  chance = 1.0,
  duration = 2.5,
}
```

### Shock payoff on wet target

```lua
{
  trigger = "projectile_hit",
  conditions = {
    { target_has_status = "wet" },
    { damage_has_tag = "damage:shock" },
  },
  effects = {
    { type = "modify_chain_extra_target_chance", add = 0.25 },
  },
}
```

## Recommended Minimal V1

Om vi vill hålla första implementationen rimlig bör v1 stödja:

1. registry-driven status definitions
2. `duration` och `intensity` stack modes
3. periodic tick damage
4. target tags från aktiva statuses
5. status events

Det räcker för att bygga:

- bleed
- burn
- shock
- wet

utan att framtida statusfamiljer blir blockerade.

## V1 Balance Targets

Detta är rekommenderade startvärden för första implementationen.

De är inte tänkta som slutlig tuning, utan som en stabil första passering.

### `bleed`

Målbild:

- kännas bra på bows, melee och armor sets
- bygga över tid
- inte vinna över burn i ren consistency

Startvärden:

- `max_stacks = 5`
- `tick_interval = 0.5`
- `base_duration = 2.5s`
- `duration_mode = refresh`
- rekommenderad startskada:
  - `tick_damage_per_stack = 1`
  - eller ungefär `15%` av applicerande träffs base damage per stack om vi väljer relativ modell

Praktisk target:

- 3 stacks bleed ska kännas relevant men inte avgörande direkt
- full 5-stack ska vara bra payoff för sustained physical builds

Crit note:

- baseline: bleed-ticks crittar inte
- framtida augment/perk kan tillåta detta
- om bleed-ticks får critta bör de fortfarande inte trigga vanliga `on_hit` som default

### `burn`

Målbild:

- stabil ranged DoT
- tydlig fire identity
- skalar med player level

Startvärden:

- `max_stacks = 4`
- `tick_interval = 0.5`
- `base_duration = 3.0s`
- `duration_mode = refresh`
- rekommenderad level scaling:
  - `resolved_burn_damage = burn_damage * (1 + 0.10 * (player_level - 1))`

Rekommenderade basvärden för tidig tuning:

- `burn_damage = 2` på level 1 för vanlig fire staff-hit
- det ger:
  - level 1: `2`
  - level 5: `2.8`
  - level 10: `3.8`

Praktisk target:

- burn ska kännas mer pålitlig än shock
- burn ska vara stark i utdragna fighter men inte ge instant payoff

Crit note:

- baseline: burn-ticks crittar inte
- framtida augment/perk kan slå på crit för DoT
- burn med crit-stöd är exakt typen av high-roll synergy som vi vill kunna stödja senare

### `shock`

Målbild:

- tydlig buildup
- payoff i form av overload
- el-path ska kännas snabb, explosiv och lite kaotisk

Startvärden:

- `max_stacks = 3`
- `base_duration = 2.0s` på varje stack innan refresh
- `duration_mode = refresh`
- ingen egen tick damage
- overload triggas på tredje elträffen inom duration-fönstret

Rekommenderad overload-payoff:

- `overload_bonus_damage = 1.25x` av applicerande elträffs base damage
- `stun_duration = 0.45s`

Praktisk target:

- overload ska märkas tydligt
- stun ska vara användbar men inte gratis perma-CC
- shock ska vara svag om spelaren inte lyckas fortsätta träffa samma eller flera mål

Crit note:

- baseline: vanliga shock stacks crittar inte eftersom de inte gör tick damage
- overload-smällen kan i framtiden tillåtas critta via specialregel eller augment

### `wet`

Målbild:

- utility, inte damage
- göra shock-path bättre utan att göra Supersoaker stark i allmänhet

Startvärden:

- `max_stacks = 1`
- `base_duration = 2.5s`
- `duration_mode = refresh`
- ingen egen tick damage

Rekommenderad interaction i v1:

- `extra_chain_target_chance_bonus = +0.25`

Praktisk target:

- wet ska ibland ge ett extra chain target
- wet ska inte vara en garanterad chain-enabler
- wet ska vara märkbart bäst i builds som redan investerat i lightning/shock

### Relative Power Order

Om allt fungerar ungefär som tänkt i första passet bör känslan vara:

- `burn`: mest stabil och konsekvent
- `bleed`: bäst i sustained physical / stack-byggande builds
- `shock`: mest explosiv payoff men kräver setup
- `wet`: nästan ingen egen kraft, bara setup utility

### First Tuning Guardrails

För att undvika att v1 sticker iväg direkt:

- stun från shock overload bör inte över `0.6s` utan god anledning
- wet bör inte ge garanterad extra chain i baseline
- burn level scaling bör inte börja över `10%` per level utan test
- bleed 5-stack bör inte out-dpsa burn tydligt utan tydlig build-investering
- critbara DoTs ska inte få trigga full on-hit/proc-kedja i baseline

## Open Decisions

Det viktigaste att låsa härnäst:

1. Ska bleed använda flat tick damage eller relativ damage från applicerande träff?
2. Ska overload damage skala från senaste elträffen, vapnets base damage eller separat shock_damage?
3. Ska elites ha reducerad stun duration från shock overload redan i v1?
4. Ska fire staffs burn scaling använda player level exakt, eller ett separat combat power value senare?
