local function copyValue(value, depth, seen)
    local valueType = type(value)
    if valueType ~= 'table' then
        if valueType == 'string' or valueType == 'boolean'
            or (valueType == 'number' and value == value
                and value ~= math.huge and value ~= -math.huge) then
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
        return value == value and value ~= math.huge and value ~= -math.huge,
            'payload_number_invalid'
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
        elseif key ~= key or key == math.huge or key == -math.huge then
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

local function nativeAlert(payload)
    if type(TriggerEvent) ~= 'function' then return false, 'dispatch_transport_unavailable' end
    if type(payload) ~= 'table' then return false, 'invalid_dispatch_payload' end
    local valid, errorMessage = validateValue(payload, 0, {}, { bytes = 0, nodes = 0 })
    if not valid then return false, errorMessage end
    local safePayload = copyValue(payload) or {}
    local ok = pcall(TriggerEvent, Constants.SupportEvents.DISPATCH_ALERT, safePayload)
    if not ok then return false, 'dispatch_transport_failed' end
    return true
end

function DispatchBridge.CreateNativeAdapter()
    return {
        name = 'native',
        priority = 0,
        capabilities = { 'Alert', 'CreateAlert' },
        Alert = nativeAlert,
        CreateAlert = nativeAlert,
    }
end

function DispatchBridge.SetNative()
    return DispatchBridge.SetAdapter(DispatchBridge.CreateNativeAdapter())
end
