# Six Chambers Runtime Rules Spec

Detta dokument låser de viktigaste runtime-reglerna som resten av överhaulen måste bygga på.

Det täcker:

- hit vs non-hit
- secondary effect rules
- rule-breaking override hierarchy
- source ownership
- snapshot vs live per effect family
- slot/runtime model
- CC model

## 1. Hit Taxonomy

### Counts as hit

Default `hit`:

- direct weapon hit
- direct skill hit
- direct projectile impact
- direct melee strike

Default inte `hit`:

- burn tick
- bleed tick
- poison tick
- aura tick
- reflected damage
- delayed secondary ping, om inte effekten uttryckligen säger att den räknas som hit

## 2. Secondary Effect Rules

Secondary effect betyder allt som sker efter final direct hit.

Exempel:

- status application
- delayed explosion
- on-hit mark
- proc bolt
- lifesteal
- stack application

Defaults:

- secondary effects är mer begränsade än huvudträffen
- de triggar inte full on-hit-kedja som default
- de triggar inte ny proc-kedja som default
- de räknas inte som hit som default

## 3. Override Hierarchy

När regler krockar gäller:

1. core rules
2. damage type rules
3. weapon family rules
4. skill / perk / relic overrides
5. temporary combat state

Specific beats general.

Det betyder:

- om en specifik perk säger att burn inte längre snapshotar, så gäller det
- om en specifik effect säger att beam ticks counts as hits, så gäller det

## 4. Rule-breaking Flags

Effekter och packets ska kunna bära små regel-flaggor i stället för att skapa specialfall överallt.

Viktiga flaggor:

- `can_crit`
- `snapshots`
- `counts_as_hit`
- `can_trigger_on_hit`
- `can_trigger_proc`
- `can_lifesteal`
- `allow_zero_damage`
- `proc_depth`

Exempel:

- `Bleed can Crit` -> `can_crit = true`
- `Burn is now dynamic` -> `snapshots = false`
- `Beam ticks count as hits` -> `counts_as_hit = true`
- `Proc-generated delayed ping cannot recurse` -> `proc_depth = 1`, `can_trigger_proc = false`

## 5. Source Ownership

All damage, healing och shielding ska vara attribuerbart per källa.

Varje runtime effect ska minst bära:

- `owner_actor_id`
- `owner_source_type`
  - `weapon`
  - `perk`
  - `relic`
  - `status`
  - `ultimate`
  - `enemy_skill`
  - `environment`
- `owner_source_id`
- `parent_source_id` optional

Det här behövs för:

- telemetry
- post-run summary
- death recap
- debug print

## 6. Snapshot vs Live by Effect Family

### Live by default

- direct hits
- direct skill hits
- direct melee hits

### Snapshot by default

- burn damage
- bleed damage
- poison damage
- delayed secondary hits
- proc damage

### State-based but not damage-snapshot driven

- wet
- shock buildup
- mark counters
- stagger meters

De här använder live state för application logic, men inte full damage recompute varje tick som default.

## 7. Weapon Slot / Runtime Model

### Backend model

- backend ska stödja `N` weapon slots
- spelet har just nu `2` aktiva slots

### Slot concepts

- `weapon_slots`
  full samling slots i backend
- `active_slots`
  de slots som just nu är tillåtna att användas i gameplay
- `active_weapon_slot`
  nuvarande slot i handen / fokus
- `offhand_slot`
  annan aktiv slot om relevant

### Weapon runtime state per slot

Varje slot ska kunna bära:

- `weapon_id`
- `ammo`
- `reload_timer`
- `cooldown_timer`
- `charges` if relevant
- `shots_since_reload`
- `passive_counters`
- `per_target_counters`
- `temporary_flags`

### Reload persistence

Default:

- reload state persisterar per slot
- vapen fortsätter sitt eget cooldown/reload state även om spelaren byter aktiv slot

## 8. Passive Counter Ownership

Counters ägs av den runtime-instans som faktiskt behöver dem.

Exempel:

- `shots_since_reload` ägs av weapon runtime state
- `hits_on_target[target_id]` ägs av weapon/passive runtime state
- `stagger_meter` ägs av target
- `status stacks` ägs av target status container

De ska inte gömmas som lösa värden på playern om de tillhör ett vapen eller ett mål.

## 9. Proc Recursion Defaults

Standardregler:

- direct hits får trigga full on-hit
- DoTs får inte trigga full on-hit
- proc damage får inte trigga ny proc damage
- reflected damage är separat och triggarlös
- proc-generated packets med `proc_depth >= 1` recursar inte vidare som default

Rule-breaking perks får öppna bakdörrar till detta, men bara uttryckligen.

## 10. CC Model

### CC Categories

#### Hard CC

- stun
- freeze
- knockdown
- silence

Default:

- hard CC använder diminishing returns

#### Soft CC

- slow
- chill
- weaken
- root by default in V1

Default:

- soft CC använder inte samma hårda DR-modell som hard CC

### Normal Enemy DR

V1-default:

- första hard CC inom DR-fönster: `100%`
- andra: `50%`
- tredje: `25%`
- fjärde: immunity i `4s`

Default DR-fönster:

- `6s`

### Boss CC Default

Om boss inte har egen profil använder den:

- reduced hard CC duration `20%` av normal duration
- samma DR-familj som andra hard CC
- `3s` temporary immunity efter full hard CC application

Bossar får senare kunna override:a detta med:

- `reduced_duration`
- `stagger_meter`
- `hybrid`

## 11. Acceptance Criteria

- Det är alltid tydligt om en effect counts as hit eller inte
- Snapshot/live är definierat per effect family
- Source ownership finns på packets och statusar
- Vapenbackend stödjer fler än två slots utan att gameplay måste göra det
- Reload/cooldown persisterar per slot
- Hard CC kan inte chainas obegränsat
- Bossar kan kontrolleras ibland men inte permanent

