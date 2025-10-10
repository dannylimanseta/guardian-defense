### Guardian Defense

Arcade tower-defense prototype built with LÖVE (Love2D). Features a grid-based map loaded from TMX, enemy pathing, simple tower placement, and basic projectile combat.

### Requirements

- **LÖVE** 11.4 or newer

### Quick Start

```bash
love .
```

If you have multiple Love2D versions installed, explicitly run 11.4 with your launcher of choice.

### Controls

- **Mouse Left**: select tile / place tower on build spot
- **S**: spawn a single enemy immediately (debug)
- **R**: reset grid
- **Space**: clear selection
- **F11** or **F**: toggle fullscreen
- **I**: print resolution info
- **Esc**: quit

### Project Structure

- `assets/`: images, sounds, levels (TMX)
- `src/config/Config.lua`: single source of truth (resolution, colors, gameplay tunables)
- `src/core/`: game loop and resolution management
- `src/systems/`: grid, enemy spawner, pathfinding
- `src/utils/MapLoader.lua`: TMX loader and layer parsing
- `src/theme.lua`: centralized UI styles/components

### Notes

- Graphics are scaled with nearest filtering for a crisp pixel look.
- The map is centered based on logical resolution (`Config.LOGICAL_WIDTH/HEIGHT`).
- Enemy movement uses BFS over `path` tiles from TMX.

### Roadmap (short)

- Basic UI panel for tower info and core health
- Multiple tower types and targeting modes
- Waves and economy loop (build/sell/upgrade)


