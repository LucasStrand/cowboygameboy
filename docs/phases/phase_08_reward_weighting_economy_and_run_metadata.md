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
  - reroll cost calculation
  - reroll offer regeneration
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
- Current gold spend/earn paths now route through canonical player economy helpers for:
  - shop buys
  - level-up rerolls
  - shop rerolls
  - blackjack wagers / doubles / splits / rewards
  - roulette wagers
  - slots wagers
  - combat and casino floor gold pickups
- Dev arena reward tooling now exposes:
  - gold pressure snapshot
  - current reroll costs
  - spend-and-reroll shop action
  - profile / offer reasoning dumps

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
- Shop pricing now follows role-aware pressure bands:
  - sustain is painful but buyable
  - utility is cheaper
  - build-forward gear is the most expensive
  - pivot gear is cheaper than full support/power gear
- If a bucket is thin, the runtime degrades gracefully without duplicate offers when possible.
- Rerolls now exist on both current reward surfaces:
  - level-up rerolls
  - shop rerolls
- Reroll costs escalate per surface and per run.

## Runtime Notes

- Build profiling is intentionally coarse in this kickoff slice.
- Current profile inference reads from:
  - equipped guns
  - owned perks
  - equipped gear
  - lightweight authored tags and inferred theme hints
- This slice does not implement real meta progression yet.
- Run metadata is runtime-only in this pass; save/load and export are left for later work.
- Run metadata now also records:
  - reward rerolls
  - shop rerolls
  - reroll counts
  - gold earn/spend reasons
  - shop enter/leave pressure snapshots

## Dev / Verification

- Dev arena reward lab can now:
  - dump current build profile
  - dump current gold-pressure state
  - reroll dev shop offers through the reward runtime
  - force level-up through the reward runtime
  - reroll level-up choices through the level-up overlay
  - show support/neutral/pivot reasoning in DevLog
- `love .` smoke run passes.
- `love . --dev` smoke run passes.
- Grep confirms current playable perk-reward surfaces no longer bypass the reward runtime.

## Still Deferred

- Real meta progression / unlock systems.
- Broader reward-pool authoring beyond current perks/gear/offers.
- Cursed economy and refill-role breadth.
- Save/load serialization and recap/export on top of run metadata.
