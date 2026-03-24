# Six Chambers Damage Resolution Spec

Detta dokument låser exakt ordning för hur damage packets ska räknas.

Målet är:

- konsekvent balans
- ärliga tooltips
- begriplig source ownership
- tydlig separation mellan direct hit, DoT och secondary effects

## Scope

Detta gäller för:

- direct hits
- melee direct hits
- explosions
- delayed secondary hits
- DoT ticks
- proc damage
- reflected damage

Inte scope här:

- exakt VFX/SFX
- exakt reward weighting
- exakt UI-layout

## Grundregel

Direct hits går genom full damage pipeline.

DoT, proc damage, reflected damage och andra secondary effects använder samma packet-format, men följer sina egna defaultregler enligt [damage_rules_matrix.md](./damage_rules_matrix.md).

## Damage Packet Shape

Varje damage packet ska minst bära:

- `owner_actor_id`
- `owner_source_type`
- `owner_source_id`
- `parent_source_id` optional
- `packet_kind`
  - `direct_hit`
  - `dot_tick`
  - `proc_damage`
  - `reflected_damage`
  - `delayed_secondary_hit`
- `family`
  - `physical`
  - `magical`
  - `true`
- `tags`
- `base_min`
- `base_max`
- `can_crit`
- `counts_as_hit`
- `can_trigger_on_hit`
- `can_trigger_proc`
- `can_lifesteal`
- `snapshot_data`

## Exact Resolution Order

### Step 1: Classify packet

Bestäm packet kind, family, source ownership och tags innan någon skadematematik körs.

### Step 2: Roll deterministic base damage

Om packet har range:

- rolla en gameplay-RNG-bunden siffra mellan `base_min` och `base_max`

Om packet inte har range:

- använd `base_min`

Detta blir packetens `rolled_base_damage`.

### Step 3: Apply flat outgoing modifiers

Applicera alla source-side `flat`-modifierare som får påverka denna packet.

Exempel:

- flat weapon damage
- flat family damage
- flat conditional damage

Resultat: `damage_after_flat`

### Step 4: Apply additive outgoing modifiers

Summera alla relevanta `add_pct`-modifierare som får påverka packeten.

De summeras i samma additiva steg.

Exempel:

- generic damage %
- family damage %
- tag-based damage %
- conditional damage %

Resultat:

- `damage_after_add_pct = damage_after_flat * (1 + summed_add_pct)`

### Step 5: Apply multiplicative outgoing modifiers

Applicera alla relevanta `mul`-modifierare.

Detta steg används för starkare eller mer sällsynta multiplikativa effekter.

Resultat:

- `damage_after_mul`

### Step 6: Resolve crit

Crit körs här, före mitigation.

Default:

- direct hits kan critta
- DoTs och secondary effects crittar inte om inget uttryckligen säger det

Om packet får critta:

1. beräkna effektiv crit chance
2. clamp normal crit roll till `100%`
3. räkna eventuell overcap
4. konvertera overcap till extra crit damage via tunable constant `crit_overcap_to_crit_damage_rate`
5. om crit-roll lyckas, multiplicera med total crit damage

Resultat:

- `damage_after_crit`

### Step 7: Snapshot pre-defense resolved damage

Efter outgoing math och crit, men före target mitigation, sparas:

- `pre_defense_damage`

Detta snapshot används för:

- delayed secondary effects
- proc ownership
- debug print
- recap / telemetry

### Step 8: Resolve defense state

Detta steg gäller bara för `physical` och `magical`.

#### 8A. Read target defense

- `physical` läser target `armor`
- `magical` läser target `magic_resist`

#### 8B. Apply target-side shred

Shred är target state.

Det reducerar targetens defense stat för alla relevanta inkommande hits.

Exempel:

- armor shred
- magic shred

#### 8C. Apply source-side penetration

Penetration är source-side.

Det reducerar defense ytterligare, men bara för denna source eller hit.

#### 8D. Clamp effective defense

V1-default:

- effective defense clampas till minimum `0`

Negative armor/MR stöds inte som default i V1.

### Step 9: Apply mitigation formula

Default mitigation formula för `physical` och `magical`:

- `damage_multiplier = 100 / (100 + effective_defense)`

Resultat:

- `damage_after_mitigation = pre_defense_damage * damage_multiplier`

### Step 10: True damage special case

Om family är `true`:

- hoppa över Step 8 och Step 9 helt
- `damage_after_mitigation = pre_defense_damage`

### Step 11: Apply target-side incoming damage modifiers

Detta steg är för target vulnerabilities och liknande incoming multipliers.

Exempel:

- expose
- vulnerable
- marked target takes more damage

Detta sker efter mitigationmodellen, inte före.

Resultat:

- `damage_after_incoming_mods`

### Step 12: Round and clamp final damage

V1-default:

- final damage flooras till heltal
- minimum final damage är `1` för packets som kommit in med positiv damage och inte uttryckligen flaggats som `allow_zero_damage`

Resultat:

- `final_damage`

### Step 13: Apply damage to target

- reducera target HP eller barrier enligt targetens försvarsregler
- emit gameplay events med source ownership kvar

### Step 14: Spawn secondary effects

Efter final direct hit får packeten skapa:

- status application
- delayed hits
- marks
- lifesteal
- proc bolts

Detta görs enligt packet kind-reglerna, inte automatiskt för allt.

## Mitigation Defaults

### Physical

- använder `armor`
- påverkas av armor shred
- påverkas av armor penetration

### Magical

- använder `magic_resist`
- påverkas av magic shred
- påverkas av magic penetration

### True

- använder varken `armor` eller `magic_resist`
- påverkas inte av pen/shred
- ska användas som payoff eller identitet, inte baslinjelösning

## Shred vs Pen

### Shred

- target state
- kan stacka över tid
- påverkar alla framtida relevanta träffar mot target

### Penetration

- source-side modifier
- appliceras per hit eller per source
- påverkar bara den source som har penetration

## Snapshot vs Live

### Direct hits

- läser live source state vid resolution

### DoT ticks

- snapshotar damage-styrka när de appliceras som default

### Delayed secondary hits

- snapshotar pre-defense source context som default
- får behålla source ownership och tags
- läser inte om hela live damage-statet igen om inte en regelbrytande effekt uttryckligen säger det

## Defaults for Packet Kinds

Se [damage_rules_matrix.md](./damage_rules_matrix.md) för hela matrisen.

Viktigast:

- `direct_hit` = full pipeline
- `dot_tick` = snapshotad, begränsad, ingen full proc-kedja
- `proc_damage` = triggar inte ny proc-kedja som default
- `reflected_damage` = separat och triggarlös som default

## Acceptance Criteria

- Samma packettyp räknas likadant oavsett source
- Crit sker före mitigation
- Physical/magical använder samma defense-steg med olika defense stats
- True damage bypassar defense helt
- Shred är target-side och penetration är source-side
- Delayed secondary hits kan förklaras i debug med snapshot + ownership

