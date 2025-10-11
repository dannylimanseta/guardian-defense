-- cards.lua - Card definitions and starter deck

local cards = {}

cards.catalog = {
    crossbow_basic = {
        id = "crossbow_basic",
        name = "Crossbow turret",
        type = "place_tower",
        cost = 1, -- energy cost
        description = "Fires 1 arrow at the enemy.",
        level = 1,
        payload = {
            tower = "crossbow"
        }
    }
}

cards.starter_deck = {
    "crossbow_basic",
    "crossbow_basic",
    "crossbow_basic",
    "crossbow_basic",
    "crossbow_basic"
}

return cards


