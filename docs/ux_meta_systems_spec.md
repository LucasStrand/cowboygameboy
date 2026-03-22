# Six Chambers UX and Meta Systems Spec

Det här dokumentet låser riktningen för:

- combat readability
- feedback ownership
- HUD priority
- build clarity
- economy pressure
- reward pools
- meta unlock philosophy
- run metadata

Målet är att djupa system ska kännas smarta och satisfierande, inte bara kaotiska.

## 1. Combat readability

Combat måste designas så att spelaren kan läsa:

- vad som träffade
- vem som orsakade effekten
- vilken typ av skada det var
- vad som faktiskt dödade målet

### Tre lager av läsbarhet

#### Lager 1: Primär tydlighet

Det spelaren måste kunna läsa direkt i strid:

- vilken attack som är min
- vilka projektiler som är farliga
- vilken target som är markerad, sårbar eller stunned
- när en stor payoff händer

#### Lager 2: Sekundär tydlighet

Saker som inte måste läsas varje frame, men som ska gå att förstå:

- chain lightning hoppade från min proc
- burn dödade målet, inte huvudträffen
- delayed detonation kom från en tidigare mark

#### Lager 3: Debug / recap

När det blir riktigt stökigt bör spelet kunna ge förklaring i efterhand:

- death recap
- hit summary
- last damaging source
- ikon eller logg för senaste stora proc

### Huvudregel för presentation

- direct hits får starkast feedback
- big proc eller payoff får näst starkast feedback
- background damage som DoT och aura-ticks får svagare feedback
- delayed hits behöver tydlig setup eller tydlig ägare innan de går av

Ju viktigare ett gameplaybeslut är, desto tydligare ska dess payoff vara visuellt och ljudmässigt.

## 2. Feedback ownership

När något händer måste spelaren kunna förstå om det kom från:

- vapnet
- relicen
- passiven
- en tidigare status

### Rekommenderad standard

Alla viktiga secondary effects bör ha en ägarsignatur.

Det kan vara:

- unik färgton
- särskild ikon
- särskilt ljud
- liten textetikett
- visuellt motiv kopplat till källan

### Starka passives bör ha tre steg av feedback

- setup feedback
- trigger feedback
- result feedback

Exempel:

Om ett vapens passive sätter upp en delayed true-damage-ping bör målet först få markering eller ikon, och när pinget går av bör samma färg, symbol eller SFX användas igen.

## 3. HUD pressure

Spelaren kan behöva hålla koll på:

- potions
- boons
- statuses
- cooldowns
- passive counters
- active weapon
- offhand state
- reload state
- mark / charge states

Allt får inte ha samma HUD-prioritet.

### Grupp A: Måste alltid synas

- HP / shield
- aktiva vapen
- ammo / reload / resource
- potion charges
- viktigaste cooldowns
- tydliga proc-counters för aktiva payoff-mekanik

### Grupp B: Bör vara lätt tillgängligt

- buffs och debuffs på spelaren
- boon summary
- passive counters som bara ibland spelar roll
- offhand state om det inte är centralt varje sekund

### Grupp C: Kan ligga i inspect / expand

- alla små modifiers
- hela statuslistan
- proc chance breakdown
- exakt source mapping

### HUD ska främst svara på

- är jag i fara
- vad kan jag använda nu
- när kommer min nästa payoff
- vilket weapon eller state är aktivt

## 4. Build clarity

Spelet måste hjälpa spelaren att förstå varför en build är stark.

### Bra build clarity

Spelaren ser:

- flera rewards med `Bleed`
- en relic som ger crit mot bleeding targets
- en perk som låter bleed critta
- en annan effekt som konsumerar bleed för burst

Då känns builden som en riktning.

### Dålig build clarity

Spelaren har bara:

- små procentsiffror
- otydliga procs
- effekter som råkar stapla utan tydlig engine

### Rekommendation

UX bör hjälpa spelaren upptäcka:

- core engine
- enablers
- payoff pieces
- finishers

Bra verktyg:

- highlightade keywords i rewards
- synliga tags
- "detta matchar din nuvarande build"-signaler
- enkel buildsammanfattning

## 5. Economy pressure

Ekonomin ska skapa meningsfulla val, inte konstant frustration.

Spelaren ska ofta få känna:

- jag har nästan råd
- om jag sparar nu kan jag göra något starkt senare
- ska jag rerolla eller ta säkra värdet

Inte:

- jag har aldrig råd
- jag måste alltid köpa samma sak
- allt känns som skatt i stället för val

### Viktiga sinks med olika roller

#### Shoppriser

Baslinje för värde och tempo.

#### Rerolls

Flexibilitet mot kostnad.

#### Repairs / refills

Defensiv ekonomi och run-stabilitet.

#### Potion refills

Greed vs safety-val.

#### Cursed items

Risk / reward-ekonomi.

### Designregel

Varje shopbesök bör helst ge minst två rimliga beslut.

Det får inte finnas ett enda självklart optimalt sätt att spendera.

## 6. Reward pools

Reward-systemet ska använda smart weighting, inte helt ren RNG.

Det betyder:

- alla rewards kan fortfarande finnas i poolen
- men systemet kan vikta upp saker som passar nuvarande build
- och vikta ner helt döda val

### Saker som kan påverka weighting

- weapon families
- damage tags
- status themes
- resursmodell
- tidigare picks
- nuvarande build-engine
- biome eller event context

### Rekommenderad reward-sammansättning

- `1` reward som stödjer nuvarande build
- `1` reward som är neutral eller stabil
- `1` reward som öppnar alternativ eller pivot

Det ger:

- progression
- flexibilitet
- kreativitet

utan att ta bort överraskning helt.

## 7. Meta unlock philosophy

Meta unlocks ska främst bredda spelet, inte bara ge permanent mer power.

### Bra meta unlocks

- nya vapenfamiljer
- nya eventtyper
- nya relics och perks
- nya merchants eller room types
- nya risk / reward-system
- nya curse / reward loops

### Mindre bra som default

- permanent `+10%` damage
- permanent `+20` max HP
- permanent bättre loot alltid

Lite rå power kan finnas, men det bör inte vara huvudspåret.

### Huvudfråga för varje unlock

Ger detta fler intressanta beslut, eller bara större siffror?

## 8. Run metadata

Run metadata ska samlas från start.

Det hjälper med:

- balans
- QA / debugging
- UX
- run-identitet

### Det som minst bör lagras

- run seed
- biome / route
- rumstyper som spawnat
- reward history
- boss pool candidates
- modifier flags
- event pool weights
- curse / blessing states
- economy state milestones

### Varför det också är bra för spelaren

Metadata kan användas till:

- death recap
- post-run summary
- dagens challenge
- seed sharing
- community comparison
- förstå varför en run kändes annorlunda

### Designregel

Metadata ska inte bara vara tekniskt internt.

En del av det bör också exponeras snyggt till spelaren.

## 9. Performance budgets

Du behöver hårda tak tidigt.

Det bör finnas tydliga budgets för minst:

- max projectiles
- max chain hops
- max aura-ticks per frame
- max on-hit-evaluations per frame

### Designprincip

När systemet når taket ska det degradera snyggt, inte krascha eller döda FPS helt.

Bra exempel på graceful degradation:

- färre visuella ticks
- begränsad chain depth
- batching av små DoTs
- presentation skärs ned före gameplay, om det går

## 10. Determinism

Gameplay-RNG bör vara reproducerbar.

Det betyder inte att all presentation måste vara perfekt deterministisk.

Men gameplaydelen bör kunna spelas upp igen för:

- debugging
- balancing
- reproduktion av konstiga runs
- analys av OP-runs eller oneshots

Om du inte kan reproducera en run kommer balansarbetet bli mycket långsammare.

## 11. Save / load

Mitt i en run måste systemet spara allt som påverkar framtida combat, inte bara inventory.

Det inkluderar minst:

- buff timers
- status stacks
- weapon runtime state
- ammo / reload state
- passive counters
- delayed hits som väntar på trigger
- room state
- reward pools
- RNG state

Annars laddar spelaren tillbaka till "samma run" men med en annan verklighet.

## 12. Telemetry

Logga sådant som förklarar power, inte bara totalskada.

Viktiga exempel:

- damage per source
- damage per tag
- proc rate
- overkill
- uptime på viktiga buffs och debuffs
- vilka rewards som faktiskt väljs
- hur ofta reroll används
- var runs dör
- vilka perks som korrelerar med höga winrates
- hur mycket av en builds styrka som kommer från direct hit kontra secondary effects

Det här gör att du snabbt ser om något är:

- OP
- bait
- feltolkat av spelare

## 13. Debug tools

Debug tools är kärnsystem, inte luxury tools.

Du bör kunna:

- ge dig själv perk
- applicera status
- spawna specifika fiender
- printa damage packet steg för steg
- inspektera aktiva modifiers
- frysa timers
- visa RNG-rolls
- se vilken effekt som äger en proc

Om du vill bygga absurda synergier måste du också kunna dissekera dem snabbt.

## Övergripande riktning

Det här är den riktning som bäst passar ett spel med:

- absurda builds
- många systemlager
- regelbrytande perks
- stora payoff moments

Spelet måste hjälpa spelaren att läsa:

- vad som hände
- varför det hände
- hur de byggde fram det

Den bästa typen av kaos är:

kaos som spelaren efteråt kan förstå och vilja återskapa
