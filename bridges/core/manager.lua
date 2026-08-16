BridgeManager = BridgeManager or {}

local categories = { 'framework', 'inventory', 'target', 'dispatch', 'phone' }
local states = {}

local function log(level, message, data)
    if Log and type(Log[level]) == 'function' then Log[level](message, data) end
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function stateFor(category)
    states[category] = states[category] or {
        active = nil,
        initialized = false,
        initializing = false,
        state = nil,
        providers = {},
    }
    return states[category]
end

local function providerState(category, provider)
    local state = stateFor(category)
    state.providers[provider.name] = state.providers[provider.name] or {
        state = BridgeHealth.States.UNAVAILABLE,
        available = false,
        initialized = false,
        selected = false,
    }
    return state.providers[provider.name]
end

local function mark(category, provider, values)
    local current = providerState(category, provider)
    for key, value in pairs(values or {}) do current[key] = value end
end

local function shutdownActive(category)
    local state = stateFor(category)
    local active = state.active
    if active then
        local stopped, errorMessage = BridgeLifecycle.Shutdown(active)
        if not stopped then
            log('warn', 'bridge shutdown failed', {
                category = category,
                bridge = active.name,
                error = errorMessage,
            })
        end
        mark(category, active, {
            initialized = false,
            selected = false,
        })
    end
    state.active = nil
    state.initialized = false
end

local function orderProviders(providers, preferred)
    if type(preferred) ~= 'string' or preferred == '' then return providers end
    local result, preferredProvider = {}, nil
    for _, provider in ipairs(providers) do
        if provider.name == preferred then
            preferredProvider = provider
        else
            result[#result + 1] = provider
        end
    end
    if preferredProvider then table.insert(result, 1, preferredProvider) end
    return result
end

local function finalizeInitialization(category, state)
    state.initializing = false
    return state.active ~= nil
end

function BridgeManager.Register(contract)
    local category = type(contract) == 'table' and contract.category or nil
    local name = type(contract) == 'table' and contract.name or nil
    local state = category and stateFor(category) or nil
    local wasActive = state and state.active and state.active.name == name
    if wasActive then shutdownActive(category) end

    local ok, provider, replacedOrError = BridgeRegistry.Register(contract)
    if not ok then
        if wasActive then BridgeManager.InitializeCategory(category) end
        return false, provider
    end

    if wasActive then BridgeManager.InitializeCategory(category) end
    return true, provider, replacedOrError
end

function BridgeManager.Unregister(category, name)
    local state = stateFor(category)
    local wasActive = state.active and state.active.name == name
    if wasActive then shutdownActive(category) end
    local removed = BridgeRegistry.Unregister(category, name)
    if wasActive then BridgeManager.InitializeCategory(category) end
    return removed ~= nil
end

function BridgeManager.GetProvider(category, name)
    if name ~= nil then return BridgeRegistry.Get(category, name) end
    local state = stateFor(category)
    return state.active
end

function BridgeManager.GetActive(category)
    return stateFor(category).active
end

function BridgeManager.InitializeCategory(category, preferred, force)
    if not BridgeContracts.IsCategory(category) then
        return false, nil, 'unknown_category'
    end

    local state = stateFor(category)
    if state.initializing then return false, nil, 'initialization_in_progress' end
    if not force and state.active and (preferred == nil or state.active.name == preferred)
        and BridgeLifecycle.ResourcesAvailable(state.active) then
        return true, state.active
    end

    shutdownActive(category)
    state.initializing = true

    local providers = BridgeRegistry.List(category)
    if #providers == 0 then
        state.state = BridgeHealth.States.OPTIONAL
        state.initialized = false
        finalizeInitialization(category, state)
        return false, nil, 'no_provider'
    end

    for _, provider in ipairs(providers) do
        mark(category, provider, {
            selected = false,
            initialized = false,
        })

        local available = BridgeLifecycle.ResourcesAvailable(provider)
        mark(category, provider, { available = available })
        if available then
            local detected, detectError = BridgeLifecycle.Detect(provider)
            if detected then
                local initialized, initializeError = BridgeLifecycle.Initialize(provider)
                if initialized then
                    local healthy, healthValue, healthError = BridgeLifecycle.HealthCheck(provider)
                    if healthy then
                        local healthState = BridgeHealth.Normalize(
                            healthValue,
                            BridgeHealth.States.ACTIVE
                        )
                        if healthState ~= BridgeHealth.States.FAILED
                            and healthState ~= BridgeHealth.States.UNAVAILABLE then
                            state.active = provider
                            state.initialized = true
                            state.state = healthState
                            mark(category, provider, {
                                state = healthState,
                                selected = true,
                                initialized = true,
                                available = true,
                                error = nil,
                            })
                            log('info', 'bridge selected', {
                                category = category,
                                bridge = provider.name,
                                state = healthState,
                            })
                            finalizeInitialization(category, state)
                            return true, provider
                        end
                        healthError = 'health_state_' .. healthState
                    end
                    BridgeLifecycle.Shutdown(provider)
                    mark(category, provider, {
                        state = BridgeHealth.States.FAILED,
                        error = healthError or 'provider_health_check_failed',
                    })
                else
                    mark(category, provider, {
                        state = BridgeHealth.States.FAILED,
                        error = initializeError or 'provider_initialization_failed',
                    })
                end
            else
                mark(category, provider, {
                    state = detectError == 'provider_not_detected'
                        and BridgeHealth.States.UNAVAILABLE or BridgeHealth.States.FAILED,
                    error = detectError,
                })
            end
        else
            mark(category, provider, {
                state = BridgeHealth.States.UNAVAILABLE,
                error = 'resources_unavailable',
            })
        end
    end

    local hasFailure = false
    for _, provider in ipairs(providers) do
        if providerState(category, provider).state == BridgeHealth.States.FAILED then
            hasFailure = true
            break
        end
    end
    state.state = hasFailure and BridgeHealth.States.FAILED or BridgeHealth.States.UNAVAILABLE
    state.initialized = false
    finalizeInitialization(category, state)
    return false, nil, state.state:lower()
end

function BridgeManager.InitializeAll()
    local result = {}
    for _, category in ipairs(categories) do
        BridgeManager.InitializeCategory(category)
        result[category] = BridgeManager.GetBridgeStatus(category)
    end
    return true, result
end

function BridgeManager.ShutdownCategory(category)
    if not BridgeContracts.IsCategory(category) then return false end
    shutdownActive(category)
    local state = stateFor(category)
    state.state = BridgeRegistry.Count(category) == 0
        and BridgeHealth.States.OPTIONAL or BridgeHealth.States.UNAVAILABLE
    return true
end

function BridgeManager.ShutdownAll()
    for _, category in ipairs(categories) do BridgeManager.ShutdownCategory(category) end
    return true
end

function BridgeManager.HandleResourceStart(resourceName)
    if type(resourceName) ~= 'string' or resourceName == '' then return false end
    local touched = false
    for _, category in ipairs(categories) do
        local categoryTouched = false
        for _, provider in ipairs(BridgeRegistry.List(category)) do
            for _, dependency in ipairs(provider.resources or {}) do
                if dependency == resourceName then
                    touched = true
                    categoryTouched = true
                    BridgeManager.InitializeCategory(category, nil, true)
                    break
                end
            end
            if categoryTouched then break end
        end
    end
    return touched
end

function BridgeManager.HandleResourceStop(resourceName)
    return BridgeManager.HandleResourceStart(resourceName)
end

function BridgeManager.Refresh(category)
    local state = stateFor(category)
    if not state.active then return BridgeManager.InitializeCategory(category) end
    local healthy, healthValue = BridgeLifecycle.HealthCheck(state.active)
    if not healthy then
        state.state = BridgeHealth.States.FAILED
        return BridgeManager.InitializeCategory(category)
    end
    state.state = BridgeHealth.Normalize(healthValue, BridgeHealth.States.ACTIVE)
    mark(category, state.active, { state = state.state })
    return true, state.active
end

function BridgeManager.Call(category, method, ...)
    local active = BridgeManager.GetActive(category)
    if not active then
        local initialized
        initialized, active = BridgeManager.InitializeCategory(category)
        if not initialized then return false, nil, 'bridge_unavailable' end
    end

    local ok, first, second, third = BridgeLifecycle.Call(active, method, ...)
    if not ok then
        mark(category, active, {
            state = BridgeHealth.States.FAILED,
            error = third or second,
        })
        BridgeManager.InitializeCategory(category)
        return false, nil, third or second or 'provider_call_failed'
    end
    return true, first, second, third
end

function BridgeManager.GetBridgeStatus(category)
    if category == nil then
        local result = {}
        for _, knownCategory in ipairs(categories) do
            result[knownCategory] = BridgeManager.GetBridgeStatus(knownCategory)
        end
        return result
    end
    if not BridgeContracts.IsCategory(category) then return nil end

    local state = stateFor(category)
    local providers = BridgeRegistry.List(category)
    local providerStatuses = {}
    for _, provider in ipairs(providers) do
        local current = providerState(category, provider)
        providerStatuses[#providerStatuses + 1] = {
            name = provider.name,
            priority = provider.priority,
            state = current.state,
            available = current.available == true,
            initialized = current.initialized == true,
            selected = current.selected == true,
            error = current.error,
            capabilities = BridgeCapabilities.Copy(provider.capabilities),
            resources = copy(provider.resources),
        }
    end

    local active = state.active
    local categoryState = state.state
    if not categoryState then
        categoryState = #providers == 0
            and BridgeHealth.States.OPTIONAL or BridgeHealth.States.UNAVAILABLE
    end
    return {
        category = category,
        state = categoryState,
        active = active and active.name or nil,
        provider = active and active.name or nil,
        available = active ~= nil,
        initialized = state.initialized == true,
        capabilities = active and BridgeCapabilities.Copy(active.capabilities) or {},
        providers = providerStatuses,
    }
end

function BridgeManager.GetBridgeCapabilities(category)
    local status = BridgeManager.GetBridgeStatus(category)
    return status and status.capabilities or {}
end

function BridgeManager.Categories()
    local result = {}
    for index, category in ipairs(categories) do result[index] = category end
    return result
end

function BridgeManager.Reset()
    BridgeManager.ShutdownAll()
    BridgeRegistry.Clear()
    states = {}
end

GetBridgeStatus = function(category)
    return BridgeManager.GetBridgeStatus(category)
end

GetBridgeCapabilities = function(category)
    return BridgeManager.GetBridgeCapabilities(category)
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('onResourceStart', function(resourceName)
        local currentResource = type(GetCurrentResourceName) == 'function'
            and GetCurrentResourceName() or nil
        if resourceName == currentResource then
            BridgeManager.InitializeAll()
        else
            BridgeManager.HandleResourceStart(resourceName)
        end
    end)

    AddEventHandler('onResourceStop', function(resourceName)
        local currentResource = type(GetCurrentResourceName) == 'function'
            and GetCurrentResourceName() or nil
        if resourceName == currentResource then
            BridgeManager.ShutdownAll()
        else
            BridgeManager.HandleResourceStop(resourceName)
        end
    end)
end
