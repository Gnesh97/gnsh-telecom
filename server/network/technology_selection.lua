TechnologySelection = TechnologySelection or {}

local fallbackOrder = {
    Technologies.FIVE_G,
    Technologies.FOUR_G,
    Technologies.THREE_G,
    Technologies.EDGE,
}

local blockedFailureStates = {
    FAILED = true,
    FAILURE = true,
    OFFLINE = true,
    DOWN = true,
    UNAVAILABLE = true,
}

local blockedCongestionStates = {
    OVERLOADED = true,
    CRITICAL = true,
}

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, nested in pairs(value) do result[key] = copy(nested) end
    return result
end

local function upper(value)
    return type(value) == 'string' and value:upper() or nil
end

local function stateBlocks(value)
    if value == true then return true end
    if value == false or value == nil then return false end
    if type(value) == 'number' then return value > 0 end
    if type(value) == 'string' then
        return blockedFailureStates[upper(value)] == true
    end
    if type(value) ~= 'table' then return false end
    if value.active == false or value.available == false or value.failed == true then
        return true
    end
    if value.state ~= nil and blockedFailureStates[upper(value.state)] then
        return true
    end
    return value.active == true
end

local function mapBlocks(map, technology)
    if type(map) ~= 'table' then return false end
    if map[technology] ~= nil then return stateBlocks(map[technology]) end
    for _, value in ipairs(map) do
        if value == technology then return true end
    end
    return false
end

local function congestionBlocks(value, constraints)
    if value == nil then return false end
    if value == false then return false end
    if type(value) == 'table' then
        value = value.state or value.status or value.congestion
    end
    local normalized = upper(value)
    if constraints and type(constraints.fallbackCongestionStates) == 'table'
        and constraints.fallbackCongestionStates[normalized] ~= nil then
        return constraints.fallbackCongestionStates[normalized] == true
    end
    return blockedCongestionStates[normalized] == true
end

local function getTower(value)
    if type(value) ~= 'table' then return nil end
    return type(value.tower) == 'table' and value.tower or value
end

local function getSector(value, constraints, tower)
    if type(value) == 'table' and type(value.sector) == 'table' then
        return value.sector
    end
    if constraints and type(constraints.sector) == 'table' then
        return constraints.sector
    end
    if tower and type(tower.sector) == 'table' then return tower.sector end
    return nil
end

local function getTechnologies(tower, sector)
    if sector and type(sector.technologies) == 'table' and #sector.technologies > 0 then
        return sector.technologies
    end
    return tower and tower.technologies or {}
end

local function containsTechnology(technologies, technology)
    if type(technologies) ~= 'table' then return false end
    for _, value in ipairs(technologies) do
        if value == technology then return true end
    end
    return false
end

local function requestedTechnology(connection, constraints)
    if type(constraints) == 'table' then
        if Technologies.IsSupported(constraints.preferredTechnology) then
            return constraints.preferredTechnology
        end
        if Technologies.IsSupported(constraints.requestedTechnology) then
            return constraints.requestedTechnology
        end
    end
    if type(connection) == 'table' then
        if Technologies.IsSupported(connection.requestedTechnology) then
            return connection.requestedTechnology
        end
        if Technologies.IsSupported(connection.technology) then
            return connection.technology
        end
    end
    return nil
end

local function signalFor(connection, constraints)
    if type(constraints) == 'table' and type(constraints.signal) == 'number' then
        return constraints.signal
    end
    if type(connection) == 'table' and type(connection.signal) == 'number' then
        return connection.signal
    end
    return nil
end

local function technologyBlocked(technology, connection, constraints, signal)
    local maps = {
        constraints and constraints.failedTechnologies,
        constraints and constraints.technologyFailures,
        constraints and constraints.unavailableTechnologies,
        type(connection) == 'table' and connection.failedTechnologies,
        type(connection) == 'table' and connection.technologyFailures,
    }
    for _, map in ipairs(maps) do
        if mapBlocks(map, technology) then return 'failure' end
    end

    local congestionMaps = {
        constraints and constraints.congestionByTechnology,
        constraints and constraints.technologyCongestion,
        type(connection) == 'table' and connection.congestionByTechnology,
    }
    for _, map in ipairs(congestionMaps) do
        if type(map) == 'table' and congestionBlocks(map[technology], constraints) then
            return 'congestion'
        end
    end

    local capacityMap = constraints and constraints.capacityByTechnology
    if type(capacityMap) == 'table' and type(capacityMap[technology]) == 'number'
        and capacityMap[technology] <= 0 then
        return 'capacity'
    end
    local availabilityMap = constraints and constraints.availableByTechnology
    if type(availabilityMap) == 'table' and availabilityMap[technology] == false then
        return 'capacity'
    end

    local minimums = constraints and constraints.minimumSignalByTechnology
    local minimum = type(minimums) == 'table' and minimums[technology]
        or constraints and constraints.minimumSignal
    if type(minimum) == 'number' and type(signal) == 'number' and signal < minimum then
        return 'signal'
    end
    return nil
end

local function orderedAvailable(technologies)
    local available = {}
    for _, technology in ipairs(technologies or {}) do
        if Technologies.IsSupported(technology) then available[technology] = true end
    end
    return available
end

function TechnologySelection.GetFallbackOrder()
    return copy(fallbackOrder)
end

function TechnologySelection.Resolve(towerOrCandidate, connection, constraints)
    constraints = type(constraints) == 'table' and constraints or {}
    local tower = getTower(towerOrCandidate)
    local sector = getSector(towerOrCandidate, constraints, tower)
    local technologies = getTechnologies(tower, sector)
    local available = orderedAvailable(technologies)
    local signal = signalFor(connection, constraints)
    local requested = requestedTechnology(connection, constraints)
    local blockedTechnology
    local blockedReason
    local selected

    for _, technology in ipairs(fallbackOrder) do
        if available[technology] then
            local reason = technologyBlocked(technology, connection, constraints, signal)
            if reason then
                blockedTechnology = blockedTechnology or technology
                blockedReason = blockedReason or reason
            else
                selected = technology
                break
            end
        end
    end

    if not selected then
        return {
            available = false,
            technology = Technologies.NO_SERVICE,
            reason = 'no_available_technology',
            fallbackFrom = requested or blockedTechnology,
            blockedTechnology = blockedTechnology,
            blockedReason = blockedReason,
            signal = signal,
            capacityMultiplier = 0,
            dataPerformance = 'UNAVAILABLE',
            services = {},
        }
    end

    local fallbackFrom = nil
    if requested and requested ~= selected then
        fallbackFrom = requested
    elseif blockedTechnology and blockedTechnology ~= selected then
        fallbackFrom = blockedTechnology
    end

    local result = {
        available = true,
        technology = selected,
        reason = fallbackFrom and 'fallback' or 'selected',
        fallbackFrom = fallbackFrom,
        blockedTechnology = blockedTechnology,
        blockedReason = blockedReason,
        signal = signal,
        capacityMultiplier = Technologies.GetCapacityMultiplier(selected),
        priority = Technologies.GetPriority(selected),
        dataPerformance = Technologies.GetServicePerformance(selected, 'data'),
        services = {},
    }
    for _, service in ipairs({ 'voice', 'sms', 'data', 'gps', 'emergency' }) do
        result.services[service] = Technologies.SupportsService(selected, service)
    end
    return result
end

TechnologySelection.ResolveTechnology = TechnologySelection.Resolve
