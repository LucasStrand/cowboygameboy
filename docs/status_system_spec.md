# Six Chambers Status System Spec

Detta dokument definierar statusar och crowd control som ett eget subsystem.

## Status Object

Varje statusinstance ska minst bära:

- `id`
- `category`
- `duration`
- `stacks`
- `tags`
- `source`
- `target`
- `cleanse_rules`
- `visual_priority`
- `cc_rules`

## Categories

V1-kategorier:

- `buff`
- `debuff`
- `mark`
- `hard_cc`
- `soft_cc`
- `utility`

## Core Rules

- Samma motor ska stödja buffs och debuffs på både spelare och fiender
- Statusinteraktioner ska byggas på tags/families, inte hårdkodade namnpar
- `cleanse`, `purge`, `expire` och `consume` är olika operationer
- Hard CC ska använda DR eller immunity

## UI Priority

Tier 1:

- stun
- freeze
- silence
- execute state

Tier 2:

- armor shred
- expose
- major damage amp
- heal block

Tier 3:

- burn
- bleed
- poison
- chill
- shock

Tier 4:

- minor stacks
- small slows
- secondary marks

UI-default:

- visa tydligt de viktigaste `3-5` statusarna

## CC Rules

Se [runtime_rules_spec.md](./runtime_rules_spec.md) för exact DR/defaults.

Statussystemet måste stödja:

- DR family
- immunity windows
- boss override profiles
- stagger-support för framtida bossar

## Initial Families

### Burn

- DoT
- snapshotad damage default
- refresh/extend duration identity

### Bleed

- DoT
- snapshotad damage default
- bra payoff för crit/consume-synergier

### Shock

- buildup-status
- overload efter tre relevanta träffar
- payoff i form av stun/damage

### Wet

- utility/status setup
- stöder shock/chain-synergi

## Remove Operations

### Cleanse

- tar bort negativa effekter från vänlig target

### Purge

- tar bort positiva effekter från fiende

### Expire

- naturligt slut på duration

### Consume

- tar bort status för payoff eller resource use

## Acceptance Criteria

- Statusar har tydlig source ownership
- CC-regler går att läsa per status eller per bossprofil
- Tags kan användas för interaktioner utan specialfall per namnpar
- UI kan välja toppstatusar via visual priority

