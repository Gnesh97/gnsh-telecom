TowerSectors = TowerSectors or {}

local DEFAULT_MAX_PER_TOWER = 16
local DEFAULT_MAX_CANDIDATES = 64
local EPSILON = 0.000000001
local definitionsByTowerId = {}
local runtimeByKey = {}
local lastStats = {
    sectorChecks = 0,
    candidateCount = 0,
    towerCount = 0,
}

local unavailableStates = {
    [Enums.TowerState.MAINTENANCE] = true,
    [Enums.TowerState.OFFLINE] = true,
    [Enums.TowerState.DESTROYED] = true,
}

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function configLimit(name, fallback, maximum)
    local value = Config and Config.Sectors and tonumber(Config.Sectors[name])
    if not isFiniteNumber(value) or value ~= math.floor(value) or value < 1 then
        value = fallback
    end
    return math.min(math.floor(value), maximum or value)
end

local function maxPerTower()
    return configLimit('maxPerTower', DEFAULT_MAX_PER_TOWER, 64)
end

local function maxCandidates()
    return configLimit('maxCandidates', DEFAULT_MAX_CANDIDATES, 256)
end

local function validState(value)
    for _, state in pairs(Enums.TowerState) do
        if value == state then return true end
    end
    return false
end

local function sectorCapacity(value)
    if isFiniteNumber(value) then return value end
    if type(value) == 'table' and isFiniteNumber(value.maximum) then
        return value.maximum
    end
    return nil
end

local function normalizeAngle(value)
    local normalized = value % 360
    if normalized < 0 then normalized = normalized + 360 end
    if normalized >= 360 then normalized = 0 end
    return normalized
end

local function addError(errors, path, message)
    errors[#errors + 1] = path .. ' ' .. message
end

local function validateTechnologies(value, errors, path)
    if type(value) ~= 'table' or #value == 0 then
        addError(errors, path, 'technologies must contain at least one technology')
        return
    end

    local seen = {}
    for index, technology in ipairs(value) do
        if not Technologies or not Technologies.IsSupported
            or not Technologies.IsSupported(technology) then
            addError(errors, path, ('unsupported technology at index %d: %s')
                :format(index, tostring(technology)))
        elseif seen[technology] then
            addError(errors, path, ('duplicate technology: %s'):format(technology))
        else
            seen[technology] = true
        end
    end
end

function TowerSectors.Validate(sector, path, tower)
    path = path or 'Sector'
    local errors = {}
    if type(sector) ~= 'table' then
        return false, { path .. ' must be a table' }, nil
    end

    local normalized = copy(sector)
    if type(normalized.id) ~= 'string' or normalized.id:match('^%s*$') then
        addError(errors, path, 'id must be a non-empty string')
    elseif #normalized.id > 64 then
        addError(errors, path, 'id must not exceed 64 characters')
    end

    if not isFiniteNumber(normalized.azimuth)
        or normalized.azimuth < 0 or normalized.azimuth >= 360 then
        addError(errors, path, 'azimuth must be between 0 and 360 degrees')
    end

    if not isFiniteNumber(normalized.beamWidth)
        or normalized.beamWidth <= 0 or normalized.beamWidth > 360 then
        addError(errors, path, 'beamWidth must be greater than zero and at most 360')
    end

    if not isFiniteNumber(normalized.coverageRadius) or normalized.coverageRadius <= 0 then
        addError(errors, path, 'coverageRadius must be greater than zero')
    elseif tower and tower.coverage and isFiniteNumber(tower.coverage.radius)
        and normalized.coverageRadius > tower.coverage.radius then
        addError(errors, path, 'coverageRadius must not exceed tower coverage.radius')
    end

    validateTechnologies(normalized.technologies, errors, path)

    local capacity = sectorCapacity(normalized.capacity)
    if not capacity or capacity <= 0 then
        addError(errors, path, 'capacity must be greater than zero')
    end

    if normalized.health == nil then normalized.health = 100 end
    if not isFiniteNumber(normalized.health) or normalized.health < 0
        or normalized.health > 100 then
        addError(errors, path, 'health must be between 0 and 100')
    end

    normalized.state = normalized.state or Enums.TowerState.OPERATIONAL
    if not validState(normalized.state) then
        addError(errors, path, 'state is not a valid TowerState')
    end

    if #errors > 0 then return false, errors, nil end
    normalized.azimuth = normalizeAngle(normalized.azimuth)
    normalized.capacity = capacity
    return true, {}, normalized
end

function TowerSectors.ValidateAll(sectors, tower, path)
    path = path or 'sectors'
    if sectors == nil then return true, {}, {} end
    if type(sectors) ~= 'table' then
        return false, { path .. ' must be a table' }, nil
    end

    local errors = {}
    local normalized = {}
    local seen = {}
    local limit = maxPerTower()
    if #sectors > limit then
        addError(errors, path, ('maximum of %d sectors is allowed per tower'):format(limit))
    end

    for index, sector in ipairs(sectors) do
        local sectorPath = ('%s[%d]'):format(path, index)
        local ok, sectorErrors, value = TowerSectors.Validate(sector, sectorPath, tower)
        if not ok then
            for _, message in ipairs(sectorErrors or {}) do errors[#errors + 1] = message end
        elseif seen[value.id] then
            addError(errors, path, ('duplicate sector id: %s'):format(value.id))
        else
            seen[value.id] = true
            normalized[#normalized + 1] = value
        end
    end

    if #errors > 0 then return false, errors, nil end
    return true, {}, normalized
end

local function runtimeKey(towerId, sectorId)
    return tostring(towerId) .. '\31' .. tostring(sectorId)
end

local function staticSector(towerId, sectorId)
    local sectors = definitionsByTowerId[towerId]
    if type(sectors) ~= 'table' then return nil end
    for _, sector in ipairs(sectors) do
        if sector.id == sectorId then return sector end
    end
    return nil
end

local function createRuntime(towerId, sector, backhaulStatus)
    return {
        towerId = towerId,
        sectorId = sector.id,
        connectedClients = 0,
        loadPercent = 0,
        effectiveCapacity = sector.capacity,
        capacityMultiplier = 1.0,
        congestion = Enums.CongestionState.NORMAL,
        capacityEffects = {},
        failureEffects = {
            signalMultiplier = 1.0,
            capacityMultiplier = 1.0,
            coverageMultiplier = 1.0,
            serviceFailures = {},
            activeFailures = {},
        },
        activeFailures = {},
        health = sector.health,
        state = sector.state,
        baseHealth = sector.health,
        baseState = sector.state,
        backhaulStatus = backhaulStatus or Enums.BackhaulState.ONLINE,
        baseBackhaulStatus = backhaulStatus or Enums.BackhaulState.ONLINE,
        updatedAt = 0,
    }
end

function TowerSectors.Initialize(towers)
    local nextDefinitions = {}
    local nextRuntime = {}
    local towerCount = 0

    for _, tower in ipairs(towers or {}) do
        local sectors = type(tower) == 'table' and tower.sectors or nil
        if type(sectors) == 'table' and #sectors > 0 then
            nextDefinitions[tower.id] = copy(sectors)
            towerCount = towerCount + 1
            for _, sector in ipairs(sectors) do
                local backhaul = tower.backhaul and tower.backhaul.status
                nextRuntime[runtimeKey(tower.id, sector.id)] = createRuntime(
                    tower.id,
                    sector,
                    backhaul
                )
            end
        end
    end

    definitionsByTowerId = nextDefinitions
    runtimeByKey = nextRuntime
    lastStats = {
        sectorChecks = 0,
        candidateCount = 0,
        towerCount = towerCount,
    }
    return true
end

function TowerSectors.GetForTower(towerOrId)
    if type(towerOrId) == 'table' then
        return copy(towerOrId.sectors or {})
    end
    return copy(definitionsByTowerId[towerOrId] or {})
end

TowerSectors.GetSectors = TowerSectors.GetForTower

function TowerSectors.HasSectors(towerOrId)
    local sectors = TowerSectors.GetForTower(towerOrId)
    return #sectors > 0
end

function TowerSectors.Get(towerId, sectorId)
    return copy(staticSector(towerId, sectorId))
end

function TowerSectors.GetAll()
    local result = {}
    local towerIds = {}
    for towerId in pairs(definitionsByTowerId) do towerIds[#towerIds + 1] = towerId end
    table.sort(towerIds)
    for _, towerId in ipairs(towerIds) do
        for _, sector in ipairs(definitionsByTowerId[towerId]) do
            local value = copy(sector)
            value.towerId = towerId
            result[#result + 1] = value
        end
    end
    return result
end

function TowerSectors.GetRuntime(towerId, sectorId)
    return copy(runtimeByKey[runtimeKey(towerId, sectorId)])
end

function TowerSectors.GetRuntimeForTower(towerId)
    local result = {}
    for _, sector in ipairs(definitionsByTowerId[towerId] or {}) do
        result[#result + 1] = TowerSectors.GetRuntime(towerId, sector.id)
    end
    return result
end

function TowerSectors.UpdateRuntime(towerId, sectorId, patch)
    local key = runtimeKey(towerId, sectorId)
    local current = runtimeByKey[key]
    if not current or type(patch) ~= 'table' then return false end

    local nextState = copy(current)
    for name, value in pairs(patch) do nextState[name] = copy(value) end
    if nextState.state ~= nil and not validState(nextState.state) then return false end
    if nextState.health ~= nil and (not isFiniteNumber(nextState.health)
        or nextState.health < 0 or nextState.health > 100) then return false end
    runtimeByKey[key] = nextState
    return true, copy(nextState)
end

function TowerSectors.SetState(towerId, sectorId, state)
    if not validState(state) then return false, 'invalid_state' end
    return TowerSectors.UpdateRuntime(towerId, sectorId, {
        state = state,
        baseState = state,
    })
end

function TowerSectors.SetHealth(towerId, sectorId, health)
    if not isFiniteNumber(health) or health < 0 or health > 100 then
        return false, 'invalid_health'
    end
    return TowerSectors.UpdateRuntime(towerId, sectorId, {
        health = health,
        baseHealth = health,
    })
end

function TowerSectors.SetLoad(towerId, sectorId, loadPercent)
    if not isFiniteNumber(loadPercent) or loadPercent < 0 then
        return false, 'invalid_load_percent'
    end
    return TowerSectors.UpdateRuntime(towerId, sectorId, { loadPercent = loadPercent })
end

function TowerSectors.IsAvailable(towerId, sectorId, sector)
    if sector and unavailableStates[sector.state] then return false end
    local runtime = TowerSectors.GetRuntime(towerId, sectorId)
    local state = runtime and runtime.state or sector and sector.state
    return not unavailableStates[state]
end

function TowerSectors.GetEffectiveCapacity(towerId, sectorId, runtime)
    local sector = TowerSectors.Get(towerId, sectorId)
    local configured = sector and sector.capacity
    if not isFiniteNumber(configured) or configured <= 0 then return nil end
    runtime = runtime or TowerSectors.GetRuntime(towerId, sectorId)
    local multiplier = runtime and runtime.capacityMultiplier
    if not isFiniteNumber(multiplier) or multiplier <= 0 then multiplier = 1 end
    return configured * multiplier
end

function TowerSectors.GetBearing(origin, target)
    if not Utils.IsPoint(origin) or not Utils.IsPoint(target) then return nil end
    local deltaX = target.x - origin.x
    local deltaY = target.y - origin.y
    if math.abs(deltaX) <= EPSILON and math.abs(deltaY) <= EPSILON then return nil end
    local bearing = math.deg(math.atan(deltaY, deltaX))
    return normalizeAngle(bearing)
end

function TowerSectors.GetAngularDistance(left, right)
    if not isFiniteNumber(left) or not isFiniteNumber(right) then return nil end
    local difference = math.abs(normalizeAngle(left) - normalizeAngle(right))
    return math.min(difference, 360 - difference)
end

function TowerSectors.IsBearingWithin(sector, bearing)
    if type(sector) ~= 'table' or not isFiniteNumber(bearing)
        or not isFiniteNumber(sector.azimuth) or not isFiniteNumber(sector.beamWidth)
        or sector.beamWidth <= 0 then
        return false
    end
    if sector.beamWidth >= 360 then return true end
    local distance = TowerSectors.GetAngularDistance(sector.azimuth, bearing)
    return distance ~= nil and distance <= sector.beamWidth / 2 + EPSILON
end

function TowerSectors.IsWithinBeam(sector, towerCoords, coords)
    if type(coords) == 'number' then
        return TowerSectors.IsBearingWithin(sector, coords)
    end
    if not Utils.IsPoint(towerCoords) or not Utils.IsPoint(coords) then return false end
    local deltaX = coords.x - towerCoords.x
    local deltaY = coords.y - towerCoords.y
    if math.abs(deltaX) <= EPSILON and math.abs(deltaY) <= EPSILON then return true end
    return TowerSectors.IsBearingWithin(sector, TowerSectors.GetBearing(towerCoords, coords))
end

function TowerSectors.GetCoverage(tower, coords)
    if type(tower) ~= 'table' or not Utils.IsPoint(tower.coords)
        or not Utils.IsPoint(coords) then return {} end

    local sectors = TowerSectors.GetForTower(tower)
    local result = {}
    local checks = 0
    local limit = math.min(#sectors, maxCandidates())
    for index = 1, limit do
        local sector = sectors[index]
        checks = checks + 1
        local distance = Signal and Signal.CalculateDistance
            and Signal.CalculateDistance(tower.coords, coords)
            or nil
        local runtime = TowerSectors.GetRuntime(tower.id, sector.id)
        local radius = sector.coverageRadius
        if distance and distance < radius
            and TowerSectors.IsAvailable(tower.id, sector.id, sector)
            and TowerSectors.IsWithinBeam(sector, tower.coords, coords) then
            local value = copy(sector)
            value.distance = distance
            value.runtime = runtime
            result[#result + 1] = value
        end
    end
    lastStats.sectorChecks = checks
    lastStats.candidateCount = #result
    return result
end

function TowerSectors.GetStats()
    return copy(lastStats)
end
