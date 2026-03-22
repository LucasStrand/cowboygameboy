# Six Chambers Consumables and Temporary Boons

Detta dokument definierar hur potions, drinks, elixirs, tonics, blessings och liknande tillfälliga effekter bör fungera.

I Six Chambers kan de få annat tema och annat namn än "potions".

Exempel:

- Monster-burkar
- saloon drinks
- tonics
- stimulants
- relic charges
- battlefield consumables

Poängen är densamma:

- spelaren aktiverar eller får en temporär effekt
- effekten påverkar stats, statuses, triggers eller abilities
- effekten ska passa in i samma arkitektur som resten av spelet

## Designmål

Consumables och boons ska:

- vara separata från permanent meta-progression
- vara separata från gear och perks
- vara tydligt temporära
- kunna ge både enkla statbuffar och konstigare build-effekter
- vara enkla att lägga till i content

## Rekommenderad modell

Vi bör dela upp detta i tre begrepp:

### 1. Consumable Definition

Själva itemet eller användningen.

Exempel:

- vit Monster
- fire tonic
- gambler flask

Den definierar:

- namn
- kategori
- användningsregler
- vad den applicerar

### 2. Temporary Boon

Själva aktiva effekten på spelaren.

Detta är det centrala begreppet.

En boon kan ge:

- stat modifiers
- granted effects
- triggers
- status application rules

### 3. Use Rule

Hur spelaren får eller använder effekten.

Exempel:

- instant use
- consumable slot
- pickup on touch
- shop purchase
- reward after event

## Locked V1 Direction

Det här är nu låst som riktning för v1:

### 1. HP Potions är eget sustain-system

- spelaren kan bära HP potions
- max stack är `3`
- användning har `60s cooldown`
- när potions är slut måste spelaren hitta ett sätt att fylla på igen

Detta är alltså inte samma sak som vanliga temporära power boosts.

### 2. Mob drops ute i runnen är främst korta boosts

Vanliga drops från mobs ute i gameplay ska inte vara ett stort inventory-spel.

De ska främst vara korta, tydliga boosts som plockas upp och används direkt eller nästan direkt.

Exempel:

- rage
- berserk
- heal
- magnet collect all xp

### 3. Monster/drinks är inte vanliga mob drops i nuläget

Monster och liknande längre buffs är tills vidare främst:

- rewards
- shop-items
- event-belöningar

Inte baseline-lösningen för vanliga drops från mobs.

## Terminologi

Jag rekommenderar att vi internt använder:

- `consumable` för saken man får eller använder
- `boon` för den tillfälliga aktiva effekten

Det gör att vi kan ha:

- en dryck som ger en boon
- en blessing/event som också ger en boon
- ett item som triggar en instant effect utan att bli permanent gear

## Hur det passar in i arkitekturen

Det här lagret hör hemma i `Run State`, inte i `Meta Profile`.

Ordningen blir:

1. player base
2. meta bonuses
3. loadout
4. perks
5. temporary boons
6. statuses
7. conditional runtime effects

Boons ska alltså räknas in i final stats, men de ska inte bli permanenta mutationer.

## Boon Types

### A. Simple stat boons

Exempel:

- `+15% physical damage for 3 minutes`
- `+20% move speed for 20 seconds`
- `+25 armor for 15 seconds`

Det här är den enklaste typen och bör vara trivial att lägga till.

### B. Utility boons

Exempel:

- ökad pickup radius
- bättre luck
- högre gold gain
- bättre shop odds

### C. Combat rule boons

Exempel:

- DoTs can crit
- item effects can crit
- shock chains one extra target
- attacks apply wet

Det här är väldigt viktiga eftersom de kan skapa de riktigt roliga broken builds.

### D. Event / trigger boons

Exempel:

- on reload, gain barrier
- on kill, gain frenzy
- every 5 seconds, pulse fire aura

### E. Transform boons

Exempel:

- convert part of crit chance into bleed chance
- convert move speed into attack speed
- burn damage also increases explosion damage

De här är farligare men mycket roliga.

## Duration Model

Boons bör stödja minst tre duration-typer:

### 1. Timed

Exempel:

- 20 sekunder
- 3 minuter

### 2. Room-limited

Exempel:

- gäller i nästa rum
- gäller i 3 rum

### 3. Run-limited

Exempel:

- gäller resten av runnen

Det här är fortfarande temporärt eftersom runnen dör vid death, men det är inte permanent progression.

### 4. Cooldown-limited charges

För sustain-consumables som HP potions räcker inte bara duration.

De behöver också:

- charges
- max stack
- use cooldown
- refill rules

## Stack Rules

Boons måste uttryckligen säga hur de stackar.

Föreslagna regler:

- `refresh`
- `extend_duration`
- `increase_intensity`
- `replace_if_stronger`
- `independent`

Exempel:

- flera vita Monster kan refresh eller extend
- flera damage tonics kan kanske inte stacka alls
- samma aura boon kanske bara tillåter en aktiv version

## V1 Modell för "Monster"

Din idé:

- vit Monster
- `+15% physical damage`
- `3 min`

Det passar perfekt som en enkel boon.

### Rekommenderad dataform

```lua
return {
  id = "white_monster",
  kind = "consumable",
  theme = "energy_drink",
  use_rule = "instant",
  grants_boon = "white_monster_damage",
}
```

Och:

```lua
return {
  id = "white_monster_damage",
  kind = "timed_boon",
  duration_seconds = 180,
  stack_rule = "refresh",
  modifiers = {
    { stat = "physical_damage", op = "add_pct", value = 0.15 },
  },
}
```

## HP Potion Model

HP potions bör modelleras separat från vanliga timed boons.

### Rekommenderad dataform

```lua
return {
  id = "hp_potion",
  kind = "consumable",
  category = "healing",
  max_charges = 3,
  use_cooldown_seconds = 60,
  on_use = {
    { type = "heal_missing_hp_pct", value = 0.35 },
  },
  refill_rules = {
    "shop",
    "reward",
    "special_pickup",
  },
}
```

### Designpoäng

HP potion-systemet fyller en viktig roll:

- ger kontrollerad sustain
- ger spelaren ett medvetet beslut
- minskar risken att en medioker run bara dör av attrition

Men eftersom charges är begränsade och refill kräver extern källa blir sustainen fortfarande värdefull.

## Battlefield Boost Drops

Det här är den andra stora consumable-kategorin i v1.

De här ska vara:

- korta
- tydliga
- ofta auto-apply eller nära instant use
- enkla att läsa i HUD

### Exempel

#### Rage

- kort offensiv buff
- exempel: `+20% physical damage for 8s`

#### Berserk

- mer aggressiv men farligare
- exempel: `+25% attack speed for 6s`
- eventuellt med defensiv nackdel

#### Heal

- direkt heal, ingen inventory-slot

#### Magnet

- dra in all närliggande XP eller allt XP i rummet

Det här är bra mob drops eftersom de:

- är enkla att förstå direkt
- ger tempo
- inte kräver menyhantering

## Viktig statfråga: `physical_damage`

Om du vill kunna ha `+15% physical damage` som separat buff behöver vi en tydlig skademodell med riktiga damage families.

I v1 bör vi uttryckligen ha:

- `damage:physical`
- `damage:magical`
- `damage:true`

Och boons kan påverka:

- global `damage`
- eller family-specific damage som `physical_damage`

## Rekommendation

Eftersom du låst att fysisk och magisk skada måste vara riktiga families ska systemet behandla detta som first-class gameplay-regel.

Det betyder:

- outgoing damage ska bära family info
- targets ska kunna ha olika mitigation mot physical vs magical
- boons, perks och items ska kunna säga `+physical damage`, `+magical damage` eller `+true damage`

Vi behöver däremot inte göra fire och lightning till egna huvudfamiljer i samma lager.

De kan fortfarande vara:

- damage tags
- statusfamiljer
- effect identities

ovanför physical/magical-lagret.

### Rekommenderad modell

I v1:

- `physical`
- `magical`
- `true`

är riktiga damage families.

Element som:

- fire
- shock

uttrycks främst via tags/status/effects ovanpå familyn.

Exempel:

- fire staff kan göra `damage:magical` + `damage:fire`
- lightning staff kan göra `damage:magical` + `damage:shock`
- axe ultimate kan göra `damage:physical`
- cursed boon eller execute-effekt kan göra `damage:true`

Boons kan fortfarande uttryckas via family-aware conditions eller dedikerade family stats.

Exempel:

- `+15% damage for damage:physical`
- `+10% damage for damage:true`

Det gör systemet mer generellt än att skapa 20 olika damage stats direkt.

## Suggested Data Shape

```lua
return {
  id = "white_monster_damage",
  kind = "timed_boon",
  duration_seconds = 180,
  stack_rule = "refresh",
  conditions = {
    { outgoing_damage_has_tag = "damage:physical" },
  },
  damage_rules = {
    { op = "add_pct", value = 0.15 },
  },
}
```

## Consumables vs Buffs vs Statuses

Det här ska inte blandas ihop.

### Consumable

Saken du får eller använder.

Exempel:

- Monster-burk
- tonic
- elixir

### Boon

Den tillfälliga positiva effekten på spelaren.

Exempel:

- `+15% physical damage for 180s`

### Status

Ett aktivt tillstånd, oftast på targets i combat.

Exempel:

- burn
- bleed
- wet
- shock

En consumable kan ge en boon.

En boon kan ändra hur statuses fungerar.

## Bra första kategorier i Six Chambers

### 1. Drinks

Cowboy/saloon/energy-tema.

Exempel:

- vit Monster = physical damage
- grön Monster = move speed
- svart Monster = crit chance

### 2. Tonics

Lite mer "klassisk roguelite consumable".

Exempel:

- iron tonic = armor
- gunslinger tonic = reload / attack speed
- blood tonic = bleed chance

### 3. Strange relic boons

Mer extrema, run-defining effekter.

Exempel:

- DoTs can crit
- chain lightning gains +1 target
- on kill explode

## Guardrails

För att systemet inte ska bli för rörigt bör vi låsa några regler:

### Regel 1

Consumables ger inte permanenta stats.

### Regel 2

Boons ska använda samma modifier- och effect-språk som perks och gear.

### Regel 3

Timed boons ska vara tydligt läsbara i HUD.

### Regel 4

Boons som ändrar crit/proc-regler är high-risk och ska vara sällsyntare än enkla statbuffar.

### Regel 5

Physical, magical och true är riktiga families i systemet.

Fire och shock behöver inte vara huvudfamilies i samma lager.

## Recommended Minimal V1

För första implementationen räcker det att stödja:

1. HP potion med `3` charges och `60s` cooldown
2. timed boon
3. run-limited boon
4. korta battlefield boost drops
5. `refresh` och `replace_if_stronger`
6. stat modifiers
7. conditional outgoing damage modifiers via family/tag
8. HUD timer/icon och potion charges

Det räcker för att bygga:

- HP potions
- vit Monster
- speed tonic
- crit tonic
- enkel shock-chain boon
- rage / berserk / magnet drops

## Open Decisions

Det viktigaste att låsa härnäst:

1. Hur stark heal ska en HP potion ge i v1?
2. Ska rage och berserk vara separata eller bara två namn för samma typ av offensiv boost?
3. Ska magnet dra all XP på skärmen eller all XP i hela rummet?
4. Hur mycket plats ska potion charges och korta boons få i HUD innan det blir stökigt?
