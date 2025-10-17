-- MapLoader.lua - Loads TMX maps and prepares data for the grid system
-- Responsible for parsing CSV tile layers and loading associated sprites

local Config = require 'src/config/Config'

local MapLoader = {}
MapLoader.__index = MapLoader

local IMAGE_CACHE = {}

local TILE_DEFINITIONS = {
    [1] = {
        type = 'entrance',
        image = 'entrance_1.png',
        opacity = 1
    },
    [2] = {
        type = 'core',
        image = 'heart_1.png',
        opacity = 1
    },
    [3] = {
        type = 'path',
        image = 'path_1.png',
        opacity = 1
    },
    [4] = {
        type = 'enemy_spawn',
        image = 'enemy_spawn_1.png',
        opacity = 1
    },
    [5] = {
        type = 'build',
        image = 'build_tile_1.png',
        opacity = 1
    },
    [6] = {
        type = 'pillar',
        image = 'pillars_1.png',
        opacity = 1
    },
    [7] = {
        type = 'wall',
        image = 'wall_1.png',
        opacity = 1
    }
}

local function getImage(imageName)
    if not imageName then
        return nil
    end

    if not IMAGE_CACHE[imageName] then
        local path = string.format('%s/%s', Config.TILESET_PATH, imageName)
        if not love.filesystem.getInfo(path) then
            error(string.format('Tileset image not found: %s', path))
        end

        local image = love.graphics.newImage(path)
        IMAGE_CACHE[imageName] = image
    end

    return IMAGE_CACHE[imageName]
end

local function parseCSVLayer(data, width, height)
    local rows = {}
    for row in data:gmatch('[^\n]+') do
        row = row:gsub('%s', '')
        if #row > 0 then
            local values = {}
            for value in row:gmatch('[-%d]+') do
                values[#values + 1] = tonumber(value)
            end
            if #values > 0 then
                rows[#rows + 1] = values
            end
        end
    end

    -- Ensure we have exactly the expected number of rows
    if #rows ~= height then
        error(string.format('TMX parse error: expected %d rows, found %d', height, #rows))
    end

    -- Convert to column-major structure for easier access by x, y
    local tiles = {}
    for x = 1, width do
        tiles[x] = {}
        for y = 1, height do
            tiles[x][y] = rows[y][x] or 0
        end
    end

    return tiles
end

local function buildTileData(tileId, x, y, tileWidth, tileHeight, flipX, flipY, flipD)
    if tileId == 0 then
        return {
            id = 0,
            type = 'empty',
            sprite = nil,
            opacity = 0,
            x = x,
            y = y,
            width = tileWidth,
            height = tileHeight,
            flipX = false,
            flipY = false,
            flipD = false
        }
    end

    local definition = TILE_DEFINITIONS[tileId]
    if not definition then
        return {
            id = tileId,
            type = 'unknown',
            sprite = nil,
            opacity = 1,
            x = x,
            y = y,
            width = tileWidth,
            height = tileHeight,
            flipX = flipX or false,
            flipY = flipY or false,
            flipD = flipD or false
        }
    end

    local sprite = getImage(definition.image)

    return {
        id = tileId,
        type = definition.type,
        sprite = sprite,
        opacity = definition.opacity or 1,
        image = definition.image,
        x = x,
        y = y,
        width = tileWidth,
        height = tileHeight,
        flipX = flipX or false,
        flipY = flipY or false,
        flipD = flipD or false
    }
end

local function parseLayers(content, width, height, tileWidth, tileHeight)
    local orderedLayers = {}
    local layerLookup = {}

    -- Tiled flip flags (use powers of two to avoid bitwise ops)
    local FLIP_H = 2^31
    local FLIP_V = 2^30
    local FLIP_D = 2^29

    for name, data in content:gmatch('<layer[^>]-name="([^"]+)"[^>]*>.-<data[^>]*>(.-)</data>') do
        local tileIds = parseCSVLayer(data, width, height)
        local layerTiles = {}
        local tilesMatrix = {}

        for x = 1, width do
            tilesMatrix[x] = {}
            for y = 1, height do
                local gid = tileIds[x][y]
                -- Decode flip flags without bitwise operators
                local flipX = gid >= FLIP_H
                if flipX then gid = gid - FLIP_H end
                local flipY = gid >= FLIP_V
                if flipY then gid = gid - FLIP_V end
                local flipD = gid >= FLIP_D
                if flipD then gid = gid - FLIP_D end
                local id = gid
                local tileData = buildTileData(id, x, y, tileWidth, tileHeight, flipX, flipY, flipD)
                tilesMatrix[x][y] = tileData

                if tileData.sprite then
                    layerTiles[#layerTiles + 1] = {
                        x = x,
                        y = y,
                        sprite = tileData.sprite,
                        opacity = tileData.opacity,
                        type = tileData.type,
                        width = tileData.width,
                        height = tileData.height,
                        flipX = tileData.flipX,
                        flipY = tileData.flipY,
                        flipD = tileData.flipD
                    }
                end
            end
        end

        local layerInfo = {
            name = name,
            tiles = layerTiles,
            matrix = tilesMatrix
        }

        orderedLayers[#orderedLayers + 1] = layerInfo
        layerLookup[name] = layerInfo
    end

    return orderedLayers, layerLookup
end

local function extractMapDimensions(content)
    local width, height, tileWidth, tileHeight = content:match('<map[^>]-width="(%d+)"[^>]-height="(%d+)"[^>]-tilewidth="(%d+)"[^>]-tileheight="(%d+)"')
    if not width then
        error('Failed to parse TMX map dimensions')
    end

    return tonumber(width), tonumber(height), tonumber(tileWidth), tonumber(tileHeight)
end

-- Parse TMX object layers to find a named core object; returns grid coordinates (x, y) or nil
local function parseCoreObject(content, tileWidth, tileHeight)
    -- Look for a self-closing object tag with name="core" and x/y/width/height attributes
    local ox, oy, ow, oh = content:match('<object[^>]-name="core"[^>]-x="([%d%.%-]+)"[^>]-y="([%d%.%-]+)"[^>]-width="([%d%.%-]+)"[^>]-height="([%d%.%-]+)"[^>]*/>')
    if not ox or not oy then
        -- Fallback: handle non-self-closing object tag variants where attributes are still on the opening tag
        ox, oy, ow, oh = content:match('<object[^>]-name="core"[^>]-x="([%d%.%-]+)"[^>]-y="([%d%.%-]+)"[^>]-width="([%d%.%-]+)"[^>]-height="([%d%.%-]+)"[^>]*>')
    end
    if ox and oy then
        local px = tonumber(ox)
        local py = tonumber(oy)
        local pw = ow and tonumber(ow) or nil
        local ph = oh and tonumber(oh) or nil
        if px and py and tileWidth and tileHeight and tileWidth > 0 and tileHeight > 0 then
            -- Use object center for grid mapping to match drawn tile centering
            local cx_px = px + (pw or tileWidth) / 2
            local cy_px = py + (ph or tileHeight) / 2
            local gridX = math.floor(cx_px / tileWidth) + 1
            local gridY = math.floor(cy_px / tileHeight) + 1
            return gridX, gridY, px, py, pw, ph, cx_px, cy_px
        end
    end
    return nil, nil, nil, nil, nil, nil, nil, nil
end

function MapLoader:load(levelName)
    local relativePath = string.format('%s/%s.tmx', Config.LEVELS_PATH, levelName)
    if not love.filesystem.getInfo(relativePath) then
        error(string.format('Level file not found: %s', relativePath))
    end

    local fileContents, err = love.filesystem.read(relativePath)
    if not fileContents then
        error(string.format('Failed to read level file %s: %s', relativePath, err))
    end

    local width, height, tileWidth, tileHeight = extractMapDimensions(fileContents)
    local layers, layerLookup = parseLayers(fileContents, width, height, tileWidth, tileHeight)

    -- Prepare composite tile matrix (first layer used for base grid)
    local tiles = {}
    if layers[1] then
        for x = 1, width do
            tiles[x] = {}
            for y = 1, height do
                tiles[x][y] = layers[1].matrix[x][y]
            end
        end
    end

    -- Track special tiles (entrance, core, paths, enemy spawns, build spots)
    local specialTiles = {
        entrance = nil,
        core = nil,
        paths = {},
        enemy_spawns = {},
        build_spots = {}
    }

    for _, layer in ipairs(layers) do
        for _, tile in ipairs(layer.tiles) do
            if tile.type == 'entrance' then
                specialTiles.entrance = {x = tile.x, y = tile.y}
            elseif tile.type == 'core' then
                specialTiles.core = {x = tile.x, y = tile.y}
            elseif tile.type == 'path' then
                specialTiles.paths[#specialTiles.paths + 1] = {x = tile.x, y = tile.y}
            elseif tile.type == 'enemy_spawn' then
                specialTiles.enemy_spawns[#specialTiles.enemy_spawns + 1] = {x = tile.x, y = tile.y}
            elseif tile.type == 'build' then
                specialTiles.build_spots[#specialTiles.build_spots + 1] = {x = tile.x, y = tile.y}
            end
        end
    end

    -- Prefer TMX object-layer defined core if present (overrides tile-based core detection)
    do
        local cx, cy, px, py, pw, ph, pcx, pcy = parseCoreObject(fileContents, tileWidth, tileHeight)
        if cx and cy then
            specialTiles.core = { x = cx, y = cy, px = px, py = py, pw = pw, ph = ph, pcx = pcx, pcy = pcy }
        end
    end

    return {
        name = levelName,
        width = width,
        height = height,
        tileWidth = tileWidth,
        tileHeight = tileHeight,
        tiles = tiles,
        layers = layers,
        layerLookup = layerLookup,
        special = specialTiles
    }
end

return setmetatable({}, MapLoader)
