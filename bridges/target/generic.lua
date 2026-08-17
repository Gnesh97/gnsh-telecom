TargetBridge = TargetBridge or {}
TargetBridges = TargetBridges or {}
TargetBridges.Registry = TargetBridges.Registry or {}

local runtimeName
local localActive
local localInitialized = false

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    return value
end

local function invoke(value, method, ...)
    local fn = value and value[method]
    if type(fn) ~= 'function' then return true end
    local args = { ... }
    local ok, result, errorMessage = pcall(function()
        return fn(value, table.unpack(args))
    end)
    if not ok then return false, tostring(result) end
    return result ~= false, errorMessage
end

local function makeContract(value, runtime)
    local name = type(value.name) == 'string' and value.name ~= ''
        and value.name or (runtime and 'runtime' or nil)
    if not name then return nil, 'target_adapter_name_required' end

    local contract = {}
    for key, item in pairs(value) do contract[key] = item end
    contract.name = name
    contract.category = 'target'
    contract.priority = runtime and (value.priority or 1000) or (value.priority or 0)
    if contract.resources == nil and type(contract.resource) == 'string' then
        contract.resources = { contract.resource }
    end
    contract.capabilities = value.capabilities or {
        'AddEntityInteraction',
        'AddModelInteraction',
        'AddZoneInteraction',
        'RemoveInteraction',
        'AddTowerTarget',
        'RemoveTowerTarget',
    }
    if type(value.AddTowerTarget) == 'function' then
        contract.AddTowerTarget = function(_, tower, callbacks)
            return value.AddTowerTarget(tower, callbacks)
        end
    end
    if type(value.RemoveTowerTarget) == 'function' then
        contract.RemoveTowerTarget = function(_, towerId)
            return value.RemoveTowerTarget(towerId)
        end
    end
    contract.Detect = value.Detect or function() return true end
    contract.Initialize = function()
        return invoke(value, 'Initialize')
    end
    contract.Shutdown = function()
        return invoke(value, 'Shutdown')
    end
    contract.HealthCheck = function()
        local fn = value.HealthCheck
        if type(fn) ~= 'function' then return 'ACTIVE' end
        local ok, result = pcall(fn, value)
        return ok and result or false
    end
    return contract
end

local function registerContract(value, runtime)
    if type(value) ~= 'table' then return false, 'invalid_target_adapter' end
    local contract, contractError = makeContract(value, runtime)
    if not contract then return false, contractError end

    if BridgeManager and type(BridgeManager.Register) == 'function' then
        local ok, errorMessage = BridgeManager.Register(contract)
        if not ok then return false, errorMessage end
    end
    TargetBridges.Registry[contract.name] = value
    return true, contract.name
end

function TargetBridge.Register(value)
    return registerContract(value, false)
end

function TargetBridge.Get(name)
    if type(name) ~= 'string' then return nil end
    return TargetBridges.Registry[name]
end

local function configuredName()
    if BridgeConfig and type(BridgeConfig.GetProvider) == 'function' then
        return BridgeConfig.GetProvider('target')
    end
    local configured = Config and Config.TargetBridge
    return type(configured) == 'string' and configured ~= '' and configured or 'auto'
end

local function detected(provider)
    if type(provider) ~= 'table' then return false end
    local fn = provider.Detect
    if type(fn) ~= 'function' then return true end
    local ok, result = pcall(function() return fn(provider) end)
    return ok and result == true
end

local function sortedProviders()
    local result = {}
    for _, provider in pairs(TargetBridges.Registry) do result[#result + 1] = provider end
    table.sort(result, function(left, right)
        local leftPriority = tonumber(left.priority) or 0
        local rightPriority = tonumber(right.priority) or 0
        if leftPriority ~= rightPriority then return leftPriority > rightPriority end
        return tostring(left.name) < tostring(right.name)
    end)
    return result
end

local function selectLocal()
    local configured = configuredName()
    if configured ~= 'auto' then
        local explicit = TargetBridges.Registry[configured]
        if explicit and detected(explicit) then return explicit end
    else
        for _, provider in ipairs(sortedProviders()) do
            if detected(provider) then return provider end
        end
    end
    return TargetBridges.Registry.native
end

local function initializeLocal()
    local selected = selectLocal()
    if not selected then
        localActive = nil
        localInitialized = false
        return false, nil, 'target_unavailable'
    end
    if localInitialized and localActive == selected then return true, selected end

    if localActive then invoke(localActive, 'Shutdown') end
    localActive = nil
    localInitialized = false
    localActive = selected
    localInitialized = invoke(selected, 'Initialize')
    if not localInitialized then
        localActive = nil
        return false, nil, 'target_initialization_failed'
    end
    return true, selected
end

local function activeProvider()
    if BridgeManager and type(BridgeManager.GetActive) == 'function' then
        local active = BridgeManager.GetActive('target')
        if active then return active end
        local initialized
        initialized, active = BridgeManager.InitializeCategory('target')
        if initialized then return active end
        return nil
    end
    if not localInitialized then initializeLocal() end
    return localActive
end

local function call(method, ...)
    local provider = activeProvider()
    if not provider then return false, nil, 'target_unavailable' end

    if BridgeManager and type(BridgeManager.Call) == 'function' then
        local ok, result, second, third = BridgeManager.Call('target', method, ...)
        if not ok and second ~= 'capability_unavailable'
            and second ~= 'bridge_unavailable' then
            return false, nil, 'target_adapter_error'
        end
        return ok, result, second, third
    end

    local fn = provider[method]
    if type(fn) ~= 'function' then return false, nil, 'capability_unavailable' end
    local args = { ... }
    local ok, first, second, third = pcall(function()
        if method == 'AddTowerTarget' or method == 'RemoveTowerTarget' then
            return fn(table.unpack(args))
        end
        return fn(provider, table.unpack(args))
    end)
    if not ok then return false, nil, 'target_adapter_error' end
    return true, first, second, third
end

local function validId(value)
    return type(value) == 'string' and value ~= '' and #value <= 96
end

local function validOptions(value)
    return value == nil or type(value) == 'table'
end

local function addInteraction(method, id, subject, options)
    if not validId(id) then return false, 'interaction_id_required' end
    if not validOptions(options) then return false, 'interaction_options_invalid' end
    local ok, accepted, handleOrError = call(method, id, subject, options or {})
    if not ok then return false, handleOrError or accepted or 'target_unavailable' end
    if accepted == false then return false, handleOrError or 'target_interaction_rejected' end
    return true, handleOrError or accepted or id
end

function TargetBridge.Initialize()
    if BridgeManager and type(BridgeManager.InitializeCategory) == 'function' then
        local configured = configuredName()
        local preferred = configured ~= 'auto' and configured or nil
        local ok, selected, errorMessage = BridgeManager.InitializeCategory(
            'target',
            preferred,
            true
        )
        return ok, selected, errorMessage
    end
    return initializeLocal()
end

function TargetBridge.SetAdapter(value)
    if value ~= nil and type(value) ~= 'table' then return false end

    if runtimeName then
        if BridgeManager and type(BridgeManager.Unregister) == 'function' then
            BridgeManager.Unregister('target', runtimeName)
        end
        TargetBridges.Registry[runtimeName] = nil
        runtimeName = nil
    end

    if value then
        local ok, nameOrError = registerContract(value, true)
        if not ok then return false, nameOrError end
        runtimeName = nameOrError
        if BridgeManager and type(BridgeManager.InitializeCategory) == 'function' then
            BridgeManager.InitializeCategory('target', runtimeName, true)
        else
            localInitialized = false
            initializeLocal()
        end
        return true
    end

    if BridgeManager and type(BridgeManager.InitializeCategory) == 'function' then
        BridgeManager.InitializeCategory('target', nil, true)
    else
        localInitialized = false
        initializeLocal()
    end
    return true
end

function TargetBridge.Reset()
    return TargetBridge.SetAdapter(nil)
end

function TargetBridge.Refresh()
    if BridgeManager and type(BridgeManager.InitializeCategory) == 'function' then
        return BridgeManager.InitializeCategory('target', nil, true)
    end
    localInitialized = false
    return initializeLocal()
end

function TargetBridge.HandleResourceStart(resourceName)
    if type(resourceName) ~= 'string' or resourceName == '' then return false end
    if BridgeManager and type(BridgeManager.HandleResourceStart) == 'function' then
        local touched = BridgeManager.HandleResourceStart(resourceName)
        return touched == true
    end
    TargetBridge.Refresh()
    return true
end

function TargetBridge.HandleResourceStop(resourceName)
    return TargetBridge.HandleResourceStart(resourceName)
end

function TargetBridge.AddEntityInteraction(id, entity, options)
    return addInteraction('AddEntityInteraction', id, entity, options)
end

function TargetBridge.AddModelInteraction(id, models, options)
    return addInteraction('AddModelInteraction', id, models, options)
end

function TargetBridge.AddZoneInteraction(id, zone, options)
    if type(zone) ~= 'table' then return false, 'interaction_zone_required' end
    return addInteraction('AddZoneInteraction', id, zone, options)
end

function TargetBridge.RemoveInteraction(id, handle)
    if not validId(id) then return false, 'interaction_id_required' end
    local ok, removed, errorMessage = call('RemoveInteraction', id, handle)
    if not ok then return false, errorMessage or removed or 'target_unavailable' end
    if removed == false then return false, errorMessage or 'target_interaction_rejected' end
    return true
end

function TargetBridge.AddTowerTarget(tower, callbacks)
    local provider = activeProvider()
    if provider and type(provider.AddTowerTarget) == 'function' then
        local ok, result, errorMessage = call('AddTowerTarget', tower, callbacks)
        if not ok then return false, errorMessage or result end
        return result ~= false, errorMessage
    end
    if type(tower) ~= 'table' or not validId(tower.id) then
        return false, 'tower_required'
    end
    return TargetBridge.AddZoneInteraction(tower.id, {
        name = tower.id,
        coords = tower.coords,
        radius = tower.radius or 3.0,
    }, callbacks or {})
end

function TargetBridge.RemoveTowerTarget(towerId)
    local provider = activeProvider()
    if provider and type(provider.RemoveTowerTarget) == 'function' then
        local ok, result, errorMessage = call('RemoveTowerTarget', towerId)
        if not ok then return false, errorMessage or result end
        return result ~= false, errorMessage
    end
    return TargetBridge.RemoveInteraction(towerId)
end

function TargetBridge.GetActive()
    return activeProvider()
end

function TargetBridge.GetName()
    local provider = activeProvider()
    return provider and provider.name or 'none'
end

function TargetBridge.GetStatus()
    local bridgeStatus = BridgeManager and BridgeManager.GetBridgeStatus
        and BridgeManager.GetBridgeStatus('target') or nil
    local active = TargetBridge.GetActive()
    if bridgeStatus then return copy(bridgeStatus) end

    local providers = {}
    for _, provider in ipairs(sortedProviders()) do
        providers[#providers + 1] = {
            name = provider.name,
            priority = provider.priority or 0,
            selected = active == provider,
            capabilities = copy(provider.capabilities or {}),
        }
    end
    return {
        category = 'target',
        configured = configuredName(),
        active = active and active.name or nil,
        available = active ~= nil,
        initialized = localInitialized,
        providers = providers,
    }
end
