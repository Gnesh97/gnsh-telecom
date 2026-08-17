BridgeManager = BridgeManager or {}

local categories = { 'framework', 'inventory', 'target', 'dispatch', 'phone' }
local states = {}
local categorySections = {
    framework = 'Framework',
    inventory = 'Inventory',
    target = 'Target',
    phone = 'Phone',
    dispatch = 'Dispatch',
}

local function log(level, message, data)
    if Log and type(Log[level]) == 'function' then Log[level](message, data) end
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function configurationFor(category)
    local sectionName = categorySections[category]
    local bridges = type(Config) == 'table' and Config.Bridges
    local section = type(bridges) == 'table' and bridges[sectionName] or nil
    return type(section) == 'table' and section or {}
end

local function legacyProviderFor(category)
    if type(Config) ~= 'table' then return nil end
    return ({
        framework = Config.Framework,
        inventory = Config.InventoryBridge,
        target = Config.TargetBridge,
        phone = Config.PhoneBridge,
    })[category]
end

local function configuredProviderFor(category, configuration)
    if BridgeConfig and type(BridgeConfig.GetProvider) == 'function' then
        return BridgeConfig.GetProvider(category)
    end
    local configured = configuration.provider
    local legacy = legacyProviderFor(category)
    if (configured == nil or configured == 'auto')
        and type(legacy) == 'string' and legacy ~= '' and legacy ~= 'auto' then
        return legacy
    end
    return configured
end

local function resolvePreferences(category, requested)
    local configuration = configurationFor(category)
    local configured = configuration.provider
    if requested == nil then
        configured = configuredProviderFor(category, configuration)
    end
    local preferred = type(configured) == 'string'
        and configured ~= '' and configured ~= 'auto' and configured or requested
    local fallback = type(configuration.fallback) == 'string'
        and configuration.fallback ~= '' and configuration.fallback or nil
    if fallback == nil and category == 'phone' then fallback = 'generic' end
    return preferred, fallback, configuration
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

local function orderProviders(providers, preferred, fallback)
    local result, used = {}, {}

    local function add(name)
        if type(name) ~= 'string' or name == '' or used[name] then return end
        for _, provider in ipairs(providers) do
            if provider.name == name then
                result[#result + 1] = provider
                used[name] = true
                return
            end
        end
    end

    add(preferred)
    if preferred ~= nil then
        add(fallback)
        return result
    end
    for _, provider in ipairs(providers) do
        if not (preferred == nil and provider.name == fallback) then
            add(provider.name)
        end
    end
    if preferred == nil then add(fallback) end
    return result
end

local function finalizeInitialization(category, state)
    state.initializing = false
    return state.active ~= nil
end

function BridgeManager.Register(contract, options)
    local category = type(contract) == 'table' and contract.category or nil
    local name = type(contract) == 'table' and contract.name or nil
    local state = category and stateFor(category) or nil
    local wasActive = state and state.active and state.active.name == name
    if wasActive then shutdownActive(category) end

    local ok, provider, replacedOrError = BridgeRegistry.Register(contract, options)
    if not ok then
        if wasActive then BridgeManager.InitializeCategory(category) end
        return false, provider
    end

    if wasActive then BridgeManager.InitializeCategory(category) end
    return true, provider, replacedOrError
end

function BridgeManager.Unregister(category, name, options)
    local state = stateFor(category)
    local wasActive = state.active and state.active.name == name
    if wasActive then shutdownActive(category) end
    local removed, errorMessage = BridgeRegistry.Unregister(category, name, options)
    if wasActive then BridgeManager.InitializeCategory(category) end
    return removed ~= nil, errorMessage
end

function BridgeManager.GetProvider(category, name)
    if name ~= nil then return BridgeRegistry.Get(category, name) end
    local state = stateFor(category)
    return state.active
end

function BridgeManager.GetActive(category)
    return stateFor(category).active
end

function BridgeManager.HasCapability(category, capability)
    if type(capability) ~= 'string' or capability == '' then return false end
    local active = BridgeManager.GetActive(category)
    return active ~= nil and active.capabilities
        and active.capabilities[capability] == true
end

function BridgeManager.InitializeCategory(category, preferred, force)
    if not BridgeContracts.IsCategory(category) then
        return false, nil, 'unknown_category'
    end

    local resolvedPreferred, fallback = resolvePreferences(category, preferred)
    preferred = resolvedPreferred

    local state = stateFor(category)
    if state.initializing then return false, nil, 'initialization_in_progress' end
    if not force and state.active and (preferred == nil or state.active.name == preferred)
        and BridgeLifecycle.ResourcesAvailable(state.active) then
        return true, state.active
    end

    shutdownActive(category)
    state.initializing = true

    local providers = orderProviders(BridgeRegistry.List(category), preferred, fallback)
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
    local allRequiredSatisfied = true
    for _, category in ipairs(categories) do
        BridgeManager.InitializeCategory(category)
        result[category] = BridgeManager.GetBridgeStatus(category)
        if not result[category].requiredSatisfied then allRequiredSatisfied = false end
    end
    return allRequiredSatisfied, result
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
        return BridgeManager.InitializeCategory(category, nil, true)
    end
    state.state = BridgeHealth.Normalize(healthValue, BridgeHealth.States.ACTIVE)
    mark(category, state.active, { state = state.state })
    if state.state == BridgeHealth.States.FAILED
        or state.state == BridgeHealth.States.UNAVAILABLE then
        return BridgeManager.InitializeCategory(category, nil, true)
    end
    return true, state.active
end

function BridgeManager.Call(category, method, ...)
    local active = BridgeManager.GetActive(category)
    if not active then
        local initialized
        initialized, active = BridgeManager.InitializeCategory(category)
        if not initialized then return false, nil, 'bridge_unavailable' end
    end

    if type(active[method]) ~= 'function' then
        return false, nil, 'capability_unavailable'
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

local function requirementStatus(category, active)
    local configuration = configurationFor(category)
    local configured = configuredProviderFor(category, configuration)
    local required = configuration.required == true
    local requireEnforcement = category == 'phone'
        and configuration.requireEnforcement == true
    local requiredSatisfied = true
    local activeState = stateFor(category).state

    if required and (active == nil or activeState == BridgeHealth.States.FAILED
        or activeState == BridgeHealth.States.UNAVAILABLE) then
        requiredSatisfied = false
    end
    if requireEnforcement then
        local supportLevel = active and active.supportLevel
        if active == nil or activeState == BridgeHealth.States.FAILED
            or activeState == BridgeHealth.States.UNAVAILABLE
            or (supportLevel ~= 'FULL' and supportLevel ~= 'FUNCTIONAL') then
            requiredSatisfied = false
        end
    end

    return {
        configured = configured,
        fallback = type(configuration.fallback) == 'string'
            and configuration.fallback ~= '' and configuration.fallback
            or (category == 'phone' and 'generic' or nil),
        required = required or requireEnforcement,
        requireEnforcement = requireEnforcement,
        requiredSatisfied = requiredSatisfied,
    }
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
            supportLevel = provider.supportLevel,
            support = copy(provider.support),
        }
    end

    local active = state.active
    local requirements = requirementStatus(category, active)
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
        supportLevel = active and active.supportLevel or nil,
        configured = requirements.configured,
        fallback = requirements.fallback,
        fallbackUsed = type(requirements.configured) == 'string'
            and type(requirements.fallback) == 'string'
            and active ~= nil and requirements.fallback == active.name
            and requirements.configured ~= requirements.fallback or false,
        required = requirements.required,
        requireEnforcement = requirements.requireEnforcement,
        requiredSatisfied = requirements.requiredSatisfied,
        providers = providerStatuses,
    }
end

function BridgeManager.GetBridgeCapabilities(category)
    local status = BridgeManager.GetBridgeStatus(category)
    return status and status.capabilities or {}
end

local function supportStatus(category, bridge, configuration)
    local status
    if bridge and type(bridge.GetStatus) == 'function' then
        local ok, result = pcall(bridge.GetStatus)
        if ok and type(result) == 'table' then status = copy(result) end
    end
    status = status or {
        category = category,
        state = 'OPTIONAL',
        active = nil,
        provider = nil,
        available = false,
        initialized = false,
        capabilities = {},
    }
    status.category = category
    status.provider = status.provider or status.active
    status.active = status.active or status.provider
    status.configured = BridgeConfig and type(BridgeConfig.GetProvider) == 'function'
        and BridgeConfig.GetProvider(category) or configuration.provider
    status.fallback = BridgeConfig and type(BridgeConfig.GetFallback) == 'function'
        and BridgeConfig.GetFallback(category) or configuration.fallback
    status.fallbackUsed = type(status.configured) == 'string'
        and type(status.fallback) == 'string'
        and status.provider ~= nil and status.provider == status.fallback
        and status.configured ~= status.fallback or false
    status.required = configuration.required == true
    status.requiredSatisfied = not status.required
        or (status.provider ~= nil
            and status.state ~= BridgeHealth.States.FAILED
            and status.state ~= BridgeHealth.States.UNAVAILABLE)
    return status
end

function BridgeManager.GetIntegrationSummary()
    local summary = {
        compatible = true,
        compatibility = 'OK',
        categories = {},
        lines = { 'Integration Summary' },
    }

    local ordered = {
        { key = 'framework', label = 'Framework' },
        { key = 'inventory', label = 'Inventory' },
        { key = 'target', label = 'Target' },
        { key = 'phone', label = 'Phone' },
        { key = 'dispatch', label = 'Dispatch' },
    }
    for _, item in ipairs(ordered) do
        local status = BridgeManager.GetBridgeStatus(item.key)
        summary.categories[item.key] = status
        if not status.requiredSatisfied then summary.compatible = false end
    end

    local bridges = type(Config) == 'table' and Config.Bridges or {}
    local notifyConfig = type(bridges) == 'table' and bridges.Notify or {}
    local progressConfig = type(bridges) == 'table' and bridges.Progress or {}
    local supportCategories = {
        { key = 'notify', label = 'Notify', bridge = NotifyBridge, config = notifyConfig },
        { key = 'progress', label = 'Progress', bridge = ProgressBridge, config = progressConfig },
    }
    for _, item in ipairs(supportCategories) do
        local status = supportStatus(item.key, item.bridge, item.config or {})
        summary.categories[item.key] = status
        if not status.requiredSatisfied then summary.compatible = false end
    end

    summary.compatibility = summary.compatible and 'OK' or 'FAILED'
    for _, item in ipairs(ordered) do
        local status = summary.categories[item.key]
        local provider = status.provider or 'none'
        local state = status.supportLevel or status.state or 'UNAVAILABLE'
        summary.lines[#summary.lines + 1] = ('%-10s: %-14s %s')
            :format(item.label, provider, state)
    end
    for _, item in ipairs(supportCategories) do
        local status = summary.categories[item.key]
        local provider = status.provider or 'none'
        local state = status.state or 'UNAVAILABLE'
        summary.lines[#summary.lines + 1] = ('%-10s: %-14s %s')
            :format(item.label, provider, state)
    end
    summary.lines[#summary.lines + 1] = 'Compatibility : ' .. summary.compatibility
    summary.text = table.concat(summary.lines, '\n')
    return summary
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
