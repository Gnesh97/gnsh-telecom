Capacity = Capacity or {}

local defaultEffects = {
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

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    if type(value) ~= 'table' then return value end

    local result = {}
    for key, nested in pairs(value) do result[key] = copy(nested) end
    return result
end

local function now()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return 0
end

local function configuredThresholds(options)
    local configured = options and options.thresholds
        or Config and Config.Capacity and Config.Capacity.thresholds
        or {}
    return {
        busy = isFiniteNumber(configured.busy) and configured.busy or 60,
        congested = isFiniteNumber(configured.congested) and configured.congested or 80,
        critical = isFiniteNumber(configured.critical) and configured.critical or 95,
        overloaded = isFiniteNumber(configured.overloaded) and configured.overloaded or 100,
    }
end

local function normalizeEffect(state, configured)
    local fallback = defaultEffects[state] or defaultEffects.NORMAL
    configured = type(configured) == 'table' and configured or {}

    return {
        signalMultiplier = isFiniteNumber(configured.signalMultiplier)
                and configured.signalMultiplier > 0
            and configured.signalMultiplier
            or fallback.signalMultiplier,
        dataPerformance = type(configured.dataPerformance) == 'string'
            and configured.dataPerformance
            or fallback.dataPerformance,
        dataAvailable = type(configured.dataAvailable) == 'boolean'
            and configured.dataAvailable
            or fallback.dataAvailable,
        callSetupReliability = isFiniteNumber(configured.callSetupReliability)
                and clamp(configured.callSetupReliability, 0, 1)
            or fallback.callSetupReliability,
        smsDelayMs = isFiniteNumber(configured.smsDelayMs)
                and math.max(0, configured.smsDelayMs)
            or fallback.smsDelayMs,
    }
end

local function configuredEffects(options)
    return options and options.effects
        or Config and Config.Capacity and Config.Capacity.effects
        or defaultEffects
end

function Capacity.GetCongestionState(loadPercent, options)
    local load = isFiniteNumber(loadPercent) and math.max(0, loadPercent) or 0
    local thresholds = configuredThresholds(options)

    if load < thresholds.busy then return Enums.CongestionState.NORMAL end
    if load < thresholds.congested then return Enums.CongestionState.BUSY end
    if load < thresholds.critical then return Enums.CongestionState.CONGESTED end
    if load <= thresholds.overloaded then return Enums.CongestionState.CRITICAL end
    return Enums.CongestionState.OVERLOADED
end

function Capacity.GetEffects(congestion, options)
    local state = congestion or Enums.CongestionState.NORMAL
    local effects = configuredEffects(options)
    return normalizeEffect(state, effects[state])
end

function Capacity.Calculate(connectedClients, effectiveCapacity, options)
    local clients = isFiniteNumber(connectedClients) and math.max(0, connectedClients) or 0
    local capacity = isFiniteNumber(effectiveCapacity) and effectiveCapacity or 0
    if capacity <= 0 then capacity = 1 end

    local loadPercent = (clients / capacity) * 100
    local congestion = Capacity.GetCongestionState(loadPercent, options)
    return {
        connectedClients = clients,
        effectiveCapacity = capacity,
        loadPercent = loadPercent,
        congestion = congestion,
        effects = Capacity.GetEffects(congestion, options),
    }
end

function Capacity.ApplySignal(signal, congestion, options)
    local normalized = isFiniteNumber(signal) and clamp(signal, 0, 100) or 0
    local effects = options and options.signalMultiplier
        and normalizeEffect(congestion or Enums.CongestionState.NORMAL, options)
        or Capacity.GetEffects(congestion, options)
    return clamp(normalized * effects.signalMultiplier, 0, 100)
end

function Capacity.GetEffectiveCapacity(tower, runtime)
    local configured = tower and tower.capacity and tower.capacity.maximum
    if not isFiniteNumber(configured) or configured <= 0 then return nil end

    local multiplier = runtime and runtime.capacityMultiplier
    if not isFiniteNumber(multiplier) or multiplier <= 0 then multiplier = 1 end
    return configured * multiplier
end

function Capacity.GetEffectiveTechnologyCapacity(effectiveCapacity, technology)
    if not isFiniteNumber(effectiveCapacity) or effectiveCapacity < 0 then return nil end
    local multiplier = Technologies and Technologies.GetCapacityMultiplier
        and Technologies.GetCapacityMultiplier(technology)
        or 1.0
    if not isFiniteNumber(multiplier) or multiplier < 0 then multiplier = 1.0 end
    return effectiveCapacity * multiplier
end

function Capacity.GetEffectiveSectorCapacity(towerId, sectorId, runtime)
    if not TowerSectors or not TowerSectors.GetEffectiveCapacity then return nil end
    return TowerSectors.GetEffectiveCapacity(towerId, sectorId, runtime)
end

local function sectorDefinitions(towerId)
    if not TowerSectors or not TowerSectors.GetForTower then return {} end
    return TowerSectors.GetForTower(towerId)
end

function Capacity.RecalculateSector(towerId, sectorId, connectionStates)
    if type(towerId) ~= 'string' or type(sectorId) ~= 'string'
        or not TowerRegistry or not TowerState or not TowerSectors then
        return nil
    end

    local tower = TowerRegistry.Get(towerId)
    local sector = TowerSectors.Get and TowerSectors.Get(towerId, sectorId)
    local runtime = TowerSectors.GetRuntime and TowerSectors.GetRuntime(towerId, sectorId)
    if not tower or not sector or not runtime then return nil end

    local connectedClients = 0
    for _, connection in ipairs(connectionStates or {}) do
        if type(connection) == 'table'
            and connection.towerId == towerId
            and connection.sectorId == sectorId then
            connectedClients = connectedClients + 1
        end
    end

    local result = Capacity.Calculate(
        connectedClients,
        Capacity.GetEffectiveSectorCapacity(towerId, sectorId, runtime)
    )
    if isFiniteNumber(runtime.debugLoadPercent) then
        result.loadPercent = math.max(0, runtime.debugLoadPercent)
        result.congestion = Capacity.GetCongestionState(result.loadPercent)
        result.effects = Capacity.GetEffects(result.congestion)
    end
    result.towerId = towerId
    result.sectorId = sectorId

    TowerSectors.UpdateRuntime(towerId, sectorId, {
        connectedClients = result.connectedClients,
        effectiveCapacity = result.effectiveCapacity,
        loadPercent = result.loadPercent,
        congestion = result.congestion,
        capacityEffects = result.effects,
        updatedAt = now(),
    })
    return result
end

function Capacity.RecalculateTower(towerId, connectionStates)
    if type(towerId) ~= 'string' or not TowerRegistry or not TowerState then return nil end

    local tower = TowerRegistry.Get(towerId)
    local runtime = TowerRegistry.GetRuntimeState(towerId)
    if not tower or not runtime then return nil end

    local connectedClients = 0
    for _, connection in ipairs(connectionStates or {}) do
        if type(connection) == 'table' and connection.towerId == towerId then
            connectedClients = connectedClients + 1
        end
    end

    local sectors = sectorDefinitions(towerId)
    local sectorResults = {}
    local effectiveCapacity
    if #sectors > 0 then
        effectiveCapacity = 0
        for _, sector in ipairs(sectors) do
            local sectorResult = Capacity.RecalculateSector(towerId, sector.id, connectionStates)
            sectorResults[sector.id] = sectorResult
            if sectorResult and isFiniteNumber(sectorResult.effectiveCapacity) then
                effectiveCapacity = effectiveCapacity + sectorResult.effectiveCapacity
            end
        end
        if effectiveCapacity <= 0 then effectiveCapacity = nil end
    end

    local result = Capacity.Calculate(
        connectedClients,
        effectiveCapacity or Capacity.GetEffectiveCapacity(tower, runtime)
    )
    if isFiniteNumber(runtime.debugLoadPercent) then
        result.loadPercent = math.max(0, runtime.debugLoadPercent)
        result.congestion = Capacity.GetCongestionState(result.loadPercent)
        result.effects = Capacity.GetEffects(result.congestion)
    end
    result.towerId = towerId
    result.sectors = sectorResults

    TowerState.Update(towerId, {
        connectedClients = result.connectedClients,
        effectiveCapacity = result.effectiveCapacity,
        loadPercent = result.loadPercent,
        congestion = result.congestion,
        capacityEffects = result.effects,
        updatedAt = now(),
    })
    return result
end

function Capacity.RecalculateAll(connectionStates)
    local results = {}
    if not TowerRegistry or not TowerRegistry.GetAll then return results end

    for _, tower in ipairs(TowerRegistry.GetAll()) do
        results[tower.id] = Capacity.RecalculateTower(tower.id, connectionStates or {})
    end
    return results
end

local function recalculateDebugLoad(towerId)
    local states = Connections and Connections.GetAll
        and Connections.GetAll()
        or {}
    local result = Capacity.RecalculateTower(towerId, states)
    if Connections and Connections.RefreshCapacity then
        Connections.RefreshCapacity({ towerId })
    end
    return result
end

function Capacity.SetDebugLoad(towerId, loadPercent)
    if type(towerId) ~= 'string' or not TowerRegistry.Exists(towerId) then
        return false, 'unknown_tower'
    end

    local value = tonumber(loadPercent)
    if not isFiniteNumber(value) or value < 0 or value > 10000 then
        return false, 'invalid_load_percent'
    end

    if not TowerState.Update(towerId, { debugLoadPercent = value }) then
        return false, 'tower_state_unavailable'
    end
    return true, recalculateDebugLoad(towerId)
end

function Capacity.ClearDebugLoad(towerId)
    if type(towerId) ~= 'string' or not TowerRegistry.Exists(towerId) then
        return false, 'unknown_tower'
    end

    local current = TowerState.Get(towerId)
    if not current then return false, 'tower_state_unavailable' end
    local nextState = copy(current)
    nextState.debugLoadPercent = nil
    if not TowerState.Set(towerId, nextState) then
        return false, 'tower_state_unavailable'
    end
    return true, recalculateDebugLoad(towerId)
end

function Capacity.ReconcileConnectionChange(previous, current, connectionStates)
    local affected = {}
    if type(previous) == 'table' and type(previous.towerId) == 'string' then
        affected[previous.towerId] = true
    end
    if type(current) == 'table' and type(current.towerId) == 'string' then
        affected[current.towerId] = true
    end

    local ids = {}
    for towerId in pairs(affected) do ids[#ids + 1] = towerId end
    table.sort(ids)

    local results = {}
    for _, towerId in ipairs(ids) do
        results[towerId] = Capacity.RecalculateTower(towerId, connectionStates or {})
    end
    return affected, results
end

function Capacity.ApplyToConnection(connectionState, runtimeState)
    if type(connectionState) ~= 'table' then return nil end

    local nextState = copy(connectionState)
    local rawSignal = nextState.rawSignal
    if not isFiniteNumber(rawSignal) then rawSignal = nextState.signal end
    rawSignal = isFiniteNumber(rawSignal) and clamp(rawSignal, 0, 100) or 0

    if not runtimeState and nextState.towerId and nextState.sectorId
        and TowerSectors and TowerSectors.GetRuntime then
        runtimeState = TowerSectors.GetRuntime(nextState.towerId, nextState.sectorId)
    end
    if not runtimeState and nextState.towerId and TowerRegistry then
        runtimeState = TowerRegistry.GetRuntimeState(nextState.towerId)
    end
    if type(runtimeState) ~= 'table' then
        nextState.rawSignal = rawSignal
        return nextState
    end

    local congestion = runtimeState.congestion or Enums.CongestionState.NORMAL
    local effects = runtimeState.capacityEffects
    if type(effects) ~= 'table' or not effects.signalMultiplier then
        effects = Capacity.GetEffects(congestion)
    else
        effects = normalizeEffect(congestion, effects)
    end

    nextState.rawSignal = rawSignal
    nextState.signal = Capacity.ApplySignal(rawSignal, congestion, effects)
    nextState.signalLevel = Signal.GetLevel(nextState.signal)
    nextState.congestion = congestion
    nextState.loadPercent = runtimeState.loadPercent or 0
    nextState.effectiveCapacity = runtimeState.effectiveCapacity
    nextState.capacityEffects = copy(effects)
    nextState.technologyCapacityMultiplier = Technologies
        and Technologies.GetCapacityMultiplier
        and Technologies.GetCapacityMultiplier(nextState.technology)
        or 1.0
    nextState.effectiveTechnologyCapacity = Capacity.GetEffectiveTechnologyCapacity(
        nextState.effectiveCapacity,
        nextState.technology
    )
    if Services and Services.Evaluate then
        nextState.services = Services.Evaluate(nextState, {
            congestion = congestion,
            congestionEffects = effects,
        }).services
    end
    return nextState
end
