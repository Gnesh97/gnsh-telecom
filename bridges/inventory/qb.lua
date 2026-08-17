local function getExport()
    if not exports then return nil end
    local ok, bridge = pcall(function() return exports['qb-inventory'] end)
    return ok and bridge or nil
end

local function invoke(method, ...)
    local bridge = getExport()
    local fn = bridge and bridge[method]
    if type(fn) ~= 'function' then return false, nil end
    local args = { ... }
    local ok, result = pcall(function() return fn(bridge, table.unpack(args)) end)
    return ok, result
end

local function itemCount(source, item)
    local ok, count = invoke('GetItemCount', source, item)
    if ok and type(count) == 'number' then return count end
    local amount = 1
    ok, count = invoke('HasItem', source, item, amount)
    if ok and count == true then return amount end
    return 0
end

local function successful(result)
    return result == true or result == 'ok'
end

if InventoryBridge and type(InventoryBridge.Register) == 'function' then
    InventoryBridge.Register({
        name = 'qb',
        resource = 'qb-inventory',
        priority = 200,
        Detect = function()
            local configured = BridgeConfig and BridgeConfig.GetProvider
                and BridgeConfig.GetProvider('inventory')
                or (Config and Config.InventoryBridge or 'auto')
            return configured == 'auto' or configured == 'qb'
        end,
        GetItemCount = function(_, source, item)
            return itemCount(source, item)
        end,
        HasItem = function(_, source, item, amount)
            local ok, result = invoke('HasItem', source, item, amount)
            if ok and type(result) == 'boolean' then return result end
            return itemCount(source, item) >= (tonumber(amount) or 1)
        end,
        CanCarry = function(_, source, item, amount)
            local ok, result = invoke('CanAddItem', source, item, amount)
            return ok and result == true
        end,
        RemoveItem = function(_, source, item, amount, metadata)
            local ok, result = invoke('RemoveItem', source, item, amount, nil, metadata)
            return ok and successful(result)
        end,
        AddItem = function(_, source, item, amount, metadata)
            local ok, result = invoke('AddItem', source, item, amount, nil, metadata)
            return ok and successful(result)
        end,
    })
end
