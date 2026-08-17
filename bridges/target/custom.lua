local function configured()
    local value = Config and Config.CustomTarget
    return type(value) == 'table' and value or nil
end

local function callConfigured(method, ...)
    local value = configured()
    local fn = value and value[method]
    if type(fn) ~= 'function' then return false, nil end
    local args = { ... }
    local ok, first, second = pcall(function() return fn(table.unpack(args)) end)
    return ok, first, second
end

local function hasMethod(value)
    for _, method in ipairs({
        'AddEntityInteraction',
        'AddModelInteraction',
        'AddZoneInteraction',
        'RemoveInteraction',
    }) do
        if type(value[method]) == 'function' then return true end
    end
    return false
end

if TargetBridge and type(TargetBridge.Register) == 'function' then
    TargetBridge.Register({
        name = 'custom',
        resource = Config and Config.CustomTarget
            and (Config.CustomTarget.resource or Config.CustomTarget.resourceName) or nil,
        priority = 400,
        Detect = function()
            local value = configured()
            return Config and Config.TargetBridge == 'custom'
                and value ~= nil and hasMethod(value)
        end,
        AddEntityInteraction = function(_, id, entity, options)
            local ok, result, handle = callConfigured(
                'AddEntityInteraction', id, entity, options
            )
            return ok and result == true, handle or id
        end,
        AddModelInteraction = function(_, id, models, options)
            local ok, result, handle = callConfigured(
                'AddModelInteraction', id, models, options
            )
            return ok and result == true, handle or id
        end,
        AddZoneInteraction = function(_, id, zone, options)
            local ok, result, handle = callConfigured(
                'AddZoneInteraction', id, zone, options
            )
            return ok and result == true, handle or id
        end,
        RemoveInteraction = function(_, id, handle)
            local ok, result = callConfigured('RemoveInteraction', id, handle)
            return ok and result == true
        end,
    })
end
