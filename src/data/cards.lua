-- cards.lua - Card definitions and starter deck

local cards = {}

cards.catalog = {
    crossbow_basic = {
        id = "crossbow_basic",
        name = "Crossbow Tower",
        type = "place_tower",
        cost = 1, -- energy cost
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


