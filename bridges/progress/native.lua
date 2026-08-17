ProgressBridge = ProgressBridge or {}

local providers = ProgressBridge.Providers or {}
local activeName = ProgressBridge.ActiveName
ProgressBridge.Providers = providers

local function isServer()
    if type(IsDuplicityVersion) == 'function' then
        local ok, value = pcall(IsDuplicityVersion)
        if ok then return value == true end
    end
    return true
end

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function copyValue(value, depth, seen)
    local valueType = type(value)
    if valueType ~= 'table' then
        if valueType == 'string' or valueType == 'boolean'
            or (valueType == 'number' and isFiniteNumber(value)) then
            return value
        end
        return nil
    end
    if (depth or 0) >= 3 then return {} end

    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    local count = 0
    for key, item in pairs(value) do
        if count >= 32 then break end
        local keyType = type(key)
        if keyType == 'string' or keyType == 'number' then
            local copied = copyValue(item, (depth or 0) + 1, seen)
            if copied ~= nil then
                result[key] = copied
                count = count + 1
            end
        end
    end
    return result
end

local function validateValue(value, depth, active, state)
    local valueType = type(value)
    if valueType == 'string' then
        if #value > 1024 then return false, 'payload_string_too_long' end
        state.bytes = state.bytes + #value
        return state.bytes <= 4096, 'payload_too_large'
    end
    if valueType == 'number' then
        return isFiniteNumber(value), 'payload_number_invalid'
    end
    if valueType == 'boolean' or valueType == 'nil' then return true end
    if valueType ~= 'table' then return false, 'payload_value_unsupported' end
    if (depth or 0) >= 3 then return false, 'payload_too_deep' end
    if active[value] then return false, 'payload_cycle' end

    state.nodes = state.nodes + 1
    if state.nodes > 64 then return false, 'payload_too_large' end
    active[value] = true
    local count = 0
    for key, item in pairs(value) do
        local keyType = type(key)
        if keyType ~= 'string' and keyType ~= 'number' then
            active[value] = nil
            return false, 'payload_key_unsupported'
        end
        if keyType == 'string' then
            if #key > 256 then active[value] = nil; return false, 'payload_key_too_long' end
            state.bytes = state.bytes + #key
        elseif not isFiniteNumber(key) then
            active[value] = nil
            return false, 'payload_number_invalid'
        end
        count = count + 1
        if count > 32 or state.bytes > 4096 then
            active[value] = nil
            return false, 'payload_too_large'
        end
        local valid, errorMessage = validateValue(item, (depth or 0) + 1, active, state)
        if not valid then
            active[value] = nil
            return false, errorMessage
        end
    end
    active[value] = nil
    return true
end

local function normalizeSource(source)
    if not isServer() then return nil end
    if source == nil then return -1 end
    local numeric = tonumber(source)
    if not isFiniteNumber(numeric) or numeric ~= math.floor(numeric)
        or numeric < -1 or numeric > 2147483647
        or numeric == 0 then
        return nil
    end
    return numeric
end

local function normalizePayload(source, action, duration, options)
    local normalizedSource = normalizeSource(source)
    if isServer() and normalizedSource == nil then
        return nil, 'invalid_progress_source'
    end
    if type(action) ~= 'string' or action == '' or #action > 64 then
        return nil, 'invalid_progress_action'
    end
    if not isFiniteNumber(duration) or duration ~= math.floor(duration)
        or duration < 1 or duration > 3600000 then
        return nil, 'invalid_progress_duration'
    end
    local normalizedOptions = {}
    if type(options) == 'table' then
        local valid, optionsError = validateValue(options, 0, {}, { bytes = 0, nodes = 0 })
        if not valid then return nil, 'invalid_progress_options:' .. tostring(optionsError) end
        normalizedOptions = copyValue(options) or {}
    end

    return {
        source = normalizedSource,
        action = action,
        duration = duration,
        options = normalizedOptions,
    }
end

local function detectProvider(provider)
    if type(provider.Detect) ~= 'function' then return true end
    local ok, detected = pcall(provider.Detect)
    return ok and detected == true
end

local function invokeProvider(provider, source, action, duration, options)
    local handler = provider and provider.StartProgress
    if type(handler) ~= 'function' then return false, 'progress_capability_unavailable' end
    local ok, result, errorMessage = pcall(handler, source, action, duration, options)
    if not ok then return false, 'progress_provider_exception' end
    if result == false then return false, errorMessage or 'progress_provider_rejected' end
    return true, errorMessage
end

function ProgressBridge.Register(provider)
    if type(provider) ~= 'table' or type(provider.name) ~= 'string'
        or provider.name == '' or type(provider.StartProgress) ~= 'function' then
        return false, 'invalid_progress_provider'
    end
    providers[provider.name] = provider
    return true
end

function ProgressBridge.Unregister(name)
    if type(name) ~= 'string' or providers[name] == nil then return false end
    providers[name] = nil
    if activeName == name then
        activeName = nil
        ProgressBridge.ActiveName = nil
    end
    return true
end

function ProgressBridge.SetAdapter(value)
    if type(value) == 'table' then
        local ok, errorMessage = ProgressBridge.Register(value)
        if not ok then return false, errorMessage end
        value = value.name
    end
    if value == nil then
        activeName = nil
        ProgressBridge.ActiveName = nil
        return true
    end
    if value == 'auto' then return ProgressBridge.Initialize() end
    if type(value) ~= 'string' or providers[value] == nil then
        return false, 'unknown_progress_provider'
    end
    activeName = value
    ProgressBridge.ActiveName = value
    return true
end

function ProgressBridge.GetActive()
    return activeName and providers[activeName] or nil
end

function ProgressBridge.StartNative(source, action, duration, options)
    local payload, errorMessage = normalizePayload(source, action, duration, options)
    if not payload then return false, errorMessage end
    return invokeProvider(
        providers.native,
        payload.source,
        payload.action,
        payload.duration,
        payload.options
    )
end

function ProgressBridge.Initialize(preferred)
    local configured = preferred
    if configured == nil and Config then configured = Config.ProgressBridge end
    configured = configured or 'auto'

    local order = configured ~= 'auto'
        and { configured, 'native' }
        or { 'ox', 'native' }
    for _, name in ipairs(order) do
        local provider = providers[name]
        if provider and detectProvider(provider) then
            activeName = name
            ProgressBridge.ActiveName = name
            return true, name
        end
    end
    activeName = nil
    ProgressBridge.ActiveName = nil
    return false, nil, 'no_progress_provider'
end

function ProgressBridge.StartProgress(source, action, duration, options)
    local payload, errorMessage = normalizePayload(source, action, duration, options)
    if not payload then return false, errorMessage end

    local provider = ProgressBridge.GetActive()
    if provider and not detectProvider(provider) then
        activeName = nil
        ProgressBridge.ActiveName = nil
        provider = nil
    end
    if not provider then
        ProgressBridge.Initialize()
        provider = ProgressBridge.GetActive()
    end
    if provider then
        local ok, providerError = invokeProvider(
            provider,
            payload.source,
            payload.action,
            payload.duration,
            payload.options
        )
        if ok then return true, providerError end
        if provider.name ~= 'native' and providers.native then
            local fallbackOk = invokeProvider(
                providers.native,
                payload.source,
                payload.action,
                payload.duration,
                payload.options
            )
            if fallbackOk then return true, 'native_fallback' end
        end
        return false, providerError
    end
    return false, 'progress_provider_unavailable'
end

local function nativeStartProgress(source, action, duration, options)
    local payload = {
        provider = 'native',
        action = action,
        duration = duration,
        options = copyValue(options) or {},
    }
    if isServer() then
        if type(TriggerClientEvent) ~= 'function' then
            return false, 'progress_transport_unavailable'
        end
        local ok = pcall(TriggerClientEvent, Constants.SupportEvents.PROGRESS_START, source, payload)
        if not ok then return false, 'progress_transport_failed' end
        return true
    end

    if type(TriggerEvent) ~= 'function' then return false, 'progress_transport_unavailable' end
    local ok = pcall(TriggerEvent, 'progress', action, duration, options)
    if not ok then return false, 'progress_transport_failed' end
    return true
end

ProgressBridge.Register({
    name = 'native',
    priority = 0,
    StartProgress = nativeStartProgress,
})

if not isServer() and type(AddEventHandler) == 'function' then
    if type(RegisterNetEvent) == 'function' then
        pcall(RegisterNetEvent, Constants.SupportEvents.PROGRESS_START)
    end
    AddEventHandler(Constants.SupportEvents.PROGRESS_START, function(payload)
        if type(payload) ~= 'table' or payload.provider ~= 'native'
            or type(payload.action) ~= 'string' or type(payload.duration) ~= 'number' then
            return
        end
        if type(TriggerEvent) == 'function' then
            pcall(TriggerEvent, 'progress', payload.action, payload.duration, payload.options or {})
        end
    end)
end
