local function configured()
    local value = Config and Config.CustomInventory
    return type(value) == 'table' and value or nil
end

local function callConfigured(method, ...)
    local value = configured()
    local fn = value and value[method]
    if type(fn) ~= 'function' then return false, nil end
    local args = { ... }
    local ok, result = pcall(function() return fn(table.unpack(args)) end)
    return ok, result
end

local function hasMethod(value)
    for _, method in ipairs({
        'HasItem',
        'RemoveItem',
        'AddItem',
        'CanCarry',
        'GetItemCount',
    }) do
        if type(value[method]) == 'function' then return true end
    end
    return false
end

if InventoryBridge and type(InventoryBridge.Register) == 'function' then
    local value = configured()
    InventoryBridge.Register({
        name = 'custom',
        resource = value and (value.resource or value.resourceName) or nil,
        priority = 400,
        Detect = function()
            local current = configured()
            return Config and Config.InventoryBridge == 'custom'
                and current ~= nil and hasMethod(current)
        end,
        HasItem = function(_, source, item, amount)
            local ok, result = callConfigured('HasItem', source, item, amount)
            return ok and result == true
        end,
        RemoveItem = function(_, source, item, amount, metadata)
            local ok, result = callConfigured('RemoveItem', source, item, amount, metadata)
            return ok and result == true
        end,
        AddItem = function(_, source, item, amount, metadata)
            local ok, result = callConfigured('AddItem', source, item, amount, metadata)
            return ok and result == true
        end,
        CanCarry = function(_, source, item, amount)
            local ok, result = callConfigured('CanCarry', source, item, amount)
            return ok and result == true
        end,
        GetItemCount = function(_, source, item)
            local ok, result = callConfigured('GetItemCount', source, item)
            return ok and tonumber(result) or 0
        end,
    })
end
