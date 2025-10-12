-- HandUI.lua - renders hand, drag-and-drop play interaction

local Config = require 'src/config/Config'
local Theme = require 'src/theme'

local HandUI = {}
HandUI.__index = HandUI

local FX_CARD_GLOW_PATH = 'assets/images/effects/fx_card_glow.png'

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
        prevMX = 0,
        prevMY = 0,
        locked = false,
        lockTweenT = 1,
        lockStartX = 0,
        lockStartY = 0,
        lockTargetX = 0,
        lockTargetY = 0,
        lockTweenDur = (Config.DECK and Config.DECK.CARD_LOCK_TWEEN_DURATION) or 0.12,
        -- smooth follow to avoid snap on drag start
        smoothX = nil,
        smoothY = nil,
        followSpeed = 16,
        tiltShear = 0,
        tiltRot = 0,
        tiltTargetShear = 0,
        tiltTargetRot = 0,
        tiltScaleY = 1,
        tiltTargetScaleY = 1
    }
    self.arrowState = {
        side = 1, -- 1 or -1 for curve side
        tweenSide = 1,
        tweenT = 1,
        tweenDur = (Config.DECK.ARROW and Config.DECK.ARROW.FLIP_TWEEN_DURATION) or 0.1
    }
    self.cardTemplate = nil
    self.hoverIndex = nil
    self.mouseX, self.mouseY = 0, 0
    -- layout tweening and play-out animation state
    self.cardStates = {} -- [key] = { x,y,rot, fromX,fromY,fromRot, toX,toY,toRot, t, dur, alpha }
    self.playAnimations = {} -- [key] = { id, startX,startY,rot, t, dur, slide }
    self.layoutTweenDur = 0.42
    self.layoutEase = 'smootherstep'
    self.lastHandIds = {}
    self.handKeys = {}
    self.indexToKey = {}
    self.nextKeyId = 1
    self.fxCardGlow = nil
    self.fxCardGlowWarned = false
    self.time = 0
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

local function easeValue(u, mode)
    if mode == 'smoothstep' then
        return u * u * (3 - 2 * u)
    elseif mode == 'smootherstep' then
        return u * u * u * (u * (u * 6 - 15) + 10)
    end
    return u
end

local function shallowCopyList(src)
    local out = {}
    for i = 1, #src do out[i] = src[i] end
    return out
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function resetDragTilt(self)
    if not self or not self.drag then return end
    if self.drag then
        self.drag.tiltTargetShear = 0
        self.drag.tiltTargetRot = 0
        self.drag.tiltTargetScaleY = 1
        self.drag.tiltShear = 0
        self.drag.tiltRot = 0
        self.drag.tiltScaleY = 1
    end
end

-- Simple word-wrapping helper returning a list of lines that fit within maxWidth
local function wrapText(font, text, maxWidth)
    local lines = {}
    local current = ""
    for token in tostring(text):gmatch("[^\n]+\n?" ) do
        local chunk = token
        if chunk:sub(-1) == "\n" then
            chunk = chunk:sub(1, -2)
            -- flush existing line before explicit newline
            local words = {}
            for w in chunk:gmatch("%S+") do words[#words+1] = w end
            for i = 1, #words do
                local trial = (current ~= "" and (current .. " " .. words[i]) or words[i])
                if font:getWidth(trial) <= maxWidth then
                    current = trial
                else
                    if current ~= "" then lines[#lines+1] = current end
                    current = words[i]
                end
            end
            lines[#lines+1] = current
            current = ""
        else
            local words = {}
            for w in chunk:gmatch("%S+") do words[#words+1] = w end
            for i = 1, #words do
                local trial = (current ~= "" and (current .. " " .. words[i]) or words[i])
                if font:getWidth(trial) <= maxWidth then
                    current = trial
                else
                    if current ~= "" then lines[#lines+1] = current end
                    current = words[i]
                end
            end
        end
    end
    if current ~= "" then lines[#lines+1] = current end
    if #lines == 0 then lines[1] = "" end
    return lines
end

-- Cache for card art images by card id
local cardArtCache = {}

local function loadCardArtForId(cardId)
	if not cardId then return nil end
	if cardArtCache[cardId] ~= nil then return cardArtCache[cardId] end
	local artName
	-- Simple mapping: any card id containing 'crossbow' uses card_crossbow.png
	if tostring(cardId):find('crossbow', 1, true) then
		artName = 'card_crossbow.png'
	end
	-- Fire tower card art mapping
	if not artName and tostring(cardId):find('fire', 1, true) then
		artName = 'card_fire.png'
	end
	-- Extended reach card art mapping
	if not artName and tostring(cardId):find('extended_reach', 1, true) then
		artName = 'card_extended_reach.png'
	end
    -- Energy Shield art (id or alias)
    if not artName and (tostring(cardId):find('energy_shield', 1, true) or tostring(cardId):find('energy_sheild', 1, true)) then
        artName = 'card_energy_shield.png'
    end
    if not artName then
		cardArtCache[cardId] = false
		return nil
	end
	-- Candidate paths to try
	local candidates = {
		string.format('%s/%s', Config.ENTITIES_PATH, 'cards/' .. artName),
		'assets/images/cards/' .. artName,
		string.format('%s/%s', Config.ENTITIES_PATH, artName)
	}
	for i = 1, #candidates do
		local path = candidates[i]
        if love.filesystem.getInfo(path) then
            local img = love.graphics.newImage(path)
            cardArtCache[cardId] = img
            return img
		end
	end
	cardArtCache[cardId] = false
	return nil
end

local function ensureCardGlow(self)
	if self.fxCardGlow == false then return nil end
	if not self.fxCardGlow then
		local ok, img = pcall(love.graphics.newImage, FX_CARD_GLOW_PATH)
        if ok and img then
            self.fxCardGlow = img
		else
			self.fxCardGlow = false
			return nil
		end
	end
	return self.fxCardGlow
end

local function computeDragGlow(self, def, cardIndex, cw, ch)
	if not self.drag or not self.drag.active then return nil end
	if self.drag.cardIndex ~= cardIndex then return nil end
	if self.drag.locked ~= true then return nil end
	if def and def.requiresTarget ~= false then return nil end
	local glowImg = ensureCardGlow(self)
	if not glowImg then return nil end
	local pulseSpeed = (Config.DECK and Config.DECK.GLOW_PULSE_SPEED) or 4.2
	local baseAlpha = (Config.DECK and Config.DECK.GLOW_ALPHA_BASE) or 0.85
	local pulseAlpha = (Config.DECK and Config.DECK.GLOW_ALPHA_PULSE) or 0.35
	local pulse = math.sin((self.time or 0) * pulseSpeed)
	local alpha = baseAlpha + pulseAlpha * ((pulse + 1) * 0.5)
	local widthScale = (Config.DECK and Config.DECK.GLOW_WIDTH_SCALE) or 1.8
	local heightScale = (Config.DECK and Config.DECK.GLOW_HEIGHT_SCALE) or 1.55
	local gw, gh = glowImg:getWidth(), glowImg:getHeight()
	local targetW = cw * widthScale
	local targetH = ch * heightScale
	local scale = math.min(targetW / gw, targetH / gh)
	local glowColor = (Config.DECK and Config.DECK.GLOW_COLOR) or {0.35, 0.78, 1.0}
	return glowImg, alpha, scale, glowColor
end

-- Shared cardface text render to keep dragged and undragged layouts identical
local function drawCardFaceText(def, id, halfW, topY, baseHalfH)
	if not def then
		Theme.drawText(id or '', -halfW + 16, topY + 8 + 20 - 15, Theme.FONTS.MEDIUM, Theme.COLORS.WHITE)
		return
	end
	-- energy cost number at top-right inside the card (based on actual drawn bounds)
	local costStr = tostring(def.cost or 0)
	local costFont = Theme.FONTS.BOLD_LARGE
	love.graphics.setFont(costFont)
	love.graphics.setColor(Theme.COLORS.WHITE)
	local costW = costFont:getWidth(costStr)
	local costX = -halfW + 22
	local costY = topY - 5
	love.graphics.print(costStr, costX, costY)

	-- Optional card art centered in the top half
	local art = loadCardArtForId(def.id or id)
	if art then
		love.graphics.setColor(1, 1, 1, 1)
		local iw, ih = art:getWidth(), art:getHeight()
		local maxW = halfW * 2 - 40
		local maxH = (baseHalfH or (halfW)) - 20
		local fitScale = math.min(maxW / iw, maxH / ih)
		local scale = math.min(fitScale * 1.07, 1)
		local centerY = topY + (baseHalfH and (baseHalfH * 0.5) or (maxH * 0.5))
		local drawX = - (iw * scale) * 0.5
		local offsetY = (Config.DECK and Config.DECK.CARD_ART_OFFSET_Y) or 0
		local drawY = centerY - (ih * scale) * 0.5 - 14 + offsetY
		love.graphics.draw(art, drawX, drawY, 0, scale, scale)
	end

	-- content block (left aligned)
	local SHIFT_DOWN = 20
	local leftX = -halfW + 16
	local titleY = topY + 8 + SHIFT_DOWN - 15 - 20
	Theme.drawText(def.name or id, leftX + 40, titleY + 6, Theme.FONTS.BOLD_MEDIUM, Theme.COLORS.WHITE)
	-- LV label below name (smaller, bold)
	if def.level then
		local lvY = titleY + Theme.FONTS.BOLD_LARGE:getHeight() + 12
		Theme.drawText(string.format('LV %d', def.level), leftX + 2, lvY + 3, Theme.FONTS.BOLD_SMALL, Theme.COLORS.WHITE)
		-- description below LV
		if def.description and #def.description > 0 then
			local descY = lvY + Theme.FONTS.SMALL:getHeight() + 6 + 110
			local font = Theme.FONTS.MEDIUM
			love.graphics.setFont(font)
			love.graphics.setColor(Theme.COLORS.WHITE)
			local wrapW = halfW * 2 - 32
			local lines = wrapText(font, def.description, wrapW)
			local lh = font:getHeight() * 0.9
			for li = 1, #lines do
				love.graphics.print(lines[li], leftX, descY + (li - 1) * lh)
			end
		end
	end
end

local function buildIdQueues(ids)
    local q = {}
    for i = 1, #ids do
        local id = ids[i]
        local list = q[id]
        if not list then list = {}; q[id] = list end
        list[#list+1] = i
    end
    return q
end

function HandUI:reconcileHandKeys(oldIds, oldKeys, newIds)
    local newKeys = {}
    local queues = buildIdQueues(oldIds)
    for j = 1, #newIds do
        local id = newIds[j]
        local list = queues[id]
        if list and #list > 0 then
            local oldIndex = table.remove(list, 1)
            newKeys[j] = oldKeys[oldIndex]
        else
            newKeys[j] = self.nextKeyId
            self.nextKeyId = self.nextKeyId + 1
        end
    end
    return newKeys
end

function HandUI:startLayoutTween()
    local hand = self.deck:getHand()
    local n = #hand
    -- build/align stable keys for duplicates
    self.handKeys = self:reconcileHandKeys(self.lastHandIds, self.handKeys, hand)
    -- Prepare target transforms per key
    for i = 1, n do
        local key = self.handKeys[i]
        self.indexToKey[i] = key
        local isHovered = (not self.drag.active) and (self.hoverIndex == i)
        local cx, cy, rot = self:getCardTransform(i, n, isHovered)
        local st = self.cardStates[key] or {}
        st.fromX = st.x or cx
        st.fromY = st.y or cy
        st.fromRot = st.rot or rot
        st.toX = cx
        st.toY = cy
        st.toRot = rot
        st.t = 0
        st.dur = self.layoutTweenDur or 0.2
        st.x = st.fromX
        st.y = st.fromY
        st.rot = st.fromRot
        st.alpha = 1
        self.cardStates[key] = st
    end
    self.lastHandIds = shallowCopyList(hand)
end

function HandUI:computeFanLayout(handCount, cw, ch, fanCfg, screenWidth)
	local count = handCount or 0
	local minSpread = fanCfg.minSpreadDeg or 0
	local maxSpread = fanCfg.maxSpreadDeg or minSpread
	local perCard = fanCfg.perCardSpreadDeg or 0
	local spreadDeg = 0
	if count > 1 then
		spreadDeg = minSpread + (count - 2) * perCard
		if spreadDeg < minSpread then spreadDeg = minSpread end
		if spreadDeg > maxSpread then spreadDeg = maxSpread end
	end
	local baseRadius = fanCfg.radius or fanCfg.maxRadius or fanCfg.minRadius or 520
	local minRadius = fanCfg.minRadius or baseRadius
	local maxRadius = fanCfg.maxRadius or baseRadius
	local radius = math.max(minRadius, math.min(maxRadius, baseRadius))
	if count <= 1 then
		return spreadDeg, radius
	end
	local halfCardW = cw * 0.5 + (fanCfg.extraWidthPadding or 0)
	local halfCardH = ch * 0.5 + (fanCfg.extraHeightPadding or 0)
	local guard = fanCfg.edgeGuard or 0
	local usableWidth = math.max(0, (screenWidth or (Config.LOGICAL_WIDTH)) - guard * 2)

	local function estimateWidth(currentSpread, currentRadius)
		local minX = math.huge
		local maxX = -math.huge
		for i = 1, count do
			local t = (i - 1) / (count - 1)
			local angleDeg = -currentSpread * 0.5 + t * currentSpread
			local a = math.rad(angleDeg)
			local sinA = math.sin(a)
			local cosA = math.cos(a)
			local center = currentRadius * sinA
			local projected = math.abs(halfCardW * cosA) + math.abs(halfCardH * sinA)
			local left = center - projected
			local right = center + projected
			if left < minX then minX = left end
			if right > maxX then maxX = right end
		end
		if minX == math.huge then
			return 0
		end
		return maxX - minX
	end

	local width = estimateWidth(spreadDeg, radius)
	if usableWidth > 0 and width > usableWidth then
		local ratio = usableWidth / width
		local targetRadius = radius * ratio
		if targetRadius < radius then
			radius = math.max(minRadius, targetRadius)
			width = estimateWidth(spreadDeg, radius)
		end
	end

	if usableWidth > 0 and width > usableWidth then
		local ratio = usableWidth / width
		local targetSpread = spreadDeg * ratio
		if targetSpread < spreadDeg then
			spreadDeg = math.max(minSpread, targetSpread)
			width = estimateWidth(spreadDeg, radius)
		end
	end

	local attempts = 0
	while usableWidth > 0 and width > usableWidth and attempts < 8 do
		attempts = attempts + 1
		if radius > minRadius then
			radius = math.max(minRadius, radius - 6)
		end
		if spreadDeg > minSpread then
			spreadDeg = math.max(minSpread, spreadDeg - 3)
		end
		width = estimateWidth(spreadDeg, radius)
		if radius == minRadius and spreadDeg == minSpread then
			break
		end
	end

	return spreadDeg, radius
end

local function fanParams()
	local fan = (Config.DECK and Config.DECK.FAN) or {}
	return {
		radius = fan.RADIUS or 520,
		minRadius = fan.MIN_RADIUS or fan.RADIUS or 520,
		maxRadius = fan.MAX_RADIUS or fan.RADIUS or 520,
		edgeGuard = fan.EDGE_GUARD or 48,
		extraWidthPadding = fan.EXTRA_WIDTH_PADDING or 0,
		extraHeightPadding = fan.EXTRA_HEIGHT_PADDING or 0,
		maxSpreadDeg = fan.MAX_SPREAD_DEG or 80,
		minSpreadDeg = fan.MIN_SPREAD_DEG or 16,
		perCardSpreadDeg = fan.PER_CARD_SPREAD_DEG or 14,
		rotationScale = fan.ROTATION_SCALE or 1,
		baselineOffsetY = fan.BASELINE_OFFSET_Y or -8,
		hoverLift = fan.HOVER_LIFT or 22
	}
end

function HandUI:getCardTransform(i, handCount, isHovered)
	local w = Config.LOGICAL_WIDTH
	local h = Config.LOGICAL_HEIGHT
	local cw = Config.DECK.CARD_WIDTH
	local ch = Config.DECK.CARD_HEIGHT
	local margin = Config.DECK.HAND_MARGIN
	local fanCfg = fanParams()
	local centerX = w * 0.5
	local baselineY = h - margin - ch * 0.5 + (fanCfg.baselineOffsetY or 0)
	local spreadDeg, radius = self:computeFanLayout(handCount, cw, ch, fanCfg, w)
	local angleDeg = 0
	if handCount and handCount > 1 then
		local t = (i - 1) / (handCount - 1)
		angleDeg = -spreadDeg * 0.5 + t * spreadDeg
	end
	local a = math.rad(angleDeg)
	local circleCX = centerX
	local circleCY = baselineY + radius
	local cx = circleCX + radius * math.sin(a)
	local cy = circleCY - radius * math.cos(a)
	if isHovered then
		cy = cy - (fanCfg.hoverLift or 0)
	end
	local rot = a * (fanCfg.rotationScale or 1)
	return cx, cy, rot, cw, ch
end

local function getDrawOrder(handCount, preferLeftmostTop)
    local order = {}
    -- When not dragging (preferLeftmostTop), draw from left to right so rightmost ends up on top
    if preferLeftmostTop then
        for i = 1, handCount do order[#order+1] = i end
        return order
    end
    -- default behavior: draw edges first, center last
    for i = 1, handCount do order[i] = i end
    table.sort(order, function(a, b)
        local center = (handCount + 1) * 0.5
        local da = math.abs(a - center)
        local db = math.abs(b - center)
        if da == db then
            return a < b
        end
        return da > db
    end)
    return order
end

function HandUI:getCardRect(i, handCount)
	local cx, cy, _, cw, ch = self:getCardTransform(i, handCount, (self.hoverIndex == i))
	local x = cx - cw * 0.5
	local y = cy - ch * 0.5
	return x, y, cw, ch
end

-- Point-in-oriented-rect test in card-local space
local function pointInOBB(px, py, cx, cy, rot, halfW, halfH)
    local dx = px - cx
    local dy = py - cy
    local cosr = math.cos(rot)
    local sinr = math.sin(rot)
    -- rotate by -rot
    local lx = dx * cosr + dy * sinr
    local ly = -dx * sinr + dy * cosr
    return math.abs(lx) <= halfW and math.abs(ly) <= halfH
end

function HandUI:getCardHitSize()
    local cw = Config.DECK.CARD_WIDTH
    local ch = Config.DECK.CARD_HEIGHT
    local vw, vh = cw, ch
    local scale = Config.DECK.CARD_TEMPLATE_SCALE or 0.7
    if not self.cardTemplate then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'card_template_1.png')
        if love.filesystem.getInfo(path) then
            self.cardTemplate = love.graphics.newImage(path)
        end
    end
    if self.cardTemplate then
        local iw = self.cardTemplate:getWidth()
        local ih = self.cardTemplate:getHeight()
        vw = math.max(cw, iw * scale)
        vh = math.max(ch, ih * scale)
    end
    local hitScale = (Config.DECK.CARD_HIT_SCALE or 1)
    return vw * hitScale, vh * hitScale
end

function HandUI:mousepressed(x, y, button)
    if button ~= 1 then return end
    local hand = self.deck:getHand()
	local n = #hand
	local order = getDrawOrder(n)
    for k = #order, 1, -1 do
        local i = order[k]
        local cx, cy, rot, cw, ch = self:getCardTransform(i, n, (self.hoverIndex == i))
        local wHit, hHit = (self:getCardHitSize())
        -- swap to match sprite orientation
        local hw = ((hHit or ch)) * 0.5
        local hh = ((wHit or cw)) * 0.5
        -- oriented hit test in card-local space
        if pointInOBB(x, y, cx, cy, rot, hw, hh) then
			self.drag.active = true
			self.drag.cardIndex = i
			self.drag.cardId = hand[i]
			self.drag.startX = x
			self.drag.startY = y
            self.drag.anchorX = cx
            self.drag.anchorY = cy
            self.drag.mx = x
            self.drag.my = y
            self.drag.prevMX = x
            self.drag.prevMY = y
            resetDragTilt(self)
            -- initialize smooth follower at current card center
            self.drag.smoothX = cx
            self.drag.smoothY = cy
			self.drag.locked = false
			self.hoverIndex = i
			return true
		end
	end
    return false
end

function HandUI:mousemoved(x, y, dx, dy)
	self.mouseX, self.mouseY = x, y
	if self.drag.active then
		self.drag.prevMX = self.drag.mx
		self.drag.prevMY = self.drag.my
		self.drag.mx = x
		self.drag.my = y
		local def = self.deck:getCardDef(self.drag.cardId)
        local dt = (love.timer and love.timer.getDelta and love.timer.getDelta()) or 0
        local tiltCfg = Config.DECK.DRAG_TILT or {}
        if tiltCfg.ENABLED ~= false then
            local dx = (self.drag.mx - self.drag.prevMX)
            local sensitivity = tiltCfg.SENSITIVITY or 0.0035
            local rotScale = tiltCfg.ROTATION_SCALE or 0.65
            local maxShear = tiltCfg.MAX_SHEAR or 0.28
            local targetShear = clamp(dx * sensitivity, -maxShear, maxShear)
            local maxRot = (tiltCfg.MAX_ROT or maxShear) or maxShear
            local targetRot = clamp(dx * sensitivity * rotScale, -maxRot, maxRot)
            self.drag.tiltTargetShear = targetShear
            self.drag.tiltTargetRot = targetRot
            local minScaleY = tiltCfg.MIN_SCALE_Y or 0.78
            local scaleComp = tiltCfg.SCALE_COMP or 0.12
            local targetScaleY = clamp(1 - math.abs(targetShear) * scaleComp, minScaleY, 1)
            self.drag.tiltTargetScaleY = targetScaleY
            local follow = tiltCfg.FOLLOW_SPEED or 14
            local lerp = dt > 0 and math.min(1, follow * dt) or 1
            self.drag.tiltShear = self.drag.tiltShear + (self.drag.tiltTargetShear - self.drag.tiltShear) * lerp
            self.drag.tiltRot = self.drag.tiltRot + (self.drag.tiltTargetRot - self.drag.tiltRot) * lerp
            self.drag.tiltScaleY = self.drag.tiltScaleY + (self.drag.tiltTargetScaleY - self.drag.tiltScaleY) * lerp
        end
        local isTargeting = not def or (def.requiresTarget ~= false)
        if isTargeting then
            -- determine target side based on relative x position
            local targetSide = (x > (self.drag.anchorX ~= 0 and self.drag.anchorX or self.drag.startX)) and -1 or 1
            if targetSide ~= self.arrowState.side then
                -- start flip tween
                self.arrowState.side = targetSide
                self.arrowState.tweenT = 0
            end
        end
        return true
    end
	-- update hover when not dragging (top-most hit wins)
    local hand = self.deck:getHand()
    local n = #hand
    local order = getDrawOrder(n, true)
    self.hoverIndex = nil
    for k = #order, 1, -1 do
        local i = order[k]
        local cx, cy, rot, cw, ch = self:getCardTransform(i, n, false)
        local wHit, hHit = (self:getCardHitSize())
        local hw = ((hHit or ch)) * 0.5
        local hh = ((wHit or cw)) * 0.5
		if pointInOBB(x, y, cx, cy, rot, hw, hh) then
			-- Only show hover if the card is currently playable (eligible interactivity)
			local canPlay = self.deck:canPlayCard(hand[i])
			if canPlay then
				self.hoverIndex = i
				break
			end
		end
    end
	return self.hoverIndex ~= nil
end

function HandUI:mousereleased(x, y, button)
    if button ~= 1 then return false end
    if not self.drag.active then return false end
    local def = self.deck:getCardDef(self.drag.cardId)
    local isTargeting = not def or (def.requiresTarget ~= false)
    -- enforce threshold: for non-targeting, only return play info if above clamp
    if not isTargeting then
        local clampY
        if Config.DECK.DRAG_CLAMP_Y_FRAC and type(Config.DECK.DRAG_CLAMP_Y_FRAC) == 'number' then
            clampY = (Config.DECK.DRAG_CLAMP_Y_FRAC) * (Config.LOGICAL_HEIGHT)
        else
            clampY = Config.DECK.DRAG_CLAMP_Y or (Config.LOGICAL_HEIGHT - Config.DECK.CARD_HEIGHT - Config.DECK.HAND_MARGIN - 60)
        end
        if (self.drag.my or y) < clampY then
            -- allowed: above threshold
        else
            -- below threshold: cancel
            resetDragTilt(self)
            self.drag.active = false
            return false
        end
    end
    local startX = nil
    local startY = nil
    if self.drag.smoothX and self.drag.smoothY then
        startX = self.drag.smoothX
        startY = self.drag.smoothY
    else
        local idx = self.drag.cardIndex
        if idx then
            local key = self.indexToKey[idx]
            local st = key and self.cardStates[key] or nil
            if st and st.x and st.y then
                startX, startY = st.x, st.y
            else
                local n = #self.deck:getHand()
                startX, startY = self:getCardTransform(idx, n, false)
            end
        end
    end
    if not isTargeting then
        startX = startX or x
        startY = startY or y
    else
        local idx = self.drag.cardIndex
        if idx then
            local key = self.indexToKey[idx]
            if key and self.cardStates[key] then
                local st = self.cardStates[key]
                if st.x and st.y then
                    startX = st.x
                    startY = st.y
                end
            end
        end
        startX = startX or x
        startY = startY or y
    end
    local info = {
        played = false,
        cardId = self.drag.cardId,
        cardIndex = self.drag.cardIndex,
        dropX = x,
        dropY = y,
        startX = startX,
        startY = startY
    }
    resetDragTilt(self)
    self.drag.active = false
    return info
end

function HandUI:onCardPlayed(index, cardId, startXOverride, startYOverride)
    local key = self.indexToKey[index]
    local st = key and self.cardStates[key] or nil
    local startX, startY, rot
    if startXOverride ~= nil and startYOverride ~= nil then
        startX = startXOverride
        startY = startYOverride
    else
        if st and st.x and st.y and st.rot then
            startX, startY, rot = st.x, st.y, st.rot
        else
            -- fallback to immediate transform if state not captured yet
            local n = #self.deck:getHand()
            startX, startY, rot = self:getCardTransform(index, n, false)
        end
    end
    rot = 0 -- keep non-target animation upright
    local anim = {
        id = cardId,
        startX = startX or 0,
        startY = startY or 0,
        rot = rot or 0,
        t = 0,
        dur = 0.18,
        slide = 60
    }
    if key then
        self.playAnimations[key] = anim
        -- remove persistent layout state for this key so it doesn't affect remaining tween
        self.cardStates[key] = nil
    else
        -- if we don't have a key, store with a synthetic one
        self.playAnimations['temp_' .. tostring(cardId) .. '_' .. tostring(love.timer.getTime())] = anim
    end
end

function HandUI:draw()
    local hand = self.deck:getHand()
    local energy = self.deck:getEnergy()
    local drawCount, discardCount = self.deck:getCounts()
    -- HUD counters
    local pad = 8
    local text = string.format("Energy: %d   Draw: %d   Discard: %d", energy, drawCount, discardCount)
    Theme.drawText(text, pad, Config.LOGICAL_HEIGHT - 24 - pad, Theme.FONTS.MEDIUM, Theme.COLORS.WHITE)

    -- Cards (fan layout)
    local n = #hand
    local order = getDrawOrder(n, true)
	local draggingIndex = (self.drag.active and self.drag.cardIndex) or nil
	local hoveredIndex = (not self.drag.active) and self.hoverIndex or nil

	local function drawCardAt(i, id, isHovered)
        local def = self.deck:getCardDef(id)
        local key = self.indexToKey[i]
        local st = key and self.cardStates[key] or nil
        local cx, cy, rot
        if st and st.x and st.y and st.rot then
            cx, cy, rot = st.x, st.y, st.rot
        else
            cx, cy, rot = self:getCardTransform(i, n, isHovered)
        end
        -- Apply hover lift visually even when using stored state
        if isHovered then
            local fan = (Config.DECK and Config.DECK.FAN) or {}
            local lift = fan.HOVER_LIFT or 22
            cy = cy - lift
        end
		local cw, ch = Config.DECK.CARD_WIDTH, Config.DECK.CARD_HEIGHT
		-- lazy-load template
        if not self.cardTemplate then
            local path = string.format('%s/%s', Config.ENTITIES_PATH, 'card_template_1.png')
            if love.filesystem.getInfo(path) then
                self.cardTemplate = love.graphics.newImage(path)
            end
        end
		love.graphics.push()
        love.graphics.translate(cx, cy)
        if rot ~= 0 then
            love.graphics.rotate(rot)
        end
        local cw2, ch2 = cw * 0.5, ch * 0.5

        local glowImg, glowAlpha, glowScale = computeDragGlow(self, def, i, cw, ch)
        if glowImg then
            local gw, gh = glowImg:getWidth(), glowImg:getHeight()
            love.graphics.setBlendMode('add')
            love.graphics.setColor(1, 1, 1, glowAlpha)
            love.graphics.draw(glowImg, 0, 0, 0, glowScale, glowScale, gw * 0.5, gh * 0.5)
            love.graphics.setBlendMode('alpha')
            love.graphics.setColor(1, 1, 1, 1)
        end

        -- card background / template
        if self.cardTemplate then
            love.graphics.setColor(1, 1, 1, 1)
            local iw = self.cardTemplate:getWidth()
            local ih = self.cardTemplate:getHeight()
            local scale = Config.DECK.CARD_TEMPLATE_SCALE or 0.7
            local drawX = -cw2 + (cw - iw * scale) / 2
            local drawY = -ch2 + (ch - ih * scale) / 2
            love.graphics.draw(self.cardTemplate, drawX, drawY, 0, scale, scale)
        else
            love.graphics.setColor(0.15, 0.15, 0.2, 1)
            love.graphics.rectangle('fill', -cw2, -ch2, cw, ch, 6, 6)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.rectangle('line', -cw2, -ch2, cw, ch, 6, 6)
        end
		-- Left-aligned layout: cost top-right, title then LV below, then description
		-- derive bounds consistently with dragged version
		local tmplScale = Config.DECK.CARD_TEMPLATE_SCALE or 0.7
		local texW = (self.cardTemplate and (self.cardTemplate:getWidth() * tmplScale)) or cw
		local texH = (self.cardTemplate and (self.cardTemplate:getHeight() * tmplScale)) or ch
		local baseHalfW = math.max(cw, texW) * 0.5
		local baseHalfH = math.max(ch, texH) * 0.5
		local shrink = (Config.DECK.CARD_BOUNDS_SHRINK_FRAC or 1)
		local halfW = baseHalfW * shrink
		local topY = -baseHalfH + (Config.DECK.CARD_BOUNDS_OFFSET_Y or 0)
		drawCardFaceText(def, id, halfW, topY, baseHalfH)
		if Config.DECK.SHOW_CARD_BOUNDS then
			local lw = Config.DECK.CARD_BOUNDS_LINE_WIDTH or 2
			local color = (isHovered and (Config.DECK.CARD_BOUNDS_LOCK_COLOR or {0.35, 0.78, 1, 0.65})) or (Config.DECK.CARD_BOUNDS_COLOR or {1, 0.4, 0.2, 0.6})
			local prevWidth = love.graphics.getLineWidth and love.graphics.getLineWidth() or 1
			love.graphics.setColor(color[1], color[2], color[3], color[4])
			love.graphics.setLineWidth(lw)
			love.graphics.rectangle('line', -halfW, topY, halfW * 2, baseHalfH * 2)
			if love.graphics.setLineWidth then love.graphics.setLineWidth(prevWidth) end
			love.graphics.setColor(1, 1, 1, 1)
		end

		love.graphics.pop()
	end

	-- draw non-hovered, non-dragging first
	for _, i in ipairs(order) do
		if i ~= draggingIndex and i ~= hoveredIndex then
			drawCardAt(i, hand[i], false)
		end
	end
	-- draw hovered on top (if any and not dragging)
	if hoveredIndex and hand[hoveredIndex] then
		drawCardAt(hoveredIndex, hand[hoveredIndex], true)
	end
	-- draw dragging card on very top with axis-aligned orientation and drag behavior
	if draggingIndex and hand[draggingIndex] then
		local i = draggingIndex
		local id = hand[i]
		local def = self.deck:getCardDef(id)
		local _, _, _, cw, ch = self:getCardTransform(i, n, false)
		local x, y = self:getCardRect(i, n)
		local targetX = self.drag.mx - cw / 2
		local targetY = self.drag.my - ch / 2
		-- smooth follower to ease into cursor position
		self.drag.smoothX = self.drag.smoothX or (x + cw / 2)
		self.drag.smoothY = self.drag.smoothY or (y + ch / 2)
		local follow = self.drag.followSpeed or 16
		local dt = love.timer.getDelta and love.timer.getDelta() or 0.016
		self.drag.smoothX = self.drag.smoothX + (targetX + cw / 2 - self.drag.smoothX) * math.min(1, follow * dt)
		self.drag.smoothY = self.drag.smoothY + (targetY + ch / 2 - self.drag.smoothY) * math.min(1, follow * dt)
        local clampY
        if Config.DECK.DRAG_CLAMP_Y_FRAC and type(Config.DECK.DRAG_CLAMP_Y_FRAC) == 'number' then
            clampY = (Config.DECK.DRAG_CLAMP_Y_FRAC) * (Config.LOGICAL_HEIGHT)
        else
            clampY = Config.DECK.DRAG_CLAMP_Y or (Config.LOGICAL_HEIGHT - Config.DECK.CARD_HEIGHT - Config.DECK.HAND_MARGIN - 60)
        end
		if not self.drag.locked then
			if targetY < clampY then
				self.drag.locked = true
				self.drag.lockTweenT = 0
				self.drag.lockStartX = x
				self.drag.lockStartY = y
				self.drag.lockTargetX = targetX
				self.drag.lockTargetY = clampY
				self.drag.anchorX = targetX + cw / 2
				self.drag.anchorY = clampY + ch / 2
			else
				x = self.drag.smoothX - cw / 2
				y = self.drag.smoothY - ch / 2
				self.drag.anchorX = x + cw / 2
				self.drag.anchorY = y + ch / 2
			end
		end
        if self.drag.locked then
            local cfg = Config.DECK.DRAG_LOCK_SOFT_FOLLOW or {}
            local softEnabled = cfg.ENABLED ~= false
            local targetShiftX = 0
            local targetShiftY = 0
            if softEnabled then
                local factorX = cfg.FACTOR_X or 0.1
                local factorY = cfg.FACTOR_Y or 0.06
                targetShiftX = (self.drag.mx - (self.drag.anchorX or 0)) * factorX
                targetShiftY = (self.drag.my - (self.drag.anchorY or 0)) * factorY
                local clampX = cfg.MAX_OFFSET_X or 22
                local clampY = cfg.MAX_OFFSET_Y or 14
                if clampX and clampX > 0 then
                    if targetShiftX > clampX then targetShiftX = clampX end
                    if targetShiftX < -clampX then targetShiftX = -clampX end
                end
                if clampY and clampY > 0 then
                    if targetShiftY > clampY then targetShiftY = clampY end
                    if targetShiftY < -clampY then targetShiftY = -clampY end
                end
            end
            local t = math.min(1, self.drag.lockTweenT or 1)
            local u = t * t * (3 - 2 * t)
            local lx = self.drag.lockStartX + (self.drag.lockTargetX - self.drag.lockStartX) * u
            local ly = self.drag.lockStartY + (self.drag.lockTargetY - self.drag.lockStartY) * u
            x = lx + targetShiftX
            y = ly + targetShiftY
		end
		-- draw axis-aligned dragged card at (x,y)
		local cx, cy = x + cw * 0.5, y + ch * 0.5
		-- lazy-load template
        if not self.cardTemplate then
            local path = string.format('%s/%s', Config.ENTITIES_PATH, 'card_template_1.png')
            if love.filesystem.getInfo(path) then
                self.cardTemplate = love.graphics.newImage(path)
            end
        end
		love.graphics.push()
		love.graphics.translate(cx, cy)
		local tiltShear = (self.drag.tiltShear or 0)
		local tiltRot = (self.drag.tiltRot or 0)
		local tiltScaleY = (self.drag.tiltScaleY or 1)
		if love.graphics.shear then
			love.graphics.shear(tiltShear, 0)
		else
			love.graphics.rotate(tiltShear * 0.25)
		end
		love.graphics.rotate(tiltRot)
		love.graphics.scale(1, tiltScaleY)
		local cw2, ch2 = cw * 0.5, ch * 0.5
		local glowImg, glowAlpha, glowScale, glowColor = computeDragGlow(self, def, i, cw, ch)
		if glowImg then
			local gw, gh = glowImg:getWidth(), glowImg:getHeight()
			love.graphics.setBlendMode('add')
			local cr, cg, cb = 1, 1, 1
			if glowColor then
				cr, cg, cb = glowColor[1], glowColor[2], glowColor[3]
			end
			love.graphics.setColor(cr, cg, cb, glowAlpha * 0.55)
			local drawScale = glowScale * 1.1
			local offsetY = 0
			love.graphics.draw(glowImg, 0, offsetY, 0, drawScale * 1.55, drawScale * 1.55, gw * 0.5, gh * 0.5)
			love.graphics.draw(glowImg, 0, offsetY, 0, drawScale, drawScale, gw * 0.5, gh * 0.5)
			love.graphics.setBlendMode('alpha')
			love.graphics.setColor(1, 1, 1, 1)
		end
		if self.cardTemplate then
			love.graphics.setColor(1, 1, 1, 1)
			local iw = self.cardTemplate:getWidth()
			local ih = self.cardTemplate:getHeight()
			local scale = Config.DECK.CARD_TEMPLATE_SCALE or 0.7
			local drawX = -cw2 + (cw - iw * scale) / 2
			local drawY = -ch2 + (ch - ih * scale) / 2
			love.graphics.draw(self.cardTemplate, drawX, drawY, 0, scale, scale)
		else
			love.graphics.setColor(0.15, 0.15, 0.2, 0.95)
			love.graphics.rectangle('fill', -cw2, -ch2, cw, ch, 6, 6)
			love.graphics.setColor(1, 1, 1, 1)
			love.graphics.rectangle('line', -cw2, -ch2, cw, ch, 6, 6)
		end
		-- derive actual drawn bounds (template vs logical), with optional shrink
		local tmplScale = Config.DECK.CARD_TEMPLATE_SCALE or 0.7
		local texW = (self.cardTemplate and (self.cardTemplate:getWidth() * tmplScale)) or cw
		local texH = (self.cardTemplate and (self.cardTemplate:getHeight() * tmplScale)) or ch
		local baseHalfW = math.max(cw, texW) * 0.5
		local baseHalfH = math.max(ch, texH) * 0.5
		local shrink = (Config.DECK.CARD_BOUNDS_SHRINK_FRAC or 1)
		local halfW = baseHalfW * shrink
		local topY = -baseHalfH + (Config.DECK.CARD_BOUNDS_OFFSET_Y or 0)
		drawCardFaceText(def, id, halfW, topY, baseHalfH)
		if Config.DECK.SHOW_CARD_BOUNDS then
			local lw = Config.DECK.CARD_BOUNDS_LINE_WIDTH or 2
			local color = (self.drag.locked and (Config.DECK.CARD_BOUNDS_LOCK_COLOR or {0.35, 0.78, 1, 0.65})) or (Config.DECK.CARD_BOUNDS_COLOR or {1, 0.4, 0.2, 0.6})
			local prevWidth = love.graphics.getLineWidth and love.graphics.getLineWidth() or 1
			love.graphics.setColor(color[1], color[2], color[3], color[4])
			love.graphics.setLineWidth(lw)
			love.graphics.rectangle('line', -halfW, topY, halfW * 2, baseHalfH * 2)
			if love.graphics.setLineWidth then love.graphics.setLineWidth(prevWidth) end
			love.graphics.setColor(1, 1, 1, 1)
		end

		love.graphics.pop()
	end

    -- Debug hit overlay removed per request

    -- Drag arrow when active (only for targeting cards)
    if self.drag.active then
        local def = self.deck:getCardDef((self.drag and self.drag.cardId))
        local isTargeting = not def or (def.requiresTarget ~= false)
        if isTargeting then
            local arrow = Config.DECK.ARROW or {}
            local color = arrow.COLOR or {1,1,1,0.85}
            local width = arrow.WIDTH or 3
            local head = arrow.HEAD_SIZE or 10
            local curveK = arrow.CURVE_STRENGTH or 0.2
            local ax = self.drag.anchorX ~= 0 and self.drag.anchorX or self.drag.startX
            local ay = self.drag.anchorY ~= 0 and self.drag.anchorY or self.drag.startY
            -- raise the start point higher on the card (stronger by default)
            local ch = Config.DECK.CARD_HEIGHT or 140
            local startRaise = arrow.START_RAISE_PIXELS or math.floor(ch * 0.6)
            ay = ay - startRaise
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
            
            -- Distance-based curve dampening: reduce curve intensity for short distances
            local minDist = arrow.MIN_DIST_FOR_FULL_CURVE or 250
            local maxDist = arrow.MAX_DIST_FOR_FULL_CURVE or 500
            local minCurveFactor = arrow.MIN_CURVE_FACTOR or 0.02
            local distFactor = 1
            if dist < minDist then
                -- Very short distance: dramatically reduce curve (interpolate from minCurveFactor to 1)
                local t = dist / minDist
                -- Use smoothstep for gentler transition
                local smoothT = t * t * (3 - 2 * t)
                distFactor = minCurveFactor + (1 - minCurveFactor) * smoothT
            elseif dist < maxDist then
                -- Medium distance: ease into full curve strength
                local t = (dist - minDist) / (maxDist - minDist)
                distFactor = 1 + 0 * t -- already at 1, smooth transition
            end
            -- Apply distance factor to curve strength
            local effectiveCurveK = curveK * distFactor
            
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

            -- First control: earlier along the path with smaller offset (flatter start)
            local cx = ax + dx * 0.4 + px * (dist * effectiveCurveK * 0.6 * sign)
            local cy = ay + dy * 0.4 + py * (dist * effectiveCurveK * 0.6 * sign)
            -- Second control: very close to end with a strong offset (more end-weighted arc)
            local c2x = ax + dx * 0.92 + px * (dist * effectiveCurveK * 2.2 * sign)
            local c2y = ay + dy * 0.92 + py * (dist * effectiveCurveK * 2.2 * sign)

            -- Render a smooth quadratic Bezier curve (A -> control -> B) with tapered width and color/alpha gradient
            -- Draw as filled quads per segment to avoid visible seams between segments
            local segments = 128
			local widthStart = (arrow.WIDTH_START or (width * 12))
            local widthEnd = (arrow.WIDTH_END or (width * 0.8))
            -- reverse gradient: start at #405F7C, end at #67AC97
            local startColor = arrow.START_COLOR or {0.251, 0.3725, 0.4863} -- #405F7C
            local endColor = arrow.END_COLOR or {0.4039, 0.6745, 0.5922} -- #67AC97
            local startAlpha = 0.0
            local endAlpha = (color[4] or 0.85)

            local function cubicPoint(t)
                local omt = 1 - t
                local omt2 = omt * omt
                local t2 = t * t
                local x = omt2*omt*ax + 3*omt2*t*cx + 3*omt*t2*c2x + t2*t*bx
                local y = omt2*omt*ay + 3*omt2*t*cy + 3*omt*t2*c2y + t2*t*by
                -- derivative for tangent
                local dxdt = 3*omt2*(cx - ax) + 6*omt*t*(c2x - cx) + 3*t2*(bx - c2x)
                local dydt = 3*omt2*(cy - ay) + 6*omt*t*(c2y - cy) + 3*t2*(by - c2y)
                local len = math.sqrt(dxdt*dxdt + dydt*dydt)
                if len < 1e-5 then len = 1 end
                local nxp = -dydt / len
                local nyp = dxdt / len
                return x, y, nxp, nyp
            end

            local prevX, prevY, prevNX, prevNY = cubicPoint(0)
            local prevW = widthStart
            for i = 1, segments do
                local tt = i / segments
                local curX, curY, curNX, curNY = cubicPoint(tt)
                local wseg = widthStart + (widthEnd - widthStart) * tt
                local r = startColor[1] + (endColor[1] - startColor[1]) * tt
                local g = startColor[2] + (endColor[2] - startColor[2]) * tt
                local b = startColor[3] + (endColor[3] - startColor[3]) * tt
                local a = startAlpha + (endAlpha - startAlpha) * tt
                love.graphics.setColor(r, g, b, a)
                -- quad corners for previous and current sample
                local p1x = prevX - prevNX * (prevW * 0.5)
                local p1y = prevY - prevNY * (prevW * 0.5)
                local p2x = prevX + prevNX * (prevW * 0.5)
                local p2y = prevY + prevNY * (prevW * 0.5)
                local p3x = curX  + curNX  * (wseg * 0.5)
                local p3y = curY  + curNY  * (wseg * 0.5)
                local p4x = curX  - curNX  * (wseg * 0.5)
                local p4y = curY  - curNY  * (wseg * 0.5)
                love.graphics.polygon('fill', p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y)
                prevX, prevY, prevNX, prevNY, prevW = curX, curY, curNX, curNY, wseg
            end
        end
    end

    -- draw play-out animations on very top
    for k, anim in pairs(self.playAnimations) do
        local defAnim = anim.id and self.deck:getCardDef(anim.id) or nil
        local cw, ch = Config.DECK.CARD_WIDTH, Config.DECK.CARD_HEIGHT
        local cx = anim.startX
        local cy = anim.startY
        local lift = (anim.slide or 120) * easeValue(math.min(1, anim.t or 0), 'smoothstep')
        cy = cy - lift
        local rot = anim.rot or 0
        local alpha = 1 - easeValue(math.min(1, anim.t or 0), 'smoothstep')
        if not self.cardTemplate then
            local path = string.format('%s/%s', Config.ENTITIES_PATH, 'card_template_1.png')
            if love.filesystem.getInfo(path) then
                self.cardTemplate = love.graphics.newImage(path)
            end
        end
        love.graphics.push()
        love.graphics.translate(cx, cy)
        love.graphics.rotate(rot)
        local cw2, ch2 = cw * 0.5, ch * 0.5
        if self.cardTemplate then
            love.graphics.setColor(1, 1, 1, alpha)
            local iw = self.cardTemplate:getWidth()
            local ih = self.cardTemplate:getHeight()
            local scale = Config.DECK.CARD_TEMPLATE_SCALE or 0.7
            local drawX = -cw2 + (cw - iw * scale) / 2
            local drawY = -ch2 + (ch - ih * scale) / 2
            love.graphics.draw(self.cardTemplate, drawX, drawY, 0, scale, scale)
        else
            love.graphics.setColor(0.15, 0.15, 0.2, 0.95 * alpha)
            love.graphics.rectangle('fill', -cw2, -ch2, cw, ch, 6, 6)
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.rectangle('line', -cw2, -ch2, cw, ch, 6, 6)
        end
		if defAnim then
			-- energy cost number at top-center (shifted up into diamond)
			local costY = -ch2 - 8
            Theme.drawTextCentered(tostring(defAnim.cost or 0), 0, costY, Theme.FONTS.BOLD_MEDIUM, {1,1,1,alpha})

			if defAnim.level then
                local SHIFT_DOWN = 20
                local levelY = costY + Theme.FONTS.BOLD_MEDIUM:getHeight() + 4 + SHIFT_DOWN
                Theme.drawTextCentered(string.format('LEVEL %d', defAnim.level), 0, levelY, Theme.FONTS.LARGE, {Theme.COLORS.ACCENT[1],Theme.COLORS.ACCENT[2],Theme.COLORS.ACCENT[3],alpha})
			end
            local titleY = costY + Theme.FONTS.BOLD_MEDIUM:getHeight() + 4 + 20 + Theme.FONTS.LARGE:getHeight() + 6
            Theme.drawShadowTextCentered(defAnim.name or anim.id or '', 0, titleY, Theme.FONTS.BOLD_LARGE, {1,1,1,alpha})
			if defAnim.description and #defAnim.description > 0 then
                local descY = titleY + Theme.FONTS.BOLD_LARGE:getHeight() + 6
                local font = Theme.FONTS.MEDIUM
				love.graphics.setFont(font)
				love.graphics.setColor(1,1,1,alpha)
				local lines = wrapText(font, defAnim.description, cw - 32)
				local lh = font:getHeight() * 0.9
				for li = 1, #lines do
					local w = font:getWidth(lines[li])
					love.graphics.print(lines[li], -w * 0.5, descY + (li - 1) * lh)
				end
			end
		elseif anim.id then
			Theme.drawTextCentered(anim.id, 0, -ch2 + 8, Theme.FONTS.MEDIUM, {1,1,1,alpha})
		end
        love.graphics.pop()
    end
    -- Reset color to avoid tinting subsequent draws
    love.graphics.setColor(1, 1, 1, 1)
end

function HandUI:update(dt)
    self.time = (self.time or 0) + dt
    -- advance flip tween if active
    if self.arrowState and self.arrowState.tweenT and self.arrowState.tweenT < 1 then
        local dur = self.arrowState.tweenDur or 0.1
        if dur <= 0 then
            self.arrowState.tweenT = 1
        else
            self.arrowState.tweenT = math.min(1, self.arrowState.tweenT + dt / dur)
        end
    end
    -- update drag tilt easing
    local tiltCfg = Config.DECK.DRAG_TILT or {}
    if self.drag then
        local follow = tiltCfg.FOLLOW_SPEED or 14
        local lerp = math.min(1, math.max(0, follow * dt))
        if self.drag.active and tiltCfg.ENABLED ~= false then
            -- keep using existing targets
        else
            if self.drag.tiltTargetShear ~= 0 or self.drag.tiltTargetRot ~= 0 or self.drag.tiltTargetScaleY ~= 1 then
                self.drag.tiltTargetShear = 0
                self.drag.tiltTargetRot = 0
                self.drag.tiltTargetScaleY = 1
            end
        end
        if lerp > 0 then
            self.drag.tiltShear = self.drag.tiltShear + (self.drag.tiltTargetShear - self.drag.tiltShear) * lerp
            self.drag.tiltRot = self.drag.tiltRot + (self.drag.tiltTargetRot - self.drag.tiltRot) * lerp
            self.drag.tiltScaleY = self.drag.tiltScaleY + (self.drag.tiltTargetScaleY - self.drag.tiltScaleY) * lerp
        else
            self.drag.tiltShear = self.drag.tiltTargetShear
            self.drag.tiltRot = self.drag.tiltTargetRot
            self.drag.tiltScaleY = self.drag.tiltTargetScaleY
        end
    end
    -- advance lock tween if active
    if self.drag and self.drag.locked and self.drag.lockTweenT and self.drag.lockTweenT < 1 then
        local dur = self.drag.lockTweenDur or 0.12
        if dur <= 0 then
            self.drag.lockTweenT = 1
        else
            self.drag.lockTweenT = math.min(1, self.drag.lockTweenT + dt / dur)
        end
    end
    
    -- detect hand composition changes to trigger layout tween
    local hand = self.deck:getHand()
    local changed = false
    if #hand ~= #self.lastHandIds then
        changed = true
    else
        for i = 1, #hand do
            if hand[i] ~= self.lastHandIds[i] then changed = true; break end
        end
    end
    if changed then
        self:startLayoutTween()
    end

    -- advance layout tween per card
    for i = 1, #hand do
        local key = self.indexToKey[i]
        if key then
            local st = self.cardStates[key]
            -- ensure a target exists (e.g., first frame)
            local cx, cy, rot = self:getCardTransform(i, #hand, (not self.drag.active) and (self.hoverIndex == i))
            if not st then
                st = { x = cx, y = cy, rot = rot, fromX = cx, fromY = cy, fromRot = rot, toX = cx, toY = cy, toRot = rot, t = 1, dur = self.layoutTweenDur or 0.2, alpha = 1 }
                self.cardStates[key] = st
            end
            -- if targets drift (hover/angle changed), retarget smoothly
            if st.toX ~= cx or st.toY ~= cy or st.toRot ~= rot then
                st.fromX, st.fromY, st.fromRot = st.x, st.y, st.rot
                st.toX, st.toY, st.toRot = cx, cy, rot
                st.t = 0
                st.dur = self.layoutTweenDur or 0.2
            end
            if st.t < 1 then
                st.t = math.min(1, st.t + dt / (st.dur > 0 and st.dur or 1e-6))
                local u = easeValue(st.t, self.layoutEase)
                st.x = st.fromX + (st.toX - st.fromX) * u
                st.y = st.fromY + (st.toY - st.fromY) * u
                -- shortest angle lerp (small angles expected)
                st.rot = st.fromRot + (st.toRot - st.fromRot) * u
            else
                st.x, st.y, st.rot = st.toX, st.toY, st.toRot
            end
        end
    end

    -- advance play-out animations and cull finished
    local toRemove = {}
    for key, anim in pairs(self.playAnimations) do
        anim.t = math.min(1, (anim.t or 0) + dt / (anim.dur or 0.18))
        if anim.t >= 1 then
            toRemove[#toRemove+1] = key
        end
    end
    for i = 1, #toRemove do
        self.playAnimations[toRemove[i]] = nil
    end
end

return HandUI


