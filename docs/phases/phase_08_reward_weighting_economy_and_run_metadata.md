# Phase 08: Reward Weighting, Economy, and Run Metadata

## Goal

- Start Phase 8 with a reward-first slice.
- Replace ad hoc reward rolling with a canonical reward runtime.
- Introduce explicit economy roles for current offers.
- Start capturing real run metadata from run start through reward/shop decisions.

## Implemented

- New `reward_runtime` canonical owner for:
  - build profile classification
  - level-up reward generation
  - shop offer generation
  - reward/shop choice recording
- New `run_metadata` runtime object with stable top-level sections:
  - `seed`
  - `route`
  - `rooms`
  - `rewards`
  - `shops`
  - `economy`
  - `build_snapshots`
- Level-up rewards now route through the reward runtime instead of raw `Perks.rollPerks(...)`.
- Saloon shop offers now route through the reward runtime instead of static local generation.
- Blackjack perk rewards now reuse the same reward runtime path instead of bypassing it.
- Current authored shop offers now expose economy-role / reward-tag intent through tags.

## Weighting Model

- V1 uses a soft `support / neutral / pivot` model.
- Level-up tries to offer:
  - one support choice
  - one neutral choice
  - one pivot choice
- Shop V1 keeps the simple saloon structure but makes the content build-aware:
  - sustain anchor
  - build-supporting gear where possible
  - pivot gear or utility fallback
- If a bucket is thin, the runtime degrades gracefully without duplicate offers when possible.

## Runtime Notes

- Build profiling is intentionally coarse in this kickoff slice.
- Current profile inference reads from:
  - equipped guns
  - owned perks
  - equipped gear
  - lightweight authored tags and inferred theme hints
- This slice does not implement real meta progression yet.
- Run metadata is runtime-only in this pass; save/load and export are left for later work.

## Dev / Verification

- Dev arena reward lab can now:
  - dump current build profile
  - reroll dev shop offers through the reward runtime
  - force level-up through the reward runtime
  - show support/neutral/pivot reasoning in DevLog
- `love .` smoke run passes.
- `love . --dev` smoke run passes.
- Grep confirms current playable perk-reward surfaces no longer bypass the reward runtime.

## Still Deferred

- Real meta progression / unlock systems.
- Broader reward-pool authoring beyond current perks/gear/offers.
- Reroll economy, cursed economy, and refill-role breadth.
- Save/load serialization and recap/export on top of run metadata.
