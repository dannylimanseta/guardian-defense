-- theme.lua - UI Theme and Style Guide
-- Centralized styling for consistent UI components

local Config = require 'src/config/Config'

local Theme = {}

-- Color Palette
Theme.COLORS = {
    -- Primary colors
    PRIMARY = {0.2, 0.6, 0.9, 1},      -- Blue
    PRIMARY_DARK = {0.1, 0.4, 0.7, 1}, -- Darker blue
    PRIMARY_LIGHT = {0.4, 0.8, 1, 1},   -- Lighter blue
    
    -- Secondary colors
    SECONDARY = {0.9, 0.6, 0.2, 1},    -- Orange
    SECONDARY_DARK = {0.7, 0.4, 0.1, 1}, -- Darker orange
    SECONDARY_LIGHT = {1, 0.8, 0.4, 1}, -- Lighter orange
    
    -- Neutral colors
    WHITE = {1, 1, 1, 1},
    BLACK = {0, 0, 0, 1},
    GRAY_LIGHT = {0.8, 0.8, 0.8, 1},
    GRAY_MEDIUM = {0.5, 0.5, 0.5, 1},
    GRAY_DARK = {0.2, 0.2, 0.2, 1},
    
    -- Status colors
    SUCCESS = {0.2, 0.8, 0.2, 1},      -- Green
    WARNING = {0.9, 0.7, 0.1, 1},      -- Yellow
    ERROR = {0.9, 0.2, 0.2, 1},        -- Red
    
    -- Accent (teal) used in card UI
    ACCENT = {0.4039, 0.6745, 0.5922, 1}, -- #67AC97

    -- Background colors
    BACKGROUND_PRIMARY = Config.COLORS.BACKGROUND,
    BACKGROUND_SECONDARY = {0.15, 0.15, 0.2, 1},
    BACKGROUND_PANEL = {0.2, 0.2, 0.25, 0.9}
}

-- Typography
local function loadFont(size)
    local path = string.format('%s/%s', Config.FONT_PATH, 'BarlowCondensed-Regular.ttf')
    local font
    if love.filesystem.getInfo(path) then
        font = love.graphics.newFont(path, size)
    else
        font = love.graphics.newFont(size)
    end
    if font and font.setFilter then font:setFilter('linear', 'linear') end
    return font
end

local function loadFontBold(size)
    local path = string.format('%s/%s', Config.FONT_PATH, 'BarlowCondensed-Bold.ttf')
    local font
    if love.filesystem.getInfo(path) then
        font = love.graphics.newFont(path, size)
    else
        font = love.graphics.newFont(size)
    end
    if font and font.setFilter then font:setFilter('linear', 'linear') end
    return font
end

Theme.FONTS = {
    SMALL = loadFont(12),
    MEDIUM = loadFont(16),
    LARGE = loadFont(24),
    TITLE = loadFont(32),
    BOLD_SMALL = loadFontBold(12),
    BOLD_MEDIUM = loadFontBold(16),
    BOLD_LARGE = loadFontBold(24),
    BOLD_TITLE = loadFontBold(32)
}

-- Component Styles
Theme.COMPONENTS = {
    BUTTON = {
        HEIGHT = Config.UI.BUTTON_HEIGHT,
        PADDING = 8,
        BORDER_RADIUS = 4,
        COLORS = {
            NORMAL = Theme.COLORS.PRIMARY,
            HOVER = Theme.COLORS.PRIMARY_LIGHT,
            PRESSED = Theme.COLORS.PRIMARY_DARK,
            DISABLED = Theme.COLORS.GRAY_MEDIUM
        }
    },
    
    PANEL = {
        PADDING = Config.UI.PANEL_PADDING,
        BORDER_WIDTH = 2,
        COLORS = {
            BACKGROUND = Theme.COLORS.BACKGROUND_PANEL,
            BORDER = Theme.COLORS.GRAY_MEDIUM
        }
    },
    
    INPUT = {
        HEIGHT = 32,
        PADDING = 8,
        BORDER_WIDTH = 2,
        COLORS = {
            BACKGROUND = Theme.COLORS.WHITE,
            BORDER = Theme.COLORS.GRAY_MEDIUM,
            FOCUSED = Theme.COLORS.PRIMARY,
            TEXT = Theme.COLORS.BLACK
        }
    }
}

-- Utility Functions
function Theme.drawButton(x, y, width, height, text, state)
    state = state or "normal"
    local colors = Theme.COMPONENTS.BUTTON.COLORS
    local color = colors[state:upper()] or colors.NORMAL
    
    -- Draw button background
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x, y, width, height)
    
    -- Draw button border
    love.graphics.setColor(Theme.COLORS.WHITE)
    love.graphics.rectangle("line", x, y, width, height)
    
    -- Draw button text
    if text then
        love.graphics.setColor(Theme.COLORS.WHITE)
        love.graphics.setFont(Theme.FONTS.MEDIUM)
        local textWidth = Theme.FONTS.MEDIUM:getWidth(text)
        local textHeight = Theme.FONTS.MEDIUM:getHeight()
        love.graphics.print(text, 
            x + (width - textWidth) / 2, 
            y + (height - textHeight) / 2)
    end
end

function Theme.drawPanel(x, y, width, height)
    local panel = Theme.COMPONENTS.PANEL
    
    -- Draw panel background
    love.graphics.setColor(panel.COLORS.BACKGROUND)
    love.graphics.rectangle("fill", x, y, width, height)
    
    -- Draw panel border
    love.graphics.setColor(panel.COLORS.BORDER)
    love.graphics.rectangle("line", x, y, width, height)
end

function Theme.drawText(text, x, y, font, color)
    font = font or Theme.FONTS.MEDIUM
    color = color or Theme.COLORS.WHITE
    
    love.graphics.setFont(font)
    love.graphics.setColor(color)
    love.graphics.print(text, x, y)
end

function Theme.drawShadowText(text, x, y, font, color, shadowColor, ox, oy)
    font = font or Theme.FONTS.MEDIUM
    color = color or Theme.COLORS.WHITE
    shadowColor = shadowColor or {0, 0, 0, 0.6}
    ox = ox or 1
    oy = oy or 1

    love.graphics.setFont(font)
    love.graphics.setColor(shadowColor)
    love.graphics.print(text, x + ox, y + oy)
    love.graphics.setColor(color)
    love.graphics.print(text, x, y)
end

function Theme.drawTextCentered(text, cx, y, font, color)
    font = font or Theme.FONTS.MEDIUM
    color = color or Theme.COLORS.WHITE
    love.graphics.setFont(font)
    love.graphics.setColor(color)
    local w = font:getWidth(text)
    love.graphics.print(text, cx - w / 2, y)
end

function Theme.drawShadowTextCentered(text, cx, y, font, color, shadowColor, ox, oy)
    font = font or Theme.FONTS.MEDIUM
    color = color or Theme.COLORS.WHITE
    shadowColor = shadowColor or {0,0,0,0.6}
    ox = ox or 1
    oy = oy or 1
    love.graphics.setFont(font)
    love.graphics.setColor(shadowColor)
    local w = font:getWidth(text)
    love.graphics.print(text, cx - w / 2 + ox, y + oy)
    love.graphics.setColor(color)
    love.graphics.print(text, cx - w / 2, y)
end

-- Minimal health bar utility
function Theme.drawHealthBar(x, y, width, height, percent, bgColor, fgColor, cornerRadius)
    percent = math.max(0, math.min(1, percent or 1))
    -- Background
    love.graphics.setColor(bgColor or {0, 0, 0, 0.8})
    if cornerRadius and cornerRadius > 0 then
        love.graphics.rectangle('fill', x, y, width, height, cornerRadius, cornerRadius)
    else
        love.graphics.rectangle('fill', x, y, width, height)
    end
    -- Foreground
    local w = math.floor(width * percent)
    if w > 0 then
        love.graphics.setColor(fgColor or {0.6, 1, 0.3, 1})
        if cornerRadius and cornerRadius > 0 then
            love.graphics.rectangle('fill', x, y, w, height, cornerRadius, cornerRadius)
        else
            love.graphics.rectangle('fill', x, y, w, height)
        end
    end
end

-- Dotted circle utility: draws dashed circle using arc segments
function Theme.drawDottedCircle(cx, cy, radius, dashDeg, gapDeg, lineWidth, color, startDeg)
    local totalDeg = 360
    dashDeg = dashDeg or 8
    gapDeg = gapDeg or 8
    lineWidth = lineWidth or 1
    color = color or Theme.COLORS.WHITE
    love.graphics.setLineWidth(lineWidth)
    love.graphics.setColor(color)
    local rad = math.rad
    local segments = math.max(64, math.ceil(360 / (dashDeg > 0 and dashDeg or 1)) * 2)
    local a = (startDeg or 0) % 360
    while a < 360 + (startDeg or 0) do
        local startRad = rad(a)
        local endRad = rad(math.min(a + dashDeg, 360 + (startDeg or 0)))
        love.graphics.arc('line', 'open', cx, cy, radius, startRad, endRad, segments)
        a = a + dashDeg + gapDeg
    end
end

-- Additive filled circle (solid) with alpha
function Theme.drawAdditiveCircleFill(cx, cy, radius, alpha)
    local prevBlend = love.graphics.getBlendMode()
    love.graphics.setBlendMode('add')
    love.graphics.setColor(1, 1, 1, alpha or 0.05)
    love.graphics.circle('fill', cx, cy, radius)
    love.graphics.setBlendMode(prevBlend)
end

return Theme
 