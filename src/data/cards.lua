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
        description = "Target tower: +10% range, -5% damage.",
        level = 1,
        payload = {
            modifiers = {
                rangePercent = Config.CARD_EFFECTS.RANGE_INCREASE.RANGE_PERCENT,
                damagePercent = Config.CARD_EFFECTS.RANGE_INCREASE.DAMAGE_PERCENT
            }
        }
    }
}

cards.starter_deck = {
    "crossbow_basic",
    "fire_basic",
    "fire_basic",
    "crossbow_basic",
    "crossbow_basic",
    "extended_reach"
}

cards.starter_hand_guarantees = {
    "crossbow_basic",
    "extended_reach"
}

return cards



