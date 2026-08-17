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

local function getClientState()
    if ClientState and type(ClientState.Get) == 'function' then
        return ClientState.Get()
    end
    return nil
end

local function clientServiceState(service)
    local state = getClientState()
    local serviceState = state and state.services and state.services[service]
    if type(serviceState) == 'table' then
        return serviceState.available == true, copy(serviceState)
    end
    if type(serviceState) == 'boolean' then
        return serviceState, {
            available = serviceState,
            reason = serviceState and 'available' or 'service_unavailable',
            blockedBy = serviceState and nil or 'connection',
        }
    end
    return false, fallbackServiceState('connection_unavailable', 'connection')
end

local publicApi = {
    HasSignal = function(source)
        local ok, value = callApi('HasSignal', source)
        if ok then return value == true end
        local state = getClientState()
        return state ~= nil and type(state.signal) == 'number' and state.signal > 0
    end,
    GetSignalStrength = function(source)
        local ok, value = callApi('GetSignalStrength', source)
        if ok then return tonumber(value) or 0 end
        local state = getClientState()
        return state and tonumber(state.signal) or 0
    end,
    GetSignalLevel = function(source)
        local ok, value = callApi('GetSignalLevel', source)
        if ok then return value or Enums.SignalLevel.NO_SERVICE end
        local state = getClientState()
        return state and state.signalLevel or Enums.SignalLevel.NO_SERVICE
    end,
    GetNetworkType = function(source)
        local ok, value = callApi('GetNetworkType', source)
        if ok then return value end
        local state = getClientState()
        return state and state.technology or nil
    end,
    GetConnectedTower = function(source)
        local ok, value = callApi('GetConnectedTower', source)
        if ok then return value end
        local state = getClientState()
        return state and state.towerId or nil
    end,
    GetNetworkState = function(source)
        local ok, value = callApi('GetNetworkState', source)
        if ok then return copy(value) end
        return copy(getClientState())
    end,
    CanCall = function(source)
        local ok, available, state = callApi('CanCall', source)
        if ok then return available == true, copy(state) end
        if PhoneBridgeManager and PhoneBridgeManager.ServiceGate then
            return PhoneBridgeManager.ServiceGate(source, 'voice')
        end
        return clientServiceState('voice')
    end,
    CanStartCall = function(source)
        local ok, available, state = callApi('CanCall', source)
        if ok then return available == true, copy(state) end
        if PhoneBridgeManager and PhoneBridgeManager.ServiceGate then
            return PhoneBridgeManager.ServiceGate(source, 'voice')
        end
        return clientServiceState('voice')
    end,
    CanSendSMS = function(source)
        local ok, available, state = callApi('CanSendSMS', source)
        if ok then return available == true, copy(state) end
        if PhoneBridgeManager and PhoneBridgeManager.ServiceGate then
            return PhoneBridgeManager.ServiceGate(source, 'sms')
        end
        return clientServiceState('sms')
    end,
    HasDataConnection = function(source)
        local ok, available, state = callApi('HasDataConnection', source)
        if ok then return available == true, copy(state) end
        if PhoneBridgeManager and PhoneBridgeManager.ServiceGate then
            return PhoneBridgeManager.ServiceGate(source, 'data')
        end
        return clientServiceState('data')
    end,
    CanUseData = function(source)
        local ok, available, state = callApi('HasDataConnection', source)
        if ok then return available == true, copy(state) end
        if PhoneBridgeManager and PhoneBridgeManager.ServiceGate then
            return PhoneBridgeManager.ServiceGate(source, 'data')
        end
        return clientServiceState('data')
    end,
    CanUseService = function(source, service)
        local ok, available, state = callApi('CanUseService', source, service)
        if ok then return available == true, copy(state) end
        if PhoneBridgeManager and PhoneBridgeManager.ServiceGate then
            return PhoneBridgeManager.ServiceGate(source, service)
        end
        return clientServiceState(service)
    end,
    BeginServiceSession = function(source, service, metadata)
        local ok, created, session = callApi('BeginServiceSession', source, service, metadata)
        if ok then return created == true, copy(session) end
        if ServiceSessions and ServiceSessions.Begin then
            return ServiceSessions.Begin(source, service, metadata)
        end
        return false, 'service_sessions_unavailable'
    end,
    UpdateServiceSession = function(sessionId, metadata, ownerSource)
        local ok, updated, session = callApi(
            'UpdateServiceSession',
            sessionId,
            metadata,
            ownerSource
        )
        if ok then return updated == true, copy(session) end
        if ServiceSessions and ServiceSessions.Update then
            return ServiceSessions.Update(sessionId, metadata, ownerSource)
        end
        return false, 'service_sessions_unavailable'
    end,
    EndServiceSession = function(sessionId, ownerSource)
        local ok, ended, session = callApi('EndServiceSession', sessionId, ownerSource)
        if ok then return ended == true, copy(session) end
        if ServiceSessions and ServiceSessions.End then
            return ServiceSessions.End(sessionId, ownerSource)
        end
        return false, 'service_sessions_unavailable'
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

    function adapter:CanStartCall(source)
        return self.api.CanStartCall(source)
    end

    function adapter:CanSendSMS(source)
        return self.api.CanSendSMS(source)
    end

    function adapter:HasDataConnection(source)
        return self.api.HasDataConnection(source)
    end

    function adapter:CanUseData(source)
        return self.api.CanUseData(source)
    end

    function adapter:CanUseService(source, service)
        return self.api.CanUseService(source, service)
    end

    function adapter:BeginServiceSession(source, service, metadata)
        return self.api.BeginServiceSession(source, service, metadata)
    end

    function adapter:UpdateServiceSession(sessionId, metadata, ownerSource)
        return self.api.UpdateServiceSession(sessionId, metadata, ownerSource)
    end

    function adapter:EndServiceSession(sessionId, ownerSource)
        return self.api.EndServiceSession(sessionId, ownerSource)
    end

    return adapter
end

function PhoneBridges.CreateGenericAdapter()
    local adapter = createPublicAdapter('generic')
    adapter.supportLevel = PhoneBridgeContract and PhoneBridgeContract.Levels.FUNCTIONAL
        or 'FUNCTIONAL'
    adapter.support = {
        signalUI = true,
        callGate = true,
        smsGate = true,
        dataGate = true,
        callLifecycle = false,
        networkChangeHooks = false,
    }
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

function PhoneBridges.CreateResourceAdapter(name, resourceNames, options)
    local adapter = createPublicAdapter(name)
    adapter.resourceNames = copy(resourceNames or {})
    adapter.resources = copy(resourceNames or {})
    adapter.priority = ({ lbphone = 300, npwd = 200, qs = 100 })[name] or 0
    for key, value in pairs(options or {}) do adapter[key] = copy(value) end
    function adapter:Detect()
        for _, resourceName in ipairs(self.resourceNames) do
            local started
            if PhoneBridgeManager and type(PhoneBridgeManager.ResourceStarted) == 'function' then
                started = PhoneBridgeManager.ResourceStarted(resourceName)
            else
                started = resourceStarted(resourceName)
            end
            if started then return true end
        end
        return false
    end
    return adapter
end

function PhoneBridges.CreateCustomAdapter()
    local adapter = createPublicAdapter('custom')
    adapter.priority = 400
    function adapter:Detect()
        local configured = BridgeConfig and BridgeConfig.GetProvider
            and BridgeConfig.GetProvider('phone')
            or (Config and Config.PhoneBridge)
        return configured == 'custom'
    end
    return adapter
end

function PhoneBridges.Register(adapter)
    if type(adapter) ~= 'table' or type(adapter.name) ~= 'string'
        or adapter.name == '' then
        return false, 'invalid phone bridge adapter'
    end

    local normalized = adapter
    if PhoneBridgeContract and type(PhoneBridgeContract.Normalize) == 'function' then
        local errorMessage
        normalized, errorMessage = PhoneBridgeContract.Normalize(adapter)
        if not normalized then return false, errorMessage end
    end

    if BridgeManager and type(BridgeManager.Register) == 'function' then
        local contract = copy(normalized)
        contract.category = 'phone'
        local ok, errorMessage = BridgeManager.Register(contract)
        if not ok then return false, errorMessage end
    end

    PhoneBridges.Registry[normalized.name] = normalized
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
    if BridgeManager and type(BridgeManager.GetActive) == 'function' then
        local active = BridgeManager.GetActive('phone')
        if active then return active end
    end

    local configured = BridgeConfig and BridgeConfig.GetProvider
        and BridgeConfig.GetProvider('phone')
        or (Config and Config.PhoneBridge or 'auto')
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
    if BridgeManager and type(BridgeManager.InitializeCategory) == 'function' then
        local configured = BridgeConfig and BridgeConfig.GetProvider
            and BridgeConfig.GetProvider('phone')
            or (Config and Config.PhoneBridge or 'auto')
        local preferred = configured ~= 'auto' and configured or nil
        local ok, selected, errorMessage = BridgeManager.InitializeCategory('phone', preferred)
        PhoneBridges.Active = selected
        PhoneBridges.Initialized = ok and selected ~= nil
        if not ok then return false, nil, errorMessage end
        log('info', 'phone bridge ready', { bridge = selected.name })
        return true, selected
    end

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
    if BridgeManager and type(BridgeManager.ShutdownCategory) == 'function' then
        BridgeManager.ShutdownCategory('phone')
    end
    if PhoneBridges.Active and type(PhoneBridges.Active.Shutdown) == 'function' then
        pcall(function() PhoneBridges.Active:Shutdown() end)
    end
    PhoneBridges.Active = nil
    PhoneBridges.Initialized = false
    return true
end

function PhoneBridges.GetActive()
    if BridgeManager and type(BridgeManager.GetActive) == 'function' then
        return BridgeManager.GetActive('phone')
    end
    return PhoneBridges.Active
end

local function callActive(method, ...)
    local active = PhoneBridges.GetActive()
    if not active or type(active[method]) ~= 'function' then
        local generic = PhoneBridges.Get('generic')
        if not generic or type(generic[method]) ~= 'function' then
            return false, fallbackServiceState('capability_unavailable', 'provider')
        end
        active = generic
    end

    local arguments = { ... }
    local ok, first, second, third = pcall(function()
        return active[method](active, table.unpack(arguments))
    end)
    if not ok then
        return false, fallbackServiceState('provider_error', 'provider')
    end
    return first, second, third
end

function PhoneBridges.CanStartCall(source)
    return callActive('CanStartCall', source)
end

function PhoneBridges.CanCall(source)
    return PhoneBridges.CanStartCall(source)
end

function PhoneBridges.CanSendSMS(source)
    return callActive('CanSendSMS', source)
end

function PhoneBridges.CanUseData(source)
    return callActive('CanUseData', source)
end

function PhoneBridges.HasDataConnection(source)
    return PhoneBridges.CanUseData(source)
end

function PhoneBridges.GetNetworkState(source)
    return callActive('GetNetworkState', source)
end

function PhoneBridges.BeginServiceSession(source, service, metadata)
    return callActive('BeginServiceSession', source, service, metadata)
end

function PhoneBridges.UpdateServiceSession(sessionId, metadata, ownerSource)
    return callActive('UpdateServiceSession', sessionId, metadata, ownerSource)
end

function PhoneBridges.EndServiceSession(sessionId, ownerSource)
    return callActive('EndServiceSession', sessionId, ownerSource)
end

function PhoneBridges.GetStatus()
    local bridgeStatus = BridgeManager and BridgeManager.GetBridgeStatus
        and BridgeManager.GetBridgeStatus('phone') or nil
    local activeProvider = PhoneBridges.GetActive()
    local active = bridgeStatus and bridgeStatus.active
        or PhoneBridges.Active and PhoneBridges.Active.name or nil
    local available = PhoneBridges.Active ~= nil
    local initialized = PhoneBridges.Initialized == true
    if bridgeStatus then
        available = bridgeStatus.available == true
        initialized = bridgeStatus.initialized == true
    end
    return {
        apiVersion = Constants.ApiVersion,
        configured = BridgeConfig and BridgeConfig.GetProvider
            and BridgeConfig.GetProvider('phone')
            or (Config and Config.PhoneBridge or 'auto'),
        active = active,
        available = available,
        initialized = initialized,
        state = bridgeStatus and bridgeStatus.state or nil,
        capabilities = bridgeStatus and bridgeStatus.capabilities or {},
        providers = bridgeStatus and bridgeStatus.providers or {},
        supportLevel = activeProvider and activeProvider.supportLevel
            or bridgeStatus and bridgeStatus.supportLevel or nil,
        support = PhoneBridgeContract and PhoneBridgeContract.CopySupport
            and PhoneBridgeContract.CopySupport(
                activeProvider and activeProvider.support
                    or bridgeStatus and bridgeStatus.support
            ) or {},
    }
end

PhoneBridges.Register(PhoneBridges.CreateGenericAdapter())

local function isServerRuntime()
    if type(IsDuplicityVersion) == 'function' then return IsDuplicityVersion() end
    return true
end

local function providerUsesResource(resourceName)
    for _, adapter in pairs(PhoneBridges.Registry or {}) do
        for _, dependency in ipairs(adapter.resources or adapter.resourceNames or {}) do
            if dependency == resourceName then return true end
        end
    end
    return false
end

local function refreshForResource(resourceName)
    if resourceName == GetCurrentResourceName() then return end
    if providerUsesResource(resourceName) then PhoneBridges.Initialize() end
end

if type(AddEventHandler) == 'function' then
    local resourceStartEvent = isServerRuntime() and 'onResourceStart' or 'onClientResourceStart'
    local resourceStopEvent = isServerRuntime() and 'onResourceStop' or 'onClientResourceStop'
    AddEventHandler(resourceStartEvent, refreshForResource)
    AddEventHandler(resourceStopEvent, refreshForResource)

    if not isServerRuntime() and Constants and Constants.Events then
        AddEventHandler(Constants.Events.CONNECTION_STATE, function(state)
            local active = PhoneBridges.GetActive()
            if active and type(active.OnNetworkState) == 'function' then
                pcall(function() active:OnNetworkState(state) end)
            end
        end)
    end
end

if isServerRuntime() and type(exports) == 'function' then
    exports('CanStartCall', PhoneBridges.CanStartCall)
    exports('CanSendPhoneSMS', PhoneBridges.CanSendSMS)
    exports('CanUsePhoneData', PhoneBridges.CanUseData)
    exports('GetPhoneNetworkState', PhoneBridges.GetNetworkState)
    exports('GetPhoneBridgeStatus', PhoneBridges.GetStatus)
    exports('BeginPhoneServiceSession', PhoneBridges.BeginServiceSession)
    exports('UpdatePhoneServiceSession', PhoneBridges.UpdateServiceSession)
    exports('EndPhoneServiceSession', PhoneBridges.EndServiceSession)
end
