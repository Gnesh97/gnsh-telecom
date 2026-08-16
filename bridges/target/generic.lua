TargetBridge = TargetBridge or {}

local adapter
local activeName

local function invoke(value, method)
    local fn = value and value[method]
    if type(fn) ~= 'function' then return true end
    local ok, result, errorMessage = pcall(fn, value)
    if not ok then return false, tostring(result) end
    return result ~= false, errorMessage
end

local function makeContract(value)
    return {
        name = type(value.name) == 'string' and value.name ~= '' and value.name or 'runtime',
        category = 'target',
        priority = value.priority or 0,
        resources = value.resources,
        capabilities = value.capabilities or { 'AddTowerTarget', 'RemoveTowerTarget' },
        Detect = function() return true end,
        Initialize = function() return invoke(value, 'Initialize') end,
        Shutdown = function() return invoke(value, 'Shutdown') end,
        HealthCheck = function() return 'ACTIVE' end,
    }
end

function TargetBridge.SetAdapter(value)
    if value ~= nil and type(value) ~= 'table' then return false end

    if BridgeManager and type(BridgeManager.Unregister) == 'function' and activeName then
        BridgeManager.Unregister('target', activeName)
        activeName = nil
    end
    adapter = value

    if value and BridgeManager and type(BridgeManager.Register) == 'function' then
        local contract = makeContract(value)
        local ok, errorMessage = BridgeManager.Register(contract)
        if not ok then
            adapter = nil
            return false, errorMessage
        end
        activeName = contract.name
        BridgeManager.InitializeCategory('target', activeName)
    end
    return true
end

function TargetBridge.AddTowerTarget(tower, callbacks)
    if adapter and type(adapter.AddTowerTarget) == 'function' then
        return adapter.AddTowerTarget(tower, callbacks)
    end
    return false, 'target_adapter_unavailable'
end

function TargetBridge.RemoveTowerTarget(towerId)
    if adapter and type(adapter.RemoveTowerTarget) == 'function' then
        return adapter.RemoveTowerTarget(towerId)
    end
    return false, 'target_adapter_unavailable'
end
