# Phase 10: Hardening

## Goal

- Stabilize the post-Phase-9 runtime enough for broader content expansion.
- Convert the current strong runtime seams into durable persistence, diagnostics, and failure-tolerant systems.
- Keep Phase 10 focused on robustness, not on introducing new combat identities.

## Status

- Phase 10 is not started in code.
- This document is the first hardening plan and acceptance contract.
- Phase 10 should begin only after the first Phase 9 readability slice lands and recap/HUD seams remain stable.

## Start Conditions

- Phase 8 recap/export truth seam remains canonical and verified.
- Phase 9 readability changes do not regress recap counts, ownership data, or damage-trace exports.
- Current authoritative owners stay intact:
  - `weapon_runtime`
  - `damage_resolver`
  - `buffs`
  - `proc_runtime`
  - `reward_runtime`
  - `run_metadata`
  - `meta_runtime`

## Hardening Priorities

- `1.` Persistence and replayable evidence
  - Decide what portion of run metadata becomes durable save/load state.
  - Preserve recap exports and score history without fragmenting truth ownership.
  - Define retention limits for trace-heavy data such as damage events.

- `2.` Failure tolerance and graceful degradation
  - Ensure recap/highscore/export surfaces do not fail when optional data is missing.
  - Bound long-run metadata growth.
  - Make debug-only enrichment opt-in where runtime overhead becomes noticeable.

- `3.` Verification and diagnostics
  - Extend harness coverage to include post-run flows, recap export, and damage-trace integrity.
  - Add one or more regression-friendly checks for boss milestones, damage totals, and source-causality seams.

- `4.` Performance and memory budgets
  - Audit event-heavy combat runs with proc/explosion chains.
  - Bound recap UI and metadata cost so long runs remain safe.
  - Document acceptable limits for stored recap rows and highscore entries.

## Concrete Scope For Slice 1

- In scope:
  - save/load plan for run metadata and score history
  - trace retention policy
  - recap/export regression checks
  - defensive handling of partial metadata
  - hard limits for recap-facing stored rows

- Out of scope:
  - new weapons/perks/status families
  - broad HUD redesign
  - unlock-meta content expansion
  - online leaderboards or backend services

## Acceptance Checklist

- [ ] Canonical recap totals survive save/load or equivalent persistence seam without drift.
- [ ] Damage-trace retention is bounded and documented.
- [ ] Missing optional metadata does not break game over, recap, or export surfaces.
- [ ] A regression harness verifies at least:
  - total damage dealt
  - damage breakdown buckets
  - boss milestones
  - recap/export alignment
- [ ] Highscore persistence survives multiple runs without malformed rows.
- [ ] One stress run with proc/explosion-heavy output stays within acceptable performance bounds.

## Debug Hooks Required

- existing recap and metadata hooks
- export copy hooks from the recap screen
- one stress preset for proc/explosion-heavy combat
- one metadata dump that includes storage/truncation stats

## Telemetry Fields Required

- `damage_event_count`
- `damage_event_retained_count`
- `scoreboard_entry_count`
- `recap_export_version`
- `metadata_persistence_version`
- `stress_run_duration_ms`

## Risks

- The largest risk is treating save/load as a UI problem instead of a truth-ownership problem.
- The second risk is allowing damage traces to grow without explicit retention policy.
- The third risk is hardening only the happy-path recap while leaving partial/missing metadata untested.
- The fourth risk is drifting from canonical summary generation by introducing alternate persistence-only recap formats.

## Exit Conditions

- The recap/export stack is robust under normal play, partial data, and long runs.
- Persistence and retention rules are documented and enforced in code.
- Regression checks exist for the most important reward/meta/combat recap seams.
- The codebase is ready for larger content expansion without turning recap/meta debugging back into manual archaeology.
