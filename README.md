### Guardian Defense

Arcade tower-defense prototype with light deckbuilding, built on LÖVE 11.4. Place towers on designated build spots, defend the Vigil Core against waves of enemies, and play cards to place towers, buff them, or alter the path.

### Requirements

- **LÖVE** 11.4 or newer
- macOS, Windows, or Linux supported by LÖVE

### Quick Start

```bash
love .
```

Tip: If multiple LÖVE versions are installed, ensure 11.4 is used.

### Controls

- **Mouse (primary)**
  - Left click tiles to select.
  - Drag cards from the bottom hand to play them.
  - Target cards: drop on valid tiles (build spots for towers, occupied towers for buffs/mods, path tiles for effects).
  - Non-target cards: drag upward past the threshold to play (e.g., Energy Shield).
- **Space**: start next wave
- **R**: reset grid (reloads level)
- **S**: spawn one enemy (debug)
- **F11** or **F**: toggle fullscreen
- **P**: toggle post-FX preview
- **Esc**: quit

### Gameplay Loop

- **Waves & Intermissions**
  - Waves spawn enemies along the TMX-defined path toward the Vigil Core.
  - Between waves, new cards are dealt to your hand and energy is replenished per `Config.DECK`.
- **Cards** (from `src/data/cards.lua`)
  - place_tower: e.g., Crossbow, Fire
  - modify_tower: e.g., Extended Reach (+range)
  - apply_tower_buff: e.g., Haste (+fire rate for a duration)
  - apply_path_effect: e.g., Bonechill Mist (slows on path; future levels can deal damage)
  - apply_core_shield: e.g., Energy Shield (temporary shield for the current/next wave)
- **Economy**
  - Enemies have a chance to drop coins which fly to the HUD counter.
  - Use coins to upgrade or destroy towers via the on-tile menu.
- **Core Health**
  - Shown as a compact HUD panel; shields absorb damage before health.

All tunables (resolution, colors, speeds, damage, UI, deck settings) live in `src/config/Config.lua` as the single source of truth.

### Project Structure

- `assets/` images, sounds, fonts, levels (TMX)
- `src/config/Config.lua` single source of truth for parameters
- `src/core/` game loop (`Game.lua`), resolution handling
- `src/data/` `cards.lua`, `enemies.lua`, `towers.lua`, `waves/`
- `src/systems/` `GridMap`, `EnemySpawnManager`, `TowerManager`, `ProjectileManager`, `WaveManager`, `DeckManager`, `Pathfinder`
- `src/ui/HandUI.lua` card hand and interactions
- `src/utils/MapLoader.lua` TMX loading and parsing
- `src/theme.lua` centralized UI styleguide and utilities
- `src/libs/moonshine/` post-processing effects used for hit blooms and UI glow

### Development Notes

- Use `src/config/Config.lua` for all gameplay and UI tuning; avoid hardcoding.
- Keep UI consistent via `src/theme.lua` components and fonts.
- Prefer mouse-first interactions for UI and placement.
- Post-FX are off by default; press P to preview.

### Screenshots / GIFs

Add media to showcase gameplay. Example placeholders:

```md
![Gameplay](assets/images/backgrounds/placeholder_gameplay.png)
![Cards](assets/images/cards/card_crossbow.png)
```

### Assets & Credits

- Fonts: Barlow Condensed (Regular/Bold) by Jeremy Tribby. Files included under their respective license.
- Post-processing: Moonshine shader collection by Matthias Richter and contributors (included in `src/libs/moonshine`).
- All other art is placeholder or project-owned. Replace as needed for distribution.

### License

See `LICENSE` in the repository root.

