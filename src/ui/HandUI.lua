-- HandUI.lua - renders hand, drag-and-drop play interaction

local Config = require 'src/config/Config'
local Theme = require 'src/theme'

local HandUI = {}
HandUI.__index = HandUI

function HandUI:new(deckManager)
    local self = setmetatable({}, HandUI)
    self.deck = deckManager
    self.drag = {
        active = false,
        cardIndex = nil,
        cardId = nil,
        startX = 0,
        startY = 0,
        mx = 0,
        my = 0
    }
    return self
end

local function layoutHand()
    local w = Config.LOGICAL_WIDTH
    local h = Config.LOGICAL_HEIGHT
    local margin = Config.DECK.HAND_MARGIN
    local cw = Config.DECK.CARD_WIDTH
    local ch = Config.DECK.CARD_HEIGHT
    local spacing = Config.DECK.CARD_SPACING
    local y = h - ch - margin
    return w, h, margin, cw, ch, spacing, y
end

function HandUI:getCardRect(i, handCount)
    local w, _, margin, cw, ch, spacing, y = layoutHand()
    local totalWidth = handCount * cw + (handCount - 1) * spacing
    local startX = (w - totalWidth) / 2
    local x = startX + (i - 1) * (cw + spacing)
    return x, y, cw, ch
end

function HandUI:mousepressed(x, y, button)
    if button ~= 1 then return end
    local hand = self.deck:getHand()
    for i = #hand, 1, -1 do
        local x0, y0, cw, ch = self:getCardRect(i, #hand)
        if x >= x0 and x <= x0 + cw and y >= y0 and y <= y0 + ch then
            self.drag.active = true
            self.drag.cardIndex = i
            self.drag.cardId = hand[i]
            self.drag.startX = x
            self.drag.startY = y
            self.drag.mx = x
            self.drag.my = y
            return true
        end
    end
    return false
end

function HandUI:mousemoved(x, y, dx, dy)
    if self.drag.active then
        self.drag.mx = x
        self.drag.my = y
        return true
    end
    return false
end

function HandUI:mousereleased(x, y, button)
    if button ~= 1 then return false end
    if not self.drag.active then return false end
    local info = {
        played = false,
        cardId = self.drag.cardId,
        cardIndex = self.drag.cardIndex,
        dropX = x,
        dropY = y
    }
    self.drag.active = false
    return info
end

function HandUI:draw()
    local hand = self.deck:getHand()
    local energy = self.deck:getEnergy()
    local drawCount, discardCount = self.deck:getCounts()
    -- HUD counters
    local pad = 8
    local text = string.format("Energy: %d   Draw: %d   Discard: %d", energy, drawCount, discardCount)
    Theme.drawText(text, pad, Config.LOGICAL_HEIGHT - 24 - pad, Theme.FONTS.MEDIUM, Theme.COLORS.WHITE)

    -- Cards
    for i, id in ipairs(hand) do
        local def = self.deck:getCardDef(id)
        local x, y, cw, ch = self:getCardRect(i, #hand)
        local isDragging = self.drag.active and self.drag.cardIndex == i
        if isDragging then
            x = self.drag.mx - cw / 2
            y = self.drag.my - ch / 2
        end
        -- card background
        love.graphics.setColor(0.15, 0.15, 0.2, 0.95)
        love.graphics.rectangle('fill', x, y, cw, ch, 6, 6)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle('line', x, y, cw, ch, 6, 6)
        -- name and cost
        if def then
            Theme.drawText(def.name or id, x + 8, y + 8, Theme.FONTS.MEDIUM, Theme.COLORS.WHITE)
            Theme.drawText(tostring(def.cost or 0), x + cw - 20, y + 8, Theme.FONTS.MEDIUM, Theme.COLORS.SECONDARY)
        else
            Theme.drawText(id, x + 8, y + 8, Theme.FONTS.MEDIUM, Theme.COLORS.WHITE)
        end
    end

    -- Drag arrow when active
    if self.drag.active then
        love.graphics.setColor(1, 1, 1, 0.6)
        love.graphics.setLineWidth(2)
        love.graphics.line(self.drag.startX, self.drag.startY, self.drag.mx, self.drag.my)
        love.graphics.setLineWidth(1)
    end
end

return HandUI


