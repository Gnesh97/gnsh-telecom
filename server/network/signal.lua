Signal = Signal or {}

local function isUnavailable(tower)
    local state = tower.state
    return state == Enums.TowerState.MAINTENANCE
        or state == Enums.TowerState.OFFLINE
        or state == Enums.TowerState.DESTROYED
end

local function getBaseSignal()
    local base = Config and Config.Signal and Config.Signal.Base
    if type(base) ~= 'number' or base ~= base or base == math.huge
        or base == -math.huge then
        return 100
    end
    return base
end

function Signal.CalculateDistance(left, right)
    if not Utils.IsPoint(left) or not Utils.IsPoint(right) then return nil end

    local dx = left.x - right.x
    local dy = left.y - right.y
    local dz = left.z - right.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function getEnvironmentConfig()
    return Config and Config.Environment or {}
end

local function isKnownEnvironment(category)
    local environment = getEnvironmentConfig()
    return type(category) == 'string'
        and type(environment.allowed) == 'table'
        and environment.allowed[category] == true
end

local function getDefaultEnvironmentCategory()
    local environment = getEnvironmentConfig()
    if isKnownEnvironment(environment.default) then return environment.default end
    return 'OPEN_AREA'
end

local function findReportedZone(coords, zoneId)
    if not Utils.IsPoint(coords) or type(zoneId) ~= 'string' then return nil end

    local zones = getEnvironmentConfig().zones
    if type(zones) ~= 'table' then return nil end

    for _, zone in ipairs(zones) do
        if type(zone) == 'table' and zone.id == zoneId
            and Utils.IsPoint(zone.coords)
            and type(zone.radius) == 'number'
            and zone.radius > 0
            and isKnownEnvironment(zone.category) then
            local distance = Signal.CalculateDistance(zone.coords, coords)
            if distance and distance <= zone.radius then return zone end
        end
    end
    return nil
end

function Signal.ResolveEnvironment(coords, reported)
    local category = getDefaultEnvironmentCategory()
    local zoneId
    local reportedCategory = type(reported) == 'table' and reported.category or nil
    local reportedZoneId = type(reported) == 'table' and reported.zoneId or nil
    local configuredZone = findReportedZone(coords, reportedZoneId)

    if configuredZone then
        category = configuredZone.category
        zoneId = configuredZone.id
    elseif isKnownEnvironment(reportedCategory) then
        category = reportedCategory
    end

    local multiplier = getEnvironmentConfig().multipliers
        and getEnvironmentConfig().multipliers[category]
    if type(multiplier) ~= 'number' or multiplier ~= multiplier
        or multiplier == math.huge or multiplier == -math.huge then
        multiplier = 1.0
    end
    multiplier = Utils.Clamp(multiplier, 0, 1)

    return {
        category = category,
        zoneId = zoneId,
        multiplier = multiplier,
    }
end

function Signal.CalculateRaw(tower, coords, environmentContext)
    if type(tower) ~= 'table' or not Utils.IsPoint(tower.coords)
        or not Utils.IsPoint(coords) or isUnavailable(tower) then
        return 0
    end

    local coverage = tower.coverage
    if type(coverage) ~= 'table' or type(coverage.radius) ~= 'number'
        or coverage.radius ~= coverage.radius or coverage.radius <= 0 then
        return 0
    end

    local distance = Signal.CalculateDistance(tower.coords, coords)
    if not distance or distance >= coverage.radius then return 0 end

    local distanceFactor = 1 - (distance / coverage.radius)
    local signal = getBaseSignal() * distanceFactor
    local environment = Signal.ResolveEnvironment(coords, environmentContext)
    signal = signal * environment.multiplier
    return Utils.Clamp(signal, 0, 100)
end

function Signal.GetLevel(signal)
    signal = Utils.Clamp(tonumber(signal) or 0, 0, 100)
    local levels = Config and Config.Signal and Config.Signal.Levels or {}
    local order = {
        'EXCELLENT',
        'GOOD',
        'NORMAL',
        'WEAK',
        'VERY_WEAK',
        'NO_SERVICE',
    }

    for _, name in ipairs(order) do
        local level = levels[name]
        if type(level) == 'table' and signal >= level.min then
            return name
        end
    end

    return Enums.SignalLevel.NO_SERVICE
end
