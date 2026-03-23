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
- presentation hook ids
- condition operators

Failures ska vara:

- tydliga
- tidiga
- path- och content-specifika

## Tooltips

Strategi:

- standardinfo genereras från data
- specialtext får override:as manuellt
- `tooltip_key` är default authoring path
- `tooltip_override` används för regelbrytande eller ovanligt komplex text
- V1 buildern stöder `perks`, `guns`, `gear`, `statuses` och nuvarande `shop/reward offers`

Genereras automatiskt:

- damage
- duration
- stacks
- chance
- cooldown
- radius
- scaling
- weapon identity / fire pattern
- reload / ammo language

Manuell override används för:

- regelbrytande perks
- komplex logik
- flavor text

V1-contract:

- `tooltip_key: string | nil`
- `tooltip_tokens: table | nil`
- `tooltip_override: string | nil`
- samma kontrakt används även för nuvarande authored shop/reward-offers
- gamla `description` får bara finnas kvar som legacy-kompatibilitet; canonical authoring path för Phase 7+ är tooltip-modellen

## Localization

Använd fulla meningar med tokens.

Exempel:

- `Applies Burn for {damage} over {duration}s.`
- `Critical hits against Bleeding enemies deal {bonus}% more damage.`

Undvik runtime-hopbyggd grammatik.

V1:

- lokal template-registry i kod
- engelska templates
- key-baserad lookup, inte fri strängkonkatenering

## Presentation Hooks

Gameplay ska emit:a events.

Presentation ska lyssna på dem.

Minimala events:

- `OnHit`
- `OnDamageTaken`
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

V1-contract:

- content kan ange `presentation_hooks`
- hook ids valideras vid load-time
- Phase 7 använder detta för proc-payoff-feedback och status lifecycle-feedback utan nya combat-lokala specialfall

## Relaterat

- [authoring_readiness_checklist.md](./authoring_readiness_checklist.md) — kodgrindar innan nytt content (sets, proc-AoE, nya families, boss-paritet).
- [unified_actor_and_content_vision.md](./unified_actor_and_content_vision.md) — mål vs nuläge: enhetlig actor-modell, offense/defense/inventory.
