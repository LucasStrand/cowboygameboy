# Phase 09: UX / Readability Pass

## Goal

- Make the current combat/build depth readable enough that players can understand what happened without opening debug tooling.
- Build on the stable ownership, proc, tooltip, reward, and recap seams from Phases 4-8.
- Keep Phase 9 focused on clarity and player-facing surfaces, not on new combat rules or hardening breadth.

## Status

- Phase 9 is not started in code.
- A repo audit confirms the current codebase still stops at the Phase 8 recap/build-summary seams.
- This document is the kickoff plan and acceptance contract for the first implementation slice.
- Phase 8 closeout is complete, so Phase 9 is no longer blocked on recap sanity signoff.
- Phase 9 remains blocked only by prioritization, not by unresolved Phase 8 truth issues.

## Start Conditions

- Phase 8 truth gate passed and its live acceptance checklist is completed.
- Current recap/runtime truth seams remain canonical:
  - `run_metadata` is raw truth
  - `MetaRuntime.summarize(...)` is the only summary projection owner
  - UI surfaces render from derived summary data rather than ad hoc gameplay state
- Existing readability foundations stay in place:
  - event-owned proc/status presentation hooks
  - tooltip/content language pipeline
  - reward/build-profile classification
  - cinematic game-over seam plus dedicated recap screen
  - recap clipboard export and damage-trace seam

## Kickoff Slice

- Slice 1 should focus on the highest-signal readability gaps, not on broad UI polish.
- Implement in this order:

- `1.` Death / recap ownership clarity
  - Add last damaging source to the recap path.
  - Add one clear "recent major proc / payoff" line when present.
  - Use the new Phase 8 damage-trace seam instead of reconstructing causality from transient draw-state.

- `2.` HUD priority baseline
  - Lock Group A as always-visible combat-critical data.
  - Keep Group B readable but secondary.
  - Leave Group C in inspect / expand surfaces rather than crowding the HUD.

- `3.` Build clarity baseline
  - Surface dominant build tags or equivalent build summary in at least one always-reachable player-facing surface.
  - Add simple build-matching language on reward-facing surfaces where it materially helps decisions.

## Concrete Scope For Slice 1

- In scope:
  - death recap clarity
  - current-run recap readability
  - last damage ownership line
  - one major payoff/proc summary line
  - first HUD A/B tier split
  - simple build summary exposure
  - better use of existing export/debug recap seams in player-facing copy

- Out of scope:
  - full HUD redesign
  - permanent meta progression
  - save/load
  - telemetry export/backend work
  - hardening/performance budgets from Phase 10

## Acceptance Checklist

- [ ] Death recap shows a readable outcome summary plus last damaging source.
- [ ] If a large proc/payoff contributed meaningfully, the recap can surface it without debug-only language.
- [ ] Group A HUD data stays readable during normal combat and during a cluttered combat test.
- [ ] Group B status information stays available without crowding Group A.
- [ ] At least one player-facing surface explains current build identity using tags/summary language.
- [ ] One reward-facing surface exposes build-matching help that is understandable without opening DevLog.
- [ ] Existing recap counts from Phase 8 still match canonical metadata after the readability changes.
- [ ] Clipboard run report and damage trace remain aligned with the recap surface after readability changes.

## Debug Hooks Required

- Existing hooks to keep using:
  - `meta_dump_summary`
  - `meta_open_recap`
  - Phase 6/7 proc and status dev presets

- New hooks Phase 9 should add early:
  - a dump for last damaging source / recap ownership fields
  - a clutter/readability combat preset
  - a temporary HUD tier overlay or equivalent diagnostic view
  - a recap-side causal-chain preview that can be toggled without leaving the recap screen

## Telemetry Fields Required

- `last_damage_source_type`
- `last_damage_source_id`
- `last_damage_family`
- `last_damage_packet_kind`
- `last_major_proc_id`
- `dominant_build_tags`
- `visible_buff_count`
- `recap_outcome`
- `damage_trace_primary_source`
- `damage_trace_last_event_source`

## Risks

- The largest risk is letting Phase 9 turn into broad UI polish without locking a first high-signal slice.
- The second risk is recomputing recap/readability fields from transient runtime state instead of canonical metadata.
- The third risk is overloading the HUD before Group A / B / C ownership is explicitly chosen.
- The fourth risk is duplicating Phase 8 export/debug text in multiple player-facing variants instead of picking one canonical wording layer.

## Exit Conditions

- Players can understand why they died and what their run was doing without needing DevLog.
- Current payoff moments read clearly in motion often enough to validate the ownership-feedback direction.
- The HUD has a documented A/B baseline instead of an accidental pileup of elements.
- Phase 8 recap truth remains intact after the readability work.
