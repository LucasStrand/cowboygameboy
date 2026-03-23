# Perks and skills system (authoring contract)

This document is the **canonical contract** for run-time **perks** in code today, and the **naming space** for future **skills** (meta, trees, or other surfaces) so new content does not fork ad hoc.

Related docs: [content_authoring_spec.md](./content_authoring_spec.md), [stat_registry.md](./stat_registry.md), [phases/phase_08_reward_weighting_economy_and_run_metadata.md](./phases/phase_08_reward_weighting_economy_and_run_metadata.md), [unified_actor_and_content_vision.md](./unified_actor_and_content_vision.md).

## Terminology

| Term | Meaning in this repo (current) |
|------|--------------------------------|
| **Perk** | A row in `src/data/perks.lua` `Perks.pool`. Granted during a run (level-up, saloon/blackjack paths that use the same cards). Persisted as **ordered perk ids** on the player. |
| **Skill** | Reserved for **design vocabulary** and future systems (e.g. meta unlocks, skill nodes). **Not** a separate Lua module yet. When you add a skill tree, either map nodes to existing perk ids or introduce `skills.lua` and a thin adapter that grants perks / modifiers—avoid a third parallel stat mutation path. |
| **Upgrade card** | Same data shape as a perk for offers UI, but you may later split “stat tuning” vs “mechanic” in pools. |
| **Weapon-bound upgrade** | Intended: modifier applies only while a specific weapon (or slot) is equipped. **Not** first-class in `weapon_runtime` yet—see [Weapon-specific upgrades](#weapon-specific-upgrades). |

## Design rules (balance and UX)

These are **authoring goals**; some are fully enforced in code today, others are roadmap.

### Power bands (rarity)

Use `rarity` consistently with what the card actually does:

| Tier | Intent | Examples |
|------|--------|----------|
| **common** | Small, always-reasonable stat bumps | +% damage, +armor, move speed |
| **uncommon** | Stronger stat or enables a sub-build | reload, mag size, sustain |
| **rare** | Changes moment-to-moment shooting or adds a proc | spread fire, ricochet, `proc_rules` |
| **legendary** | Run-defining (“OP” in feel); **very low `weight`**, clear fantasy | should read as a capstone; pair with risk or rarity later if power is extreme |

`Perks.rollPerks` already scales uncommon/rare weights with player luck; legendary should follow the same pattern when you add those rows.

### Global stat tweaks vs mechanics

- **Stat-only cards** — mutate `player.stats` in `apply`; keep deltas easy to reason about after many picks.
- **Mechanic cards** — prefer `proc_rules` + `presentation_hooks`, or a single boolean/stat flag documented in `stat_registry`, instead of new branches in `game.lua`.

### Rerolls (implemented)

- **Level-up:** `r` rerolls the three offers; cost from `RewardRuntime.getRerollCost("levelup", …)` (base + step per use, see `REROLL_BASE_COST` / `REROLL_STEP_COST` in `reward_runtime.lua`). Gold spend and history go through `RunMetadata.recordReroll`.
- **Shop:** same API with surface `"shop"` / normalized `"shop"`.

Design rule: rerolls are an **economy sink** and a way to chase build tags; tune base/step with run gold income.

### Stacking the same upgrade (current vs desired)

- **Current behavior:** once a perk `id` is owned, it is **excluded** from the level-up candidate pool (`buildPerkCandidates` in `reward_runtime.lua`). You **cannot** take the same card twice to stack +15% damage twice.
- **If you want stackable upgrades**, pick one approach and implement it explicitly:
  1. **Ranked ids** — `damage_up_1`, `damage_up_2` (different rows, same tooltip family); pool stays “unique id” friendly.
  2. **Repeatable id** — stop excluding owned id and make `apply` **purely additive**; `rebuildPerksFromIds` must replay stacks correctly (list can contain duplicate ids).
  3. **Numeric stack field** — store `{ id = "damage_up", stacks = 3 }` on the player instead of a flat id list (larger refactor).

Until one of these is implemented, treat “stacking” as **different perks that reinforce the same theme** (tags), not the same row twice.

### Banked / deferred picks (“open later”)

Not implemented. Intended UX: player earns **reward tokens** or **sealed packs** and opens them from inventory or between rooms so they are not forced to evaluate three new mechanics mid-fight.

When you add it: new player state (e.g. `pending_rewards`), UI state, and metadata events analogous to `recordRewardChosen`. Keep the **same perk definitions** so offers stay data-driven.

### Weapon-specific upgrades

**Today (global perks):** `StatRuntime.build_player_context` merges `player.stats` with the **active gun’s** `baseStats` when resolving weapon stats (`computeResolvedStats` in `weapon_runtime.lua`). So a perk that raises `projectile_damage` affects whichever gun is resolved—not a single weapon id permanently.

**Authoring toward weapon identity (partial):**

- Guns already carry tags like `weapon:<id>` (see `adaptWeaponDef` in `weapon_runtime.lua`).
- You can add matching **profiler tags** on perks (e.g. `weapon:revolver`) so `RewardRuntime.buildProfile` surfaces them when that gun is equipped—**offer bias only**, not enforcement.
- **True weapon-only modifiers** need runtime support, e.g. `weapon_slots[i].modifier_stack` merged only in `computeResolvedStats` for that slot, or perk metadata `binds_to_weapon_tag` filtered at grant time. Document new fields here when you add them.

### “Fler skills” without chaos

- Add perks in **small thematic batches** (e.g. reload line, crit line, mobility line) with distinct `id`s and `tooltip_key`s.
- Every new perk: update **`FEATURE_HINTS`** in `reward_runtime.lua` if tags alone are not enough for build matching.
- Run load with normal `ContentValidator.validate_all()` so tooltips and proc shapes stay valid.

## Runtime pipeline (where perks live)

1. **Offer generation:** `RewardRuntime.rollLevelUpChoices` (`src/systems/reward_runtime.lua`) builds a **tag profile** from weapons, owned perks, and gear, then picks three candidates targeting buckets `support`, `neutral`, `pivot`. Fallback: `Perks.rollPerks` via `Progression.rollLevelUpPerks` if the reward list is empty.
2. **Grant:** `Player:applyPerk` appends `perk.id` to `player.perks` and runs `perk.apply(player)` (`src/entities/player.lua`).
3. **Rebuild:** `Player:rebuildPerksFromIds` resets run base stats and reapplies perks in order. There is **no per-perk unapply**; anything not representable as “re-run apply from base” needs a deliberate design (e.g. proc-only perks with empty `apply`).
4. **Combat hooks:** `Player:getProcRules()` merges `proc_rules` from every owned perk definition into entries consumed by `ProcRuntime` (`src/systems/proc_runtime.lua`).

## Perk record schema (required and optional)

Author new perks only inside `Perks.pool` in `src/data/perks.lua` unless you split the file and keep a single loader—validation iterates `Perks.pool`.

### Required (enforced by `content_validator`)

| Field | Type | Notes |
|-------|------|--------|
| `id` | string | Stable, unique. Used in saves, metadata, and `Perks.byId`. |
| `name` | string | Display name. |
| `description` | string | Short line; UI may prefer tooltip templates. |
| `weight` | number | Positive. Base weight for rolls / reward weighting. |
| `apply` | function | `(player) -> ()`. Must be safe to call again on a fresh run base during `rebuildPerksFromIds`. |

### Strongly expected for player-facing content

| Field | Type | Notes |
|-------|------|--------|
| `tooltip_key` or `tooltip_override` | string | Phase 7+ contract; see [content_authoring_spec.md](./content_authoring_spec.md). |
| `tags` | array of strings | Used by reward profiling and bucket hints. |

### Optional

| Field | Type | Notes |
|-------|------|--------|
| `rarity` | `"common"` \| `"uncommon"` \| `"rare"` \| `"legendary"` | Affects `Perks.rollPerks` luck scaling; should match design tier. |
| `tooltip_tokens` | table | Substitutions for `tooltip_key`. |
| `keywords` | array of strings | Tooltip / card keyword surfacing when wired. |
| `proc_rules` | array | See **Proc rules (implemented subset)** below. |
| `presentation_hooks` | table | e.g. `on_proc = "hook_id"`; hook must exist in `presentation_hooks` data. If `on_proc` is set, `proc_rules` must be non-empty. |

## Tag vocabulary (reward and build profile)

Tags are free-form strings but **prefixes** are validated (`content_validator` `KNOWN_TAG_PREFIXES`). Common patterns:

- **`theme:*`** — e.g. `theme:damage`, `theme:mobility`, `theme:proc`. Drives overlap with the player’s current build.
- **`reward:*`** — explicit offer bucket: `reward:support`, `reward:neutral`, `reward:pivot`. If present, overrides automatic bucket from overlap score.
- **`role:*`** — e.g. `role:power`; surfaced on offers / metadata.
- **`attack:*`**, **`damage:*`**, **`setup:*`** — finer build hints for profiling.

`reward_runtime.lua` also maintains **`FEATURE_HINTS`** keyed by perk `id` for extra tags when `tags` alone are insufficient—**add an entry there when you add a perk** if profiling should notice it.

## Stat mutations in `apply`

- **Today:** perks mutate **`player.stats`** directly (often legacy camelCase like `damageMultiplier`, `moveSpeed`). Those fields map to canonical ids via `StatRegistry.legacy_aliases` (`src/data/stat_registry.lua`).
- **Rule:** Any **new** numeric or boolean stat you read in combat or UI should exist in **`stat_registry`** first, then be written using the same field name the player entity and `getEffectiveStats()` expect (legacy or canonical—match surrounding code).
- **Pitfall:** `shoot_cooldown` is derived from `rate_of_fire` at weapon resolution time; prefer changing **`rateOfFire` / `rate_of_fire`** on the player when authoring cadence perks (see [player_weapon_stat_resolution.md](./player_weapon_stat_resolution.md)).

## Proc rules (implemented subset)

`content_validator` currently allows **only** this shape (same family as attack profile proc snippets):

- `rule.id` — string  
- `rule.trigger` — string event name; player path uses resolver-fired **`OnHit`**.
- Optional filters: `source_owner_type`, `packet_kind`, `source_actor_kind` (must match what `proc_runtime` passes on the payload).
- `rule.counter` — `{ mode = "source_target_hits", every_n = number }`.
- `rule.effect` — `{ type = "delayed_damage", ... }` with fields consumed by `ProcRuntime` / `DamagePacket` (e.g. `delay`, `family`, `damage_scale`, flags like `can_crit`, `can_trigger_proc`).

Extending triggers or effect types requires **code changes** in `proc_runtime.lua` and **validator updates** in `content_validator.lua` in the same PR.

## Load-time validation

On startup, `content_validator.validatePerks()` checks perk rows, tags, tooltips, `proc_rules`, and presentation hooks. If validation is disabled in a special build, still run a normal load before shipping content.

## Roadmap slices (suggested order)

1. **More authored perks** — expand `perks.lua` + `tooltip_templates.lua`; tune `weight` / `rarity`; keep proc-heavy cards rare.
2. **Stacking policy** — choose ranked ids vs duplicate ids vs stack struct; adjust `buildPerkCandidates` and save format accordingly.
3. **Weapon-bound modifiers** — extend `weapon_runtime` slot state + `StatRuntime` context so some modifiers apply per slot or per `weapon:*` tag only.
4. **Banked rewards** — pending reward queue + UI; reuse `RewardRuntime` roll functions for generation.
5. **Modifier pipeline** — move from imperative `apply` to `StatRuntime`-style modifier list on player (aligns with [combat_progression_architecture.md](./combat_progression_architecture.md)).

## Future direction (skills / modifier refactor)

Longer-term vision (see [combat_progression_architecture.md](./combat_progression_architecture.md)): perks should ideally contribute **modifiers** into a shared pipeline instead of only imperative `apply` blocks. Until that lands:

1. Keep **`apply`** idempotent relative to run base.  
2. Put **rule-breaking behavior** in **`proc_rules`**, status applications, or dedicated runtime flags—**not** scattered `if player.perks` in combat code.  
3. When introducing **skills**, define whether a skill **grants a perk id**, **applies a stat bundle**, or **unlocks a template**—document the mapping in this file when you add it.
