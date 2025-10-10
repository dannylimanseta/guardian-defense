-- Config.lua - Central configuration for all game parameters
-- Single source of truth for easy playtesting and adjustments

local Config = {}

-- Window and Resolution Settings
Config.WINDOW_TITLE = "Guardian Defense"
Config.LOGICAL_WIDTH = 1280  -- Design resolution width
Config.LOGICAL_HEIGHT = 720  -- Design resolution height

-- Grid Map Settings
Config.GRID_WIDTH = 25       -- Number of tiles horizontally
Config.GRID_HEIGHT = 12      -- Number of tiles vertically
Config.TILE_SIZE = 50        -- Size of each tile in pixels
Config.TILESET_PATH = "assets/images/tiles"
Config.ENTITIES_PATH = "assets/images/entities"
Config.LEVELS_PATH = "assets/levels"
Config.FONT_PATH = "assets/fonts"
Config.SOUNDS_PATH = "assets/sounds"
Config.UI_ASSETS_PATH = "assets/ui"
Config.LAYERS = {
    GROUND = "Tile Layer 1"
}

-- Colors (RGBA values)
Config.COLORS = {
    BACKGROUND = {0.153, 0.173, 0.298, 1}, -- #252C4C
    GRID_LINES = {1, 1, 1, 0},        -- White grid fully transparent
    GRID_BACKGROUND = {0.153, 0.173, 0.298, 1}, -- #252C4C
    HOVER_TILE = {1, 1, 1, 0},          -- White hover effect (0% opacity)
    SELECTED_TILE = {1, 1, 1, 0.0}        -- White selection (5% opacity)
}

-- UI Settings
Config.UI = {
    FONT_SIZE = 16,
    BUTTON_HEIGHT = 32,
    PANEL_PADDING = 8,
    SHOW_CORE_HEALTH = false
}

-- Game Settings
Config.GAME = {
    TARGET_FPS = 60,
    DEBUG_MODE = true,
    CORE_HEALTH = 10,
    SCREEN_HIT_MOVE_AMP = 4
}

-- UI: Enemy Health Bars
Config.ENEMY_HP_BAR = {
    WIDTH = 20,
    HEIGHT = 3,
    OFFSET_Y = -10, -- relative to enemy top center in pixels
    BG_COLOR = {0, 0, 0, 0.8},
    FG_COLOR = {0.6, 1, 0.3, 1}
}

-- Enemy Settings
Config.ENEMY = {
    SPEED_TILES_PER_SECOND = 0.9,  -- 70% slower (30% of original speed)
    SPAWN_INTERVAL = 2,          -- Seconds between spawns
    MAX_ACTIVE = 20,             -- Max enemies active at once
    DAMAGE_ON_HIT = 1,           -- Damage to core on hit
    DEFAULT_HP = 3,              -- Enemy starting HP
    KNOCKBACK_VELOCITY_PPS = 60, -- Knockback impulse (pixels per second)
    KNOCKBACK_DAMP = 8,          -- Velocity damping factor (per second)
    KNOCKBACK_RETURN_RATE = 1,   -- Offset return-to-rest rate (per second)
    KNOCKBACK_ROT_IMPULSE = 2    -- Rotational impulse scale per hit
}

-- Tower Settings
Config.TOWER = {
    SIZE_SCALE = 0.8,      -- Render scale relative to tile
    PLACEMENT_ALPHA = 0.9, -- Visual alpha when placed (if using placeholder)
    RANGE_TILES = 2,       -- Max targeting range in tiles
    FIRE_COOLDOWN = 0.8,   -- Seconds between shots
    PROJECTILE_SPEED_TPS = 10, -- Projectile speed (tiles per second)
    PROJECTILE_DAMAGE = 1,
    PROJECTILE_SCALE = 0.6, -- Visual scale of projectile sprite
    PROJECTILE_HIT_RADIUS_TILES = 0.35, -- Collision radius in tiles
    ROTATE_LERP = 12,      -- How quickly towers rotate toward target (higher = snappier)
    RECOIL_PIXELS = 6,     -- Backward offset (pixels) applied on fire
    RECOIL_RETURN_SPEED = 60, -- Pixels per second returning to rest
    FIRE_ALIGNMENT_DEG = 10,  -- Only fire when within this angle to target
    FIRE_ACQUIRE_DELAY = 0.25, -- Delay after acquiring a target before first shot
    SPAWN_ANIM = {
        DURATION = 0.35,      -- seconds for fade/slide/bounce-in
        SLIDE_PIXELS = 24,    -- start this many pixels above, slide into place
        BACK_S = 1.4          -- back overshoot strength (easeOutBack)
    },
    SPAWN_POOF = {
        NUM = 7,
        LIFE_MIN = 0.35,
        LIFE_MAX = 0.4,
        SPEED_MIN = 50,
        SPEED_MAX = 80,
        GRAVITY = 180,        -- pixels/sec^2 downward
        SIZE_MIN = 3,
        SIZE_MAX = 4,
        START_ALPHA = 0.35,
        END_ALPHA = 0         -- fade out to transparent
    },
    RANGE_INDICATOR = {
        DASH_DEG = 4,
        GAP_DEG = 4,
        LINE_WIDTH = 3,
        COLOR = {1, 1, 1, 0.5},
        FILL_ALPHA = 0.03,
        FILL_ENABLED = true,
        ROTATE_ENABLED = true,
        ROTATE_DEG_PER_SEC = 27,
        FADE_IN_SPEED = 8,
        FADE_OUT_SPEED = 6,
        BOUNCE_SCALE = 0.06,
        BOUNCE_DURATION = 0.25
    }
}

-- Deck / Card System Settings
Config.DECK = {
    HAND_SIZE = 5,
    ENERGY_PER_WAVE = 5,
    DISCARD_ON_WAVE_END = true,
    -- UI layout (logical coordinates)
    HAND_MARGIN = 12,
    CARD_WIDTH = 100,
    CARD_HEIGHT = 140,
    CARD_SPACING = 12,
    CARD_TEMPLATE_SCALE = 0.7,
    DRAG_CLAMP_Y = 540, -- when dragging a card upward, clamp its Y to this (higher value = sooner)
    CARD_LOCK_TWEEN_DURATION = 0.12,
    ARROW = {
        COLOR = {1, 1, 1, 0.85},
        WIDTH = 3,
        HEAD_SIZE = 10,
        CURVE_STRENGTH = 0.28, -- stronger curvature factor relative to distance
        FLIP_TWEEN_DURATION = 0.12 -- seconds to animate side flip
    }
}

return Config
