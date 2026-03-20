# Six Chambers

A 2D cowboy roguelike platformer built with [LOVE2D](https://love2d.org/) and Lua.

For current status, vibe, and prompt-friendly context, see [GAME_CONTEXT.md](GAME_CONTEXT.md).

## How to Run

1. Install [LOVE2D 11.5](https://love2d.org/) for your platform
2. Run from this directory:
   ```
   love .
   ```
   Or drag the folder onto `love.exe`.

## Controls

| Key | Action |
|-----|--------|
| A/D or Arrow Keys | Move left/right |
| Space / W / Up | Jump |
| Mouse (left click) | Shoot (aim with cursor) |
| Mouse (right click) | Reload |
| R | Reload |
| F1 | Toggle debug hitboxes |
| ESC | Return to menu |

## Game Loop

1. Fight through 5 rooms of enemies
2. Clear all enemies to unlock the exit door
3. After 5 rooms, reach the **Saloon Checkpoint**:
   - Play **Blackjack** to wager gold for perk rewards
   - Visit the **Bartender** to buy healing, gear, or ammo upgrades
4. Continue to the next set of 5 rooms (harder enemies)
5. On death, restart from room 1

## Progression

- **XP & Leveling**: Kill enemies to earn XP. On level-up, pick 1 of 3 perks (common/uncommon/rare).
- **Gold**: Dropped by enemies. Spend at the bartender or wager at blackjack.
- **Gear**: 3 slots (hat, vest, boots) providing stat bonuses. Buy from shop or find from drops.
- **Perks**: 12 unique perks ranging from stat boosts to special abilities like Scattershot, Ricochet, Explosive Rounds, and Dead Eye.

## Project Structure

```
main.lua / conf.lua        -- LOVE2D entry point and window config
lib/                        -- Third-party libraries (bump, hump, sti, anim8)
src/
  states/                   -- Game states (menu, game, levelup, saloon, gameover)
  entities/                 -- Player, bullet, enemy, pickup
  systems/                  -- Combat, progression, inventory, room manager, blackjack, shop
  data/                     -- Data definitions (perks, enemies, gear, rooms)
  ui/                       -- HUD and perk card UI
assets/                     -- Sprites, maps, sounds, fonts (placeholder)
```

## Tech Stack

- **LOVE2D 11.5** -- Game framework
- **bump.lua** -- AABB collision detection
- **hump** -- Gamestate management, camera, timers, vectors
- **STI** -- Tiled map integration (available for future use)
- **anim8** -- Sprite animation (available for future use)

## What's Implemented

- Player movement with gravity, coyote time, and jump buffering
- Revolver with 6-shot cylinder, mouse aiming, reload mechanic
- 3 enemy types: Bandit (melee), Gunslinger (ranged), Buzzard (flying)
- 4 hand-designed room layouts, randomly sequenced
- Difficulty scaling (more and tougher enemies per room)
- XP/level system with 12 perks across 3 rarity tiers
- Gold economy with drops and spending
- Saloon checkpoint with blackjack gambling and bartender shop
- Gear system (hat/vest/boots) with stat bonuses
- HUD with HP bar, ammo cylinder, XP bar, gold counter
- Screen shake on shooting
- Kill plane for pit deaths
- Debug hitbox rendering (F1)
