TelecomClientDebug = TelecomClientDebug or {}

local enabled = false
local rendering = false
local currentState

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function count(value)
    return type(value) == 'table' and #value or 0
end

local function lines()
    local state = currentState or {}
    local environment = state.environment or {}
    local failures = state.failureEffects or {}
    local debug = state.debug or {}
    local alternatives = debug.alternatives or {}
    local alternativeSummary = {}

    for _, candidate in ipairs(alternatives) do
        alternativeSummary[#alternativeSummary + 1] = ('%s:%s')
            :format(tostring(candidate.towerId), tostring(candidate.score))
    end

    return {
        '[gnsh-telecom] debug overlay',
        ('tower=%s distance=%s signal=%s raw=%s level=%s tech=%s')
            :format(
                tostring(state.towerId),
                tostring(debug.distance),
                tostring(state.signal),
                tostring(state.rawSignal),
                tostring(state.signalLevel),
                tostring(state.technology)
            ),
        ('health=%s load=%s congestion=%s capacity=%s backhaul=%s')
            :format(
                tostring(debug.health),
                tostring(state.loadPercent),
                tostring(state.congestion),
                tostring(state.effectiveCapacity),
                tostring(debug.backhaulStatus)
            ),
        ('environment=%s/%s x%s failures=%s x%s alternatives=%s')
            :format(
                tostring(environment.category),
                tostring(environment.zoneId),
                tostring(environment.multiplier),
                tostring(count(failures.activeFailures)),
                tostring(failures.signalMultiplier),
                tostring(table.concat(alternativeSummary, ','))
            ),
    }
end

local function render()
    if type(BeginTextCommandDisplayText) ~= 'function'
        or type(AddTextComponentSubstringPlayerName) ~= 'function'
        or type(EndTextCommandDisplayText) ~= 'function' then
        return
    end

    local y = 0.16
    for _, line in ipairs(lines()) do
        if type(SetTextFont) == 'function' then SetTextFont(0) end
        if type(SetTextScale) == 'function' then SetTextScale(0.28, 0.28) end
        if type(SetTextColour) == 'function' then SetTextColour(255, 255, 255, 220) end
        if type(SetTextOutline) == 'function' then SetTextOutline() end
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(line)
        EndTextCommandDisplayText(0.015, y)
        y = y + 0.022
    end
end

local function startRendering()
    if rendering or type(CreateThread) ~= 'function' then return end
    rendering = true
    CreateThread(function()
        while enabled do
            if type(Wait) == 'function' then Wait(0) end
            if enabled then render() end
        end
        rendering = false
    end)
end

function TelecomClientDebug.UpdateState(state)
    currentState = type(state) == 'table' and copy(state) or nil
    return true
end

function TelecomClientDebug.Enable()
    if not Config or not Config.Debug or Config.Debug.enabled ~= true then
        return false, 'debug_disabled'
    end
    enabled = true
    startRendering()
    return true
end

function TelecomClientDebug.Disable()
    enabled = false
    return true
end

function TelecomClientDebug.Toggle()
    if enabled then
        TelecomClientDebug.Disable()
    else
        local ok, errorCode = TelecomClientDebug.Enable()
        if not ok then return false, errorCode end
    end
    return true, enabled
end

function TelecomClientDebug.IsEnabled()
    return enabled
end

function TelecomClientDebug.GetStatus()
    return {
        enabled = enabled,
        rendering = rendering,
        hasState = currentState ~= nil,
    }
end

if type(AddEventHandler) == 'function' and Constants and Constants.Events then
    if type(RegisterNetEvent) == 'function' then
        RegisterNetEvent(Constants.Events.DEBUG_OVERLAY)
        RegisterNetEvent(Constants.Events.DEBUG_MESSAGE)
    end
    AddEventHandler(Constants.Events.DEBUG_OVERLAY, function(value)
        if value == true then
            TelecomClientDebug.Enable()
        else
            TelecomClientDebug.Disable()
        end
    end)
    AddEventHandler(Constants.Events.DEBUG_MESSAGE, function(message)
        if type(print) == 'function' then
            print(('[gnsh-telecom] %s'):format(tostring(message)))
        end
    end)
end
