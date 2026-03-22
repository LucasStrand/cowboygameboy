# Six Chambers Content Authoring Spec

Detta dokument låser hur datadrivet content ska vara säkert, förklarbart och underhållbart.

## Load-Time Validation

Content errors ska hittas vid load-time, inte under gameplay.

Följande ska valideras:

- stat ids
- effect ids
- trigger ids
- tag names
- status families
- tooltip keys
- localization keys
- target filters
- animation hooks
- VFX/SFX-referenser
- proc rules
- condition operators

Failures ska vara:

- tydliga
- tidiga
- path- och content-specifika

## Tooltips

Strategi:

- standardinfo genereras från data
- specialtext får override:as manuellt

Genereras automatiskt:

- damage
- duration
- stacks
- chance
- cooldown
- radius
- scaling

Manuell override används för:

- regelbrytande perks
- komplex logik
- flavor text

## Localization

Använd fulla meningar med tokens.

Exempel:

- `Applies Burn for {damage} over {duration}s.`
- `Critical hits against Bleeding enemies deal {bonus}% more damage.`

Undvik runtime-hopbyggd grammatik.

## Presentation Hooks

Gameplay ska emit:a events.

Presentation ska lyssna på dem.

Minimala events:

- `OnHit`
- `OnCrit`
- `OnStatusApplied`
- `OnStatusRefreshed`
- `OnStatusExpired`
- `OnCleanse`
- `OnPurge`
- `OnShieldBreak`
- `OnKill`

Princip:

- gameplay säger vad som hände
- presentation bestämmer hur det ser och låter ut

