Selection = Selection or {}

local defaultWeights = {
    signalWeight = 1.0,
    loadPenaltyWeight = 0.25,
    healthPenaltyWeight = 0.20,
    technologyPenaltyWeight = 0.10,
}

local unavailableStates = {
    [Enums.TowerState.MAINTENANCE] = true,
    [Enums.TowerState.OFFLINE] = true,
    [Enums.TowerState.DESTROYED] = true,
}

local function isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function readWeight(configured, fallback)
    if not isFiniteNumber(configured) or configured < 0 then
        return fallback
    end
    return configured
end

local function getWeights(options)
    local configured = options and options.weights or Config.Selection or {}
    return {
        signalWeight = readWeight(configured.signalWeight, defaultWeights.signalWeight),
        loadPenaltyWeight = readWeight(
            configured.loadPenaltyWeight,
            defaultWeights.loadPenaltyWeight
        ),
        healthPenaltyWeight = readWeight(
            configured.healthPenaltyWeight,
            defaultWeights.healthPenaltyWeight
        ),
        technologyPenaltyWeight = readWeight(
            configured.technologyPenaltyWeight,
            defaultWeights.technologyPenaltyWeight
        ),
    }
end

local function getCandidateId(candidate)
    if type(candidate) ~= 'table' then return nil end
    if type(candidate.towerId) == 'string' then return candidate.towerId end
    if type(candidate.tower) == 'table' and type(candidate.tower.id) == 'string' then
        return candidate.tower.id
    end
    return nil
end

local function getSector(candidate)
    if type(candidate) ~= 'table' or type(candidate.sectorId) ~= 'string' then
        return nil
    end
    if type(candidate.sector) == 'table' then return candidate.sector end
    if TowerSectors and TowerSectors.Get then
        return TowerSectors.Get(getCandidateId(candidate), candidate.sectorId)
    end
    return nil
end

local function getRuntimeState(candidate, options)
    local towerId = getCandidateId(candidate)
    if not towerId then return nil end

    local sectorId = candidate.sectorId
    if type(sectorId) == 'string' and options and options.runtimeBySectorId then
        local composite = towerId .. ':' .. sectorId
        return options.runtimeBySectorId[composite]
            or options.runtimeBySectorId[sectorId]
    end

    if type(sectorId) == 'string' and TowerSectors and TowerSectors.GetRuntime then
        local sectorRuntime = TowerSectors.GetRuntime(towerId, sectorId)
        if sectorRuntime then return sectorRuntime end
    end

    if options and options.runtimeByTowerId ~= nil then
        return options.runtimeByTowerId[towerId]
    end

    if TowerRegistry and TowerRegistry.GetRuntimeState then
        return TowerRegistry.GetRuntimeState(towerId)
    end

    return nil
end

local function getTowerState(candidate, runtime)
    if runtime and runtime.state ~= nil then return runtime.state end
    return candidate.tower and candidate.tower.state
end

local function getLoadPercent(candidate, runtime)
    local load = runtime and runtime.loadPercent
    if not isFiniteNumber(load) then
        local connectedClients = runtime and runtime.connectedClients
        local sector = getSector(candidate)
        local capacity = runtime and runtime.effectiveCapacity
            or candidate.tower
                and candidate.tower.capacity
                and candidate.tower.capacity.maximum
            or sector and sector.capacity
        if isFiniteNumber(connectedClients) and isFiniteNumber(capacity) and capacity > 0 then
            load = (connectedClients / capacity) * 100
        end
    end
    return math.max(0, isFiniteNumber(load) and load or 0)
end

local function getHealth(candidate, runtime)
    local health = runtime and runtime.health
    if not isFiniteNumber(health) then
        local sector = getSector(candidate)
        health = sector and sector.health
    end
    if not isFiniteNumber(health) then
        local hardware = candidate.tower and candidate.tower.hardware
        health = hardware and hardware.health
    end
    return clamp(isFiniteNumber(health) and health or 100, 0, 100)
end

local function supportsTechnology(candidate, preferredTechnology)
    if preferredTechnology == nil then return true end
    local sector = getSector(candidate)
    local technologies = sector and sector.technologies or candidate.tower.technologies
    if type(technologies) ~= 'table' then return false end
    for _, technology in ipairs(technologies) do
        if technology == preferredTechnology then return true end
    end
    return false
end

local function getTechnologyPenalty(candidate, options)
    local preferredTechnology = options and options.preferredTechnology
    if preferredTechnology == nil then return 0 end
    return supportsTechnology(candidate, preferredTechnology) and 0 or 100
end

local function buildScoreDetails(candidate, runtime, options)
    local weights = getWeights(options)
    local signal = clamp(isFiniteNumber(candidate.signal) and candidate.signal or 0, 0, 100)
    local loadPercent = getLoadPercent(candidate, runtime)
    local health = getHealth(candidate, runtime)
    local technologyPenaltyPercent = getTechnologyPenalty(candidate, options)

    local signalScore = signal * weights.signalWeight
    local loadPenalty = loadPercent * weights.loadPenaltyWeight
    local healthPenalty = (100 - health) * weights.healthPenaltyWeight
    local technologyPenalty = technologyPenaltyPercent * weights.technologyPenaltyWeight

    return {
        score = signalScore - loadPenalty - healthPenalty - technologyPenalty,
        signal = signal,
        signalScore = signalScore,
        loadPercent = loadPercent,
        loadPenalty = loadPenalty,
        health = health,
        healthPenalty = healthPenalty,
        technologyPenaltyPercent = technologyPenaltyPercent,
        technologyPenalty = technologyPenalty,
        state = getTowerState(candidate, runtime),
    }
end

function Selection.Score(candidate, options)
    local towerId = getCandidateId(candidate)
    if not towerId or type(candidate.tower) ~= 'table' or not isFiniteNumber(candidate.signal)
        or candidate.signal <= 0 then
        return nil, nil
    end

    local runtime = getRuntimeState(candidate, options)
    if unavailableStates[getTowerState(candidate, runtime)] then
        return nil, nil
    end

    local details = buildScoreDetails(candidate, runtime, options)
    return details.score, details
end

local function compareRanked(left, right)
    if left.score ~= right.score then return left.score > right.score end
    if left.signal ~= right.signal then return left.signal > right.signal end

    local leftLoad = left.scoreDetails.loadPercent
    local rightLoad = right.scoreDetails.loadPercent
    if leftLoad ~= rightLoad then return leftLoad < rightLoad end

    if left.towerId == right.towerId
        and tostring(left.sectorId or '') ~= tostring(right.sectorId or '') then
        return tostring(left.sectorId or '') < tostring(right.sectorId or '')
    end

    return left.towerId < right.towerId
end

function Selection.Rank(candidates, options)
    local ranked = {}
    for _, candidate in ipairs(candidates or {}) do
        local score, details = Selection.Score(candidate, options)
        if score ~= nil then
            local result = Utils.DeepCopy(candidate)
            result.score = score
            result.scoreDetails = details
            ranked[#ranked + 1] = result
        end
    end

    table.sort(ranked, compareRanked)
    return ranked
end

function Selection.GetBest(candidates, options)
    return Selection.Rank(candidates, options)[1]
end
