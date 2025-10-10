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
        anchorX = 0,
        anchorY = 0,
        mx = 0,
        my = 0,
        locked = false
    }
    self.arrowState = {
        side = 1, -- 1 or -1 for curve side
        tweenSide = 1,
        tweenT = 1,
        tweenDur = (Config.DECK.ARROW and Config.DECK.ARROW.FLIP_TWEEN_DURATION) or 0.1
    }
    self.cardTemplate = nil
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
            self.drag.anchorX = x0 + cw / 2
            self.drag.anchorY = y0 + ch / 2
            self.drag.mx = x
            self.drag.my = y
            self.drag.locked = false
            return true
        end
    end
    return false
end

function HandUI:mousemoved(x, y, dx, dy)
    if self.drag.active then
        self.drag.mx = x
        self.drag.my = y
        -- determine target side based on relative x position
        local targetSide = (x > (self.drag.anchorX ~= 0 and self.drag.anchorX or self.drag.startX)) and -1 or 1
        if targetSide ~= self.arrowState.side then
            -- start flip tween
            self.arrowState.side = targetSide
            self.arrowState.tweenT = 0
        end
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
            local targetX = self.drag.mx - cw / 2
            local targetY = self.drag.my - ch / 2
            local clampY = Config.DECK.DRAG_CLAMP_Y or (Config.LOGICAL_HEIGHT - Config.DECK.CARD_HEIGHT - Config.DECK.HAND_MARGIN - 60)
            if not self.drag.locked then
                if targetY < clampY then
                    -- lock card in place when crossing threshold the first time
                    self.drag.locked = true
                    self.drag.anchorX = targetX + cw / 2
                    self.drag.anchorY = clampY + ch / 2
                else
                    -- follow cursor below threshold
                    x = targetX
                    y = targetY
                    self.drag.anchorX = x + cw / 2
                    self.drag.anchorY = y + ch / 2
                end
            end
            -- if locked, keep card anchored at locked anchor
            if self.drag.locked then
                x = self.drag.anchorX - cw / 2
                y = self.drag.anchorY - ch / 2
            end
        end
        -- card background (image template if available)
        if not self.cardTemplate then
            local path = string.format('%s/%s', Config.ENTITIES_PATH, 'card_template_1.png')
            if love.filesystem.getInfo(path) then
                self.cardTemplate = love.graphics.newImage(path)
                self.cardTemplate:setFilter('nearest', 'nearest')
            end
        end
        if self.cardTemplate then
            love.graphics.setColor(1, 1, 1, 1)
            local iw = self.cardTemplate:getWidth()
            local ih = self.cardTemplate:getHeight()
            local sx = cw / iw
            local sy = ch / ih
            love.graphics.draw(self.cardTemplate, x, y, 0, sx, sy)
        else
            love.graphics.setColor(0.15, 0.15, 0.2, 0.95)
            love.graphics.rectangle('fill', x, y, cw, ch, 6, 6)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.rectangle('line', x, y, cw, ch, 6, 6)
        end
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
        local arrow = Config.DECK.ARROW or {}
        local color = arrow.COLOR or {1,1,1,0.85}
        local width = arrow.WIDTH or 3
        local head = arrow.HEAD_SIZE or 10
        local curveK = arrow.CURVE_STRENGTH or 0.2
        local ax = self.drag.anchorX ~= 0 and self.drag.anchorX or self.drag.startX
        local ay = self.drag.anchorY ~= 0 and self.drag.anchorY or self.drag.startY
        local bx = self.drag.mx
        local by = self.drag.my

        -- Quadratic Bezier from A to B with control offset to create an upward bow
        local dx = bx - ax
        local dy = by - ay
        local dist = math.sqrt(dx*dx + dy*dy)
        local nx = dx / (dist > 0 and dist or 1)
        local ny = dy / (dist > 0 and dist or 1)
        -- perpendicular vector for curvature
        local px = -ny
        local py = nx
        -- Flip curvature side with tweening
        -- Compute current tweened sign between previous and target side
        local targetSign = ((bx > ax) and -1 or 1)
        local t = math.min(1, self.arrowState.tweenT or 1)
        -- ease function (smoothstep)
        local u = t * t * (3 - 2 * t)
        local sign = ((self.arrowState.side == -1) and (-1) or 1)
        if self.arrowState.tweenT and self.arrowState.tweenT < 1 then
            -- blend from -sign to sign
            local from = -sign
            local to = sign
            local blend = from * (1 - u) + to * u
            sign = blend
        end
        local cx = ax + dx * 0.5 + px * (dist * curveK * sign)
        local cy = ay + dy * 0.5 + py * (dist * curveK * sign)

        love.graphics.setColor(color)
        love.graphics.setLineWidth(width)
        -- Render a smooth quadratic Bezier curve (A -> control -> B) without love.math dependency
        local segments = 28
        local points = {}
        local prevX, prevY = ax, ay
        for i = 0, segments do
            local t = i / segments
            local omt = 1 - t
            local xq = omt*omt*ax + 2*omt*t*cx + t*t*bx
            local yq = omt*omt*ay + 2*omt*t*cy + t*t*by
            points[#points+1] = xq
            points[#points+1] = yq
            prevX, prevY = xq, yq
        end
        love.graphics.line(points)

        -- No arrow head (fork) at the end; restore default line width
        love.graphics.setLineWidth(1)
    end
    -- Reset color to avoid tinting subsequent draws
    love.graphics.setColor(1, 1, 1, 1)
end

function HandUI:update(dt)
    -- advance flip tween if active
    if self.arrowState and self.arrowState.tweenT and self.arrowState.tweenT < 1 then
        local dur = self.arrowState.tweenDur or 0.1
        if dur <= 0 then
            self.arrowState.tweenT = 1
        else
            self.arrowState.tweenT = math.min(1, self.arrowState.tweenT + dt / dur)
        end
    end
end

return HandUI


