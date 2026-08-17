InventoryBridge = InventoryBridge or {}
InventoryBridges = InventoryBridges or {}
InventoryBridges.Registry = InventoryBridges.Registry or {}

local runtimeName

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    return value
end

local function invoke(value, method)
    local fn = value and value[method]
    if type(fn) ~= 'function' then return true end
    local ok, result, errorMessage = pcall(fn, value)
    if not ok then return false, tostring(result) end
    return result ~= false, errorMessage
end

local function makeContract(value, runtime)
    local name = type(value.name) == 'string' and value.name ~= ''
        and value.name or 'runtime'
    local contract = {}
    for key, item in pairs(value) do contract[key] = item end

    contract.name = name
    contract.category = 'inventory'
    contract.priority = runtime and (value.priority or 1000) or (value.priority or 0)
    if contract.resources == nil and type(contract.resource) == 'string' then
        contract.resources = { contract.resource }
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
        if not ok then return false end
        return result
    end
    return contract
end

local function registerContract(value, runtime)
    if type(value) ~= 'table' then return false, 'invalid_inventory_adapter' end
    local name = type(value.name) == 'string' and value.name ~= ''
        and value.name or (runtime and 'runtime' or nil)
    if not name then return false, 'inventory_adapter_name_required' end

    local contract = makeContract(value, runtime)
    if BridgeManager and type(BridgeManager.Register) == 'function' then
        local ok, errorMessage = BridgeManager.Register(contract)
        if not ok then return false, errorMessage end
    end
    InventoryBridges.Registry[name] = value
    return true, name
end

function InventoryBridge.Register(value)
    return registerContract(value, false)
end

local function activeProvider()
    if BridgeManager and type(BridgeManager.GetActive) == 'function' then
        local active = BridgeManager.GetActive('inventory')
        if active then return active end
        local initialized
        initialized, active = BridgeManager.InitializeCategory('inventory')
        if initialized then return active end
    end
    return nil
end

local function call(method, source, ...)
    local provider = activeProvider()
    if not provider then return false, nil, 'inventory_unavailable' end

    if BridgeManager and type(BridgeManager.Call) == 'function' then
        local ok, result, errorMessage = BridgeManager.Call(
            'inventory',
            method,
            source,
            ...
        )
        if not ok and errorMessage ~= 'capability_unavailable'
            and errorMessage ~= 'bridge_unavailable' then
            return false, nil, 'inventory_adapter_error'
        end
        return ok, result, errorMessage
    end
    if type(provider[method]) ~= 'function' then
        return false, nil, 'capability_unavailable'
    end
    if BridgeLifecycle and BridgeLifecycle.Call then
        return BridgeLifecycle.Call(provider, method, source, ...)
    end
    local args = { source, ... }
    return pcall(function() return provider[method](provider, table.unpack(args)) end)
end

local function validItem(item)
    return type(item) == 'string' and item ~= '' and #item <= 64
end

local function normalizeAmount(amount)
    amount = tonumber(amount) or 1
    if amount ~= math.floor(amount) or amount <= 0 or amount > 10000
        or amount ~= amount or amount == math.huge or amount == -math.huge then
        return nil
    end
    return amount
end

local function validateRequest(item, amount)
    if item == nil or item == '' then return true, nil end
    if not validItem(item) then return false, 'invalid_item' end
    local normalized = normalizeAmount(amount)
    if not normalized then return false, 'invalid_amount' end
    return true, normalized
end

function InventoryBridge.SetAdapter(value)
    if value ~= nil and type(value) ~= 'table' then return false end

    if runtimeName and BridgeManager and type(BridgeManager.Unregister) == 'function' then
        BridgeManager.Unregister('inventory', runtimeName)
        InventoryBridges.Registry[runtimeName] = nil
        runtimeName = nil
    end

    if value then
        local ok, nameOrError = registerContract(value, true)
        if not ok then return false, nameOrError end
        runtimeName = nameOrError
        if BridgeManager and type(BridgeManager.InitializeCategory) == 'function' then
            BridgeManager.InitializeCategory('inventory', runtimeName, true)
        end
        return true
    end

    if BridgeManager and type(BridgeManager.InitializeCategory) == 'function' then
        BridgeManager.InitializeCategory('inventory', nil, true)
    end
    return true
end

function InventoryBridge.HasItem(source, item, amount)
    local valid, normalized = validateRequest(item, amount)
    if item == nil or item == '' then return true end
    if not valid then return false, normalized end
    local ok, result, errorMessage = call('HasItem', source, item, normalized)
    if not ok then return false, errorMessage or 'inventory_unavailable' end
    return result == true
end

function InventoryBridge.RemoveItem(source, item, amount)
    local valid, normalized = validateRequest(item, amount)
    if item == nil or item == '' then return true end
    if not valid then return false, normalized end
    local ok, result, errorMessage = call('RemoveItem', source, item, normalized)
    if not ok then return false, errorMessage or 'inventory_unavailable' end
    return result == true
end

function InventoryBridge.AddItem(source, item, amount, metadata)
    local valid, normalized = validateRequest(item, amount)
    if item == nil or item == '' then return true end
    if not valid then return false, normalized end
    if metadata ~= nil and type(metadata) ~= 'table' then
        return false, 'invalid_metadata'
    end
    metadata = metadata and copy(metadata) or nil
    local ok, result, errorMessage = call('AddItem', source, item, normalized, metadata)
    if not ok then return false, errorMessage or 'inventory_unavailable' end
    return result == true
end

function InventoryBridge.CanCarry(source, item, amount)
    local valid, normalized = validateRequest(item, amount)
    if item == nil or item == '' then return true end
    if not valid then return false, normalized end

    local ok, result = call('CanCarry', source, item, normalized)
    if ok then return result == true end

    local provider = activeProvider()
    if provider and type(provider.AddItem) == 'function' then return true end
    return false
end

function InventoryBridge.CanAddItem(source, item, amount)
    return InventoryBridge.CanCarry(source, item, amount or 1)
end

function InventoryBridge.GetItemCount(source, item)
    if item == nil or item == '' then return 0 end
    if not validItem(item) then return 0 end
    local ok, result = call('GetItemCount', source, item)
    if not ok then return 0 end
    local count = tonumber(result)
    return count and count >= 0 and count or 0
end

function InventoryBridge.GetName()
    local provider = activeProvider()
    return provider and provider.name or 'none'
end
