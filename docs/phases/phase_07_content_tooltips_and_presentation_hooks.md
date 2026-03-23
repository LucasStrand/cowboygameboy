# Phase 07: Content Tooltips and Presentation Hooks

## Goal

- Start Phase 7 as a content-facing slice.
- Add a real tooltip authoring model for perks and guns.
- Expand content validation to cover tooltip and presentation contracts.
- Add the first minimal event-driven presentation subscriber on top of `CombatEvents`.

## Status

- Phase 7 is implemented and verified for the intended V1 scope.
- Remaining future breadth belongs to later content/readability expansion, not to unresolved Phase 7 core contracts.

## Implemented

- New tooltip template registry with key-based full-sentence lines.
- New tooltip builder service that supports:
  - `tooltip_key`
  - `tooltip_tokens`
  - `tooltip_override`
  - legacy `description` fallback during migration
- All current perks now have either a tooltip template key or override.
- All current guns now have a tooltip template key.
- All current gear items now have tooltip template keys and tokens.
- All current statuses now have tooltip template keys.
- Current authored shop offers now use the same tooltip contract.
- `phantom_third` now has:
  - a manual tooltip override
  - a named presentation hook id
- New presentation hook registry plus a minimal presentation runtime subscriber.
- The first hook is `phantom_third_payoff`, driven from resolver-owned `OnDamageTaken` payloads.

## UI Surfaces Migrated

- Level-up perk cards now render tooltip-builder output instead of raw `perk.description`.
- Saloon perk-selection inherits the same card behavior via `PerkCard`.
- Character sheet in gameplay now shows:
  - resolved perk names instead of raw ids
  - equipped gun summaries from the tooltip builder
  - equipped gear summaries from the tooltip builder
- Character sheet in saloon shows the same gun summaries.
- Saloon shop now renders gear and authored shop text through the shared tooltip pipeline.
- Shop heal/ammo offers now use explicit offer tooltip keys instead of raw freeform text as the target path.

## Validation Changes

- Perks and guns must now provide either `tooltip_key` or `tooltip_override`.
- Gear and statuses now validate tooltip contracts too.
- Tooltip keys must exist in the local template registry.
- Tooltip overrides must be strings.
- Presentation hook ids must exist in the local hook registry.
- status lifecycle hook ids are also validated when present
- `presentation_hooks.on_proc` is only valid on content that also has `proc_rules`.
- The old incorrect `gear.tooltipKey` file-path validation was removed and replaced with string validation.

## Runtime Notes

- Phase 7 V1 keeps gameplay canonical:
  - combat/resolver still own what happened
  - presentation subscribers own how payoff feedback is shown
- The new presentation runtime does not add combat-local special cases.
- `phantom_third` payoff feedback is now event-owned instead of undocumented side behavior.
- Buff runtime now emits canonical lifecycle events for:
  - `OnStatusApplied`
  - `OnStatusRefreshed`
  - `OnStatusExpired`
  - `OnCleanse`
  - `OnPurge`
- High-signal status lifecycle hooks now exist for bleed, burn, shock and stun.
- Dev arena admin tooling now supports:
  - direct level-up opening
  - reward/shop offer refresh and free apply
  - one-click Phase 6/7 quick presets
  - status time stepping on player and nearest enemy
  - DevLog echo for canonical status lifecycle events

## Verification

- LOVE project boot passes with the expanded validator.
- `love .` smoke run passes.
- `love . --dev` smoke run passes.
- Grep confirms the migrated perk UI now goes through the tooltip builder.
- Shop offer rendering now goes through the shared offer tooltip path.
- Dev arena can now force reward and status-lifecycle verification without normal progression.

## Future Breadth

- Broader localization breadth.
- Larger event-owned readability layers beyond the `phantom_third` payoff.
- Additional content types and wider UI/readability polish beyond current playable surfaces.
