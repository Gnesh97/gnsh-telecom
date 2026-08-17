Connections = Connections or {}

local statesBySource = {}
local previousBySource = {}
local positionsBySource = {}
local environmentsBySource = {}
local handoverBySource = {}

local meaningfulFields = {
    'towerId',
    'sectorId',
    'signal',
    'signalLevel',
    'technology',
    'carrierId',
    'congestion',
    'backhaulStatus',
}

local function environmentChanged(left, right)
    local leftEnvironment = left and left.environment or {}
    local rightEnvironment = right and right.environment or {}
    return leftEnvironment.category ~= rightEnvironment.category
        or leftEnvironment.zoneId ~= rightEnvironment.zoneId
        or leftEnvironment.multiplier ~= rightEnvironment.multiplier
end

local function failureEffectsChanged(left, right)
    local leftEffects = left and left.failureEffects or {}
    local rightEffects = right and right.failureEffects or {}
    if leftEffects.signalMultiplier ~= rightEffects.signalMultiplier
        or leftEffects.capacityMultiplier ~= rightEffects.capacityMultiplier
        or leftEffects.coverageMultiplier ~= rightEffects.coverageMultiplier
        or leftEffects.backhaulStatus ~= rightEffects.backhaulStatus then
        return true
    end

    local leftFailures = leftEffects.activeFailures or {}
    local rightFailures = rightEffects.activeFailures or {}
    if #leftFailures ~= #rightFailures then return true end
    for index, failure in ipairs(leftFailures) do
        local other = rightFailures[index]
        if not other or failure.id ~= other.id or failure.type ~= other.type then
            return true
        end
    end
    return false
end

local function normalizeSource(source)
    local number = tonumber(source)
    if not number or number ~= number or number == math.huge or number == -math.huge
        or number <= 0 or number % 1 ~= 0 then
        return nil, nil
    end
    number = math.floor(number)
    return tostring(number), number
end

local function isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function now()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return type(os.time) == 'function' and os.time() * 1000 or 0
end

local function handoverSettings()
    local configured = Config and Config.Handover or {}
    return {
        enabled = Config and Config.Features and Config.Features.Handover == true
            and configured.enabled ~= false,
        advantage = isFiniteNumber(configured.minimumScoreAdvantage)
            and math.max(0, configured.minimumScoreAdvantage) or 10,
        holdMs = isFiniteNumber(configured.candidateHoldMs)
            and math.max(0, configured.candidateHoldMs) or 2000,
        cooldownMs = isFiniteNumber(configured.cooldownMs)
            and math.max(0, configured.cooldownMs) or 3000,
    }
end

local function findRankedTower(ranked, towerId, sectorId)
    for _, candidate in ipairs(ranked or {}) do
        if candidate.towerId == towerId
            and (candidate.sectorId or nil) == (sectorId or nil) then
            return candidate
        end
    end
    return nil
end

local function sameServingCandidate(left, right)
    return left and right
        and left.towerId == right.towerId
        and (left.sectorId or nil) == (right.sectorId or nil)
end

local function servingKey(candidate)
    if not candidate or not candidate.towerId then return nil end
    local sectorId = candidate.sectorId or '*'
    return ('%d:%s|%d:%s'):format(
        #candidate.towerId,
        candidate.towerId,
        #sectorId,
        sectorId
    )
end

local function chooseServingCandidate(source, previous, ranked)
    local best = ranked[1]
    if not best then return nil end

    local settings = handoverSettings()
    local key = tostring(source)
    local handover = handoverBySource[key] or {}
    handoverBySource[key] = handover
    if not settings.enabled or not previous or not previous.towerId then
        handover.target = nil
        return best
    end

    local current = findRankedTower(ranked, previous.towerId, previous.sectorId)
    if not current then
        handover.target = nil
        return best
    end
    if sameServingCandidate(best, current) then
        handover.target = nil
        return current
    end

    local timestamp = now()
    if handover.lastHandoverAt
        and timestamp - handover.lastHandoverAt < settings.cooldownMs then
        return current
    end
    if best.score < current.score + settings.advantage then
        handover.target = nil
        return current
    end

    local bestKey = servingKey(best)
    if handover.target ~= bestKey then
        handover.target = bestKey
        handover.targetSince = timestamp
        return current
    end
    if timestamp - (handover.targetSince or timestamp) < settings.holdMs then
        return current
    end

    handover.lastHandoverAt = timestamp
    handover.target = nil
    handover.targetSince = nil
    return best
end

local function servicesChanged(left, right)
    local leftServices = left.services or {}
    local rightServices = right.services or {}

    local function changed(leftState, rightState)
        if type(leftState) == 'table' and type(rightState) == 'table' then
            return leftState.available ~= rightState.available
                or leftState.reason ~= rightState.reason
                or leftState.blockedBy ~= rightState.blockedBy
                or leftState.minimumSignal ~= rightState.minimumSignal
                or leftState.dataPerformance ~= rightState.dataPerformance
                or leftState.callSetupReliability ~= rightState.callSetupReliability
                or leftState.smsDelayMs ~= rightState.smsDelayMs
        end
        return leftState ~= rightState
    end

    for name, leftState in pairs(leftServices) do
        if changed(leftState, rightServices[name]) then return true end
    end
    for name, rightState in pairs(rightServices) do
        if changed(leftServices[name], rightState) then return true end
    end
    return false
end

local function emptyState(source)
    return {
        source = source,
        towerId = nil,
        sectorId = nil,
        signal = 0,
        rawSignal = 0,
        signalLevel = Signal.GetLevel(0),
        technology = nil,
        carrierId = nil,
        congestion = Enums.CongestionState.NORMAL,
        loadPercent = 0,
        effectiveCapacity = nil,
        capacityEffects = {},
        failureEffects = {
            signalMultiplier = 1.0,
            capacityMultiplier = 1.0,
            coverageMultiplier = 1.0,
            serviceFailures = {},
            backhaulStatus = nil,
            healthDelta = 0,
            activeFailures = {},
        },
        serviceFailures = {},
        backhaulStatus = Enums.BackhaulState.ONLINE,
        interference = { multiplier = 1.0, active = false, jammers = {} },
        environment = Signal.ResolveEnvironment(nil, nil),
        services = {},
        updatedAt = now(),
    }
end

local function normalizeState(source, state)
    if type(state) ~= 'table' then return nil, 'state must be a table' end

    local normalized = Utils.DeepCopy(state)
    if normalized.source ~= nil then
        local _, declaredSource = normalizeSource(normalized.source)
        if declaredSource ~= source then return nil, 'state source does not match key' end
    end
    if normalized.towerId ~= nil and type(normalized.towerId) ~= 'string' then
        return nil, 'towerId must be a string or nil'
    end
    if normalized.sectorId ~= nil and type(normalized.sectorId) ~= 'string' then
        return nil, 'sectorId must be a string or nil'
    end
    if normalized.sectorId ~= nil and normalized.towerId == nil then
        return nil, 'sectorId requires towerId'
    end
    if normalized.carrierId ~= nil and type(normalized.carrierId) ~= 'string' then
        return nil, 'carrierId must be a string or nil'
    end
    if type(normalized.signal) ~= 'number' or normalized.signal ~= normalized.signal
        or normalized.signal < 0 or normalized.signal > 100 then
        return nil, 'signal must be between 0 and 100'
    end
    if normalized.rawSignal ~= nil and (not isFiniteNumber(normalized.rawSignal)
        or normalized.rawSignal < 0 or normalized.rawSignal > 100) then
        return nil, 'rawSignal must be between 0 and 100'
    end
    if normalized.services ~= nil and type(normalized.services) ~= 'table' then
        return nil, 'services must be a table'
    end

    normalized.source = source
    normalized.rawSignal = normalized.rawSignal or normalized.signal
    normalized.signalLevel = normalized.signalLevel or Signal.GetLevel(normalized.signal)
    normalized.congestion = normalized.congestion or Enums.CongestionState.NORMAL
    normalized.services = normalized.services or {}
    normalized.updatedAt = normalized.updatedAt or now()
    return normalized
end

local function resolveServerCoords(source)
    if type(GetPlayerPed) ~= 'function' or type(GetEntityCoords) ~= 'function' then
        return nil
    end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    return Utils.IsPoint(coords) and coords or nil
end

local function sendState(source, state)
    if type(TriggerClientEvent) == 'function' then
        TriggerClientEvent(Constants.Events.CONNECTION_STATE, source, state)
    end
end

function Connections.HasChanged(previous, current)
    if previous == nil or current == nil then return previous ~= current end
    for _, field in ipairs(meaningfulFields) do
        if previous[field] ~= current[field] then return true end
    end
    if environmentChanged(previous, current) then return true end
    if failureEffectsChanged(previous, current) then return true end
    return servicesChanged(previous, current)
end

function Connections.Get(source)
    local key = normalizeSource(source)
    if not key or not statesBySource[key] then return nil end
    return Utils.DeepCopy(statesBySource[key])
end

function Connections.GetPrevious(source)
    local key = normalizeSource(source)
    if not key or not previousBySource[key] then return nil end
    return Utils.DeepCopy(previousBySource[key])
end

function Connections.GetAll()
    local states = {}
    for _, state in pairs(statesBySource) do
        states[#states + 1] = Utils.DeepCopy(state)
    end
    table.sort(states, function(left, right)
        return left.source < right.source
    end)
    return states
end

function Connections.Set(source, state, options)
    local key, number = normalizeSource(source)
    if not key then return false, 'invalid player source' end

    local normalized, errorMessage = normalizeState(number, state)
    if not normalized then return false, errorMessage end

    local previous = statesBySource[key]
    previousBySource[key] = previous and Utils.DeepCopy(previous) or nil
    statesBySource[key] = normalized

    local affected
    if not (options and options.skipCapacity == true)
        and Capacity and Capacity.ReconcileConnectionChange then
        affected = select(1, Capacity.ReconcileConnectionChange(
            previous,
            normalized,
            Connections.GetAll()
        ))
    end
    return true, Connections.HasChanged(previous, normalized), affected
end

function Connections.Remove(source)
    local key = normalizeSource(source)
    if not key or not statesBySource[key] then return false end
    local previous = statesBySource[key]
    previousBySource[key] = Utils.DeepCopy(previous)
    statesBySource[key] = nil
    positionsBySource[key] = nil
    environmentsBySource[key] = nil
    handoverBySource[key] = nil

    if Capacity and Capacity.ReconcileConnectionChange then
        Capacity.ReconcileConnectionChange(previous, nil, Connections.GetAll())
    end
    return true
end

function Connections.Clear()
    statesBySource = {}
    previousBySource = {}
    positionsBySource = {}
    environmentsBySource = {}
    handoverBySource = {}
    if Capacity and Capacity.RecalculateAll then Capacity.RecalculateAll({}) end
end

function Connections.Count()
    local count = 0
    for _ in pairs(statesBySource) do count = count + 1 end
    return count
end

function Connections.RefreshCapacity(towerIds, deferredSource)
    if type(towerIds) ~= 'table' or not Capacity or not Capacity.ApplyToConnection then
        return {}
    end

    local affected = {}
    for key, value in pairs(towerIds) do
        if type(key) == 'number' then
            if type(value) == 'string' then affected[value] = true end
        elseif value then
            affected[key] = true
        end
    end

    local changedBySource = {}
    for _, current in ipairs(Connections.GetAll()) do
        if current.towerId and affected[current.towerId] then
            local nextState = Capacity.ApplyToConnection(current)
            local ok, changed = Connections.Set(
                current.source,
                nextState,
                { skipCapacity = true }
            )
            if ok and changed then
                changedBySource[current.source] = true
                local updated = Connections.Get(current.source)
                if current.source ~= deferredSource then
                    sendState(current.source, updated)
                    if TelecomAPI and TelecomAPI.EmitStateEvents then
                        TelecomAPI.EmitStateEvents(current, updated)
                    end
                end
            end
        end
    end
    return changedBySource
end

function Connections.RefreshTower(towerId)
    if type(towerId) ~= 'string' then return {} end

    local changedBySource = {}
    for _, current in ipairs(Connections.GetAll()) do
        if current.towerId == towerId then
            local key = normalizeSource(current.source)
            local coords = key and positionsBySource[key]
            if coords then
                local updated, changed = Connections.Reevaluate(
                    current.source,
                    coords,
                    key and environmentsBySource[key]
                )
                if changed and updated then changedBySource[current.source] = true end
            end
        end
    end
    return changedBySource
end

function Connections.RefreshTowers(towerIds)
    local changedBySource = {}
    local ordered = {}
    local seen = {}
    for key, value in pairs(towerIds or {}) do
        local towerId = type(key) == 'number' and value or value and key
        if type(towerId) == 'string' and not seen[towerId] then
            seen[towerId] = true
            ordered[#ordered + 1] = towerId
        end
    end
    table.sort(ordered)
    for _, towerId in ipairs(ordered) do
        for source, changed in pairs(Connections.RefreshTower(towerId)) do
            if changed then changedBySource[source] = true end
        end
    end
    return changedBySource
end

function Connections.Reevaluate(source, coords, reportedEnvironment)
    local key, number = normalizeSource(source)
    if not key then return nil, false, 'invalid player source' end
    local previous = Connections.Get(number)

    if not Utils.IsPoint(coords) then
        coords = resolveServerCoords(number)
    end
    if not Utils.IsPoint(coords) then
        return Connections.Get(number), false, 'player position unavailable'
    end

    positionsBySource[key] = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
    }
    environmentsBySource[key] = Utils.DeepCopy(reportedEnvironment)

    local environment = Signal.ResolveEnvironment(coords, reportedEnvironment)
    local candidates = Coverage.GetCandidates(coords, environment)
    local ranked = Selection.Rank(candidates)
    local best = chooseServingCandidate(number, previous, ranked)
    local state = emptyState(number)
    if best then
        state.towerId = best.towerId
        state.sectorId = best.sectorId
        state.signal = best.signal
        state.rawSignal = best.signal
        state.signalLevel = Signal.GetLevel(best.signal)
        local sector = best.sector
        local technologies = sector and sector.technologies or best.tower.technologies
        state.technology = best.technology
            or technologies and technologies[1]
        state.technologyFallbackFrom = best.technologyFallbackFrom
        state.carrierId = best.carrierId
        local towerRuntime = TowerRegistry.GetRuntimeState(best.towerId)
        local runtime = best.sectorId and TowerSectors and TowerSectors.GetRuntime
            and TowerSectors.GetRuntime(best.towerId, best.sectorId)
            or towerRuntime
        state.failureEffects = runtime and runtime.failureEffects
            or towerRuntime and towerRuntime.failureEffects
            or state.failureEffects
        state.serviceFailures = state.failureEffects.serviceFailures or {}
        state.towerState = runtime and runtime.state or best.tower.state
        local routedBackhaul = BackhaulRouting and BackhaulRouting.GetTowerStatus
            and BackhaulRouting.GetTowerStatus(best.towerId)
            or towerRuntime and towerRuntime.backhaulStatus
            or Enums.BackhaulState.ONLINE
        state.backhaulStatus = runtime
            and runtime.backhaulStatus == Enums.BackhaulState.OFFLINE
            and Enums.BackhaulState.OFFLINE
            or routedBackhaul
        state.interference = Jammers and Jammers.GetEffect
            and Jammers.GetEffect(coords, technologies)
            or state.interference
        state.debug = {
            distance = best.distance,
            sectorId = best.sectorId,
            health = best.scoreDetails and best.scoreDetails.health,
            backhaulStatus = state.backhaulStatus,
            alternatives = {},
        }
        for index = 2, math.min(#ranked, 5) do
            state.debug.alternatives[#state.debug.alternatives + 1] = {
                towerId = ranked[index].towerId,
                score = ranked[index].score,
            }
        end
    end
    state.environment = environment
    state.services = Services.Evaluate(state).services

    local ok, _, affected = Connections.Set(number, state)
    if not ok then return nil, false, 'connection state rejected' end

    Connections.RefreshCapacity(affected, number)

    local updated = Connections.Get(number)
    local changed = Connections.HasChanged(previous, updated)
    if TelecomStatistics and TelecomStatistics.RecordConnection then
        TelecomStatistics.RecordConnection(previous, updated)
    end
    if changed then
        sendState(number, updated)
        if TelecomAPI and TelecomAPI.EmitStateEvents then
            TelecomAPI.EmitStateEvents(previous, updated)
        end
        if Config.Debug.enabled and Log and Log.debug and best then
            Log.debug('connection selection', {
                source = number,
                towerId = best.towerId,
                score = best.score,
                signal = updated.signal,
                rawSignal = updated.rawSignal,
                loadPercent = updated.loadPercent or best.scoreDetails.loadPercent,
                congestion = updated.congestion,
                effectiveCapacity = updated.effectiveCapacity,
                health = best.scoreDetails.health,
            })
        end
    end
    return updated, changed
end

local function handlePlayerJoining()
    local _, number = normalizeSource(source)
    if number then Connections.Set(number, emptyState(number)) end
end

local function handlePlayerDropped()
    local previous = Connections.Get(source)
    if Connections.Remove(source)
        and previous
        and TelecomAPI
        and TelecomAPI.EmitStateEvents then
        TelecomAPI.EmitStateEvents(previous, nil)
    end
end

local positionFields = {
    x = true,
    y = true,
    z = true,
    environment = true,
}

local environmentFields = {
    category = true,
    zoneId = true,
}

local function isBoundedString(value, maximumLength)
    return type(value) == 'string' and #value <= maximumLength
end

local function validPositionPayload(payload)
    if type(payload) ~= 'table' or not Utils.IsPoint(payload) then return false end
    if TelecomSecurity and TelecomSecurity.IsSafeTable
        and not TelecomSecurity.IsSafeTable(payload, 2, 8) then
        return false
    end

    for key in pairs(payload) do
        if not positionFields[key] then return false end
    end

    local environment = payload.environment
    if environment == nil then return true end
    if type(environment) ~= 'table' then return false end
    for key in pairs(environment) do
        if not environmentFields[key] then return false end
    end
    if environment.category ~= nil
        and not isBoundedString(environment.category, 32) then
        return false
    end
    if environment.zoneId ~= nil
        and not isBoundedString(environment.zoneId, 64) then
        return false
    end
    return true
end

local function handlePositionUpdate(payload)
    local _, normalizedSource = normalizeSource(source)
    if not normalizedSource then return end
    if not validPositionPayload(payload) then return end
    if not TelecomRateLimit or not TelecomRateLimit.Allow then return end

    local allowed = TelecomRateLimit.Allow(normalizedSource, 'position', 1000, 4)
    if not allowed then return end

    local serverCoords = resolveServerCoords(normalizedSource)
    local coords = serverCoords or payload
    local environment
    if not serverCoords then environment = payload.environment end
    Connections.Reevaluate(normalizedSource, coords, environment)
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('playerJoining', handlePlayerJoining)
    AddEventHandler('playerDropped', handlePlayerDropped)
    AddEventHandler(Constants.Events.POSITION_UPDATE, handlePositionUpdate)
    AddEventHandler('onResourceStop', function(resourceName)
        if resourceName == GetCurrentResourceName() then Connections.Clear() end
    end)
end

if type(RegisterNetEvent) == 'function' then
    RegisterNetEvent(Constants.Events.POSITION_UPDATE)
end
