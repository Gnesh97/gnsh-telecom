ClientState = ClientState or {}

local currentState
local running = false

local function debugState(state)
    if not Config.Debug.enabled or type(print) ~= 'function' then return end

    local serviceParts = {}
    for _, serviceName in ipairs(ServicePolicy.Names or {}) do
        local serviceState = state.services and state.services[serviceName]
        local available = type(serviceState) == 'table'
            and serviceState.available
            or serviceState == true
        serviceParts[#serviceParts + 1] = ('%s=%s')
            :format(serviceName, available and 'on' or 'off')
    end
    local serviceSummary = #serviceParts > 0 and table.concat(serviceParts, ',') or 'none'

    print(('[gnsh-telecom] connection tower=%s signal=%s level=%s technology=%s')
        :format(
            tostring(state.towerId),
            tostring(state.signal),
            tostring(state.signalLevel),
            tostring(state.technology)
        ))
    print(('[gnsh-telecom] services %s'):format(serviceSummary))

    local dataState = state.services and state.services.data or {}
    local voiceState = state.services and state.services.voice or {}
    local smsState = state.services and state.services.sms or {}
    print(('[gnsh-telecom] network congestion=%s load=%s effectiveCapacity=%s dataPerformance=%s callSetupReliability=%s smsDelayMs=%s')
        :format(
            tostring(state.congestion),
            tostring(state.loadPercent),
            tostring(state.effectiveCapacity),
            tostring(dataState.dataPerformance),
            tostring(voiceState.callSetupReliability),
            tostring(smsState.smsDelayMs)
        ))

    local environment = state.environment or {}
    print(('[gnsh-telecom] environment category=%s zone=%s multiplier=%s')
        :format(
            tostring(environment.category),
            tostring(environment.zoneId),
            tostring(environment.multiplier)
        ))

    local failureEffects = state.failureEffects or {}
    print(('[gnsh-telecom] failures active=%s signalMultiplier=%s capacityMultiplier=%s')
        :format(
            tostring(#(failureEffects.activeFailures or {})),
            tostring(failureEffects.signalMultiplier),
            tostring(failureEffects.capacityMultiplier)
        ))
end

local function getInterval()
    local interval = Config and Config.Performance and Config.Performance.stationaryIntervalMs
    if type(interval) ~= 'number' or interval <= 0 then return 3000 end
    return interval
end

local function getPlayerCoords()
    if type(PlayerPedId) ~= 'function' or type(GetEntityCoords) ~= 'function' then
        return nil
    end

    local ped = PlayerPedId()
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    if not Utils.IsPoint(coords) then return nil end
    return { x = coords.x, y = coords.y, z = coords.z }
end

function ClientState.Get()
    return currentState and Utils.DeepCopy(currentState) or nil
end

function ClientState.Apply(state)
    if type(state) ~= 'table' then return false end
    currentState = Utils.DeepCopy(state)
    debugState(currentState)
    return true
end

function ClientState.Clear()
    currentState = nil
end

function ClientState.ReportPosition(coords)
    if not Utils.IsPoint(coords) or type(TriggerServerEvent) ~= 'function' then
        return false
    end

    local environment = Environment and Environment.GetContext
        and Environment.GetContext(coords)
        or { category = 'OPEN_AREA' }
    local payloadEnvironment = {
        category = environment.category,
    }
    if type(environment.zoneId) == 'string' and environment.zoneId ~= '' then
        payloadEnvironment.zoneId = environment.zoneId
    end

    TriggerServerEvent(Constants.Events.POSITION_UPDATE, {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        environment = payloadEnvironment,
    })
    return true
end

function ClientState.Start()
    if running then return false end
    running = true

    if type(CreateThread) == 'function' then
        CreateThread(function()
            while running do
                local coords = getPlayerCoords()
                if coords then ClientState.ReportPosition(coords) end
                Wait(getInterval())
            end
        end)
    end
    return true
end

function ClientState.Stop()
    running = false
end

function ClientState.IsRunning()
    return running
end

if type(AddEventHandler) == 'function' then
    if type(RegisterNetEvent) == 'function' then
        RegisterNetEvent(Constants.Events.CONNECTION_STATE)
    end
    AddEventHandler(Constants.Events.CONNECTION_STATE, function(state)
        ClientState.Apply(state)
    end)
    AddEventHandler('onClientResourceStop', function(resourceName)
        if resourceName == GetCurrentResourceName() then
            ClientState.Stop()
            ClientState.Clear()
        end
    end)
end

if type(CreateThread) == 'function' then ClientState.Start() end
