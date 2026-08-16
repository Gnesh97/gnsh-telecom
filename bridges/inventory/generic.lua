InventoryBridge = InventoryBridge or {}

local adapter

function InventoryBridge.SetAdapter(value)
    if value ~= nil and type(value) ~= 'table' then return false end
    adapter = value
    return true
end

function InventoryBridge.HasItem(source, item, amount)
    if item == nil or item == '' then return true end
    amount = tonumber(amount) or 1
    if adapter and type(adapter.HasItem) == 'function' then
        local ok, result = pcall(adapter.HasItem, source, item, amount)
        return ok and result == true, ok and nil or 'inventory_adapter_error'
    end
    return false, 'inventory_unavailable'
end

function InventoryBridge.RemoveItem(source, item, amount)
    if item == nil or item == '' then return true end
    if adapter and type(adapter.RemoveItem) == 'function' then
        local ok, result = pcall(adapter.RemoveItem, source, item, amount or 1)
        return ok and result ~= false, ok and nil or 'inventory_adapter_error'
    end
    return false, 'inventory_unavailable'
end

function InventoryBridge.GetName()
    return adapter and adapter.name or 'none'
end
