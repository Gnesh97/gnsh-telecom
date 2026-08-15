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

local function evaluateService(service, signal, connected, context)
    local minimumSignal = ServicePolicy.GetMinimumSignal(service)
    local state = {
        available = false,
        signal = signal,
        minimumSignal = minimumSignal,
        reason = 'policy',
        blockedBy = 'policy',
        congestion = context.congestion,
    }

    if not isFiniteNumber(minimumSignal) then
        return state
    end

    if not connected then
        state.reason = 'no_service'
        state.blockedBy = 'signal'
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
    local evaluationContext = {
        towerState = context.towerState or connectionState.towerState,
        backhaulStatus = context.backhaulStatus or connectionState.backhaulStatus,
        congestion = context.congestion or connectionState.congestion,
        congestionBlocks = context.congestionBlocks or connectionState.congestionBlocks,
        serviceFailures = context.serviceFailures or connectionState.serviceFailures,
    }
    local serviceStates = {}

    for _, service in ipairs(ServicePolicy.Names or {}) do
        serviceStates[service] = evaluateService(
            service,
            signal,
            connected,
            evaluationContext
        )
    end

    return {
        source = connectionState.source,
        towerId = connectionState.towerId,
        signal = signal,
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
