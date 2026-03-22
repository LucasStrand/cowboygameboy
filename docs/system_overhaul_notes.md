# Six Chambers System Overhaul Notes

Det här dokumentet samlar låsta beslut och öppna frågor för överhaulen av:

- stats
- vapen
- perks / skills / augments
- armor / sets
- statuses
- consumables
- damage pipeline

Syftet är att ha ett enda begripligt underlag innan implementationen börjar på riktigt.

## Låsta beslut hittills

### Slots och loadout

- arkitekturen ska stödja fler än två vapenslots
- spelet har just nu bara två aktiva vapenslots
- spelaren kan inte kasta bort sina vapen fritt
- valet av secondary är därför ett riktigt buildbeslut

### Damage families

- `physical` är riktig huvudfamily
- `magical` är riktig huvudfamily
- `true` är riktig huvudfamily
- `armor` mitigerar physical
- `magic_resist` mitigerar magical
- `true damage` ignorerar båda helt

### Stats och scaling

- crit chance kan gå till `100%`
- crit över cap ska kunna konverteras till högre crit damage
- exakt CDR-cap låses senare via playtest
- armor shred och magic penetration ska finnas med i modellen

### Standardregler och regelbrott

- standardreglerna gäller alltid först
- specifika skills / perks / relics / augments får bryta dem uttryckligen
- starka builds ska vara läsbara, inte kännas som dold fusklogik
- galenskap ska främst komma från kombinationer, timing, conditions och state tracking
- regelbrott ska vara sällsynt, tydligt och värdefullt

Det betyder som default:

- direct hits går genom full damage pipeline
- direct hits kan trigga full on-hit
- DoTs snapshotar sin styrka när de appliceras
- DoTs crittar inte som default
- DoTs triggar inte full on-hit / proc-kedja som default
- proc damage triggar inte ny proc damage som default
- reflected damage är separat och triggarlös som default
- secondary effects är mer begränsade än huvudträffen

Det betyder också:

- specific beats general
- om en perk uttryckligen säger att den bryter en standardregel, så gör den det

Exempel på bra regelbrott:

- "Your Bleeds can Crit"
- "Burn recalculates dynamically from current Spell Power"
- "Chain lightning can trigger other on-hit effects at 30% efficiency"

### Statusriktning

- burn förlänger timer när den appliceras igen
- shock bygger upp och exploderar efter tre elträffar
- wet hjälper el att sprida sig vidare
- statusar kan ha egna styrkor och svagheter beroende på fight-längd
- burn, bleed och liknande snapshotar sin styrka när de appliceras som default
- statusar och CC är ett eget system, inte bara "extra effekter"
- samma grundmotor ska stödja buffs på spelare, buffs på fiender, debuffs på spelare och debuffs på fiender
- hard CC ska inte kunna chainas obegränsat
- vanliga fiender bör använda DR eller tillfällig immunity mot hard CC
- bossar bör ha egna CC-regler, ofta via reducerad duration, stagger eller immunity windows
- statusinteraktioner bör byggas på tags / families, inte hårdkodade namnpar
- systemet ska stödja `cleanse`, `purge`, `expire` och `consume` som olika operationer

### Proc-regel

Grundregel:

- saker triggar inte andra saker om det inte uttryckligen står att de gör det

Undantag:

- vissa sällsynta augments / skills får bryta den regeln med flit
- de ska vara tydliga, medvetet kraftfulla och ovanliga

Bra default:

- direct hits får trigga full on-hit
- DoT får inte trigga full on-hit
- proc damage får inte trigga nya proc damage om inget specifikt säger det
- reflected damage är separat och triggarlöst som default

### Source ownership och statistik

- varje källa ska äga sin egen damage, healing och shielding
- spelaren ska kunna se statistik per item / weapon / passive / legendary / skill

Det betyder att systemet måste hålla reda på:

- vem som skapade en träff
- vem som skapade en status
- vem som skapade en delayed secondary hit

### Gameplayfilosofi

- vissa builds får gärna bli brutalt starka
- vissa runs får vara mediokra eller dåliga
- low-roll recovery får finnas, men spelet måste inte alltid rädda en död run
- spelet får gärna känna av hur det går och erbjuda hjälp eller skala motstånd vid behov

### Bossar och elites

- bossar kommer skräddarsys och tweakas för hand
- elites ska ibland vara riktigt jävliga
- elite-buffs kan fungera som hårda counters mot vissa builds

### Combat flavor

- ranged ska kunna motarbetas av chargers, slows och zoner / AoE som tvingar rörelse
- både AoE-fokuserade och single-target-fokuserade builds ska kunna bli brutalt starka

### Läsbar galenskap

- spelaren får bryta balans, men helst på läsbara sätt
- styrka bör främst komma från kombinationer, inte från en enda absurd siffra
- true damage ska främst användas som payoff eller identitet, inte som vardagslösning
- grundreglerna ska vara tydliga
- data ska vara säker och validerad
- UI ska visa det viktigaste, inte allt
- tooltips och content måste gå att underhålla över tid
- VFX, SFX och animation ska kunna växa utan att gameplaykoden kollapsar

Bra exempel:

- mark + crit + reload passive + execute multiplier
- beam weapon som stackar expose och sedan smäller med burst
- shotgun med "var tredje skott exploderar"

Bra användning av true damage:

- execute
- boss mechanic
- "next shot after reload deals bonus true damage"
- "detonate all bleeds for true damage"

### Kärnidéer för hela systemet

- allt viktigt ska ha tydliga kategorier
- interaktioner ska helst ske via tags och regler
- standardregler ska finnas, men perks / relics får bryta dem uttryckligen
- systemet måste kunna förklara sig självt via tooltip, debug log, statusregler och validerad data

## Enkel förklaring av order of operations

Det här är bara ordningen spelet räknar en träff i.

Exempel:

Om ett skott säger:

- 100 base damage
- `+20 flat damage`
- `+30% physical damage`
- `x1.10 global damage`
- crit för `200%`

så betyder en möjlig ordning:

1. börja på `100`
2. lägg på flat bonus -> `120`
3. lägg på add_pct -> `156`
4. lägg på mul -> `171.6`
5. om crit -> `343.2`
6. om träffen är physical, använd armor
7. om träffen är magical, använd MR
8. om träffen är true, hoppa över mitigation
9. efteråt får delayed hits, statuses eller procs skapas om effekten säger det

Poängen är inte att just denna ordning är slutgiltig ännu.

Poängen är att vi måste låsa en sådan ordning centralt så att:

- tooltips stämmer
- balans går att förstå
- delayed true damage blir förutsägbar
- penetration och shred beter sig konsekvent

## Begrepp

### Vad är en hit

En hit är en direkt träff från en attack, skill eller projectile som går genom full damage pipeline.

Inte hits som default:

- burn ticks
- bleed ticks
- poison ticks
- aura ticks
- reflected damage

### Vad är en secondary effect

Allt som spawns efter final direct hit.

Exempel:

- status effects
- delayed explosions
- on-hit marks
- proc bolts
- lifesteal
- stack application

## Override-hierarki

Det här är rekommenderad ordning när regler krockar:

1. core rules
2. damage type rules
3. weapon family rules
4. skill / perk / relic overrides
5. temporary combat state

Det gör att man alltid kan säga var en regel kommer ifrån.

## Rule-breaking perks

En viktig intern kategori bör vara `rule-breaking perks`.

Det här är perks eller augments som inte bara ger mer stats, utan faktiskt ändrar spelreglerna.

Exempel:

- `Hemorrhage Logic`
  bleed can crit
- `Feedback Loop`
  proc damage may trigger one additional proc chain
- `White Heat`
  burn becomes dynamic instead of snapshot
- `Armor-Piercing Embers`
  burn inherits part of hit penetration
- `Pulse Chamber`
  beam ticks now count as hits, but with reduced on-hit damage

## Content authoring och presentation

Det här är den tekniska ryggraden bakom allt det andra.

Grundprinciper:

- content errors ska hittas vid load-time, inte under gameplay
- standardinfo bör kunna genereras från data
- specialtext får override:as manuellt när det behövs
- dynamiska tooltips bör använda hela meningar med tokens
- gameplay ska säga vad som hände
- presentation ska bestämma hur det ser ut och låter

## UX, readability och meta-system

Det här är lagret som avgör om djupa system känns smarta eller bara röriga.

Grundprinciper:

- combat måste vara läsbart i flera lager
- starka secondary effects behöver tydlig ownership
- HUD ska visa det kritiska, inte allt
- build-UI ska hjälpa spelaren förstå sin engine
- ekonomin ska skapa val, inte bara frustration
- reward pools ska vara smart viktade, inte helt dum RNG
- meta unlocks ska främst bredda spelet
- run metadata ska samlas från start för balans, QA och recap
- performance budgets måste finnas tidigt
- gameplay-RNG bör vara reproducerbar
- save/load måste spara riktig run-verklighet, inte bara inventory
- telemetry ska förklara power, inte bara totalskada
- debug tools är kärnsystem för att förstå absurda synergier

## Nuvarande kod, väldigt kort

### Stats idag

I [player.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/entities/player.lua#L288) kopieras `self.stats`, gear läggs på ovanpå, och gun-stats byts sedan ut via en revolverbaserad delta-modell.

Det betyder:

- dagens system fungerar
- men det är inte ett riktigt centralt statsystem än

### Weapon slots idag

I [player.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/entities/player.lua#L172) finns två aktiva slots i player-state.

Det betyder:

- spelet idag kör två slots
- men framtida arkitektur får inte hårdkoda att två alltid är max

### Damage idag

I [player.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/entities/player.lua#L757) skapas bullet-damage i princip som `floor(bulletDamage * damageMultiplier)`.

I [combat.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/systems/combat.lua#L35) skickas den vidare direkt till enemy.

I [enemy.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/entities/enemy.lua#L671) tappar enemy HP rakt av.

I [player.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/entities/player.lua#L972) använder player armor när spelaren tar skada.

Det betyder:

- det finns ännu ingen riktig gemensam damage pipeline

## Viktiga öppna frågor

Det här är saker som fortfarande behöver låsas.

### Mitigation-modell

- ska armor och MR vara flat reduction
- ska de ha diminishing returns
- ska shred och penetration appliceras före eller efter annan mitigation

### Caps

- max CDR
- min reload time
- min stun duration
- max chain count
- max projectile count

### Delayed effects

- hur lång delay får sekundär true damage ha innan det känns segt
- hur mycket delayed hits får ärva från snapshot kontra source context

### Recovery och scaling

- hur mycket ska spelet hjälpa en svag run
- hur aggressivt får spelet svara på en överstark run

### Bossregler

- vilka CC-regler som gäller på bossar
- vilka statusar som bossar ska tåla sämre eller bättre
- hur stagger, reduced CC duration eller temporary immunity ska fungera på bossar

### Elitebuffar

- hur många buffs elites ska få
- vilka buffar som får vara hårda counters
- hur många counters som är kul innan det blir orättvist

### UX och meta-system

- exakt HUD-prioritet för realtidsinfo
- hur mycket build support UI ska exponera under run
- exakt reward weighting-modell
- vilka meta unlocks som är breadth vs raw power
- vilka run metadata-fält som ska loggas och vilka som ska visas för spelaren

### Runtime support

- exakta performance budgets och graceful degradation-regler
- hur deterministisk gameplay-RNG måste vara
- exakt save/load-shape för mid-run state
- vilka telemetry-fält som ska loggas som standard
- vilka debug tools som måste finnas i första verktygsversionen

## Rekommenderat nästa steg

Nästa dokument bör låsa exakt runtime-ordning för:

- stat compute order
- damage resolution order
- crit and overcap rules
- mitigation, penetration och shred
- proc order
- source ownership

Det dokumentet blir den riktiga implementation-specen.

Det som redan nu är tydligt högst prioritet att låsa är:

1. exact damage order
2. exact modifier order
3. snapshot vs live per effect-typ
4. proc recursion rules
5. armor / MR-formel
6. CC-regler för elites och bosses
7. slot / runtime model för vapen
8. data validation schema
9. tooltip strategy
10. debug / telemetry strategy
