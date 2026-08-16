InventoryBridge = InventoryBridge or {}

local adapter

function InventoryBridge.SetAdapter(value)
    if value ~= nil and type(value) ~= 'table' then return false end
    adapter = value
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
