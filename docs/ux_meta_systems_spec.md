# Six Chambers UX and Meta Systems Spec

This document locks direction for:

- combat readability
- feedback ownership
- HUD priority
- build clarity
- economy pressure
- reward pools
- meta unlock philosophy
- run metadata
- performance, debug, and runtime support

Goal: deep systems should feel smart and satisfying, not merely chaotic.

## 1. Combat readability

Combat must let the player read:

- what hit
- who caused the effect
- what damage type it was
- what actually killed the target

### Three layers

**Primary** — must read in the middle of a fight:

- which attacks are yours
- which projectiles are dangerous
- which target is marked, vulnerable, or stunned
- when a major payoff happens

**Secondary** — not every frame, but understandable afterward:

- chain lightning jumped from your proc
- burn killed the target, not the main hit
- delayed detonation came from an earlier mark

**Recap / debug** — when it gets noisy, explain after the fact:

- death recap
- hit summary
- last damaging source
- icon or log for the latest major proc

### Presentation default

- direct hits get the strongest feedback
- big procs or payoffs the next strongest
- background damage (DoT, aura ticks) weaker
- delayed hits need clear setup or a clear owner before they resolve

The more important a gameplay decision is, the clearer its payoff should be visually and in audio.

## 2. Feedback ownership

The player should understand whether something came from:

- the weapon
- a relic
- a passive
- an earlier status

Important secondary effects should have an **ownership signature**: color, icon, sound, small label, or visual motif tied to the source.

Strong passives should have three beats: **setup**, **trigger**, **result**. Example: a delayed true-damage ping should mark the target first; when the ping fires, reuse the same color, symbol, or SFX.

## 3. HUD priority

The player may track potions, boons, statuses, cooldowns, passive counters, active weapon, offhand, reload, marks/charges — not everything gets equal HUD weight.

### Group A: always visible

- HP / shield
- active weapons
- ammo / reload / main resource
- potion charges
- key cooldowns
- clear proc counters for payoffs that matter in real time

### Group B: easy to reach

- buffs/debuffs on the player
- boon summary
- passive counters that only matter sometimes
- offhand state if it is not central every second

### Group C: inspect / expand

- small modifiers
- full status list
- proc chance breakdown
- exact source mapping

HUD should mainly answer: am I in danger, what can I use now, when is my next payoff, which weapon or state is active.

## 4. Build clarity

The game should help the player see **why** a build is strong.

Good clarity: several rewards tagged `Bleed`, a relic that crits bleeding targets, a perk that lets bleed crit, another effect that consumes bleed for burst — it reads as a direction.

Poor clarity: only small percentage numbers, vague procs, effects that stack without a visible engine.

The UI should help surface:

- core engine
- enablers
- payoff pieces
- finishers

Useful affordances:

- highlighted keywords in rewards
- visible tags
- build-matching reward hints
- a simple build summary

## 5. Economy pressure

Economy should create meaningful choices, not constant frustration. The player should often feel: almost able to afford, saving now enables something big later, reroll vs safe pick — not: never able to afford, always buying the same thing, everything feels like a tax.

**Sink roles:**

- shop prices — baseline value and tempo
- rerolls — flexibility vs cost
- repairs / refills — defensive stability
- potion refills — greed vs safety
- cursed items — risk/reward

**Design rule:** each shop visit should offer at least two reasonable decisions. Avoid a single always-optimal spend.

## 6. Reward pools

Use smart weighting, not pure RNG. Everything can stay in the pool, but weight up what fits the current build and weight down dead choices.

**Weighting inputs:** weapon family, damage tags, status themes, resource model, prior picks, current build engine, biome/event context.

**Default draft shape:** one reward supports the current build, one is neutral/stable, one opens a pivot or alternative — progression, flexibility, and surprise without pure noise.

## 7. Meta unlock philosophy

Meta should **widen** the game more than it inflates raw power.

Good unlocks: new weapon families, new events, new relics/perks, new croupiers or room types, new risk/reward or curse loops.

Avoid as the default track: permanent `+10%` damage, flat max HP, always-better loot. Some raw power for onboarding is fine; it should not be the main spine.

Ask per unlock: does this add interesting decisions, or only bigger numbers?

## 8. Run metadata

Collect metadata from the start — balance, QA/debug, UX, run identity.

**Store at minimum:** run seed, biome/route, room history (or room types spawned), reward history, boss pool candidates, modifier flags, event pool weights, curse/blessing state, economy milestones.

**Player-facing use:** death recap, post-run summary, daily challenges, seed sharing, community comparison, understanding why a run felt different.

Metadata should not be only internal; surface part of it cleanly to the player.

## 9. Performance budgets

Set hard caps early:

- max projectiles
- max chain hops
- max aura ticks per frame
- max on-hit evaluations per frame

When a budget is hit, degrade gracefully (fewer visual ticks, capped chain depth, batched small DoTs). Prefer cutting presentation before gameplay when possible.

## 10. Determinism

Gameplay RNG should be reproducible. Presentation need not be perfectly deterministic, but runs should be replayable or reproducible for debugging, balance, weird repros, and analysis of over-tuned builds.

## 11. Save / load

Mid-run save must persist everything that affects future combat, not just inventory:

- buff timers
- status stacks
- weapon runtime state and counters
- ammo / reload state
- passive counters
- delayed hits waiting on a trigger
- room state
- reward pool state
- RNG state

Otherwise the player reloads into a “same run” with a different reality.

## 12. Telemetry

Log what explains **power**, not only total damage:

- damage per source
- damage per tag
- proc rate
- overkill
- important buff/debuff uptime
- which rewards are actually taken
- how often reroll is used
- where runs end (death points)
- perks that correlate with strong outcomes (when sample size allows)
- how much of a build’s strength comes from direct hit vs secondary effects

That makes it easier to spot what is overpowered, bait, or misunderstood.

## 13. Debug tools

Debug tools are core systems, not luxuries. You should be able to:

- grant perks
- apply statuses
- spawn specific enemies
- print damage packets step by step
- inspect active modifiers
- freeze timers
- show RNG rolls
- see which effect owns a proc

If you want absurd synergies, you need to dissect them quickly.

## 14. Overall direction

This direction fits a game with absurd builds, many layers, rule-breaking perks, and big payoff moments. The game should help the player read what happened, why it happened, and how they built toward it. The best chaos is chaos the player can understand afterward and want to recreate.
