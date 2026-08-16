DispatchBridge = DispatchBridge or {}

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
        category = 'dispatch',
        priority = value.priority or 0,
        resources = value.resources,
        capabilities = value.capabilities or { 'Alert' },
        Detect = function() return true end,
        Initialize = function() return invoke(value, 'Initialize') end,
        Shutdown = function() return invoke(value, 'Shutdown') end,
        HealthCheck = function() return 'ACTIVE' end,
    }
end

function DispatchBridge.SetAdapter(value)
    if value ~= nil and type(value) ~= 'table' then return false end

    if BridgeManager and type(BridgeManager.Unregister) == 'function' and activeName then
        BridgeManager.Unregister('dispatch', activeName)
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
        BridgeManager.InitializeCategory('dispatch', activeName)
    end
    return true
end

function DispatchBridge.Alert(payload)
    if adapter and type(adapter.Alert) == 'function' then
        local ok, result = pcall(adapter.Alert, payload)
        if ok then return result ~= false end
        return false
    end
    if Log and Log.warn then Log.warn('dispatch alert', payload) end
    return false, 'dispatch_adapter_unavailable'
end
