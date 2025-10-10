# Assets Folder Structure

This folder contains all game assets organized by type.

## Folder Structure

- **images/** - Game sprites, textures, and graphics
  - `tiles/` - Tile sprites for the grid
  - `entities/` - Character and entity sprites
  - `effects/` - Visual effects and particles
  - `backgrounds/` - Background images

- **sounds/** - Audio files
  - `music/` - Background music
  - `sfx/` - Sound effects
  - `ui/` - UI interaction sounds

- **fonts/** - Custom fonts
  - `.ttf` or `.otf` font files

- **ui/** - UI-specific assets
  - `icons/` - UI icons and buttons
  - `panels/` - UI panel graphics

## Asset Loading

Assets are loaded in the game using Love2D's built-in functions:
- `love.graphics.newImage()` for images
- `love.audio.newSource()` for sounds
- `love.graphics.newFont()` for fonts

## File Formats

- **Images**: PNG, JPG, GIF
- **Sounds**: OGG, WAV, MP3
- **Fonts**: TTF, OTF

## Naming Convention

Use descriptive names with underscores:
- `tower_basic.png`
- `enemy_goblin.png`
- `ui_button_hover.wav`
