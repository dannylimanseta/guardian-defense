-- Pathfinder.lua - BFS pathfinding restricted to path tiles

local Pathfinder = {}
Pathfinder.__index = Pathfinder

local DIRECTIONS = {
    {x = 1, y = 0},
    {x = -1, y = 0},
    {x = 0, y = 1},
    {x = 0, y = -1}
}

local function isTraversable(tile)
    if not tile then return false end
    return tile.type == 'path'
end

local function key(x, y)
    return x .. "," .. y
end

function Pathfinder:findPath(mapData, startX, startY, goalX, goalY)
    -- Guard clauses
    if not mapData or not mapData.layers or not mapData.layerLookup then
        return nil
    end

    local width = mapData.width
    local height = mapData.height
    if startX < 1 or startX > width or startY < 1 or startY > height then return nil end
    if goalX < 1 or goalX > width or goalY < 1 or goalY > height then return nil end

    -- Allow start and goal even if not 'path'; otherwise require 'path'
    local function canVisit(x, y)
        local tile = mapData.layers[1].matrix[x][y]
        if (x == startX and y == startY) or (x == goalX and y == goalY) then
            return true
        end
        return isTraversable(tile)
    end

    local queue = {}
    local head = 1
    local tail = 1
    local visited = {}
    local parent = {}

    if not canVisit(startX, startY) then
        return nil
    end

    queue[tail] = {x = startX, y = startY}
    tail = tail + 1
    visited[key(startX, startY)] = true

    -- Randomize direction order per call to split ties across equal-length branches
    local dirs = {DIRECTIONS[1], DIRECTIONS[2], DIRECTIONS[3], DIRECTIONS[4]}
    for i = #dirs, 2, -1 do
        local j = math.random(i)
        dirs[i], dirs[j] = dirs[j], dirs[i]
    end

    while head < tail do
        local node = queue[head]
        head = head + 1

        if node.x == goalX and node.y == goalY then
            -- Reconstruct path
            local path = {}
            local k = key(node.x, node.y)
            while k do
                local p = parent[k]
                local cx, cy = node.x, node.y
                path[#path + 1] = {x = cx, y = cy}
                if not p then break end
                node = {x = p.x, y = p.y}
                k = key(node.x, node.y)
            end
            -- reverse
            for i = 1, math.floor(#path / 2) do
                path[i], path[#path - i + 1] = path[#path - i + 1], path[i]
            end
            return path
        end

        for _, d in ipairs(dirs) do
            local nx = node.x + d.x
            local ny = node.y + d.y
            if nx >= 1 and nx <= width and ny >= 1 and ny <= height then
                if canVisit(nx, ny) then
                    local k2 = key(nx, ny)
                    if not visited[k2] then
                        visited[k2] = true
                        parent[k2] = {x = node.x, y = node.y}
                        queue[tail] = {x = nx, y = ny}
                        tail = tail + 1
                    end
                end
            end
        end
    end

    return nil
end

return setmetatable({}, Pathfinder)


