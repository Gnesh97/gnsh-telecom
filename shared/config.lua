Config = {
    ResourceName = 'gnsh-telecom',
    Version = '0.1.0',
    Locale = 'en',

    Debug = {
        enabled = true,
        logLevel = 'info',
        adminAce = 'gnsh-telecom.admin',
    },

    Features = {
        Capacity = true,
        Failures = true,
        Technician = false,
        Incidents = false,
        NOC = false,
        Handover = true,
        Backhaul = false,
        Sabotage = false,
        Jammers = false,
        Statistics = false,
    },

    Signal = {
        Base = 100,
        Levels = {
            EXCELLENT = { min = 90, max = 100 },
            GOOD = { min = 75, max = 89 },
            NORMAL = { min = 55, max = 74 },
            WEAK = { min = 30, max = 54 },
            VERY_WEAK = { min = 10, max = 29 },
            NO_SERVICE = { min = 0, max = 9 },
        },
    },

    Services = {
        voice = { minimumSignal = 25 },
        sms = { minimumSignal = 15 },
        data = { minimumSignal = 35 },
        gps = { minimumSignal = 20 },
        emergency = { minimumSignal = 10 },
    },

    Capacity = {
        thresholds = {
            busy = 60,
            congested = 80,
            critical = 95,
            overloaded = 100,
        },
        effects = {
            NORMAL = {
                signalMultiplier = 1.00,
                dataPerformance = 'NORMAL',
                dataAvailable = true,
                callSetupReliability = 1.00,
                smsDelayMs = 0,
            },
            BUSY = {
                signalMultiplier = 0.98,
                dataPerformance = 'DEGRADED',
                dataAvailable = true,
                callSetupReliability = 0.98,
                smsDelayMs = 250,
            },
            CONGESTED = {
                signalMultiplier = 0.92,
                dataPerformance = 'SLOW',
                dataAvailable = true,
                callSetupReliability = 0.90,
                smsDelayMs = 750,
            },
            CRITICAL = {
                signalMultiplier = 0.82,
                dataPerformance = 'VERY_SLOW',
                dataAvailable = true,
                callSetupReliability = 0.75,
                smsDelayMs = 1500,
            },
            OVERLOADED = {
                signalMultiplier = 0.65,
                dataPerformance = 'UNAVAILABLE',
                dataAvailable = false,
                callSetupReliability = 0.50,
                smsDelayMs = 3000,
            },
        },
    },

    Performance = {
        stationaryIntervalMs = 3000,
        walkingIntervalMs = 1500,
        vehicleIntervalMs = 500,
        meaningfulSignalDelta = 2,
    },

    Spatial = {
        cellSize = 1000.0,
    },

    Selection = {
        signalWeight = 1.0,
        loadPenaltyWeight = 0.25,
        healthPenaltyWeight = 0.20,
        technologyPenaltyWeight = 0.10,
    },

    Environment = {
        default = 'OPEN_AREA',
        allowed = {
            OPEN_AREA = true,
            URBAN = true,
            BUILDING = true,
            UNDERGROUND = true,
            TUNNEL = true,
            SPECIAL_ZONE = true,
        },
        multipliers = {
            OPEN_AREA = 1.00,
            URBAN = 0.90,
            BUILDING = 0.75,
            UNDERGROUND = 0.55,
            TUNNEL = 0.45,
            SPECIAL_ZONE = 0.80,
        },
        zones = {},
    },

    PhoneBridge = 'auto',
    Towers = {
        {
            id = 'TEST_TOWER_A',
            coords = vector3(1988.33, 3733.77, 32.43),
            coverage = {
                radius = 1000.0,
                minimum = 10.0,
            },
            technologies = { '4G', '5G' },
            capacity = {
                maximum = 100,
            },
        },

        {
            id = 'TEST_TOWER_B',
            coords = vector3(1336.12, 3556.3, 34.91),
            coverage = {
                radius = 1000.0,
                minimum = 10.0,
            },
            technologies = { '4G' },
            capacity = {
                maximum = 100,
            },
        },
    },
}

local function addError(errors, message)
    errors[#errors + 1] = message
end

local function addWarning(warnings, message)
    warnings[#warnings + 1] = message
end

local function isNumber(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function isPoint(value)
    local valueType = type(value)
    local supportsCoordinates = valueType == 'table'
        or valueType == 'userdata'
        or valueType == 'vector3'

    return supportsCoordinates
        and isNumber(value.x)
        and isNumber(value.y)
        and isNumber(value.z)
end

local function validateSignalLevels(config, errors)
    local levels = config.Signal and config.Signal.Levels
    if type(levels) ~= 'table' then
        addError(errors, 'Signal.Levels must be a table')
        return
    end

    for name, level in pairs(levels) do
        if type(level) ~= 'table' or not isNumber(level.min) or not isNumber(level.max) then
            addError(errors, ('invalid signal level definition: %s'):format(tostring(name)))
        elseif level.min < 0 or level.max > 100 or level.min > level.max then
            addError(errors, ('invalid signal level range: %s'):format(tostring(name)))
        end
    end
end

local function validateServices(config, errors)
    if type(config.Services) ~= 'table' then
        addError(errors, 'Services must be a table')
        return
    end

    for service, policy in pairs(config.Services) do
        if type(policy) ~= 'table' or not isNumber(policy.minimumSignal)
            or policy.minimumSignal < 0 or policy.minimumSignal > 100 then
            addError(errors, ('invalid service policy: %s'):format(tostring(service)))
        end
    end
end

local function validateCapacity(config, errors)
    local capacity = config.Capacity
    if type(capacity) ~= 'table' then
        addError(errors, 'Capacity must be a table')
        return
    end

    local thresholds = capacity.thresholds
    local thresholdNames = { 'busy', 'congested', 'critical', 'overloaded' }
    if type(thresholds) ~= 'table' then
        addError(errors, 'Capacity.thresholds must be a table')
    else
        local previous
        for _, name in ipairs(thresholdNames) do
            local value = thresholds[name]
            if not isNumber(value) or value < 0 or value > 100 then
                addError(errors, ('Capacity.thresholds.%s must be between 0 and 100')
                    :format(name))
            elseif previous ~= nil and value <= previous then
                addError(errors, 'Capacity thresholds must be strictly increasing')
            end
            previous = value
        end
    end

    local effects = capacity.effects
    local effectNames = { 'NORMAL', 'BUSY', 'CONGESTED', 'CRITICAL', 'OVERLOADED' }
    local performanceNames = {
        NORMAL = true,
        DEGRADED = true,
        SLOW = true,
        VERY_SLOW = true,
        UNAVAILABLE = true,
    }
    if type(effects) ~= 'table' then
        addError(errors, 'Capacity.effects must be a table')
        return
    end

    for _, name in ipairs(effectNames) do
        local effect = effects[name]
        if type(effect) ~= 'table' then
            addError(errors, ('Capacity.effects.%s must be a table'):format(name))
        else
            if not isNumber(effect.signalMultiplier)
                or effect.signalMultiplier <= 0 or effect.signalMultiplier > 1 then
                addError(errors, ('Capacity.effects.%s.signalMultiplier must be greater than zero and at most one')
                    :format(name))
            end
            if not performanceNames[effect.dataPerformance] then
                addError(errors, ('Capacity.effects.%s.dataPerformance is invalid'):format(name))
            end
            if type(effect.dataAvailable) ~= 'boolean' then
                addError(errors, ('Capacity.effects.%s.dataAvailable must be boolean'):format(name))
            end
            if not isNumber(effect.callSetupReliability)
                or effect.callSetupReliability < 0 or effect.callSetupReliability > 1 then
                addError(errors, ('Capacity.effects.%s.callSetupReliability must be between 0 and 1')
                    :format(name))
            end
            if not isNumber(effect.smsDelayMs) or effect.smsDelayMs < 0 then
                addError(errors, ('Capacity.effects.%s.smsDelayMs must be non-negative'):format(name))
            end
        end
    end
end

local function validateFeatures(config, errors)
    if type(config.Features) ~= 'table' then return end
    for name, enabled in pairs(config.Features) do
        if type(enabled) ~= 'boolean' then
            addError(errors, ('feature flag must be boolean: %s'):format(tostring(name)))
        end
    end
end

local function validateDebug(config, errors)
    if type(config.Debug) ~= 'table' then return end
    if type(config.Debug.enabled) ~= 'boolean' then
        addError(errors, 'Debug.enabled must be boolean')
    end
    local validLevels = { debug = true, info = true, warn = true, error = true }
    if not validLevels[config.Debug.logLevel] then
        addError(errors, 'Debug.logLevel must be debug, info, warn or error')
    end
    if type(config.Debug.adminAce) ~= 'string' or config.Debug.adminAce == '' then
        addError(errors, 'Debug.adminAce must be a non-empty string')
    end
end

local function validateTowers(config, errors, warnings)
    if type(config.Towers) ~= 'table' then
        addError(errors, 'Towers must be a table')
        return
    end

    local seen = {}
    for index, tower in ipairs(config.Towers) do
        local prefix = ('Towers[%d]'):format(index)
        if type(tower) ~= 'table' then
            addError(errors, prefix .. ' must be a table')
        else
            if type(tower.id) ~= 'string' or tower.id == '' then
                addError(errors, prefix .. '.id must be a non-empty string')
            elseif seen[tower.id] then
                addError(errors, ('duplicate tower id: %s'):format(tower.id))
            else
                seen[tower.id] = true
            end

            if not isPoint(tower.coords) then
                addError(errors, prefix .. '.coords must contain numeric x, y and z')
            end

            local coverage = tower.coverage
            if type(coverage) ~= 'table' or not isNumber(coverage.radius)
                or coverage.radius <= 0 or not isNumber(coverage.minimum)
                or coverage.minimum < 0 or coverage.radius < coverage.minimum then
                addError(errors, prefix .. '.coverage is invalid')
            end

            if type(tower.technologies) ~= 'table' or #tower.technologies == 0 then
                addError(errors, prefix .. '.technologies must not be empty')
            else
                for _, technology in ipairs(tower.technologies) do
                    local supported = Technologies
                        and Technologies.IsSupported
                        and Technologies.IsSupported(technology)
                    if not supported then
                        addError(errors, ('unsupported technology on %s: %s')
                            :format(tostring(tower.id), tostring(technology)))
                    end
                end
            end

            local capacity = tower.capacity
            if type(capacity) ~= 'table' or not isNumber(capacity.maximum)
                or capacity.maximum <= 0 then
                addError(errors, prefix .. '.capacity.maximum must be greater than zero')
            end
        end
    end

    if #config.Towers == 0 then
        addWarning(warnings, 'no towers configured; telecom core will start without coverage')
    end
end

function Config.Validate(config)
    config = config or Config
    local errors, warnings = {}, {}

    if type(config) ~= 'table' then
        return false, { 'Config must be a table' }, warnings
    end
    if type(config.ResourceName) ~= 'string' or config.ResourceName == '' then
        addError(errors, 'ResourceName must be a non-empty string')
    end
    if type(config.Version) ~= 'string' or config.Version == '' then
        addError(errors, 'Version must be a non-empty string')
    end
    if type(config.Debug) ~= 'table' then addError(errors, 'Debug must be a table') end
    if type(config.Features) ~= 'table' then addError(errors, 'Features must be a table') end
    validateDebug(config, errors)
    validateFeatures(config, errors)
    local validPhoneBridges = { auto = true, generic = true, lbphone = true, npwd = true, qs = true, custom = true }
    if not validPhoneBridges[config.PhoneBridge] then
        addError(errors, 'PhoneBridge must be auto, generic, lbphone, npwd, qs or custom')
    end
    if type(config.Spatial) ~= 'table' or not isNumber(config.Spatial.cellSize)
        or config.Spatial.cellSize <= 0 then
        addError(errors, 'Spatial.cellSize must be greater than zero')
    end
    if type(config.Signal) ~= 'table' or not isNumber(config.Signal.Base)
        or config.Signal.Base <= 0 then
        addError(errors, 'Signal.Base must be greater than zero')
    else
        validateSignalLevels(config, errors)
    end

    validateServices(config, errors)
    validateCapacity(config, errors)
    validateTowers(config, errors, warnings)

    return #errors == 0, errors, warnings
end
