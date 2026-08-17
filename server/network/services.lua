Services = Services or {}

local unavailableTowerStates = {
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

local function normalizeSignal(value)
    if not isFiniteNumber(value) then return 0 end
    if value < 0 then return 0 end
    if value > 100 then return 100 end
    return value
end

local function serviceFailureActive(failures, service)
    local failure = failures and failures[service]
    if failure == true then return true end
    if type(failure) == 'table' then
        return failure.active ~= false
    end
    return false
end

local function getCongestionEffects(congestion, explicit)
    if type(explicit) == 'table' then return explicit end
    if Capacity and Capacity.GetEffects then
        return Capacity.GetEffects(congestion)
    end
    return {
        dataPerformance = 'NORMAL',
        dataAvailable = true,
        callSetupReliability = 1.0,
        smsDelayMs = 0,
    }
end

local performanceRank = {
    NORMAL = 1,
    DEGRADED = 2,
    SLOW = 3,
    VERY_SLOW = 4,
    UNAVAILABLE = 5,
}

local function worstPerformance(left, right)
    if not left then return right end
    if not right then return left end
    if (performanceRank[right] or 0) > (performanceRank[left] or 0) then
        return right
    end
    return left
end

local function applyQos(serviceState, qosState)
    if type(serviceState) ~= 'table' or type(qosState) ~= 'table' then
        return serviceState
    end

    serviceState.qos = qosState
    if qosState.blocked then
        serviceState.available = false
        serviceState.reason = 'qos'
        serviceState.blockedBy = 'qos'
        return serviceState
    end

    if qosState.degraded and serviceState.available then
        serviceState.reason = 'qos_degraded'
        serviceState.blockedBy = 'qos'
        local ratio = tonumber(qosState.ratio) or 0
        if serviceState.dataPerformance then
            serviceState.dataPerformance = ratio < 0.5
                and worstPerformance(serviceState.dataPerformance, 'VERY_SLOW')
                or worstPerformance(serviceState.dataPerformance, 'SLOW')
        end
        if serviceState.callSetupReliability then
            serviceState.callSetupReliability = serviceState.callSetupReliability
                * math.max(0, math.min(1, ratio))
        end
        if serviceState.smsDelayMs then
            serviceState.smsDelayMs = serviceState.smsDelayMs
                + math.floor((1 - math.max(0, math.min(1, ratio))) * 1000)
        end
    end
    return serviceState
end

local function evaluateService(service, signal, connected, context)
    local minimumSignal = ServicePolicy.GetMinimumSignal(service)
    local congestionEffects = getCongestionEffects(
        context.congestion,
        context.congestionEffects
    )
    local technologyPerformance = Technologies and Technologies.GetServicePerformance
        and Technologies.GetServicePerformance(context.technology, service)
    local dataPerformance = service == 'data'
        and worstPerformance(congestionEffects.dataPerformance, technologyPerformance)
        or nil
    local state = {
        available = false,
        signal = signal,
        minimumSignal = minimumSignal,
        reason = 'policy',
        blockedBy = 'policy',
        congestion = context.congestion,
        dataPerformance = dataPerformance,
        callSetupReliability = service == 'voice'
            and congestionEffects.callSetupReliability
            or nil,
        smsDelayMs = service == 'sms' and congestionEffects.smsDelayMs or nil,
    }

    if not isFiniteNumber(minimumSignal) then
        return state
    end

    if not connected then
        state.reason = 'no_service'
        state.blockedBy = 'signal'
        return state
    end

    if context.technology == Technologies.NO_SERVICE then
        state.reason = 'technology'
        state.blockedBy = 'technology'
        return state
    end

    if context.technology and Technologies.IsSupported
        and Technologies.IsSupported(context.technology)
        and Technologies.SupportsService
        and not Technologies.SupportsService(context.technology, service) then
        state.reason = 'technology'
        state.blockedBy = 'technology'
        return state
    end

    if unavailableTowerStates[context.towerState] then
        state.reason = 'tower'
        state.blockedBy = 'tower'
        return state
    end

    if context.backhaulStatus == Enums.BackhaulState.OFFLINE then
        state.reason = 'backhaul'
        state.blockedBy = 'backhaul'
        return state
    end

    if context.congestionBlocks and context.congestionBlocks[service] then
        state.reason = 'congestion'
        state.blockedBy = 'congestion'
        return state
    end

    if service == 'data' and congestionEffects.dataAvailable == false then
        state.reason = 'congestion'
        state.blockedBy = 'congestion'
        return state
    end

    if serviceFailureActive(context.serviceFailures, service) then
        state.reason = 'failure'
        state.blockedBy = 'failure'
        return state
    end

    if signal < minimumSignal then
        state.reason = 'signal'
        state.blockedBy = 'signal'
        return state
    end

    state.available = true
    state.reason = 'available'
    state.blockedBy = nil
    return state
end

function Services.Evaluate(connectionState, context)
    context = context or {}
    connectionState = type(connectionState) == 'table' and connectionState or {}

    local signal = normalizeSignal(connectionState.signal)
    local connected = type(connectionState.towerId) == 'string' and signal > 0
    local qosEnabled = not (Config and Config.Features)
        or Config.Features.QoS ~= false
    local evaluationContext = {
        towerState = context.towerState or connectionState.towerState,
        backhaulStatus = context.backhaulStatus or connectionState.backhaulStatus,
        congestion = context.congestion or connectionState.congestion,
        congestionEffects = context.congestionEffects or connectionState.capacityEffects,
        congestionBlocks = context.congestionBlocks or connectionState.congestionBlocks,
        serviceFailures = context.serviceFailures or connectionState.serviceFailures,
        technology = context.technology or connectionState.technology,
        qos = qosEnabled and (context.qos or connectionState.qos) or nil,
    }
    if qosEnabled and not evaluationContext.qos and QosEngine
        and QosEngine.GetSourceServiceStates and connectionState.source ~= nil then
        local ok, qos = pcall(QosEngine.GetSourceServiceStates, connectionState.source)
        if ok then evaluationContext.qos = qos end
    end
    local serviceStates = {}

    for _, service in ipairs(ServicePolicy.Names or {}) do
        local serviceState = evaluateService(
            service,
            signal,
            connected,
            evaluationContext
        )
        serviceStates[service] = applyQos(
            serviceState,
            evaluationContext.qos and evaluationContext.qos[service]
        )
    end

    return {
        source = connectionState.source,
        towerId = connectionState.towerId,
        signal = signal,
        technology = evaluationContext.technology,
        qos = evaluationContext.qos,
        services = serviceStates,
    }
end

function Services.CanUse(source, service)
    if not Connections or not Connections.Get then
        return false, {
            available = false,
            reason = 'connection_unavailable',
            blockedBy = 'connection',
        }
    end

    local connectionState = Connections.Get(source)
    if not connectionState then
        return false, {
            available = false,
            reason = 'player_not_connected',
            blockedBy = 'connection',
        }
    end

    local evaluation = Services.Evaluate(connectionState)
    local serviceState = evaluation.services[service]
    if not serviceState then
        return false, {
            available = false,
            reason = 'unknown_service',
            blockedBy = 'policy',
        }
    end

    return serviceState.available, serviceState
end
