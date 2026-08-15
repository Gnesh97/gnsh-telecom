SpatialIndex = SpatialIndex or {}

local towersById = {}
local cellsByKey = {}
local built = false
local stats = {
    built = false,
    cellCount = 0,
    towerCount = 0,
    towerCellLinks = 0,
    candidateCount = 0,
    cellSize = 0,
}

local function getCellSize()
    local size = Config and Config.Spatial and Config.Spatial.cellSize
    if type(size) ~= 'number' or size ~= size or size == math.huge
        or size == -math.huge or size <= 0 then
        return nil
    end
    return size
end

local function makeCellKey(cellX, cellY)
    return ('%d:%d'):format(cellX, cellY)
end

local function getCellCoordinates(coords)
    if not Utils.IsPoint(coords) then return nil end
    local size = getCellSize()
    if not size then return nil end

    return math.floor(coords.x / size), math.floor(coords.y / size)
end

local function getTowerCellBounds(tower, size)
    local radius = tower.coverage.radius
    local coords = tower.coords
    return math.floor((coords.x - radius) / size),
        math.floor((coords.x + radius) / size),
        math.floor((coords.y - radius) / size),
        math.floor((coords.y + radius) / size)
end

local function countKeys(values)
    local count = 0
    for _ in pairs(values) do count = count + 1 end
    return count
end

local function buildIndex(towers, size)
    local nextTowers = {}
    local nextCells = {}
    local towerCellLinks = 0

    for _, tower in ipairs(towers) do
        nextTowers[tower.id] = Utils.DeepCopy(tower)

        local minX, maxX, minY, maxY = getTowerCellBounds(tower, size)
        for cellX = minX, maxX do
            for cellY = minY, maxY do
                local key = makeCellKey(cellX, cellY)
                nextCells[key] = nextCells[key] or {}
                nextCells[key][#nextCells[key] + 1] = tower.id
                towerCellLinks = towerCellLinks + 1
            end
        end
    end

    for _, cell in pairs(nextCells) do
        table.sort(cell)
    end

    return nextTowers, nextCells, {
        built = true,
        cellCount = countKeys(nextCells),
        towerCount = #towers,
        towerCellLinks = towerCellLinks,
        candidateCount = 0,
        cellSize = size,
    }
end

local function getSourceTowers(towers)
    if towers ~= nil then return towers end
    if TowerRegistry and TowerRegistry.GetAll then
        return TowerRegistry.GetAll()
    end
    return Config and Config.Towers or {}
end

function SpatialIndex.GetCell(coords)
    local cellX, cellY = getCellCoordinates(coords)
    if not cellX then return nil end
    return makeCellKey(cellX, cellY)
end

function SpatialIndex.Rebuild(towers)
    local size = getCellSize()
    if not size then
        return false, { 'Spatial.cellSize must be greater than zero' }, {}
    end

    local source = getSourceTowers(towers)
    local ok, errors, warnings, normalized = TowerValidation.ValidateAll(source)
    if not ok then
        return false, errors, warnings
    end

    local nextTowers, nextCells, nextStats = buildIndex(normalized, size)
    towersById = nextTowers
    cellsByKey = nextCells
    stats = nextStats
    built = true

    return true, {}, warnings, Utils.DeepCopy(stats)
end

function SpatialIndex.InsertTower(tower)
    local ok, errors, normalized = TowerValidation.Validate(tower, 'Tower')
    if not ok then return false, errors end

    local definitions = {}
    for _, existing in pairs(towersById) do
        definitions[#definitions + 1] = Utils.DeepCopy(existing)
    end
    definitions[#definitions + 1] = normalized

    return SpatialIndex.Rebuild(definitions)
end

function SpatialIndex.GetNearbyTowers(coords)
    local key = SpatialIndex.GetCell(coords)
    if not key then
        stats.candidateCount = 0
        return {}
    end

    local idsInCell = cellsByKey[key] or {}
    local candidates = {}
    for _, id in ipairs(idsInCell) do
        candidates[#candidates + 1] = Utils.DeepCopy(towersById[id])
    end
    table.sort(candidates, function(left, right)
        return left.id < right.id
    end)
    stats.candidateCount = #candidates
    return candidates
end

function SpatialIndex.GetStats()
    return Utils.DeepCopy(stats)
end

function SpatialIndex.IsBuilt()
    return built
end
