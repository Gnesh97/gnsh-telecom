PhoneBridges = PhoneBridges or {}
PhoneBridges.Registry = PhoneBridges.Registry or {}
PhoneBridges.DetectionOrder = PhoneBridges.DetectionOrder or {
    'lbphone',
    'npwd',
    'qs',
}
PhoneBridges.Active = nil
PhoneBridges.Initialized = false

local function log(level, message, data)
    if Log and type(Log[level]) == 'function' then
        Log[level](message, data)
    end
end

local function copy(value)
    return Utils and Utils.DeepCopy and Utils.DeepCopy(value) or value
end

local function fallbackServiceState(reason, blockedBy)
    return {
        available = false,
        reason = reason or 'connection_unavailable',
        blockedBy = blockedBy or 'connection',
    }
end

local function getApiFunction(name)
    local api = rawget(_G, 'TelecomAPI')
    local fn = api and api[name]
    return type(fn) == 'function' and fn or nil
end

local function callApi(name, ...)
    local fn = getApiFunction(name)
    if not fn then
        log('error', 'phone bridge public API function unavailable', {
            functionName = name,
        })
        return false, nil, 'api_unavailable'
    end

    local ok, first, second = pcall(fn, ...)
    if not ok then
        log('error', 'phone bridge public API call failed', {
            functionName = name,
            error = tostring(first),
        })
        return false, nil, 'api_error'
    end
    return true, first, second
end

local publicApi = {
    HasSignal = function(source)
        local ok, value = callApi('HasSignal', source)
        return ok and value == true or false
    end,
    GetSignalStrength = function(source)
        local ok, value = callApi('GetSignalStrength', source)
        return ok and tonumber(value) or 0
    end,
    GetSignalLevel = function(source)
        local ok, value = callApi('GetSignalLevel', source)
        return ok and value or Enums.SignalLevel.NO_SERVICE
    end,
    GetNetworkType = function(source)
        local ok, value = callApi('GetNetworkType', source)
        return ok and value or nil
    end,
    GetConnectedTower = function(source)
        local ok, value = callApi('GetConnectedTower', source)
        return ok and value or nil
    end,
    GetNetworkState = function(source)
        local ok, value = callApi('GetNetworkState', source)
        return ok and copy(value) or nil
    end,
    CanCall = function(source)
        local ok, available, state = callApi('CanCall', source)
        if not ok then return false, fallbackServiceState() end
        return available == true, copy(state)
    end,
    CanSendSMS = function(source)
        local ok, available, state = callApi('CanSendSMS', source)
        if not ok then return false, fallbackServiceState() end
        return available == true, copy(state)
    end,
    HasDataConnection = function(source)
        local ok, available, state = callApi('HasDataConnection', source)
        if not ok then return false, fallbackServiceState() end
        return available == true, copy(state)
    end,
    CanUseService = function(source, service)
        local ok, available, state = callApi('CanUseService', source, service)
        if not ok then return false, fallbackServiceState() end
        return available == true, copy(state)
    end,
}

function PhoneBridges.GetTelecomAPI()
    return copy(publicApi)
end

local function createPublicAdapter(name)
    local adapter = {
        name = name,
        api = publicApi,
        initialized = false,
    }

    function adapter:Initialize()
        self.api = PhoneBridges.GetTelecomAPI()
        self.initialized = true
        return true
    end

    function adapter:Shutdown()
        self.initialized = false
        return true
    end

    function adapter:HasSignal(source)
        return self.api.HasSignal(source)
    end

    function adapter:GetSignalStrength(source)
        return self.api.GetSignalStrength(source)
    end

    function adapter:GetSignalLevel(source)
        return self.api.GetSignalLevel(source)
    end

    function adapter:GetNetworkType(source)
        return self.api.GetNetworkType(source)
    end

    function adapter:GetConnectedTower(source)
        return self.api.GetConnectedTower(source)
    end

    function adapter:GetNetworkState(source)
        return self.api.GetNetworkState(source)
    end

    function adapter:CanCall(source)
        return self.api.CanCall(source)
    end

    function adapter:CanSendSMS(source)
        return self.api.CanSendSMS(source)
    end

    function adapter:HasDataConnection(source)
        return self.api.HasDataConnection(source)
    end

    function adapter:CanUseService(source, service)
        return self.api.CanUseService(source, service)
    end

    return adapter
end

function PhoneBridges.CreateGenericAdapter()
    local adapter = createPublicAdapter('generic')
    function adapter:Detect()
        return true
    end
    return adapter
end

local function resourceStarted(resourceName)
    if type(resourceName) ~= 'string' or resourceName == ''
        or type(GetResourceState) ~= 'function' then
        return false
    end
    local ok, state = pcall(GetResourceState, resourceName)
    return ok and state == 'started'
end

function PhoneBridges.CreateResourceAdapter(name, resourceNames)
    local adapter = createPublicAdapter(name)
    adapter.resourceNames = copy(resourceNames or {})
    function adapter:Detect()
        for _, resourceName in ipairs(self.resourceNames) do
            if resourceStarted(resourceName) then return true end
        end
        return false
    end
    return adapter
end

function PhoneBridges.CreateCustomAdapter()
    local adapter = createPublicAdapter('custom')
    function adapter:Detect()
        return Config and Config.PhoneBridge == 'custom'
    end
    return adapter
end

function PhoneBridges.Register(adapter)
    if type(adapter) ~= 'table' or type(adapter.name) ~= 'string'
        or adapter.name == '' then
        return false, 'invalid phone bridge adapter'
    end
    PhoneBridges.Registry[adapter.name] = adapter
    return true
end

function PhoneBridges.Get(name)
    if type(name) ~= 'string' then return nil end
    return PhoneBridges.Registry[name]
end

local function detect(adapter)
    if type(adapter) ~= 'table' or type(adapter.Detect) ~= 'function' then
        return false
    end
    local ok, result = pcall(function() return adapter:Detect() end)
    if not ok then
        log('error', 'phone bridge detection failed', {
            bridge = adapter.name,
            error = tostring(result),
        })
        return false
    end
    return result == true
end

function PhoneBridges.Select()
    local configured = Config and Config.PhoneBridge or 'auto'
    local generic = PhoneBridges.Get('generic')

    if configured ~= 'auto' then
        local explicit = PhoneBridges.Get(configured)
        if explicit and detect(explicit) then return explicit end
        log('warn', 'configured phone bridge unavailable; using generic', {
            bridge = configured,
        })
        return generic
    end

    for _, name in ipairs(PhoneBridges.DetectionOrder or {}) do
        local adapter = PhoneBridges.Get(name)
        if adapter and detect(adapter) then return adapter end
    end
    return generic
end

local function initializeAdapter(adapter)
    if not adapter or type(adapter.Initialize) ~= 'function' then
        return false, 'adapter unavailable'
    end
    local ok, initialized, errorMessage = pcall(function()
        return adapter:Initialize()
    end)
    if not ok then
        log('error', 'phone bridge initialization failed', {
            bridge = adapter.name,
            error = tostring(initialized),
        })
        return false, tostring(initialized)
    end
    if initialized ~= true then
        log('error', 'phone bridge initialization rejected', {
            bridge = adapter.name,
            error = tostring(errorMessage),
        })
        return false, errorMessage or 'adapter rejected initialization'
    end
    return true
end

function PhoneBridges.Initialize()
    local selected = PhoneBridges.Select()
    if not selected then
        log('error', 'no phone bridge adapter registered')
        return false, nil, 'no adapter'
    end
    if PhoneBridges.Initialized and PhoneBridges.Active == selected then
        return true, selected
    end

    if PhoneBridges.Active and type(PhoneBridges.Active.Shutdown) == 'function' then
        pcall(function() PhoneBridges.Active:Shutdown() end)
    end

    local ok, errorMessage = initializeAdapter(selected)
    if not ok and selected.name ~= 'generic' then
        local generic = PhoneBridges.Get('generic')
        log('error', 'phone bridge failed; falling back to generic', {
            bridge = selected.name,
            error = errorMessage,
        })
        ok, errorMessage = initializeAdapter(generic)
        selected = generic
    end
    if not ok then
        PhoneBridges.Active = nil
        PhoneBridges.Initialized = false
        return false, nil, errorMessage
    end

    PhoneBridges.Active = selected
    PhoneBridges.Initialized = true
    log('info', 'phone bridge ready', { bridge = selected.name })
    return true, selected
end

function PhoneBridges.Shutdown()
    if PhoneBridges.Active and type(PhoneBridges.Active.Shutdown) == 'function' then
        pcall(function() PhoneBridges.Active:Shutdown() end)
    end
    PhoneBridges.Active = nil
    PhoneBridges.Initialized = false
    return true
end

function PhoneBridges.GetActive()
    return PhoneBridges.Active
end

function PhoneBridges.GetStatus()
    return {
        apiVersion = Constants.ApiVersion,
        configured = Config and Config.PhoneBridge or 'auto',
        active = PhoneBridges.Active and PhoneBridges.Active.name or nil,
        available = PhoneBridges.Active ~= nil,
        initialized = PhoneBridges.Initialized == true,
    }
end

local function isPhoneDependency(resourceName)
    if type(resourceName) ~= 'string' then return false end
    for _, adapter in pairs(PhoneBridges.Registry or {}) do
        for _, candidate in ipairs(adapter.resourceNames or {}) do
            if candidate == resourceName then return true end
        end
    end
    return false
end

PhoneBridges.Register(PhoneBridges.CreateGenericAdapter())

if type(AddEventHandler) == 'function' then
    AddEventHandler('onResourceStart', function(resourceName)
        if resourceName == GetCurrentResourceName() then
            PhoneBridges.Initialize()
        elseif isPhoneDependency(resourceName) then
            PhoneBridges.Initialize()
        end
    end)
    AddEventHandler('onResourceStop', function(resourceName)
        if resourceName == GetCurrentResourceName() then
            PhoneBridges.Shutdown()
        elseif isPhoneDependency(resourceName) then
            PhoneBridges.Initialize()
        end
    end)
end
