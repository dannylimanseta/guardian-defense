-- ResolutionManager.lua - Handles resolution scaling for PC games
-- Best practices for PC game resolution handling

local Config = require 'src/config/Config'

local ResolutionManager = {}

function ResolutionManager:init()
    -- Get current screen dimensions
    self.screenWidth, self.screenHeight = love.graphics.getDimensions()
    
    -- Game's logical resolution (what we design for)
    self.logicalWidth = Config.LOGICAL_WIDTH
    self.logicalHeight = Config.LOGICAL_HEIGHT
    
    -- Calculate scaling factors
    self.scaleX = self.screenWidth / self.logicalWidth
    self.scaleY = self.screenHeight / self.logicalHeight
    
    -- Use uniform scaling to maintain aspect ratio
    self.scale = math.min(self.scaleX, self.scaleY)
    
    -- Calculate letterbox/pillarbox dimensions
    self.drawWidth = self.logicalWidth * self.scale
    self.drawHeight = self.logicalHeight * self.scale
    
    -- Calculate offsets for centering
    self.offsetX = math.floor(((self.screenWidth - self.drawWidth) / 2) + 0.5)
    self.offsetY = math.floor(((self.screenHeight - self.drawHeight) / 2) + 0.5)
    
    -- Set up canvas for rendering
    self.canvas = love.graphics.newCanvas(self.logicalWidth, self.logicalHeight)
    if self.canvas.setWrap then self.canvas:setWrap('clamp', 'clamp') end
    
    -- Fullscreen toggle state
    self.pendingFullscreenToggle = false
    
    -- no debug print
end

function ResolutionManager:startDraw()
    -- Set up canvas for rendering
    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(Config.COLORS.BACKGROUND)
end

function ResolutionManager:endDraw()
    -- Finish canvas rendering
    love.graphics.setCanvas()
    
    -- Draw canvas to screen with proper scaling and centering
    love.graphics.push()
    love.graphics.translate(self.offsetX, self.offsetY)
    love.graphics.scale(self.scale)
    love.graphics.draw(self.canvas)
    love.graphics.pop()
end

function ResolutionManager:screenToGame(screenX, screenY)
    -- Convert screen coordinates to game coordinates
    local gameX = (screenX - self.offsetX) / self.scale
    local gameY = (screenY - self.offsetY) / self.scale
    
    -- Clamp to game bounds
    gameX = math.max(0, math.min(self.logicalWidth, gameX))
    gameY = math.max(0, math.min(self.logicalHeight, gameY))
    
    return gameX, gameY
end

function ResolutionManager:gameToScreen(gameX, gameY)
    -- Convert game coordinates to screen coordinates
    local screenX = gameX * self.scale + self.offsetX
    local screenY = gameY * self.scale + self.offsetY
    
    return screenX, screenY
end

function ResolutionManager:resize(width, height)
    -- Handle window resize
    self.screenWidth = width
    self.screenHeight = height
    
    -- Recalculate scaling
    self.scaleX = self.screenWidth / self.logicalWidth
    self.scaleY = self.screenHeight / self.logicalHeight
    self.scale = math.min(self.scaleX, self.scaleY)
    
    self.drawWidth = self.logicalWidth * self.scale
    self.drawHeight = self.logicalHeight * self.scale
    
    self.offsetX = (self.screenWidth - self.drawWidth) / 2
    self.offsetX = math.floor((self.offsetX) + 0.5)
    self.offsetY = math.floor(((self.screenHeight - self.drawHeight) / 2) + 0.5)
    
    -- no debug print
end

function ResolutionManager:toggleFullscreen()
    -- Schedule fullscreen toggle for next frame to avoid crashes
    self.pendingFullscreenToggle = true
end

function ResolutionManager:update()
    -- Handle pending fullscreen toggle
    if self.pendingFullscreenToggle then
        self.pendingFullscreenToggle = false
        
        -- Toggle fullscreen mode
        local fullscreen = love.window.getFullscreen()
        
        -- Use a safer approach with error handling
        local success, err = pcall(function()
            love.window.setFullscreen(not fullscreen)
        end)
        
        if not success then return end
        
        -- Update dimensions after fullscreen change
        self.screenWidth, self.screenHeight = love.graphics.getDimensions()
        
        -- Recalculate scaling for new resolution
        self.scaleX = self.screenWidth / self.logicalWidth
        self.scaleY = self.screenHeight / self.logicalHeight
        self.scale = math.min(self.scaleX, self.scaleY)
        
        self.drawWidth = self.logicalWidth * self.scale
        self.drawHeight = self.logicalHeight * self.scale
        
        self.offsetX = (self.screenWidth - self.drawWidth) / 2
        self.offsetY = (self.screenHeight - self.drawHeight) / 2
        
        -- no debug print
    end
end

function ResolutionManager:getScaleInfo()
    -- Return scaling information for debugging
    return {
        screenWidth = self.screenWidth,
        screenHeight = self.screenHeight,
        logicalWidth = self.logicalWidth,
        logicalHeight = self.logicalHeight,
        scale = self.scale,
        drawWidth = self.drawWidth,
        drawHeight = self.drawHeight,
        offsetX = self.offsetX,
        offsetY = self.offsetY,
        aspectRatio = self.screenWidth / self.screenHeight,
        logicalAspectRatio = self.logicalWidth / self.logicalHeight
    }
end

return ResolutionManager
