-- cards.lua - Card definitions and starter deck

local Config = require 'src/config/Config'

local cards = {}

cards.catalog = {
    crossbow_basic = {
        id = "crossbow_basic",
        name = "Crossbow turret",
        type = "place_tower",
        cost = 1, -- energy cost
        requiresTarget = true,
        description = "Fires 1 arrow at the enemy.",
        level = 1,
        payload = {
            tower = "crossbow"
        }
    },
    fire_basic = {
        id = "fire_basic",
        name = "Fire Tower",
        type = "place_tower",
        cost = 2,
        requiresTarget = true,
        description = "Applies burn. First tick hits instantly.",
        level = 1,
        payload = {
            tower = "fire"
        }
    },
    energy_shield = {
        id = "energy_shield",
        name = "Energy Shield",
        type = "apply_core_shield",
        cost = 1,
        requiresTarget = false,
        description = "For this wave only, conjure a temporary 3 HP energy shield for your Vigil Core.",
        level = 1,
        payload = {
            shieldHp = 3
        }
    },
    extended_reach = {
        id = "extended_reach",
        name = "Extended Reach",
        type = "modify_tower",
        cost = 1,
        requiresTarget = true,
        description = "Target tower: +10% range.",
        level = 1,
        payload = {
            modifiers = {
                rangePercent = Config.CARD_EFFECTS.RANGE_INCREASE.RANGE_PERCENT
            }
        }
    },
    bonechill_mist = {
        id = "bonechill_mist",
        name = "Bonechill Mist",
        type = "apply_path_effect",
        cost = 0,
        requiresTarget = true,
        description = "For this wave only, Slows enemies walking through the mist. Deals damage at higher levels.",
        level = 1,
        payload = {
            effect = "bonechill_mist",
            slowPercent = 0.20, -- 20% slow at L1
            slowTicks = 3,      -- lasts 3 ticks (stack/refresh like burn)
            damagePerTick = 0,  -- L1 no damage; future levels add damage
            tickInterval = 0.5  -- seconds per tick (mirrors burn cadence)
        }
    }
}

cards.starter_deck = {
    "crossbow_basic",
    "crossbow_basic",
    "crossbow_basic",
    "fire_basic",
    "fire_basic",
    "crossbow_basic",
    "extended_reach",
    "bonechill_mist",
    "bonechill_mist",
    "energy_shield"
}

-- no starter_hand_guarantees: all draws are random from the deck

return cards



