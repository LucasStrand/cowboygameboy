# Six Chambers Content Authoring Spec

Det här dokumentet beskriver den tekniska ryggraden för datadrivet content.

Om combat-systemet är hjärtat, så är content authoring skelettet som håller ihop det.

Det här dokumentet fokuserar på:

- data validation
- tooltips
- localization
- asset hooks
- den större helhetsfilosofin för hur content ska vara begripligt och underhållbart

## 1. Data validation

### Designprincip

Content errors ska hittas vid load-time, inte under gameplay.

Systemet ska faila högt, tydligt och tidigt.

När content laddas bör systemet verifiera att följande faktiskt finns och är giltiga:

- stat ids
- effect ids
- trigger ids
- tag names
- status families
- tooltip keys
- localization keys
- target filters
- animation hooks
- VFX / SFX referenser
- proc rules
- condition operators

### Exempel på fel som ska fångas direkt

- felstavat stat-id
- effect försöker använda okänd trigger
- tooltip refererar till saknad variabel
- status säger att den är cleansebar men saknar cleanse group
- skill försöker ge buff till target type den inte stödjer

### Varför detta är viktigt

Ju mer av spelet som blir datadrivet, desto mindre går det att lita på att fel "märks när man testar".

Du vill veta direkt:

- vad som är fel
- var felet är
- varför det hände

Annars får du buggar som ser ut som balansproblem men egentligen är trasig data.

## 2. Tooltips

### Rekommendation

Kör hybrid.

Det betyder:

- standardiserad info genereras från data
- specialtext kan override:as manuellt när det behövs

### Det som bör genereras automatiskt

- damage
- duration
- stacks
- chance
- cooldown
- radius
- scaling
- target type

Exempel:

`Applies Burn for 12 damage over 4s.`

Det här bör systemet kunna generera själv.

### Det som ofta behöver manuell override

- regelbrytande perks
- komplex logik
- flavor text
- Arena-liknande "this effect changes the rules" mechanics

Exempel:

`Every third shot ignites the target and refunds 1 ammo if the target is marked.`

Det här blir ofta för stelt om det genereras helt automatiskt.

### Varför hybrid är bäst

Om allt skrivs manuellt blir det:

- tidskrävande
- lätt att missa uppdatera
- inkonsekvent textkvalitet

Om allt genereras blir det:

- stelt språk
- svårförklarade specialeffekter
- tooltips som känns robotiska

## 3. Localization

### Designprincip

Dynamiska värden är bra.

Dynamisk grammatik ska begränsas så mycket som möjligt.

### Rekommenderad lösning

Använd hela meningar eller tydliga fulla textmallar med tokens.

Exempel:

- `Applies Burn for {damage} over {duration}s.`
- `Critical hits against Bleeding enemies deal {bonus}% more damage.`

Varje språk ska äga sin egen fulla mening.

Systemet fyller bara i värden.

### Varför detta är bättre

Annars är det lätt att bygga något som bara fungerar bra på ett språk, ofta engelska.

Det blir snabbt dyrt när du senare vill ha:

- svenska
- engelska
- språk med annan grammatik

## 4. Asset hooks: VFX, SFX, animation

### Rekommendation

Äg presentation via events, inte via specialkod per effect.

Gameplay-systemet bör emit:a events som:

- `OnHit`
- `OnCrit`
- `OnStatusApplied`
- `OnStatusRefreshed`
- `OnStatusExpired`
- `OnCleanse`
- `OnPurge`
- `OnShieldBreak`
- `OnKill`

Sedan får presentation systems lyssna på dessa och trigga:

- VFX
- SFX
- camera shake
- screen flash
- hit pause
- animation layers
- UI popups

### Varför detta är viktigt

Om presentation binds direkt i specialfall som:

- just burn spelar detta ljud från denna klass
- just detta crit-event kör denna animation om vapnet är bow

så blir systemet snabbt svårskött.

Event-baserat ägande gör att:

- content kan återanvändas
- presentation kan ändras utan att gameplaylogik rörs
- polish och balans kan itereras separat

### Praktisk designprincip

Gameplay ska säga vad som hände.

Presentation ska bestämma hur det ser ut och låter.

## 5. Den större helhetsfilosofin

Om man kokar ner hela systemriktningen till några kärnidéer blir det:

- grundreglerna ska vara tydliga
- data ska vara säker och validerad
- UI ska bara visa det viktigaste
- builds ska kunna bli absurda genom tur och synergi
- kombinationer ska kännas designade, inte slumpade
- tooltips och content måste vara möjliga att underhålla
- VFX, SFX och animation ska kunna växa utan att spränga gameplaykoden

Det betyder att systemet bör byggas runt följande:

### 1. Allt viktigt ska ha tydliga kategorier

Exempel:

- `hard_cc`
- `soft_cc`
- `buff`
- `debuff`
- `dot`
- `mark`
- `proc`
- `rule_breaking_perk`

### 2. Interaktioner ska helst ske via tags och regler

Inte via hundratals hårdkodade specialfall.

### 3. Standardregler ska finnas, men perks och relics får bryta dem uttryckligen

Det är här de sjukaste Arena-liknande runs kommer leva.

### 4. Systemet måste kunna förklara sig självt

Både för spelaren och för dig som designer:

- via tooltip
- via debug log
- via tydliga statusregler
- via validerad data

## Rekommenderade nästa implementationsteg

- bygg load-time validation för contentfiler
- definiera tooltip-schema med genererade fält och manuell override
- definiera localization tokens och textmallar
- definiera presentation events som gameplay får emit:a
