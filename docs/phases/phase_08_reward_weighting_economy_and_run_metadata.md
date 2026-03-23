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
- New `meta_runtime` seam now summarizes run metadata into a recap-friendly shape.
- Run metadata now records additional Phase 8 closeout milestones:
  - checkpoints reached
  - bosses killed from explicit kill events
  - run-end outcome
  - final build snapshot at recap / death
- Game over screen now renders a real recap summary from `run_metadata` instead of only flat score stats.
- Dev arena/admin tooling now also exposes:
  - meta summary dump to `DevLog`
  - direct open of the recap screen from the current run

## Truth Matrix

- `goldEarned` / `goldSpent` come only from `run_metadata.economy`.
- `rerollsUsed` comes only from `run_metadata.economy.reroll_counts`.
- `perksPicked` comes only from reward-choice history in `run_metadata.rewards.chosen`.
- `checkpointsReached` comes only from checkpoint milestone history in `run_metadata.milestones.checkpoints`.
- `bossesKilled` comes only from explicit boss kill events routed through `RunMetadata.recordBossKilled(...)`.
- `recent picks` / `recent buys` come only from reward/shop history.
- `dominantTags` come only from stored build snapshots.
- `MetaRuntime.summarize(...)` is read-only projection logic, not an alternate truth owner.
- Game over recap text is now built from `MetaRuntime` recap lines so UI and verification use the same formatter.

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
  - checkpoint milestones
  - boss kill milestones
  - run-end recap data
- Phase 8 closeout intentionally stops at recap/meta seams.
- Full persistent unlock progression remains deferred on purpose rather than half-built here.

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
- Smoke boot still passes after adding meta summary + recap hooks.
- Recap can now be opened from the dev panel to verify Phase 8 metadata without needing a full death flow.

## Verification Status

- Phase 8 now has a dedicated LOVE runtime harness at `tmp/phase8_meta_harness/`.
- The harness writes evidence to `tmp/phase8_meta_harness_output.txt`.
- Truth gate status: passed.
- Static audit status: passed.
- Verified source-of-truth surfaces:
  - `MetaRuntime.summarize(...)` is the only summary projection owner.
  - `MetaRuntime.toDebugLines(...)` and `MetaRuntime.toRecapLines(...)` both render from the same derived summary object.
  - `bossesKilled` is no longer inferred from room exit and now comes only from explicit boss `OnKill` events.
- The truth gate verifies:
  - reward choice history vs summary counts
  - shop purchase/reroll history vs summary counts
  - checkpoint history vs summary counts
  - explicit boss kill events vs summary counts
  - recap/debug text generation vs the same summary object
  - repeated summary calls are deterministic for the same metadata snapshot
- Harness evidence currently ends with `SUMMARY: PASS`.
- Manual live acceptance remains the last gate before starting Phase 9:
  - normal gameplay death recap
  - dev-panel `meta_dump_summary`
  - dev-panel `meta_open_recap`
  - one boss run and one non-boss run
- If any of those surfaces disagree, Phase 8 must be re-opened and Phase 9 blocked.

## Final Acceptance Checklist

- Use this checklist as the only manual signoff gate between Phase 8 and Phase 9.
- Do not start Phase 9 implementation until every item below is confirmed in live play.
- If any item fails, Phase 8 returns to open status.

- [ ] Normal death recap renders and the economy / milestone lines are plausible for the run.
- [x] Dev-panel `meta_dump_summary` matches the same run's canonical recap counts.
- [x] Dev-panel `meta_open_recap` opens the same derived summary surface without mutating totals.
- [x] One boss run increments `bossesKilled` only after an actual boss death.
- [x] One non-boss run leaves `bossesKilled` at `0`.
- [ ] Dominant tags and recent picks / buys stay consistent across raw metadata, DevLog dump, and game-over recap.
- [ ] If a mismatch is found, Phase 8 roadmap status is reverted before any Phase 9 code starts.

### Checklist Audit Notes

- `meta_dump_summary` is mechanically verified because it renders `MetaRuntime.toDebugLines(...)` from the same `MetaRuntime.summarize(...)` output that also drives the recap surface.
- `meta_open_recap` is mechanically verified because it routes through `queueRunRecap(...)`, writes canonical `run_end` data, and the Phase 8 harness confirms recap-open does not mutate gold or reroll totals.
- Boss and non-boss milestone behavior are mechanically verified by the dedicated Phase 8 harness:
  - boss count stays `0` after a normal enemy kill
  - boss count becomes `1` after an actual boss `OnKill`
- Remaining unchecked items are intentionally still live-play gates, not assumptions.

## Still Deferred

- Real persistent meta progression / unlock systems.
- Broader reward-pool authoring beyond current perks/gear/offers.
- Cursed economy and refill-role breadth.
- Save/load serialization and recap export on top of run metadata.
