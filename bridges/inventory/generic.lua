InventoryBridge = InventoryBridge or {}

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
    local name = type(value.name) == 'string' and value.name ~= ''
        and value.name or 'runtime'
    local capabilities = value.capabilities
    if capabilities == nil then
        capabilities = {}
        for _, method in ipairs({ 'HasItem', 'RemoveItem', 'AddItem', 'CanCarry', 'GetItemCount' }) do
            if type(value[method]) == 'function' then capabilities[#capabilities + 1] = method end
        end
    end
    return {
        name = name,
        category = 'inventory',
        priority = value.priority or 0,
        resources = value.resources,
        capabilities = capabilities,
        Detect = function() return true end,
        Initialize = function()
            return invoke(value, 'Initialize')
        end,
        Shutdown = function()
            return invoke(value, 'Shutdown')
        end,
        HealthCheck = function()
            local fn = value.HealthCheck
            if type(fn) ~= 'function' then return 'ACTIVE' end
            local ok, result = pcall(fn, value)
            if not ok then return false end
            return result
        end,
    }
end

function InventoryBridge.SetAdapter(value)
    if value ~= nil and type(value) ~= 'table' then return false end

    if BridgeManager and type(BridgeManager.Unregister) == 'function' and activeName then
        BridgeManager.Unregister('inventory', activeName)
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
        BridgeManager.InitializeCategory('inventory', activeName)
    end
    return true
end

function InventoryBridge.CanAddItem(source, item)
    if item == nil or item == '' then return true end
    return adapter ~= nil and type(adapter.AddItem) == 'function'
end

function InventoryBridge.HasItem(source, item, amount)
    if item == nil or item == '' then return true end
    amount = tonumber(amount) or 1
    if adapter and type(adapter.HasItem) == 'function' then
        local ok, result = pcall(adapter.HasItem, source, item, amount)
        if not ok then return false, 'inventory_adapter_error' end
        return result == true
    end
    return false, 'inventory_unavailable'
end

function InventoryBridge.RemoveItem(source, item, amount)
    if item == nil or item == '' then return true end
    if adapter and type(adapter.RemoveItem) == 'function' then
        local ok, result = pcall(adapter.RemoveItem, source, item, amount or 1)
        if not ok then return false, 'inventory_adapter_error' end
        return result == true
    end
    return false, 'inventory_unavailable'
end

function InventoryBridge.AddItem(source, item, amount)
    if item == nil or item == '' then return true end
    if adapter and type(adapter.AddItem) == 'function' then
        local ok, result = pcall(adapter.AddItem, source, item, amount or 1)
        if not ok then return false, 'inventory_adapter_error' end
        return result == true
    end
    return false, 'inventory_unavailable'
end

function InventoryBridge.GetName()
    return adapter and adapter.name or 'none'
end
