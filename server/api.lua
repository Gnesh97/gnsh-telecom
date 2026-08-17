TelecomAPI = TelecomAPI or {}
TelecomAPI.ApiVersion = Constants.ApiVersion

local function copy(value)
    return Utils.DeepCopy(value)
end

local function getState(source)
    if not Connections or not Connections.Get then return nil end
    return Connections.Get(source)
end

local function noConnectionService(reason, blockedBy)
    return false, {
        available = false,
        reason = reason or 'player_not_connected',
        blockedBy = blockedBy or 'connection',
    }
end

function TelecomAPI.HasSignal(source)
    local state = getState(source)
    return state ~= nil and type(state.signal) == 'number' and state.signal > 0
end

function TelecomAPI.GetSignalStrength(source)
    local state = getState(source)
    if not state or type(state.signal) ~= 'number' then return 0 end
    return state.signal
end

function TelecomAPI.GetSignalLevel(source)
    local state = getState(source)
    if not state then return Enums.SignalLevel.NO_SERVICE end
    return state.signalLevel or Signal.GetLevel(state.signal)
end

function TelecomAPI.GetNetworkType(source)
    local state = getState(source)
    return state and state.technology or nil
end

function TelecomAPI.GetConnectedTower(source)
    local state = getState(source)
    return state and state.towerId or nil
end

function TelecomAPI.GetNetworkState(source)
    local state = getState(source)
    if not state then return nil end
    state.apiVersion = TelecomAPI.ApiVersion
    return copy(state)
end

function TelecomAPI.CanUseService(source, service)
    if type(service) ~= 'string' or service == '' then
        return noConnectionService('unknown_service', 'policy')
    end
    if not Services or not Services.CanUse then
        return noConnectionService('service_unavailable', 'service')
    end

    local available, state = Services.CanUse(source, service)
    return available, copy(state)
end

function TelecomAPI.CanCall(source)
    return TelecomAPI.CanUseService(source, 'voice')
end

function TelecomAPI.CanSendSMS(source)
    return TelecomAPI.CanUseService(source, 'sms')
end

function TelecomAPI.HasDataConnection(source)
    return TelecomAPI.CanUseService(source, 'data')
end

function TelecomAPI.BeginServiceSession(source, service, metadata)
    if not ServiceSessions or not ServiceSessions.Begin then
        return false, 'service_sessions_unavailable'
    end
    return ServiceSessions.Begin(source, service, metadata)
end

function TelecomAPI.UpdateServiceSession(sessionId, metadata, ownerSource)
    if not ServiceSessions or not ServiceSessions.Update then
        return false, 'service_sessions_unavailable'
    end
    return ServiceSessions.Update(sessionId, metadata, ownerSource)
end

function TelecomAPI.EndServiceSession(sessionId, ownerSource)
    if not ServiceSessions or not ServiceSessions.End then
        return false, 'service_sessions_unavailable'
    end
    return ServiceSessions.End(sessionId, ownerSource)
end

function TelecomAPI.GetServiceSessions(limit)
    if not ServiceSessions or not ServiceSessions.GetAll then return {} end
    return copy(ServiceSessions.GetAll(limit))
end

function TelecomAPI.GetTowerState(towerId)
    if not TowerRegistry or not TowerRegistry.GetRuntimeState then return nil end
    return copy(TowerRegistry.GetRuntimeState(towerId))
end

function TelecomAPI.GetIncidentSnapshot()
    if not IncidentManager or not IncidentManager.GetSnapshot then
        return { incidents = {}, counts = {} }
    end
    return copy(IncidentManager.GetSnapshot())
end

function TelecomAPI.GetBackhaulStatus(towerId)
    if BackhaulRouting and BackhaulRouting.GetTowerStatus then
        return BackhaulRouting.GetTowerStatus(towerId)
    end
    local runtime = TowerRegistry and TowerRegistry.GetRuntimeState
        and TowerRegistry.GetRuntimeState(towerId)
    return runtime and runtime.backhaulStatus or Enums.BackhaulState.ONLINE
end

function TelecomAPI.GetStatistics()
    if TelecomStatistics and TelecomStatistics.GetSnapshot then
        return copy(TelecomStatistics.GetSnapshot())
    end
    return { enabled = false }
end

function TelecomAPI.GetBridgeStatus(category)
    if BridgeManager and type(BridgeManager.GetBridgeStatus) == 'function' then
        return copy(BridgeManager.GetBridgeStatus(category))
    end
    return category and nil or {}
end

function TelecomAPI.GetBridgeCapabilities(category)
    if BridgeManager and type(BridgeManager.GetBridgeCapabilities) == 'function' then
        return copy(BridgeManager.GetBridgeCapabilities(category))
    end
    return {}
end

local function serviceStateChanged(left, right)
    if type(left) ~= 'table' or type(right) ~= 'table' then
        return left ~= right
    end

    local fields = {
        'available',
        'signal',
        'minimumSignal',
        'reason',
        'blockedBy',
        'congestion',
        'dataPerformance',
        'callSetupReliability',
        'smsDelayMs',
    }
    for _, field in ipairs(fields) do
        if left[field] ~= right[field] then return true end
    end
    return false
end

local function servicesChanged(previous, current)
    local previousServices = previous and previous.services or {}
    local currentServices = current and current.services or {}

    for name, state in pairs(previousServices) do
        if serviceStateChanged(state, currentServices[name]) then return true end
    end
    for name, state in pairs(currentServices) do
        if serviceStateChanged(previousServices[name], state) then return true end
    end
    return false
end

local function emit(eventName, source, current, previous)
    if type(eventName) ~= 'string' or type(TriggerEvent) ~= 'function' then return end
    TriggerEvent(eventName, source, copy(current), copy(previous))
end

function TelecomAPI.EmitStateEvents(previous, current)
    local source = current and current.source or previous and previous.source
    if source == nil or (previous == nil and current == nil) then return false end
    if previous and current and Connections.HasChanged
        and not Connections.HasChanged(previous, current) then
        return false
    end

    local events = Constants.ApiEvents or {}
    emit(events.CONNECTION_CHANGED, source, current, previous)

    local previousSignal = previous and previous.signal or 0
    local currentSignal = current and current.signal or 0
    if previousSignal ~= currentSignal then
        emit(events.SIGNAL_CHANGED, source, current, previous)
    end

    local previousLevel = previous and previous.signalLevel or Enums.SignalLevel.NO_SERVICE
    local currentLevel = current and current.signalLevel or Enums.SignalLevel.NO_SERVICE
    if previousLevel ~= currentLevel then
        emit(events.SIGNAL_LEVEL_CHANGED, source, current, previous)
    end

    local previousTower = previous and previous.towerId or nil
    local currentTower = current and current.towerId or nil
    local previousSector = previous and previous.sectorId or nil
    local currentSector = current and current.sectorId or nil
    if previousTower ~= currentTower then
        emit(events.TOWER_CHANGED, source, current, previous)
        if previousTower and currentTower then
            emit(events.HANDOVER, source, current, previous)
        end
    elseif previousSector ~= currentSector then
        emit(events.SECTOR_CHANGED, source, current, previous)
        if previousTower and currentTower then
            emit(events.HANDOVER, source, current, previous)
        end
    end

    local previousTechnology = previous and previous.technology or nil
    local currentTechnology = current and current.technology or nil
    if previousTechnology ~= currentTechnology then
        emit(events.NETWORK_TYPE_CHANGED, source, current, previous)
    end

    if servicesChanged(previous, current) then
        emit(events.SERVICE_CHANGED, source, current, previous)
    end
    return true
end

function TelecomAPI.EmitIncidentEvent(towerId, current, previous)
    local events = Constants.ApiEvents or {}
    if events.INCIDENT_CHANGED then
        emit(events.INCIDENT_CHANGED, towerId, current, previous)
    end
end

local exportNames = {
    'HasSignal',
    'GetSignalStrength',
    'GetSignalLevel',
    'GetNetworkType',
    'GetConnectedTower',
    'GetNetworkState',
    'CanCall',
    'CanSendSMS',
    'HasDataConnection',
    'CanUseService',
    'BeginServiceSession',
    'UpdateServiceSession',
    'EndServiceSession',
    'GetServiceSessions',
    'GetTowerState',
    'GetIncidentSnapshot',
    'GetBackhaulStatus',
    'GetStatistics',
    'GetBridgeStatus',
    'GetBridgeCapabilities',
}

if type(exports) == 'function' then
    for _, name in ipairs(exportNames) do
        exports(name, TelecomAPI[name])
    end
end
