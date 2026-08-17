local function getExport()
    if not exports then return nil end
    local ok, bridge = pcall(function() return exports['qs-inventory'] end)
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
    local ok, count = invoke('GetItemTotalAmount', source, item)
    if ok and type(count) == 'number' then return count end
    ok, count = invoke('GetItemCount', source, item)
    if ok and type(count) == 'number' then return count end
    return 0
end

local function successful(result)
    return result == true or result == 'ok'
end

if InventoryBridge and type(InventoryBridge.Register) == 'function' then
    InventoryBridge.Register({
        name = 'qs',
        resource = 'qs-inventory',
        priority = 100,
        Detect = function()
            return not Config or Config.InventoryBridge == 'auto'
                or Config.InventoryBridge == 'qs'
        end,
        GetItemCount = function(_, source, item)
            return itemCount(source, item)
        end,
        HasItem = function(_, source, item, amount)
            return itemCount(source, item) >= (tonumber(amount) or 1)
        end,
        CanCarry = function(_, source, item, amount)
            local ok, result = invoke('CanCarryItem', source, item, amount)
            if ok and type(result) == 'boolean' then return result end
            ok, result = invoke('CanCarry', source, item, amount)
            return ok and result == true
        end,
        RemoveItem = function(_, source, item, amount, metadata)
            local ok, result = invoke('RemoveItem', source, item, amount, metadata)
            return ok and successful(result)
        end,
        AddItem = function(_, source, item, amount, metadata)
            local ok, result = invoke('AddItem', source, item, amount, metadata)
            return ok and successful(result)
        end,
    })
end
