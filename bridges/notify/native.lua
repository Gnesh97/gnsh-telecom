NotifyBridge = NotifyBridge or {}

local providers = NotifyBridge.Providers or {}
local activeName = NotifyBridge.ActiveName
NotifyBridge.Providers = providers

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
        or (numeric == 0) then
        return nil
    end
    return numeric
end

local function normalizePayload(source, kind, message, data)
    local normalizedSource = normalizeSource(source)
    if isServer() and normalizedSource == nil then
        return nil, 'invalid_notify_source'
    end
    if type(message) ~= 'string' or message == '' or #message > 1024 then
        return nil, 'invalid_notify_message'
    end

    local normalizedKind = type(kind) == 'string' and kind:lower() or 'info'
    local allowedKinds = {
        info = true,
        success = true,
        warning = true,
        error = true,
    }
    if not allowedKinds[normalizedKind] then normalizedKind = 'info' end

    local normalizedData = {}
    if type(data) == 'table' then
        local valid, dataError = validateValue(data, 0, {}, { bytes = 0, nodes = 0 })
        if not valid then return nil, 'invalid_notify_data:' .. tostring(dataError) end
        normalizedData = copyValue(data) or {}
    end

    return {
        source = normalizedSource,
        kind = normalizedKind,
        message = message,
        data = normalizedData,
    }
end

local function detectProvider(provider)
    if type(provider.Detect) ~= 'function' then return true end
    local ok, detected = pcall(provider.Detect)
    return ok and detected == true
end

local function invokeProvider(provider, source, kind, message, data)
    local handler = provider and provider.Notify
    if type(handler) ~= 'function' then return false, 'notify_capability_unavailable' end
    local ok, result, errorMessage = pcall(handler, source, kind, message, data)
    if not ok then return false, 'notify_provider_exception' end
    if result == false then return false, errorMessage or 'notify_provider_rejected' end
    return true, errorMessage
end

function NotifyBridge.Register(provider)
    if type(provider) ~= 'table' or type(provider.name) ~= 'string'
        or provider.name == '' or type(provider.Notify) ~= 'function' then
        return false, 'invalid_notify_provider'
    end
    providers[provider.name] = provider
    return true
end

function NotifyBridge.Unregister(name)
    if type(name) ~= 'string' or providers[name] == nil then return false end
    providers[name] = nil
    if activeName == name then
        activeName = nil
        NotifyBridge.ActiveName = nil
    end
    return true
end

function NotifyBridge.SetAdapter(value)
    if type(value) == 'table' then
        local ok, errorMessage = NotifyBridge.Register(value)
        if not ok then return false, errorMessage end
        value = value.name
    end
    if value == nil then
        activeName = nil
        NotifyBridge.ActiveName = nil
        return true
    end
    if value == 'auto' then return NotifyBridge.Initialize() end
    if type(value) ~= 'string' or providers[value] == nil then
        return false, 'unknown_notify_provider'
    end
    activeName = value
    NotifyBridge.ActiveName = value
    return true
end

function NotifyBridge.GetActive()
    return activeName and providers[activeName] or nil
end

function NotifyBridge.NotifyNative(source, kind, message, data)
    local payload, errorMessage = normalizePayload(source, kind, message, data)
    if not payload then return false, errorMessage end
    return invokeProvider(
        providers.native,
        payload.source,
        payload.kind,
        payload.message,
        payload.data
    )
end

function NotifyBridge.GetStatus()
    local active = NotifyBridge.GetActive()
    return {
        category = 'notify',
        state = active and 'ACTIVE' or 'OPTIONAL',
        active = active and active.name or nil,
        provider = active and active.name or nil,
        available = active ~= nil,
        initialized = active ~= nil,
        capabilities = active and { Notify = true } or {},
    }
end

function NotifyBridge.Initialize(preferred)
    local bridges = type(Config) == 'table' and Config.Bridges
    local configuration = type(bridges) == 'table' and bridges.Notify or {}
    local legacyConfigured = type(Config) == 'table' and Config.NotifyBridge or nil
    local configured = preferred
    if configured == nil then
        configured = configuration.provider or legacyConfigured
        if configured == 'auto' and type(legacyConfigured) == 'string'
            and legacyConfigured ~= 'auto' then
            configured = legacyConfigured
        end
    end
    configured = configured or 'auto'
    local fallback = configuration.fallback or 'native'
    local order = {}
    local seen = {}
    local function add(name)
        if type(name) == 'string' and name ~= '' and not seen[name] then
            order[#order + 1] = name
            seen[name] = true
        end
    end
    if configured == 'auto' then
        add('ox')
        add('framework')
    else
        add(configured)
    end
    add(fallback)
    add('native')
    for _, name in ipairs(order) do
        local provider = providers[name]
        if provider and detectProvider(provider) then
            activeName = name
            NotifyBridge.ActiveName = name
            return true, name
        end
    end
    activeName = nil
    NotifyBridge.ActiveName = nil
    return false, nil, 'no_notify_provider'
end

function NotifyBridge.Notify(source, kind, message, data)
    local payload, errorMessage = normalizePayload(source, kind, message, data)
    if not payload then return false, errorMessage end

    local provider = NotifyBridge.GetActive()
    if provider and not detectProvider(provider) then
        activeName = nil
        NotifyBridge.ActiveName = nil
        provider = nil
    end
    if not provider then
        NotifyBridge.Initialize()
        provider = NotifyBridge.GetActive()
    end
    if provider then
        local ok, providerError = invokeProvider(
            provider,
            payload.source,
            payload.kind,
            payload.message,
            payload.data
        )
        if ok then return true, providerError end
        if provider.name ~= 'native' and providers.native then
            local fallbackOk = invokeProvider(
                providers.native,
                payload.source,
                payload.kind,
                payload.message,
                payload.data
            )
            if fallbackOk then return true, 'native_fallback' end
        end
        return false, providerError
    end
    return false, 'notify_provider_unavailable'
end

local function nativeNotify(source, kind, message, data)
    local payload = {
        provider = 'native',
        kind = kind,
        message = message,
        data = copyValue(data) or {},
    }
    if isServer() then
        if type(TriggerClientEvent) ~= 'function' then
            return false, 'notify_transport_unavailable'
        end
        local ok = pcall(TriggerClientEvent, Constants.SupportEvents.NOTIFY, source, payload)
        if not ok then return false, 'notify_transport_failed' end
        return true
    end

    if type(TriggerEvent) ~= 'function' then return false, 'notify_transport_unavailable' end
    local ok = pcall(TriggerEvent, 'chat:addMessage', {
        color = { 30, 144, 255 },
        args = { 'Telecom', message },
    })
    if not ok then return false, 'notify_transport_failed' end
    return true
end

NotifyBridge.Register({
    name = 'native',
    priority = 0,
    Notify = nativeNotify,
})

if not isServer() and type(AddEventHandler) == 'function' then
    if type(RegisterNetEvent) == 'function' then
        pcall(RegisterNetEvent, Constants.SupportEvents.NOTIFY)
    end
    AddEventHandler(Constants.SupportEvents.NOTIFY, function(payload)
        if type(payload) ~= 'table' or payload.provider ~= 'native'
            or type(payload.message) ~= 'string' then return end
        if type(TriggerEvent) == 'function' then
            pcall(TriggerEvent, 'chat:addMessage', {
                color = { 30, 144, 255 },
                args = { 'Telecom', payload.message },
            })
        end
    end)
end
