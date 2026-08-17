BridgeSDK = BridgeSDK or {}

local supportedCategories = {
    'framework',
    'inventory',
    'target',
    'phone',
    'dispatch',
    'notify',
    'progress',
}

local supportedCategorySet = {}
for _, category in ipairs(supportedCategories) do
    supportedCategorySet[category] = true
end

local registrationsByOwner = {}

local function copyList(values)
    local result = {}
    for index, value in ipairs(values or {}) do result[index] = value end
    return result
end

local function validResourceName(value)
    return type(value) == 'string'
        and #value > 0
        and #value <= 128
        and value:match('^[%w_.-]+$') ~= nil
end

local function validBridgeName(value)
    return type(value) == 'string'
        and #value > 0
        and #value <= 64
        and value:match('^[%w][%w_.-]*$') ~= nil
end

local function currentResourceName()
    if type(GetCurrentResourceName) ~= 'function' then return nil end
    local ok, value = pcall(GetCurrentResourceName)
    return ok and validResourceName(value) and value or nil
end

local function invokingResourceName()
    if type(GetInvokingResource) ~= 'function' then return nil end
    local ok, value = pcall(GetInvokingResource)
    return ok and validResourceName(value) and value or nil
end

local function resolveOwnerResource()
    return invokingResourceName() or currentResourceName()
end

local function ownerResourceStarted(resourceName)
    if not validResourceName(resourceName) then return false end
    if resourceName == currentResourceName() then return true end
    if type(GetResourceState) ~= 'function' then return true end
    local ok, state = pcall(GetResourceState, resourceName)
    return ok and state == 'started'
end

local function registrationKey(category, name)
    return category .. '\0' .. name
end

local function rememberRegistration(ownerResource, category, name)
    registrationsByOwner[ownerResource] = registrationsByOwner[ownerResource] or {}
    registrationsByOwner[ownerResource][registrationKey(category, name)] = {
        category = category,
        name = name,
    }
end

local function forgetRegistration(ownerResource, category, name)
    local owned = registrationsByOwner[ownerResource]
    if not owned then return end
    owned[registrationKey(category, name)] = nil
    if next(owned) == nil then registrationsByOwner[ownerResource] = nil end
end

local function supportBridge(category)
    if category == 'notify' then
        return type(NotifyBridge) == 'table' and NotifyBridge or nil
    end
    if category == 'progress' then
        return type(ProgressBridge) == 'table' and ProgressBridge or nil
    end
    return nil
end

local function providerExists(category, name)
    local provider = BridgeRegistry.Get(category, name)
    if provider ~= nil then return true end

    local bridge = supportBridge(category)
    return bridge ~= nil
        and type(bridge.Providers) == 'table'
        and bridge.Providers[name] ~= nil
end

local function definitionCopy(category, definition)
    local result = {}
    for key, value in pairs(definition) do
        if key ~= 'category'
            and key ~= 'ownerResource'
            and key ~= 'external'
            and key ~= 'replace'
            and key ~= 'activate'
            and key ~= 'autoActivate' then
            result[key] = value
        end
    end
    result.category = category

    if result.resources == nil then
        local resourceName = result.resource or result.resourceName
        if type(resourceName) == 'string' then result.resources = { resourceName } end
    end
    return result
end

local function normalizeDefinition(category, definition)
    if not supportedCategorySet[category] then
        return nil, 'unsupported_category'
    end
    if type(definition) ~= 'table' then
        return nil, 'invalid_definition'
    end
    if definition.category ~= nil and definition.category ~= category then
        return nil, 'category_mismatch'
    end
    if not validBridgeName(definition.name) then
        return nil, 'invalid_bridge_name'
    end

    local normalized, errorMessage = BridgeContracts.Normalize(
        definitionCopy(category, definition)
    )
    if not normalized then return nil, errorMessage end

    if #normalized.resources > 16 then
        return nil, 'too_many_resources'
    end
    for _, resourceName in ipairs(normalized.resources) do
        if not validResourceName(resourceName) then
            return nil, 'invalid_resource_dependency'
        end
    end

    local capabilityCount = 0
    for capability, enabled in pairs(normalized.capabilities) do
        if enabled == true then
            capabilityCount = capabilityCount + 1
            if type(normalized[capability]) ~= 'function' then
                return nil, 'capability_callback_missing:' .. capability
            end
        end
    end
    if capabilityCount == 0 then return nil, 'bridge_capability_missing' end

    local requiredMethod = ({ notify = 'Notify', progress = 'StartProgress' })[category]
    if requiredMethod and type(normalized[requiredMethod]) ~= 'function' then
        return nil, 'required_callback_missing:' .. requiredMethod
    end

    return normalized
end

local function lifecycleReady(provider)
    local detected, detectError = BridgeLifecycle.Detect(provider)
    if not detected then return false, detectError or 'provider_not_detected' end

    local initialized, initializeError = BridgeLifecycle.Initialize(provider)
    if not initialized then
        return false, initializeError or 'provider_initialization_failed'
    end

    local healthy, healthValue, healthError = BridgeLifecycle.HealthCheck(provider)
    if not healthy then
        BridgeLifecycle.Shutdown(provider)
        return false, healthError or 'provider_health_check_failed'
    end

    local healthState = BridgeHealth.Normalize(healthValue, BridgeHealth.States.ACTIVE)
    if healthState == BridgeHealth.States.FAILED
        or healthState == BridgeHealth.States.UNAVAILABLE then
        BridgeLifecycle.Shutdown(provider)
        return false, 'health_state_' .. healthState
    end
    return true
end

local function activateSupport(category, provider)
    local bridge = supportBridge(category)
    if not bridge or type(bridge.SetAdapter) ~= 'function' then
        return false, 'support_bridge_unavailable'
    end

    local ready, readyError = lifecycleReady(provider)
    if not ready then return false, readyError end

    local active = type(bridge.GetActive) == 'function' and bridge.GetActive() or nil
    if active and active.name ~= provider.name then
        local stopped, stopError = BridgeLifecycle.Shutdown(active)
        if not stopped then
            BridgeLifecycle.Shutdown(provider)
            return false, stopError or 'active_provider_shutdown_failed'
        end
    end

    local selected, selectError = bridge.SetAdapter(provider.name)
    if not selected then
        BridgeLifecycle.Shutdown(provider)
        return false, selectError or 'support_provider_selection_failed'
    end
    return true
end

local function statusFor(category, name, provider, metadata)
    local status
    local bridge = supportBridge(category)
    if bridge and type(bridge.GetStatus) == 'function' then
        local ok, result = pcall(bridge.GetStatus)
        if ok and type(result) == 'table' then status = result end
    elseif BridgeManager and type(BridgeManager.GetBridgeStatus) == 'function' then
        status = BridgeManager.GetBridgeStatus(category)
    end

    local providerStatus
    for _, item in ipairs(status and status.providers or {}) do
        if item.name == name then
            providerStatus = item
            break
        end
    end

    local active = status and (status.active or status.provider) == name
    return {
        category = category,
        name = name,
        ownerResource = metadata.ownerResource,
        external = metadata.external == true,
        sequence = metadata.sequence,
        priority = provider.priority,
        state = providerStatus and providerStatus.state
            or (active and status.state or 'UNAVAILABLE'),
        active = active,
        available = providerStatus and providerStatus.available == true or active,
        initialized = providerStatus and providerStatus.initialized == true or active,
        error = providerStatus and providerStatus.error or nil,
        capabilities = BridgeCapabilities.Copy(provider.capabilities),
        resources = copyList(provider.resources),
    }
end

local function unregisterOwned(category, name, ownerResource)
    local metadata = BridgeRegistry.GetMetadata(category, name)
    if not metadata then return false, 'bridge_not_found' end
    if metadata.external ~= true then return false, 'bridge_not_external' end
    if metadata.ownerResource ~= ownerResource then return false, 'bridge_owner_mismatch' end

    local provider = BridgeRegistry.Get(category, name)
    local bridge = supportBridge(category)
    if bridge then
        local active = type(bridge.GetActive) == 'function' and bridge.GetActive() or nil
        if active and active.name == name then
            BridgeLifecycle.Shutdown(active)
            if type(bridge.SetAdapter) == 'function' then bridge.SetAdapter(nil) end
        end
        if type(bridge.Unregister) == 'function' then
            local removed = bridge.Unregister(name)
            if not removed and type(bridge.Providers) == 'table'
                and bridge.Providers[name] ~= nil then
                return false, 'support_provider_unregistration_failed'
            end
        end
    else
        local removed, errorMessage = BridgeManager.Unregister(category, name, {
            ownerResource = ownerResource,
            externalOnly = true,
        })
        if not removed then return false, errorMessage or 'bridge_unregistration_failed' end
        forgetRegistration(ownerResource, category, name)
        return true, provider
    end

    local removed, errorMessage = BridgeRegistry.Unregister(category, name, {
        ownerResource = ownerResource,
        externalOnly = true,
    })
    if not removed then return false, errorMessage or 'bridge_unregistration_failed' end

    forgetRegistration(ownerResource, category, name)
    return true, provider
end

function BridgeSDK.RegisterBridge(category, definition)
    local ownerResource = resolveOwnerResource()
    if not ownerResource then return false, 'owner_required' end
    if not ownerResourceStarted(ownerResource) then return false, 'owner_not_started' end

    local normalized, errorMessage = normalizeDefinition(category, definition)
    if not normalized then return false, errorMessage end
    if providerExists(category, normalized.name) then
        return false, 'bridge_duplicate'
    end

    local bridge = supportBridge(category)
    if bridge and type(bridge.Register) ~= 'function' then
        return false, 'support_bridge_unavailable'
    end

    local provider
    local registered
    if bridge then
        registered, errorMessage = bridge.Register(normalized)
        if not registered then return false, errorMessage or 'provider_registration_failed' end
        local registryOk
        registryOk, provider, errorMessage = BridgeRegistry.Register(normalized, {
            external = true,
            ownerResource = ownerResource,
            rejectDuplicate = true,
        })
        if not registryOk then
            bridge.Unregister(normalized.name)
            return false, errorMessage
        end
    else
        registered, provider, errorMessage = BridgeManager.Register(normalized, {
            external = true,
            ownerResource = ownerResource,
            rejectDuplicate = true,
        })
        if not registered then return false, errorMessage end
    end

    rememberRegistration(ownerResource, category, normalized.name)

    local activate = definition.activate ~= false and definition.autoActivate ~= false
    if activate then
        if bridge then
            activateSupport(category, bridge.Providers[normalized.name] or normalized)
        else
            BridgeManager.InitializeCategory(category, normalized.name, true)
        end
    end

    local metadata = BridgeRegistry.GetMetadata(category, normalized.name)
    return true, statusFor(category, normalized.name, provider, metadata)
end

function BridgeSDK.UnregisterBridge(category, name)
    local ownerResource = resolveOwnerResource()
    if not ownerResource then return false, 'owner_required' end
    if not supportedCategorySet[category] then return false, 'unsupported_category' end
    if not validBridgeName(name) then return false, 'invalid_bridge_name' end
    return unregisterOwned(category, name, ownerResource)
end

function BridgeSDK.GetBridgeRegistration(category, name)
    if not supportedCategorySet[category] or not validBridgeName(name) then return nil end
    local metadata = BridgeRegistry.GetMetadata(category, name)
    local provider = BridgeRegistry.Get(category, name)
    if not metadata or metadata.external ~= true or not provider then return nil end
    return statusFor(category, name, provider, metadata)
end

function BridgeSDK.GetBridgeRegistrations(category)
    if category ~= nil and not supportedCategorySet[category] then
        return nil, 'unsupported_category'
    end

    local result = {}
    local categories = category and { category } or supportedCategories
    for _, knownCategory in ipairs(categories) do
        for _, provider in ipairs(BridgeRegistry.List(knownCategory)) do
            local metadata = BridgeRegistry.GetMetadata(knownCategory, provider.name)
            if metadata and metadata.external == true then
                result[#result + 1] = statusFor(
                    knownCategory,
                    provider.name,
                    provider,
                    metadata
                )
            end
        end
    end
    return result
end

function BridgeSDK.GetBridgeStatus(category)
    if category == nil then
        local result = BridgeManager.GetBridgeStatus()
        local notify = BridgeSDK.GetBridgeStatus('notify')
        local progress = BridgeSDK.GetBridgeStatus('progress')
        result.notify = notify
        result.progress = progress
        return result
    end
    if not supportedCategorySet[category] then return nil end
    local bridge = supportBridge(category)
    if bridge and type(bridge.GetStatus) == 'function' then
        local ok, status = pcall(bridge.GetStatus)
        if ok and type(status) == 'table' then return status end
    end
    return BridgeManager.GetBridgeStatus(category)
end

function BridgeSDK.GetBridgeCapabilities(category)
    local status = BridgeSDK.GetBridgeStatus(category)
    return status and BridgeCapabilities.Copy(status.capabilities) or {}
end

function BridgeSDK.GetSupportedCategories()
    return copyList(supportedCategories)
end

if type(exports) == 'function' then
    exports('RegisterBridge', BridgeSDK.RegisterBridge)
    exports('UnregisterBridge', BridgeSDK.UnregisterBridge)
    exports('GetBridgeRegistration', BridgeSDK.GetBridgeRegistration)
    exports('GetBridgeRegistrations', BridgeSDK.GetBridgeRegistrations)
    exports('GetSupportedBridgeCategories', BridgeSDK.GetSupportedCategories)
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('onResourceStop', function(resourceName)
        local owned = registrationsByOwner[resourceName]
        if not owned then return end
        local pending = {}
        for _, registration in pairs(owned) do pending[#pending + 1] = registration end
        for _, registration in ipairs(pending) do
            unregisterOwned(registration.category, registration.name, resourceName)
        end
        registrationsByOwner[resourceName] = nil
    end)
end
