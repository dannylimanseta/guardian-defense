-- DeckManager.lua - manages deck, draw/discard, hand, and energy per wave

local Config = require 'src/config/Config'
local CardsData = require 'src/data/cards'

local DeckManager = {}
DeckManager.__index = DeckManager

local function shallowCopy(tbl)
    local out = {}
    for i, v in ipairs(tbl) do out[i] = v end
    return out
end

local function shuffleInPlace(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

function DeckManager:new()
    local self = setmetatable({}, DeckManager)
    self.catalog = CardsData.catalog
    self.drawPile = {}
    self.discardPile = {}
    self.hand = {}
    self.energy = 0
    self.state = {
        draggingCardIndex = nil,
        draggingCardId = nil,
        isDragging = false
    }
    return self
end

function DeckManager:loadOrCreateDeck()
    -- Roguelite persistence: load if exists, else starter deck
    local saveName = 'deck_save.txt'
    if love.filesystem.getInfo(saveName) then
        local ok, contents = pcall(love.filesystem.read, saveName)
        if ok and type(contents) == 'string' then
            for id in contents:gmatch("[^\r\n]+") do
                if id and #id > 0 then
                    table.insert(self.drawPile, id)
                end
            end
        end
    end
    if #self.drawPile == 0 then
        self.drawPile = shallowCopy(CardsData.starter_deck)
    end
    shuffleInPlace(self.drawPile)
end

function DeckManager:saveDeck()
    -- Save current draw pile as newline-separated ids
    local saveName = 'deck_save.txt'
    local buf = {}
    for i = 1, #self.drawPile do
        buf[#buf+1] = self.drawPile[i]
    end
    local contents = table.concat(buf, "\n")
    love.filesystem.write(saveName, contents)
end

function DeckManager:startWave()
    self.energy = Config.DECK.ENERGY_PER_WAVE
    -- discard leftover hand if configured
    if Config.DECK.DISCARD_ON_WAVE_END and #self.hand > 0 then
        for i = 1, #self.hand do
            table.insert(self.discardPile, self.hand[i])
        end
        self.hand = {}
    end
    self:drawToHandSize()
end

function DeckManager:drawCards(n)
    for i = 1, n do
        if #self.drawPile == 0 and #self.discardPile > 0 then
            -- reshuffle discard into draw
            for j = 1, #self.discardPile do
                table.insert(self.drawPile, self.discardPile[j])
            end
            self.discardPile = {}
            shuffleInPlace(self.drawPile)
        end
        local id = table.remove(self.drawPile)
        if not id then return end
        table.insert(self.hand, id)
    end
end

function DeckManager:drawToHandSize()
    local target = Config.DECK.HAND_SIZE
    local need = math.max(0, target - #self.hand)
    if need > 0 then self:drawCards(need) end
end

function DeckManager:getCardDef(id)
    return self.catalog[id]
end

function DeckManager:getHand()
    return self.hand
end

function DeckManager:getCounts()
    return #self.drawPile, #self.discardPile
end

function DeckManager:getEnergy()
    return self.energy
end

function DeckManager:canPlayCard(cardId)
    local def = self:getCardDef(cardId)
    if not def then return false, 'invalid' end
    if (def.cost or 0) > (self.energy or 0) then return false, 'energy' end
    return true
end

function DeckManager:playCardFromHand(index)
    local id = self.hand[index]
    if not id then return nil, 'no_card' end
    local ok, reason = self:canPlayCard(id)
    if not ok then return nil, reason end
    table.remove(self.hand, index)
    local def = self:getCardDef(id)
    self.energy = math.max(0, (self.energy or 0) - (def.cost or 0))
    -- move to discard
    table.insert(self.discardPile, id)
    return def
end

function DeckManager:refundLastPlayed(cardId)
    -- simple refund path if placement fails
    if cardId then
        -- remove the last occurrence of cardId from discard and put back to hand front
        for i = #self.discardPile, 1, -1 do
            if self.discardPile[i] == cardId then
                table.remove(self.discardPile, i)
                table.insert(self.hand, 1, cardId)
                local def = self:getCardDef(cardId)
                self.energy = (self.energy or 0) + (def and def.cost or 0)
                break
            end
        end
    end
end

return DeckManager


