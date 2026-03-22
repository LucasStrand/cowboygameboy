# Six Chambers Status System Spec

Det här dokumentet låser grundreglerna för statusar och crowd control.

Målet är att göra statusar till ett riktigt subsystem med tydlig logik för:

- application
- duration
- stacks
- UI
- cleanse / purge / consume
- crowd control
- interactions

## Grundfilosofi

Statusar och crowd control är inte bara "extra effekter".

De är ett eget system med tydliga regler för:

- hur de appliceras
- hur länge de varar
- hur de staplas
- hur de visas
- hur de tas bort
- hur de interagerar med andra system

Om detta inte låses tidigt blir det snabbt oklart vad som är:

- debuff
- status
- markering
- CC
- tillstånd
- proc-effekt

## Vad en status är

En status bör vara ett objekt i systemet med minst:

- `id`
- `duration`
- `stacks`
- `tags`
- `source`
- `target`
- `category`
- `cleanse_rules`
- `visual_priority`
- `cc_rules`

Bra exempel på categories:

- `buff`
- `debuff`
- `mark`
- `hard_cc`
- `soft_cc`
- `utility`
- `environmental`

## Samma motor för buffs och debuffs

Samma grundmotor bör stödja:

- buffs på spelare
- buffs på fiender
- debuffs på spelare
- debuffs på fiender

Detta är bättre än att bygga tre separata system.

Status-metadata ska i stället avgöra:

- om effekten är buff eller debuff
- vilka targets den får appliceras på
- om den kan cleansas
- om den syns i UI
- vilken priority den har
- vilka tags den bär

## Standardregler för crowd control

### Hard CC får inte chainas obegränsat

Det gäller främst:

- stun
- freeze
- silence
- knockdown
- root, om root är stark nog i spelet

Varför:

- annars kommer någon build stunlocka bossar
- encounters trivialiseras
- andra strategier blir irrelevanta

Det är inte kul broken.

Det är bara att combatsystemet slutar fungera.

### Rekommenderad DR för vanliga fiender

Exempel:

- första stun inom DR-fönster: `100%` duration
- andra stun: `50%`
- tredje stun: `25%`
- fjärde stun: immunity i några sekunder

Det gör att CC fortfarande känns starkt, men inte kan loopas obegränsat.

### Rekommenderad bossmodell

Bossar bör inte använda exakt samma regler som vanliga fiender.

Bättre lösningar:

- reduced hard CC duration
- stagger meter i stället för full stun
- temporary immunity mot samma CC-typ efter träff

### Boss immunity decay

Immunity eller DR bör kunna återställas över tid.

Det gör att:

- spelaren kan kontrollera bossen ibland
- men inte permanent
- fighten får rytm

Det är bättre än att bossen bara är permanent immun mot allt.

## Status priority och UI

När ett mål har många statusar samtidigt måste UI välja vad som faktiskt ska visas.

Annars blir det:

- visuellt stökigt
- svårt att läsa
- svårt att förstå vad som spelar roll just nu

### Rekommenderade priority tiers

#### Tier 1: Kritisk information

- stun
- freeze
- silence
- shield break vulnerability
- death mark
- execute state

#### Tier 2: Viktiga combat states

- expose
- armor shred
- major damage amp
- heal block
- unstoppable

#### Tier 3: Vanliga DoTs och setup-statusar

- burn
- bleed
- poison
- chill
- shock

#### Tier 4: Minor / utility

- små stackande debuffs
- låga slow-effekter
- mindre marks
- sekundära states

### UI-regel

Visa bara de viktigaste `3-5` statusarna tydligt.

Resten kan gömmas bakom:

- `+X`
- expansion i target info
- debugvy
- inspectvy

UI ska främst svara på:

- är målet kontrollerat
- är målet sårbart
- är målet farligt
- är det rätt läge att använda min payoff

## Status families och tags

Statusinteraktioner bör byggas på tags och families, inte på hårdkodade namnpar.

Exempel på tags:

- `fire`
- `bleed`
- `shock`
- `wet`
- `poison`
- `armor_break`
- `crit_setup`
- `execute_setup`

Det gör att systemet kan fråga:

- har target `wet`
- har target någon `fire`-effekt
- har target `3+` debuff stacks
- har target en `crit_setup` status

utan att varje kombination måste specialfallas.

### Exempel på bra kombinationslager

- `wet + shock`
  ökad chain range eller stun chance
- `bleed + crit`
  crit mot bleeding targets ger bonus eller konsumerar bleed
- `burn + execute`
  burn detonerar om target är under viss HP
- `armor set + status`
  gear bonus aktiveras om target har flera debuff-tags
- `frost + impact`
  chillade targets tar bonus stagger damage

### Viktig designregel

Interaktioner bör byggas utifrån:

- tag
- stack count
- duration
- source type
- target condition

inte bara effect-namn.

## Remove-typer

Systemet bör uttryckligen stödja olika sätt att ta bort eller använda statusar.

### `cleanse`

Tar bort negativa effekter från vänlig target.

### `purge`

Tar bort positiva effekter från fiende.

### `expire`

Statusen går ut naturligt när duration når `0`.

### `consume`

Statusen tas bort för att användas som resource eller payoff.

Exempel:

- detonate burns
- consume all bleed stacks
- remove mark to gain crit

Detta är bättre än ett generiskt "remove status".

## Rekommenderad status-shape

```lua
return {
  id = "burn",
  category = "debuff",
  tags = { "fire", "dot" },
  duration_seconds = 4.0,
  stack_rule = "extend_duration",
  snapshot_damage = true,
  cleanse_rules = {
    can_cleanse = true,
    can_purge = false,
    can_consume = true,
  },
  visual_priority = 3,
  cc_rules = nil,
}
```

Och för hard CC:

```lua
return {
  id = "stun",
  category = "hard_cc",
  tags = { "cc", "stun" },
  duration_seconds = 0.45,
  stack_rule = "refresh_if_stronger",
  cleanse_rules = {
    can_cleanse = true,
    can_purge = false,
    can_consume = false,
  },
  visual_priority = 1,
  cc_rules = {
    uses_dr = true,
    dr_family = "hard_cc",
  },
}
```

## Rekommenderade öppna beslut att låsa snart

- exakt DR-fönster för hard CC
- om root ska räknas som hard CC eller stark soft CC
- om bossar ska använda stagger meter, reduced duration eller båda
- hur många statusikoner som ska visas i vanlig HUD
- vilka tags som måste finnas i v1
