# Six Chambers Weapon Architecture

Detta dokument definierar den konkreta modellen för:

- `weapon definition`
- `attack profile`
- `capability rules`
- `resolved weapon stats`

Tanken är att vapen ska kunna vara:

- tydligt olika
- byggdrivande
- kompatibla med samma statsystem
- fria att bryta vissa generella regler

Det här är extra viktigt eftersom spelet just nu kör med två aktiva vapen, men arkitekturen bör kunna stödja fler slots senare utan att modellen behöver göras om.

## Implementation status (kod kontra detta dokument)

- **Faktisk stat-upplösning** för spelaren sker i `StatRuntime.compute_actor_stats` och följer modellen i [`player_weapon_stat_resolution.md`](player_weapon_stat_resolution.md): delta mot revolver-bas för kärnvapenstats (inkl. `crit_chance` / `crit_damage` och `rate_of_fire`), sedan härleds `shoot_cooldown` som `1 / rate_of_fire`. `inaccuracy` från vapnet **överstyr** utan delta.
- **Schema nedan** (`base_stats`, `capabilities`, `visuals` m.m.) är delvis **aspirationellt** — dagens `src/data/guns.lua` använder `baseStats`, `sprite`, `attack_profile_id`, `rules`, `onShoot`, m.m. Alla fält i exemplet finns inte nödvändigtvis i Lua-data ännu; använd validatorn och befintliga vapen som källa för vad som är bindande.

## Översikt

Föreslagen pipeline per attack:

1. läs player final stats
2. läs valt vapens `weapon definition`
3. läs kopplad `attack profile`
4. applicera `capability rules`
5. bygg `resolved weapon stats`
6. kör attackprofilen med resolved data
7. emit events för projectile, hit, kill, recoil, VFX

## 1. Weapon Definition

Weapon definition beskriver vad vapnet är som item/loadout-enhet.

Det ska innehålla:

- identitet
- loadout-data
- basvärden
- vilka stats det accepterar
- vilka regler som är låsta till vapnet

### Rekommenderat schema

```lua
return {
  id = "blunderbuss",
  name = "Blunderbuss",
  rarity = "uncommon",
  slot_type = "weapon",
  family = "shotgun",
  attack_profile = "shotgun_blast",
  tags = {
    "weapon:shotgun",
    "attack:projectile",
    "attack:recoil_mobility",
  },
  visuals = {
    sprite = "Blunderbuss.png",
    muzzle_fx = "muzzle_shotgun",
    fire_sfx = "shoot_shotgun",
  },
  base_stats = {
    reload_time = 1.8,
    magazine_size = 2,
    projectile_speed = 580,
    projectile_damage = 6,
    projectile_count = 5,
    projectile_spread = 0.45,
    attack_speed = 1.0,
    crit_chance = 0,
    crit_damage = 1.5,
    recoil_impulse = 280,
  },
  capabilities = {
    allow_magazine_size_bonus = false,
    allow_reload_time_bonus = true,
    allow_projectile_bounce_bonus = false,
    allow_projectile_pierce_bonus = false,
    allow_chain_bonus = false,
    allow_recoil_scaling = true,
    recoil_has_mobility_tech = true,
  },
  rules = {
    damage_scales_recoil = 0.8,
    recoil_only_when_aiming_down = true,
  },
}
```

## 2. Attack Profile

Attack profile beskriver vad som faktiskt händer när vapnet används.

Viktigt:

- flera vapen kan dela samma attack profile
- vapnets data sätter flavour och regler
- attackprofilen sätter beteende

### Attack profile ansvarar för

- attack cadence
- projektilspawn
- recoil / self-force
- hur hit-resultat skapas
- interna counters eller proc-state som är kopplade till attackmönstret
- vilka combat events som emittas

### Rekommenderat schema

```lua
return {
  id = "shotgun_blast",
  type = "projectile_weapon",
  on_attack = {
    {
      type = "spawn_projectiles",
      projectile_kind = "pellet",
      count_from = "projectile_count",
      speed_from = "projectile_speed",
      damage_from = "projectile_damage",
      spread_from = "projectile_spread",
    },
    {
      type = "apply_self_recoil",
      impulse_from = "recoil_impulse",
      require_tag = "attack:recoil_mobility",
    },
  },
}
```

Attack profiles bör också kunna deklarera eller använda lokal runtime state som:

- shot counter
- hit counter
- per-target hit counter
- cooldown för intern passive

Det här behövs för design som:

- "var tredje skott"
- "var tredje träff på samma fiende"
- "efter reload gäller nästa två träffar"

## 3. Capability Rules

Capability rules bestämmer hur generella stats får påverka ett visst vapen.

Detta är inte samma sak som vanliga modifiers.

Det här lagret behövs för att kunna säga:

- "den här shotgunnens ammo får aldrig öka"
- "den här crossbowen har alltid pierce"
- "det här vapnet får recoil av damage scaling"

### Typer av capability rules

#### A. Allow / deny

Exempel:

- `allow_magazine_size_bonus = false`
- `allow_projectile_bounce_bonus = true`
- `allow_attack_speed_bonus = true`

#### B. Native features

Exempel:

- `native_pierce = 2`
- `native_explosive = true`
- `native_chain_targets = 1`

#### C. Transform rules

Exempel:

- damage bonus skalar recoil
- crit chance konverteras delvis till weakspot damage
- attack speed påverkar charge time istället för raw fire rate

#### D. Constraints

Exempel:

- magazine size får aldrig gå över 2
- projectile count får aldrig bli över 1 för denna crossbow
- chain får inte aktiveras för denna vapentyp

## 4. Resolved Weapon Stats

Resolved weapon stats är resultatet av att kombinera:

- global player final stats
- vapnets egna base stats
- capability rules
- tags
- temporära states om nödvändigt

Poängen är att varje vapen får sitt eget slutvärde utan att förlora sin identitet.

### Rekommenderat schema

```lua
{
  weapon_id = "blunderbuss",
  family = "shotgun",
  tags = {
    "weapon:shotgun",
    "attack:projectile",
    "attack:recoil_mobility",
  },
  attack_speed = 1.12,
  reload_time = 1.35,
  magazine_size = 2,
  projectile_damage = 9,
  projectile_speed = 580,
  projectile_count = 7,
  projectile_spread = 0.62,
  projectile_pierce = 0,
  projectile_bounce = 0,
  crit_chance = 0.05,
  crit_damage = 1.75,
  recoil_impulse = 410,
}
```

Resolved weapon stats bör inte försöka bära allt.

Counters som:

- `shots_fired_since_reload`
- `hits_on_target[target_id]`
- `passive_proc_cooldown`

är runtime state och hör hemma i weapon runtime / attack profile state, inte i statsystemet.

### Viktig princip

`resolved weapon stats` ska vara read-only runtime output.

De ska inte lagras som permanent mutation på playern.

## 5. Resolution Flow

Rekommenderad beräkningsordning:

### Steg 1. Hämta global player final stats

Exempel:

- `damage`
- `crit_chance`
- `crit_damage`
- `reload_time`
- `magazine_size`
- `projectile_count`

### Steg 2. Börja från weapon base stats

Vapnets egna värden är alltid basen för resolved output.

### Steg 3. Applicera tillåtna globala modifiers

Om vapnet tillåter en viss stat så får den påverkas.

Exempel:

- shotgun tillåter `reload_time`
- shotgun tillåter `projectile_count`
- shotgun tillåter inte `magazine_size`

### Exempel: third-hit true damage passive

Implementation note:

- Phase 6 now lands this pattern as the first live showcase rule-breaker.
- The current runtime implementation uses a perk-authored proc rule that listens to resolver-owned `OnHit` events, counts hits per source + target, and schedules a delayed canonical `true`-family packet on every third hit.

Det här är ett bra exempel på varför vapenarkitekturen behöver både resolved stats och runtime state.

Scenario:

- vapnet gör vanlig `physical` huvudskada
- vapnet har en passive som räknar träffar på target
- var tredje träff triggar en extra true-damage-ping lite senare
- den extra träffen gör `110-135` base true damage
- eller alternativt `15%` av den resolved physical damage som huvudträffen utgick från

Detta bör modelleras som:

1. huvudträffen skapas som normal `damage:physical` instance
2. passive state uppdaterar counter för source + target
3. när counter når `3` emitas en effect
4. effekten schemalägger en ny `damage:true` instance med liten delay
5. true-damage-instancen snapshotar relevant data från huvudträffen
6. counter resetas eller fortsätter enligt passivens regel

Viktig designregel:

- extra true damage är inte en stat
- det är inte heller "mer weapon damage" på huvudträffen
- det är en separat effect-driven damage instance

Om passiven säger:

- "110-135 extra true damage"

så resolved den range direkt från effect-data.

Om passiven säger:

- "15% av min physical"

så bör systemet snapshotta den resolved physical-basen från huvudträffen eller från source context innan mitigation på target.

Det gör att ordningen blir begriplig:

- först vanlig attack
- sedan separat ping av true damage

och att true damage inte råkar börja läsa targetens armor eller MR.

### Steg 4. Applicera native features och rules

Exempel:

- native pierce adderas
- recoil scaling läggs på
- hard caps tillämpas

### Steg 5. Applicera temporary states

Exempel:

- buff som ökar crit under 4 sekunder
- room modifier som ökar projectile speed

### Steg 6. Clamp och round

Här säkrar vi att vapnet fortfarande är spelbart och begripligt.

## 6. Vad ska vara globalt vs weapon-local

Det här måste vara tydligt redan från början.

### Bra kandidater för globala stats

- `damage`
- `crit_chance`
- `crit_damage`
- `luck`
- `move_speed`
- `armor`
- `pickup_radius`

### Bra kandidater för weapon-resolved stats

- `reload_time`
- `magazine_size`
- `projectile_damage`
- `projectile_count`
- `projectile_speed`
- `projectile_spread`
- `projectile_pierce`
- `projectile_bounce`
- `recoil_impulse`

### Bra kandidater för effects, inte stats

- explosive rounds
- bleed on hit
- chain lightning on crit
- split projectile on kill
- spawn shard on pierce

## 7. Shotgun Example

Mål:

- kort magasin
- stark burst
- traversal via recoil
- ska kunna bli galen med reload och power
- ska inte kunna skala ammo

### Base identity

- `magazine_size = 2`
- `projectile_count = 5`
- `projectile_damage = 6`
- `recoil_impulse = 280`
- `reload_time = 1.8`

### Capability rules

- `allow_magazine_size_bonus = false`
- `allow_reload_time_bonus = true`
- `allow_projectile_count_bonus = true`
- `allow_recoil_scaling = true`
- `recoil_has_mobility_tech = true`

### Transform rules

- varje `+10% damage` kan ge `+8% recoil_impulse`
- `attack_speed` påverkar inte recoil direkt
- om spelaren siktar nedåt eller bakåt kan recoil användas för movement

### Resultat

Byggen kan fokusera på:

- traversal
- burst
- pellet count
- on-hit proc chaos

utan att shotgunen förvandlas till "bara ännu ett större magasin-vapen"

## 8. Crossbow Example

Mål:

- långsam
- tung träff
- piercing som identitet
- starka on-hit och on-pierce interactions

### Base identity

- `projectile_count = 1`
- `projectile_damage = 22`
- `reload_time = 1.9`
- `projectile_speed = 640`
- `projectile_pierce = 2`

### Capability rules

- `allow_magazine_size_bonus = false`
- `allow_projectile_count_bonus = false`
- `allow_projectile_pierce_bonus = true`
- `allow_projectile_bounce_bonus = false`
- `native_pierce = 2`

### Good synergy paths

- crit
- weakspot
- bleed on hit
- on pierce spawn shard
- shock on hit

### Resultat

Crossbowen känns då som ett precision/control-vapen, inte bara ett skin för revolvern.

## 9. Dual Slot Synergy

Eftersom spelet just nu kör med två aktiva vapen behöver vi tänka på synergier mellan dem, men modellen bör fungera även om fler slots blir aktiva senare.

### Exempel på bra dual-slot-mönster

- shotgun + crossbow
  shotgun för mobilitet och close burst, crossbow för precision och pierce
- pistol + chain weapon
  pistol som stabil baseline, elvapen som high-proc payoff
- aura / thorns armor + heavy shotgun
  nära spelstil där flera lager av damage triggar samtidigt

### Designregel

Vi bör sträva efter att slot 2 inte bara är "backup damage".

Den bör ofta vara:

- utility
- traversal
- crowd clear
- proc enabler
- elite killer

## 10. Combat Events From Weapons

Varje attackprofil bör emittera tydliga events så att perks och effects kan haka på.

Exempel:

- `weapon_fired`
- `projectile_spawned`
- `projectile_hit`
- `projectile_pierced`
- `projectile_bounced`
- `projectile_expired`
- `reload_started`
- `reload_completed`
- `self_recoil_applied`

Detta är kopplingen mellan weapon architecture och effect system.

## 11. VFX Separation

Vi vill ha mycket projektiler, ljus och effekter.

Det betyder att attackprofilen ska kunna be om:

- muzzle flash
- projectile trail
- impact effect
- chain arc
- shock burst
- aura pulse

Men själva VFX-systemet bör läsa combat events och resolved attack output, inte äga gameplaylogiken.

## 12. Rekommenderad minimal implementation

Om vi vill bygga detta stegvis bör första versionen stödja:

1. `weapon definition`
2. `attack profile`
3. `capability allow/deny`
4. `resolved weapon stats`
5. events för `weapon_fired`, `projectile_hit`, `reload_completed`

Det räcker för att bygga:

- vanlig pistol
- traversal shotgun
- piercing crossbow

utan att låsa ute framtida content.

## 13. Föreslagna nästa beslut

När vi fortsätter diskussionen bör vi låsa:

1. vilka weapon families som ska finnas i första stora refaktorn
2. vilka stats som ska vara globala respektive weapon-resolved
3. vilka capability rules som måste stödjas från dag ett
4. vilka combat events som ska vara officiella i v1

## 14. Initial Asset-Driven V1 Scope

För att hålla refaktorn jordad i verkliga assets utgår vi tills vidare från det som redan finns i:

- [Items.png](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/assets/weapons/Items.png)
- [Weapons](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/assets/weapons/Weapons)

Följande content är uttryckligen intressant som första våg:

### Weapons

- elstav från `Items.png`
- eldstav från `Items.png`
- pilbåge
  källa: [BowArrow.png](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/assets/weapons/Weapons/BowArrow.png)
- stora yxan från `Items.png`
- supersoaker
  källa: [SuperSoaker.png](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/assets/weapons/Weapons/SuperSoaker.png)

### Armor

- all armor vi kan läsa ut ur `Items.png`

Det här betyder att v1 inte bara ska byggas runt pistoler och shotguns, utan runt flera tydligt olika weapon families direkt.

## 15. Initial Weapon Family Candidates

Baserat på nuvarande assets och diskussionen bör följande weapon families få plats i första större modellen:

### 1. Firearms

Vanliga skjutvapen med projectile-beteende.

Exempel:

- revolver
- shotgun
- rifle
- supersoaker som joke / low-power utility weapon

### 2. Bows / Crossbows

Långsammare precision-vapen med tydlig on-hit-identitet.

Exempel:

- pilbåge från `BowArrow.png`
- crossbow hör till samma family för enkelhetens skull

Låst beslut:

- bow och crossbow behandlas som samma weapon family i v1
- skillnader mellan dem uttrycks via enskilda weapon definitions, inte via separata familjer

### 3. Staves

Magiska vapen som gör att systemet måste stödja annat än "vanlig kula".

Exempel:

- eldstav
- elstav

Staves är viktiga eftersom de testar:

- element-tags
- status application
- aura / chain / splash
- VFX-intensiva attacker

Låsta beslut för staves:

- staves är rena ranged weapons
- eldstavens identitet är `burn`
- burn ska skala med level
- elstaven har `shock` och chain-identitet

Det betyder att staff-familjen redan i v1 kräver att attack profiles kan läsa:

- status application
- level-skalning
- secondary hit behavior

Implementation note:

- Dessa staff-identiteter är fortfarande framtida authored content direction.
- Nuvarande repo har runtime-stöd för `status_applications`, men skickar inte med default-statushooks på live guns ännu.

### 4. Heavy melee

Långsamma men identitetsstarka melee-vapen.

Exempel:

- stora yxan

Det är viktigt att heavy melee inte bara blir "knife but bigger", utan en egen attack family med annan cadence och annan payoff.

Viktig ändring:

- stora yxan ska inte ligga i vanliga weapon slots
- den ska vara första exemplet på ett `legendary ultimate`
- när spelaren får den låses en `Q`-ability upp

Ultimate-konceptet bör därför modelleras som ett separat system från vanliga vapenslots, även om det fortfarande kan använda attack profiles och effects.

## 16. Supersoaker Design Note

Supersoakeren ska med, men den ska inte designas som ett normalt "bra" vapen.

Din beskrivning är viktig:

- meningslös
- dryg om man råkar plocka upp den
- skjuter patetiska bubblor

Det betyder att vi bör behandla den som ett av följande:

### A. Joke / cursed weapon

Medvetet svag, men rolig eller konstig.

### B. Utility weapon

Svag i raw damage, men kan ge:

- push
- slow
- wet status
- setup för lightning/shock-synergi

### C. Low-roll weapon

En del av run-variationen där vissa pickups faktiskt är dåliga.

Min rekommendation är att inte låsa detta ännu, men att arkitekturen måste tillåta ett vapen som är:

- medvetet svagt
- visuellt distinkt
- potentiellt användbart i en nisch

Låst riktning:

- supersoakern kan applicera `wet`
- den ska fortfarande kännas usel i raw damage
- dess range ska vara extremt kort
- även med wet-synergi ska den inte automatiskt bli ett starkt standardval

Implementation note:

- Detta är fortfarande en designriktning för framtida authored weapon content.
- Repon skickar inte med en live supersoaker-hook som applicerar `wet` som default i nuläget.

## 17. Armor Content Direction

Eftersom du uttryckligen vill ha all armor från `Items.png` som intressant scope bör armor delas upp i minst fyra families redan i designspråket:

### 1. Heavy armor

- tank
- thorns
- barrier
- mindre mobilitet

### 2. Mobile armor

- move speed
- dash
- attack speed
- låg bulk

### 3. Utility armor

- cooldown reduction
- pickup radius
- luck
- status chance

### 4. Offensive set armor

- crit
- crit damage
- bleed
- shock
- on-hit procs

## 18. Immediate Follow-Up Questions

Det mest värdefulla vi kan låsa härnäst för den här assetgruppen är:

1. Hur ska `level` definieras för eld/burn-skalning: player level, room tier eller annat power value?
2. Hur ofta ska legendary ultimates kunna dyka upp jämfört med vanliga weapons/perks?
3. Exakt hur stark ska supersoakerns wet-synergi vara utan att vapnet blir för bra?
4. Hur stor stun/payoff ska lightning staff få vid shock overload?

## 19. Legendary Ultimates

Yxan visar att vi behöver ett separat spår för sällsynta, starka abilities som inte är vanliga vapenslots.

### Grundidé

- ultimate är inte `weapon slot 1` eller `weapon slot 2`
- ultimate är en separat unlock under runnen
- ultimate binder normalt till `Q`

### Första exempel: spinning axe

När spelaren får den legendariska yxan:

- `Q` låses upp
- spelaren snurrar yxan runt sig
- attacken gör hög physical AOE damage
- den kan använda samma effect/event-system som andra attacker

### Arkitekturprincip

Ultimates bör dela teknik med vanliga attacks:

- attack profile
- effects
- combat events
- VFX hooks

Men de ska inte dela loadout-regler med vanliga vapen.

Statusdefinitionerna som vapen och attacks använder finns i [status_architecture.md](./status_architecture.md).
