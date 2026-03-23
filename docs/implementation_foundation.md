# Six Chambers Implementation Foundation

Det här dokumentet översätter de tekniska arkitekturfrågorna till vanlig svenska.

Målet är att göra nästa steg begripligt innan systemen byggs om på riktigt.

## Först: korrigering om vapenslots

Arkitekturen ska stödja fler än två vapenslots.

Det som gäller just nu i spelet är bara:

- två slots är aktiva
- secondary-valet är viktigt
- vapen går inte att kasta bort fritt

Alltså:

- `två slots aktivt i spelet nu` är en game rule
- `fler slots måste kunna stödjas senare` är ett arkitekturkrav

Det här är viktigt, för annars råkar man lätt hårdkoda in `slot 1` och `slot 2` överallt.

## Vad de fem punkterna betyder i vanlig svenska

### 1. Hur actor stats byggs från sources

Det här betyder bara:

Hur räknar spelet fram spelarens riktiga slutvärden?

Exempel på sources:

- spelarens basvärden
- armor
- vapen
- perks
- buffs
- meta-progression

Idag är detta ganska blandat.

I [player.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/entities/player.lua#L288) kopieras `self.stats`, gear läggs ovanpå om statnamnet redan finns, och gun-stats byts sedan ut via en revolver-baserad delta-modell.

Det vi behöver framåt är enklare:

1. börja från base stats
2. lägg på modifiers från alla källor
3. räkna fram final player stats
4. låt varje vapen läsa dessa och skapa egna resolved weapon stats

### 2. Hur damage resolution sker steg för steg

Det här betyder bara:

I vilken ordning räknar spelet en träff?

Exempel:

- rollar vi damage range först
- när rollas crit
- när läggs physical eller magical bonus på
- när används armor eller MR
- när triggas bleed, burn eller delayed true damage

Idag är detta enkelt men utspritt.

I [player.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/entities/player.lua#L757) skapas bullet damage i princip som `floor(bulletDamage * damageMultiplier)`.

I [combat.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/systems/combat.lua#L35) skickas den skadan direkt till enemy.

I [enemy.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/entities/enemy.lua#L671) tappar enemy bara HP rakt av.

I [player.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/entities/player.lua#L972) använder player däremot armor när spelaren tar skada.

Så idag finns ingen riktig gemensam damage pipeline än.

Det vi behöver framåt är ungefär:

1. skapa en damage instance
2. räkna source scaling
3. slå crit om den får critta
4. applicera damage family
5. applicera target mitigation om familyn använder mitigation
6. applicera statuses eller delayed secondary hits
7. trigga procs och events

### 3. Hur effects och triggers representeras i data

Det här betyder bara:

Vi behöver ett standardsätt att beskriva:

- när något händer
- vad som då ska ske

Exempel:

- på hit: applicera bleed
- på tredje hit: gör true damage
- på reload: ge nästa två skott bonus
- varannan sekund: pulse aura

Om vi inte gör detta blir all sådan logik specialfall i `player.lua`, `combat.lua` eller ett visst vapen.

### 4. Hur weapon runtime state lagras

Det här betyder bara:

Vi måste skilja på vad ett vapen är och vad vapnet håller på med just nu.

Exempel på statisk vapendata:

- base damage
- family
- native pierce
- capability rules

Exempel på runtime state:

- current ammo
- reload timer
- cooldown
- skott sedan reload
- träffar på samma target
- passive cooldown

Idag finns redan en början i [player.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/entities/player.lua#L172), där varje slot har:

- `gun`
- `ammo`
- `reloading`
- `reloadTimer`
- `shootCooldown`

Det är bra, men framtida passiver kräver mer runtime state än så.

### 5. Hur allt detta kopplas till nuvarande Lua-kod utan total rewrite

Det här betyder bara:

Vi måste ha en migrationsväg.

Vi kan inte pausa spelet och skriva om allt samtidigt.

Den rimliga vägen är:

1. bygg ett stat registry
2. bygg compute för final player stats
3. låt nuvarande vapen läsa från det nya utan att resten skrivs om direkt
4. inför damage instances först på nya eller refaktorerade attacker
5. inför trigger/effect-system på några features först
6. flytta gamla perks och gear gradvis

## Vad koden gör idag, väldigt kort

### Stats idag

- playern har ett statblock
- gear lägger bara på bonus om statnyckeln redan finns
- guns ersätter flera gun-stats via delta från default-revolver

Se [player.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/entities/player.lua#L288).

### Weapon slots idag

- spelet har två aktiva slot-index i player state
- slot 1 är default ranged
- slot 2 kan vara gun eller tomt / melee-läge
- active slot växlas manuellt

Se [player.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/entities/player.lua#L172).

### Damage idag

- bullets bär i princip bara damage-tal och några flags
- träff på enemy gör direkt `enemy:takeDamage(b.damage, world)`
- explosions och melee gör också direkt damage

Se [combat.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/systems/combat.lua#L35) och [combat.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/systems/combat.lua#L276).

### Mitigation idag

- enemy har i praktiken ingen riktig damage pipeline än
- player använder armor och block reduction när player tar skada

Se [enemy.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/entities/enemy.lua#L671) och [player.lua](/C:/Users/9914k/Dev/Cowboygamejam/cowboygameboy/src/entities/player.lua#L972).

## Vad vi egentligen försöker få på plats

I enkel form:

- ett rent statsystem
- en ren damage pipeline
- ett data-driven effect-system
- separat runtime state för vapen och statuses
- en migration som inte kräver total rewrite

Det är detta som gör framtida idéer möjliga utan att koden kollapsar.

## Nästa rekommenderade dokument

Det naturliga nästa steget är ett dokument som låser exakt runtime-ordning för:

- stats compute order
- damage resolution order
- trigger order
- proc safety rules
- runtime state ownership
