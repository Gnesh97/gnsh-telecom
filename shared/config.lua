Config = Config or {}

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

local environmentCategories = {
    'OPEN_AREA',
    'URBAN',
    'BUILDING',
    'UNDERGROUND',
    'TUNNEL',
    'SPECIAL_ZONE',
}

local knownEnvironmentCategories = {}
for _, category in ipairs(environmentCategories) do
    knownEnvironmentCategories[category] = true
end

local function validateEnvironment(config, errors)
    local environment = config.Environment
    if type(environment) ~= 'table' then
        addError(errors, 'Environment must be a table')
        return
    end

    local allowed = environment.allowed
    if type(allowed) ~= 'table' then
        addError(errors, 'Environment.allowed must be a table')
    else
        for category, enabled in pairs(allowed) do
            if not knownEnvironmentCategories[category] then
                addError(errors, ('Environment.allowed contains unknown category: %s')
                    :format(tostring(category)))
            elseif type(enabled) ~= 'boolean' then
                addError(errors, ('Environment.allowed.%s must be boolean')
                    :format(category))
            end
        end
    end

    if type(environment.default) ~= 'string'
        or not knownEnvironmentCategories[environment.default]
        or type(allowed) ~= 'table'
        or allowed[environment.default] ~= true then
        addError(errors, 'Environment.default must be an allowed environment category')
    end

    local multipliers = environment.multipliers
    if type(multipliers) ~= 'table' then
        addError(errors, 'Environment.multipliers must be a table')
    else
        for category, multiplier in pairs(multipliers) do
            if not knownEnvironmentCategories[category] then
                addError(errors, ('Environment.multipliers contains unknown category: %s')
                    :format(tostring(category)))
            elseif not isNumber(multiplier) or multiplier < 0 or multiplier > 1 then
                addError(errors, ('Environment.multipliers.%s must be between 0 and 1')
                    :format(category))
            end
        end
        for _, category in ipairs(environmentCategories) do
            if type(allowed) == 'table' and allowed[category] == true
                and not isNumber(multipliers[category]) then
                addError(errors, ('Environment.multipliers.%s must be configured for allowed categories')
                    :format(category))
            end
        end
    end

    local zones = environment.zones
    if type(zones) ~= 'table' then
        addError(errors, 'Environment.zones must be a table')
        return
    end

    local seen = {}
    for index, zone in ipairs(zones) do
        local prefix = ('Environment.zones[%d]'):format(index)
        if type(zone) ~= 'table' then
            addError(errors, prefix .. ' must be a table')
        else
            if type(zone.id) ~= 'string' or zone.id == '' then
                addError(errors, prefix .. '.id must be a non-empty string')
            elseif seen[zone.id] then
                addError(errors, ('duplicate environment zone id: %s'):format(zone.id))
            else
                seen[zone.id] = true
            end

            if not isPoint(zone.coords) then
                addError(errors, prefix .. '.coords must contain numeric x, y and z')
            end
            if not isNumber(zone.radius) or zone.radius <= 0 then
                addError(errors, prefix .. '.radius must be greater than zero')
            end
            if not knownEnvironmentCategories[zone.category]
                or type(allowed) ~= 'table'
                or allowed[zone.category] ~= true then
                addError(errors, prefix .. '.category must be an allowed environment category')
            end
        end
    end
end

local function validateFailureScheduler(config, errors)
    local scheduler = config.FailureScheduler
    if type(scheduler) ~= 'table' then
        addError(errors, 'FailureScheduler must be a table')
        return
    end
    if type(scheduler.enabled) ~= 'boolean' then
        addError(errors, 'FailureScheduler.enabled must be boolean')
    end
    if not isNumber(scheduler.intervalMs) or scheduler.intervalMs <= 0 then
        addError(errors, 'FailureScheduler.intervalMs must be greater than zero')
    end
end

local function validatePersistence(config, errors)
    local persistence = config.Persistence
    if type(persistence) ~= 'table' then
        addError(errors, 'Persistence must be a table')
        return
    end
    if type(persistence.enabled) ~= 'boolean' then
        addError(errors, 'Persistence.enabled must be boolean')
    end
    local adapters = { auto = true, memory = true, oxmysql = true }
    if not adapters[persistence.adapter] then
        addError(errors, 'Persistence.adapter must be auto, memory or oxmysql')
    end
    if not isNumber(persistence.auditRetention)
        or persistence.auditRetention ~= math.floor(persistence.auditRetention)
        or persistence.auditRetention < 1 or persistence.auditRetention > 1000 then
        addError(errors, 'Persistence.auditRetention must be an integer between 1 and 1000')
    end
    if not isNumber(persistence.maxPayloadBytes)
        or persistence.maxPayloadBytes ~= math.floor(persistence.maxPayloadBytes)
        or persistence.maxPayloadBytes < 512 or persistence.maxPayloadBytes > 16384 then
        addError(errors, 'Persistence.maxPayloadBytes must be an integer between 512 and 16384')
    end
    if not isNumber(persistence.maxRetries)
        or persistence.maxRetries ~= math.floor(persistence.maxRetries)
        or persistence.maxRetries < 0 or persistence.maxRetries > 10 then
        addError(errors, 'Persistence.maxRetries must be an integer between 0 and 10')
    end
    if not isNumber(persistence.retryIntervalMs)
        or persistence.retryIntervalMs ~= math.floor(persistence.retryIntervalMs)
        or persistence.retryIntervalMs < 250 or persistence.retryIntervalMs > 60000 then
        addError(errors, 'Persistence.retryIntervalMs must be an integer between 250 and 60000')
    end
end

local function validateOperations(config, errors)
    local handover = config.Handover
    if type(handover) ~= 'table' then
        addError(errors, 'Handover must be a table')
    else
        if type(handover.enabled) ~= 'boolean' then
            addError(errors, 'Handover.enabled must be boolean')
        end
        if not isNumber(handover.minimumScoreAdvantage) or handover.minimumScoreAdvantage < 0 then
            addError(errors, 'Handover.minimumScoreAdvantage must be non-negative')
        end
        if not isNumber(handover.candidateHoldMs) or handover.candidateHoldMs < 0 then
            addError(errors, 'Handover.candidateHoldMs must be non-negative')
        end
        if not isNumber(handover.cooldownMs) or handover.cooldownMs < 0 then
            addError(errors, 'Handover.cooldownMs must be non-negative')
        end
    end

    local noc = config.NOC
    if type(noc) ~= 'table' then
        addError(errors, 'NOC must be a table')
    elseif type(noc.ace) ~= 'string' or noc.ace == '' then
        addError(errors, 'NOC.ace must be a non-empty string')
    else
        local positiveIntegerFields = {
            refreshIntervalMs = true,
            reconcileIntervalMs = true,
            subscriptionTtlMs = true,
            maxSubscriptions = true,
            maxTowers = true,
            maxEntities = true,
            maxDeltaEntities = true,
            maxDeltasPerSecond = true,
        }
        for field in pairs(positiveIntegerFields) do
            if noc[field] ~= nil
                and (not isNumber(noc[field]) or noc[field] ~= math.floor(noc[field])
                    or noc[field] < 1) then
                addError(errors, ('NOC.%s must be a positive integer'):format(field))
            end
        end
    end

    local backhaul = config.Backhaul
    if type(backhaul) ~= 'table' then
        addError(errors, 'Backhaul must be a table')
    else
        if type(backhaul.coreNodes) ~= 'table' then
            addError(errors, 'Backhaul.coreNodes must be a table')
        end
        if type(backhaul.towerNodes) ~= 'table' then
            addError(errors, 'Backhaul.towerNodes must be a table')
        end
        if type(backhaul.nodes) ~= 'table' or type(backhaul.links) ~= 'table' then
            addError(errors, 'Backhaul.nodes and Backhaul.links must be tables')
        end
        for _, field in ipairs({ 'towerRegions', 'regions' }) do
            if backhaul[field] ~= nil and type(backhaul[field]) ~= 'table' then
                addError(errors, ('Backhaul.%s must be a table'):format(field))
            end
        end
        for _, field in ipairs({
            'routeCacheTtlMs', 'maxRouteCacheEntries', 'maxRecomputeNodes',
            'maxPathHops', 'maxRegionalTowers',
        }) do
            local value = backhaul[field]
            if value ~= nil and (not isNumber(value) or value ~= math.floor(value) or value < 1) then
                addError(errors, ('Backhaul.%s must be a positive integer'):format(field))
            end
        end
    end

    local incidents = config.Incidents
    if type(incidents) ~= 'table' then
        addError(errors, 'Incidents must be a table')
    elseif type(incidents.autoCreate) ~= 'boolean'
        or type(incidents.severityByFailure) ~= 'table' then
        addError(errors, 'Incidents configuration is invalid')
    end

    local technician = config.Technician
    if type(technician) ~= 'table' or type(technician.jobs) ~= 'table' then
        addError(errors, 'Technician.jobs must be a table')
    else
        if not isNumber(technician.interactionDistance)
            or technician.interactionDistance <= 0 then
            addError(errors, 'Technician.interactionDistance must be greater than zero')
        end
        for name, duration in pairs({
            repairDurationMs = technician.repairDurationMs,
            diagnosticDurationMs = technician.diagnosticDurationMs,
        }) do
            if not isNumber(duration) or duration ~= math.floor(duration)
                or duration < 0 or duration > 3600000 then
                addError(errors, ('Technician.%s must be an integer between 0 and 3600000')
                    :format(name))
            end
        end
    end

    local sabotage = config.Sabotage
    if type(sabotage) ~= 'table' or type(sabotage.actions) ~= 'table' then
        addError(errors, 'Sabotage.actions must be a table')
    end

    local jammers = config.Jammers
    if type(jammers) ~= 'table' or not isNumber(jammers.maxActive)
        or jammers.maxActive < 0 then
        addError(errors, 'Jammers.maxActive must be non-negative')
    end

    local statistics = config.Statistics
    if type(statistics) ~= 'table' or not isNumber(statistics.flushIntervalMs)
        or statistics.flushIntervalMs <= 0 then
        addError(errors, 'Statistics.flushIntervalMs must be greater than zero')
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

local qosClasses = {
    'EMERGENCY',
    'VOICE',
    'SMS',
    'DATA_HIGH',
    'DATA_NORMAL',
    'BACKGROUND',
}

local function validateQoS(config, errors)
    if config.Features and config.Features.QoS == false then return end
    local qos = config.QoS
    if type(qos) ~= 'table' then
        addError(errors, 'QoS must be a table')
        return
    end
    if type(qos.priorities) ~= 'table' then
        addError(errors, 'QoS.priorities must be a table')
        return
    end
    for _, class in ipairs(qosClasses) do
        local priority = qos.priorities[class]
        if not isNumber(priority) or priority < 0 then
            addError(errors, ('QoS.priorities.%s must be non-negative'):format(class))
        end
    end
end

local serviceSessionClasses = {
    'VOICE',
    'SMS',
    'DATA',
    'GPS',
    'EMERGENCY',
    'BACKGROUND_DATA',
}

local function validateServiceSessions(config, errors)
    if config.Features and config.Features.ServiceSessions == false then return end
    local sessions = config.ServiceSessions
    if type(sessions) ~= 'table' then
        addError(errors, 'ServiceSessions must be a table')
        return
    end

    local integerFields = {
        maxActive = 1,
        maxActivePerSource = 1,
        maxMetadataFields = 1,
        maxMetadataDepth = 1,
        maxDurationMs = 1000,
        maxBeginsPerSecond = 1,
        maxUpdatesPerSecond = 1,
        maxEndsPerSecond = 1,
    }
    for field, minimum in pairs(integerFields) do
        local value = sessions[field]
        if not isNumber(value) or value ~= math.floor(value) or value < minimum then
            addError(errors, ('ServiceSessions.%s must be an integer at least %d')
                :format(field, minimum))
        end
    end

    if type(sessions.demands) ~= 'table' then
        addError(errors, 'ServiceSessions.demands must be a table')
        return
    end
    for _, service in ipairs(serviceSessionClasses) do
        local demand = sessions.demands[service]
        if not isNumber(demand) or demand < 0 then
            addError(errors, ('ServiceSessions.demands.%s must be non-negative')
                :format(service))
        end
    end
end

local function validateCarriers(config, errors)
    if not (config.Features and config.Features.Carriers == true) then return end
    if config.Carriers == nil then return end
    if type(config.Carriers) ~= 'table' then
        addError(errors, 'Carriers must be a table')
        return
    end
    if Carriers and Carriers.NormalizeAll then
        local ok, carrierErrors = Carriers.NormalizeAll(config.Carriers)
        if not ok then
            for _, message in ipairs(carrierErrors or {}) do
                addError(errors, message)
            end
        end
    end
end

local bridgeSections = {
    Framework = true,
    Inventory = true,
    Target = true,
    Phone = true,
    Dispatch = true,
    Notify = true,
    Progress = true,
}

local bridgeProviders = {
    Framework = {
        auto = true,
        standalone = true,
        qbcore = true,
        qbox = true,
        esx = true,
        custom = true,
    },
    Inventory = {
        auto = true,
        standalone = true,
        ox = true,
        qb = true,
        qs = true,
        custom = true,
    },
    Target = {
        auto = true,
        native = true,
        ox = true,
        qb = true,
        custom = true,
    },
    Phone = {
        auto = true,
        generic = true,
        lbphone = true,
        npwd = true,
        qs = true,
        custom = true,
    },
    Dispatch = {
        auto = true,
        native = true,
    },
    Notify = {
        auto = true,
        native = true,
        ox = true,
        framework = true,
    },
    Progress = {
        auto = true,
        native = true,
        ox = true,
    },
}

BridgeConfig = BridgeConfig or {}

local bridgeSectionNames = {
    framework = 'Framework',
    inventory = 'Inventory',
    target = 'Target',
    phone = 'Phone',
    dispatch = 'Dispatch',
    notify = 'Notify',
    progress = 'Progress',
}

local legacyProviderFields = {
    framework = 'Framework',
    inventory = 'InventoryBridge',
    target = 'TargetBridge',
    phone = 'PhoneBridge',
    notify = 'NotifyBridge',
    progress = 'ProgressBridge',
}

function BridgeConfig.GetProvider(category, sourceConfig)
    local sectionName = bridgeSectionNames[category]
    local currentConfig = type(sourceConfig) == 'table' and sourceConfig or Config
    local bridges = type(currentConfig) == 'table' and currentConfig.Bridges
    local section = type(bridges) == 'table' and bridges[sectionName] or nil
    local configured = type(section) == 'table' and section.provider or nil
    local legacyField = legacyProviderFields[category]
    local legacy = legacyField and type(currentConfig) == 'table'
        and currentConfig[legacyField] or nil
    if (configured == nil or configured == 'auto')
        and type(legacy) == 'string' and legacy ~= '' and legacy ~= 'auto' then
        configured = legacy
    end
    return type(configured) == 'string' and configured ~= '' and configured or 'auto'
end

function BridgeConfig.GetFallback(category, sourceConfig)
    local sectionName = bridgeSectionNames[category]
    local currentConfig = type(sourceConfig) == 'table' and sourceConfig or Config
    local bridges = type(currentConfig) == 'table' and currentConfig.Bridges
    local section = type(bridges) == 'table' and bridges[sectionName] or nil
    local fallback = type(section) == 'table' and section.fallback or nil
    return type(fallback) == 'string' and fallback ~= '' and fallback or nil
end

local function customDispatchName(config)
    local custom = type(config) == 'table' and config.CustomDispatch
    if type(custom) ~= 'table' then return 'custom-dispatch' end
    return type(custom.name) == 'string' and custom.name ~= ''
        and custom.name or 'custom-dispatch'
end

local function supportedBridgeValue(name, value, config)
    if bridgeProviders[name] and bridgeProviders[name][value] then return true end
    return name == 'Dispatch' and value == customDispatchName(config)
end

local function validBridgeName(value)
    return type(value) == 'string' and value ~= '' and #value <= 64
end

local function validateBridgeSection(name, section, config, errors)
    if type(section) ~= 'table' then
        addError(errors, ('Bridges.%s must be a table'):format(name))
        return
    end

    local provider = section.provider
    if not validBridgeName(provider) then
        addError(errors, ('Bridges.%s.provider must be a non-empty string'):format(name))
    elseif not supportedBridgeValue(name, provider, config) then
        addError(errors, ('Bridges.%s.provider is unsupported: %s'):format(name, provider))
    end

    if section.fallback ~= nil then
        if not validBridgeName(section.fallback) then
            addError(errors, ('Bridges.%s.fallback must be a non-empty string'):format(name))
        elseif not supportedBridgeValue(name, section.fallback, config) then
            addError(errors, ('Bridges.%s.fallback is unsupported: %s')
                :format(name, section.fallback))
        end
    end

    if section.required ~= nil and type(section.required) ~= 'boolean' then
        addError(errors, ('Bridges.%s.required must be boolean'):format(name))
    end
    if section.requireEnforcement ~= nil and type(section.requireEnforcement) ~= 'boolean' then
        addError(errors, ('Bridges.%s.requireEnforcement must be boolean'):format(name))
    end
end

local function validateBridges(config, errors)
    local bridges = config.Bridges
    if type(bridges) ~= 'table' then
        addError(errors, 'Bridges must be a table')
        return
    end

    for name in pairs(bridges) do
        if not bridgeSections[name] then
            addError(errors, ('Bridges contains unknown category: %s'):format(tostring(name)))
        end
    end
    for name in pairs(bridgeSections) do
        validateBridgeSection(name, bridges[name], config, errors)
    end
end

local function hasConfiguredMethod(config, field, methods)
    local value = config[field]
    if type(value) ~= 'table' then return false end
    for _, method in ipairs(methods) do
        if type(value[method]) == 'function' then return true end
    end
    return false
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
            local candidate = tower
            if TelecomDeployment and TelecomDeployment.NormalizeTower then
                local deploymentOk, deploymentErrors, deploymentTower =
                    TelecomDeployment.NormalizeTower(tower, prefix, config)
                for _, message in ipairs(deploymentErrors or {}) do
                    addError(errors, message)
                end
                if deploymentTower then candidate = deploymentTower end
                if not deploymentOk and not deploymentTower then candidate = tower end
            else
                if tower.class ~= nil
                    and (type(tower.class) ~= 'string'
                        or type(config.TowerArchetypes) ~= 'table'
                        or type(config.TowerArchetypes[tower.class]) ~= 'table') then
                    addError(errors, prefix .. '.unknown tower archetype')
                end
                if tower.coverageZone ~= nil
                    and (type(config.CoverageZones) ~= 'table'
                        or type(config.CoverageZones[tower.coverageZone]) ~= 'table') then
                    addError(errors, prefix .. '.unknown coverage zone')
                end
            end

            if type(candidate.id) ~= 'string' or candidate.id == '' then
                addError(errors, prefix .. '.id must be a non-empty string')
            elseif seen[candidate.id] then
                addError(errors, ('duplicate tower id: %s'):format(candidate.id))
            else
                seen[candidate.id] = true
            end

            if not isPoint(candidate.coords) then
                addError(errors, prefix .. '.coords must contain numeric x, y and z')
            end

            local coverage = candidate.coverage
            if type(coverage) ~= 'table' or not isNumber(coverage.radius)
                or coverage.radius <= 0 or not isNumber(coverage.minimum)
                or coverage.minimum < 0 or coverage.radius < coverage.minimum then
                addError(errors, prefix .. '.coverage is invalid')
            end

            if type(candidate.technologies) ~= 'table' or #candidate.technologies == 0 then
                addError(errors, prefix .. '.technologies must not be empty')
            else
                for _, technology in ipairs(candidate.technologies) do
                    local supported = Technologies
                        and Technologies.IsSupported
                        and Technologies.IsSupported(technology)
                    if not supported then
                        addError(errors, ('unsupported technology on %s: %s')
                            :format(tostring(candidate.id), tostring(technology)))
                    end
                end
            end

            local capacity = candidate.capacity
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

local function validateDeployment(config, errors)
    local deployment = config.Deployment
    if type(deployment) ~= 'table' then
        addError(errors, 'Deployment must be a table')
    elseif not isNumber(deployment.defaultCoverageMinimum)
        or deployment.defaultCoverageMinimum < 0
        or deployment.defaultCoverageMinimum > 100 then
        addError(errors, 'Deployment.defaultCoverageMinimum must be between 0 and 100')
    end

    local archetypes = config.TowerArchetypes
    if type(archetypes) ~= 'table' or next(archetypes) == nil then
        addError(errors, 'TowerArchetypes must contain at least one archetype')
    else
        for name, archetype in pairs(archetypes) do
            local prefix = ('TowerArchetypes.%s'):format(tostring(name))
            if type(name) ~= 'string' or name == '' then
                addError(errors, 'TowerArchetypes contains an invalid name')
            elseif type(archetype) ~= 'table' then
                addError(errors, prefix .. ' must be a table')
            else
                if not isNumber(archetype.coverageRadius) or archetype.coverageRadius <= 0 then
                    addError(errors, prefix .. '.coverageRadius must be greater than zero')
                end
                if not isNumber(archetype.capacity) or archetype.capacity <= 0 then
                    addError(errors, prefix .. '.capacity must be greater than zero')
                end
            end
        end
    end

    local zones = config.CoverageZones
    local requiredZones = {
        'METRO_CORE',
        'METRO_EDGE',
        'TOWN',
        'HIGHWAY',
        'RURAL',
        'WILDERNESS',
        'INTENTIONAL_DEADZONE',
    }
    if type(zones) ~= 'table' then
        addError(errors, 'CoverageZones must be a table')
    else
        for _, name in ipairs(requiredZones) do
            if type(zones[name]) ~= 'table' then
                addError(errors, ('CoverageZones.%s must be a table'):format(name))
            end
        end
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
    validateCarriers(config, errors)
    validateBridges(config, errors)
    local validFrameworks = {
        auto = true,
        standalone = true,
        qbcore = true,
        qbox = true,
        esx = true,
        custom = true,
    }
    local configuredFramework = BridgeConfig.GetProvider('framework', config)
    if not validFrameworks[configuredFramework] then
        addError(errors, 'Framework must be auto, standalone, qbcore, qbox, esx or custom')
    elseif configuredFramework == 'custom'
        and not hasConfiguredMethod(config, 'CustomFramework', {
            'GetPlayer',
            'GetStablePlayerId',
            'GetJob',
            'HasJob',
            'IsAdmin',
            'GetCharacterName',
            'AddMoney',
            'RemoveMoney',
        }) then
        addError(errors, 'CustomFramework must define at least one adapter method')
    end
    local validInventoryBridges = {
        auto = true,
        standalone = true,
        ox = true,
        qb = true,
        qs = true,
        custom = true,
    }
    local configuredInventory = BridgeConfig.GetProvider('inventory', config)
    if not validInventoryBridges[configuredInventory] then
        addError(errors, 'InventoryBridge must be auto, standalone, ox, qb, qs or custom')
    elseif configuredInventory == 'custom'
        and not hasConfiguredMethod(config, 'CustomInventory', {
            'HasItem',
            'RemoveItem',
            'AddItem',
            'CanCarry',
            'GetItemCount',
        }) then
        addError(errors, 'CustomInventory must define at least one adapter method')
    end
    local validTargetBridges = {
        auto = true,
        native = true,
        ox = true,
        qb = true,
        custom = true,
    }
    local configuredTarget = BridgeConfig.GetProvider('target', config)
    if not validTargetBridges[configuredTarget] then
        addError(errors, 'TargetBridge must be auto, native, ox, qb or custom')
    elseif configuredTarget == 'custom'
        and not hasConfiguredMethod(config, 'CustomTarget', {
            'AddEntityInteraction',
            'AddModelInteraction',
            'AddZoneInteraction',
            'RemoveInteraction',
        }) then
        addError(errors, 'CustomTarget must define at least one adapter method')
    end
    local validPhoneBridges = { auto = true, generic = true, lbphone = true, npwd = true, qs = true, custom = true }
    local configuredPhone = BridgeConfig.GetProvider('phone', config)
    if not validPhoneBridges[configuredPhone] then
        addError(errors, 'PhoneBridge must be auto, generic, lbphone, npwd, qs or custom')
    end
    if type(config.Spatial) ~= 'table' or not isNumber(config.Spatial.cellSize)
        or config.Spatial.cellSize <= 0 then
        addError(errors, 'Spatial.cellSize must be greater than zero')
    end
    if config.Sectors ~= nil then
        if type(config.Sectors) ~= 'table' then
            addError(errors, 'Sectors must be a table')
        else
            for _, field in ipairs({ 'maxPerTower', 'maxCandidates' }) do
                local value = config.Sectors[field]
                if not isNumber(value) or value ~= math.floor(value) or value < 1 then
                    addError(errors, ('Sectors.%s must be a positive integer'):format(field))
                end
            end
            if isNumber(config.Sectors.maxPerTower)
                and isNumber(config.Sectors.maxCandidates)
                and config.Sectors.maxCandidates < config.Sectors.maxPerTower then
                addError(errors, 'Sectors.maxCandidates must be at least maxPerTower')
            end
        end
    end
    if type(config.Signal) ~= 'table' or not isNumber(config.Signal.Base)
        or config.Signal.Base <= 0 then
        addError(errors, 'Signal.Base must be greater than zero')
    else
        validateSignalLevels(config, errors)
    end

    validateServices(config, errors)
    validateCapacity(config, errors)
    validateServiceSessions(config, errors)
    validateQoS(config, errors)
    validateEnvironment(config, errors)
    validateFailureScheduler(config, errors)
    validatePersistence(config, errors)
    validateOperations(config, errors)
    validateDeployment(config, errors)
    validateTowers(config, errors, warnings)

    return #errors == 0, errors, warnings
end
