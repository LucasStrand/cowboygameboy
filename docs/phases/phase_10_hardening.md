# Phase 10: Hardening

## Goal

- Stabilize the post-Phase-9 runtime enough for broader content expansion.
- Convert the current strong runtime seams into durable persistence, diagnostics, and failure-tolerant systems.
- Keep Phase 10 focused on robustness, not on introducing new combat identities.

## Status

- **Slice 1 is implemented in code** (bounded run-metadata growth, scoreboard write hardening, defensive recap entry, clipboard export version stamps, regression harness, dev stress preset).
- **Slice 2+ is implemented in code** (versioned run-metadata snapshot export/import, `saveToFile`/`loadFromFile`, dev action `meta_save_snapshot`, extended `--phase10-regression` including boss milestone + persist round-trip + recap export header checks).
- **Gameplay “Continue run”** (full world state) remains **out of scope**; snapshots are **metadata-only** (see `RunMetadata.saveToFile`).
- This document remains the acceptance contract.

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

- [x] Canonical recap totals survive save/load or equivalent persistence seam without drift. *(`RunMetadata.exportPersistable` / `importPersistable` / `saveToFile` / `loadFromFile`; `--phase10-regression` compares `MetaRuntime.summarize` before vs after round-trip.)*
- [x] Damage-trace retention is bounded and documented. *(Ring buffers / table caps in `run_metadata.lua`; counts via `RunMetadata.retentionStats` and dev action `meta_dump_retention`.)*
- [x] Missing optional metadata does not break game over, recap, or export surfaces. *(Recap uses `pcall` around `MetaRuntime.summarize` and scoreboard `recordRun`.)*
- [x] A regression harness verifies at least:
  - total damage dealt
  - damage breakdown buckets
  - boss milestones (`recordBossKilled` → `summarize.bossesKilled`)
  - persist round-trip (memory + disk when `love.filesystem` available)
  - recap export header / format line (`run_recap.buildRunReportText`)
- [x] Highscore persistence survives multiple runs without malformed rows. *(Load path sanitizes rows; failed disk write rolls back the in-memory list.)*
- [x] Stress observation hook for proc/explosion-heavy preset. *(Wall-clock since `preset_phase10_proc_explosion_stress` until next `meta_dump_retention` logs `stress_wall_duration_ms` and stores last sample in `phase10_telemetry.lua`. **No automated FPS/ms CI budget** — see “Stress budget (soft)” below.)*

## Debug Hooks Required

- existing recap and metadata hooks
- export copy hooks from the recap screen
- [x] one stress preset for proc/explosion-heavy combat — `preset_phase10_proc_explosion_stress`
- [x] one metadata dump that includes storage/truncation stats — `meta_dump_retention`

## Slice 1 Commands

- Headless regression: `love . --phase10-regression` (from repo root; prints `[phase10-regression] OK` or exits with failure).
- Clipboard export lines include `Format vN | metadata retention policy vM` (see `RunMetadata.RECAP_EXPORT_VERSION` / `METADATA_RETENTION_VERSION`).

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
