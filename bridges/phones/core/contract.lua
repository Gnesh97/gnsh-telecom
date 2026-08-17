PhoneBridgeContract = PhoneBridgeContract or {}

PhoneBridgeContract.Levels = {
    FULL = 'FULL',
    FUNCTIONAL = 'FUNCTIONAL',
    DISPLAY = 'DISPLAY',
}

local supportFields = {
    'signalUI',
    'callGate',
    'smsGate',
    'dataGate',
    'callLifecycle',
    'networkChangeHooks',
}

local supportMethods = {
    signalUI = { 'HasSignal', 'GetSignalStrength', 'GetSignalLevel' },
    callGate = { 'CanStartCall', 'CanCall' },
    smsGate = { 'CanSendSMS' },
    dataGate = { 'CanUseData', 'HasDataConnection' },
    callLifecycle = { 'StartCall', 'CreateCall', 'EndCall' },
    networkChangeHooks = { 'OnNetworkState', 'RegisterNetworkChangeHook' },
}

local validLevels = {
    FULL = true,
    FUNCTIONAL = true,
    DISPLAY = true,
}

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function hasMethod(provider, methods)
    for _, method in ipairs(methods or {}) do
        if type(provider[method]) == 'function' then return true end
    end
    return false
end

local function normalizeSupport(provider, declared)
    declared = type(declared) == 'table' and declared or {}
    local support = {}
    for _, field in ipairs(supportFields) do
        if declared[field] == false then
            support[field] = false
        else
            support[field] = hasMethod(provider, supportMethods[field])
        end
    end
    return support
end

local function honestLevel(requested, support)
    if requested == PhoneBridgeContract.Levels.FULL then
        for _, field in ipairs(supportFields) do
            if not support[field] then
                requested = PhoneBridgeContract.Levels.FUNCTIONAL
                break
            end
        end
    end

    if requested == PhoneBridgeContract.Levels.FUNCTIONAL
        and not support.signalUI then
        return PhoneBridgeContract.Levels.DISPLAY
    end
    if requested == PhoneBridgeContract.Levels.FUNCTIONAL then
        for _, field in ipairs({ 'callGate', 'smsGate', 'dataGate' }) do
            if not support[field] then
                return PhoneBridgeContract.Levels.DISPLAY
            end
        end
    end
    return requested
end

function PhoneBridgeContract.CopySupport(support)
    local result = {}
    for _, field in ipairs(supportFields) do
        result[field] = support and support[field] == true or false
    end
    return result
end

function PhoneBridgeContract.Validate(provider)
    if type(provider) ~= 'table' then
        return false, 'phone bridge provider must be a table'
    end
    if type(provider.name) ~= 'string' or provider.name == '' then
        return false, 'phone bridge provider name must be a non-empty string'
    end
    if provider.supportLevel ~= nil
        and (type(provider.supportLevel) ~= 'string'
            or not validLevels[provider.supportLevel]) then
        return false, 'phone bridge support level is invalid'
    end
    if provider.support ~= nil and type(provider.support) ~= 'table' then
        return false, 'phone bridge support must be a table'
    end
    return true
end

function PhoneBridgeContract.Normalize(provider)
    local valid, errorMessage = PhoneBridgeContract.Validate(provider)
    if not valid then return nil, errorMessage end

    local normalized = copy(provider)
    local requested = provider.supportLevel
    if requested == nil then
        requested = PhoneBridgeContract.Levels.FUNCTIONAL
    end
    local support = normalizeSupport(provider, provider.support)
    normalized.support = support
    normalized.supportLevel = honestLevel(requested, support)
    return normalized
end

function PhoneBridgeContract.Supports(provider, field)
    return type(provider) == 'table'
        and type(field) == 'string'
        and provider.support
        and provider.support[field] == true
end
