-- Config.lua - Central configuration for all game parameters
-- Single source of truth for easy playtesting and adjustments

local Config = {}

-- Window and Resolution Settings
Config.WINDOW_TITLE = "Guardian Defense"
Config.LOGICAL_WIDTH = 1440  -- Design resolution width
Config.LOGICAL_HEIGHT = 900  -- Design resolution height

-- Grid Map Settings
Config.GRID_WIDTH = 25       -- Number of tiles horizontally
Config.GRID_HEIGHT = 12      -- Number of tiles vertically
Config.TILE_SIZE = 70        -- Size of each tile in pixels
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
    HOVER_TILE = {1, 1, 1, 0.05},          -- White hover effect (5% opacity)
    SELECTED_TILE = {1, 1, 1, 0.0}        -- White selection (5% opacity)
}

-- UI Settings
Config.UI = {
    FONT_SIZE = 16,
    BUTTON_HEIGHT = 32,
    PANEL_PADDING = 8,
    SHOW_CORE_HEALTH = true,
    SHOW_CORE_HEALTH_ABOVE_CORE = false,
    COIN_TRACKER = {
        ICON = 'coin_1.png',
        MARGIN = 18,
        OFFSET_Y = 80,
        ICON_SCALE = 0.7,
        ICON_TEXT_SPACING = 12,
        FONT = 'BOLD_LARGE',
        COLOR = {1, 1, 1, 1},
        SHADOW_COLOR = {0, 0, 0, 0.6}
    },
    TOWER_MENU = {
        WIDTH = 220,
        ROW_HEIGHT = 44,
        PADDING = 12,
        CORNER_RADIUS = 18,
        GAP = 8,
        OFFSET_X = 40,
        OFFSET_Y = -30,
        ICON_SIZE = 28,
        ICON_TEXT_SPACING = 10,
        FADE_IN_DURATION = 0.18,
        FADE_IN_STAGGER = 0.06
    }
}

-- Game Settings
Config.GAME = {
    TARGET_FPS = 60,
    DEBUG_MODE = true,
    CORE_HEALTH = 5,
    SCREEN_HIT_MOVE_AMP = 4,
    COIN_DROP = {
        enemy_1 = { chance = 0.7, coins = 1 },
        enemy_2 = { chance = 0.7, coins = 2 },
        pickup = {
            travelTime = 0.9,
            travelTimeVariance = 0.25,
            arcHeight = -220,
            lateralJitter = 24,
            delayBetweenCoins = 0.08,
            startLift = -10
        }
    }
}

-- UI: Enemy Health Bars
Config.ENEMY_HP_BAR = {
    WIDTH = 20,
    HEIGHT = 3,
    OFFSET_Y = -10, -- relative to enemy top center in pixels
    BG_COLOR = {1, 1, 1, 0.18},
    FG_COLOR = {1, 1, 1, 1},
    CORNER_RADIUS = 3
}

-- Core Health Bar (minimal)
Config.CORE_HP_BAR = {
    WIDTH = 36,
    HEIGHT = 4,
    OFFSET_Y = -50, -- relative to core center in pixels (negative = above)
    BG_COLOR = {1, 1, 1, 0.2},
    FG_COLOR = {1, 1, 1, 1},
    CORNER_RADIUS = 2
}

-- Enemy Settings
Config.ENEMY = {
    SPEED_TILES_PER_SECOND = 0.9,  -- 70% slower (30% of original speed)
    SPAWN_INTERVAL = 2,          -- Seconds between spawns
    SPAWN_INTERVAL_MULTIPLIER = 1.8, -- Multiplies wave spawn spacing for more breathing room
    MAX_ACTIVE = 20,             -- Max enemies active at once
    DAMAGE_ON_HIT = 1,           -- Damage to core on hit
    DEFAULT_HP = 48,              -- Enemy starting HP (reduced 20%)
    KNOCKBACK_VELOCITY_PPS = 60, -- Knockback impulse (pixels per second)
    KNOCKBACK_DAMP = 8,          -- Velocity damping factor (per second)
    KNOCKBACK_RETURN_RATE = 1,   -- Offset return-to-rest rate (per second)
    KNOCKBACK_ROT_IMPULSE = 2,   -- Rotational impulse scale per hit
    -- Hit VFX
    HIT_FLASH_DURATION = 0.12,   -- seconds the white flash/bloom lasts
    HIT_GLOW_STRENGTH = 10,      -- moonshine glow blur strength (higher = blurrier)
    HIT_GLOW_MIN_LUMA = 0.0,     -- include all luma in glow threshold for strong bloom
    SPAWN_PATH_OFFSET = 0.24,    -- Initial fraction along the first path segment for spawned enemies
    SPAWN_PATH_OFFSET_JITTER = 0.1 -- Random variance applied to spawn path offset
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
    ENERGY_PER_WAVE = 10,
    DISCARD_ON_WAVE_END = true,
    -- UI layout (logical coordinates)
    HAND_MARGIN = 12,
    CARD_WIDTH = 100,
    CARD_HEIGHT = 140,
    CARD_SPACING = 12,
    CARD_TEMPLATE_SCALE = 0.7,
    CARD_ART_OFFSET_Y = 15,
    CARD_HIT_SCALE = 1.5,
    SHOW_CARD_BOUNDS = false,
    CARD_BOUNDS_SHRINK_FRAC = 1,
    CARD_BOUNDS_OFFSET_Y = 10,
    CARD_BOUNDS_LINE_WIDTH = 2,
    CARD_BOUNDS_COLOR = {1, 0.4, 0.2, 0.6},
    CARD_BOUNDS_LOCK_COLOR = {0.35, 0.78, 1, 0.65},
    -- Drag clamp: lock the card once cursor crosses this Y. Prefer fractional for resolution independence.
    -- If DRAG_CLAMP_Y_FRAC is set, it's used as fraction of LOGICAL_HEIGHT. Otherwise uses DRAG_CLAMP_Y pixels.
    DRAG_CLAMP_Y = 540,
    DRAG_CLAMP_Y_FRAC = 0.75,
    CARD_LOCK_TWEEN_DURATION = 0.12,
    DRAG_LOCK_SOFT_FOLLOW = {
        ENABLED = true,
        FACTOR_X = 0.1,
        FACTOR_Y = 0.06,
        MAX_OFFSET_X = 22,
        MAX_OFFSET_Y = 14
    },
    DRAG_TILT = {
        ENABLED = true,
        SENSITIVITY = 0.0035,
        MAX_SHEAR = 0.28,
        FOLLOW_SPEED = 14,
        SCALE_COMP = 0.12,
        ROTATION_SCALE = 0.65,
        MAX_ROT = 0.18,
        MIN_SCALE_Y = 0.78
    },
    ARROW = {
        COLOR = {1, 1, 1, 0.85},
        WIDTH = 3,
        HEAD_SIZE = 10,
        CURVE_STRENGTH = 0.28, -- stronger curvature factor relative to distance
        FLIP_TWEEN_DURATION = 0.12 -- seconds to animate side flip
    },
    -- Fan layout settings for the hand (Slay the Spire-style)
    FAN = {
        RADIUS = 520,              -- Base radius of the fan arc (pixels)
        MAX_SPREAD_DEG = 80,       -- Max total spread angle across the hand
        MIN_SPREAD_DEG = 16,       -- Minimum total spread when very few cards
        PER_CARD_SPREAD_DEG = 14,  -- Increment of spread per additional card
        ROTATION_SCALE = 1,        -- 1 = tangent to the arc, <1 reduces tilt
        BASELINE_OFFSET_Y = 32,    -- Offset (pixels) to nudge baseline up/down (shifted +20px)
        HOVER_LIFT = 22            -- How much a hovered/dragged card lifts visually
    }
}

-- Difficulty presets for waves/enemies
Config.DIFFICULTY_PRESETS = {
    easy = { count = 0.9, spawnSpeed = 0.95, hp = 0.9, speed = 0.95, reward = 1.0 },
    normal = { count = 1.0, spawnSpeed = 1.0, hp = 1.0, speed = 1.0, reward = 1.0 },
    hard = { count = 1.2, spawnSpeed = 1.1, hp = 1.15, speed = 1.05, reward = 1.1 }
}

-- Current difficulty selection
Config.CURRENT_DIFFICULTY = 'normal'

return Config
