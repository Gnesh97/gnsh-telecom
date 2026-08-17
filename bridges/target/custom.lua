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

local function resourceStarted(name)
    if type(name) ~= 'string' or name == '' then return true end
    if type(GetResourceState) ~= 'function' then return false end
    local ok, state = pcall(GetResourceState, name)
    return ok and state == 'started'
end

if TargetBridge and type(TargetBridge.Register) == 'function' then
    TargetBridge.Register({
        name = 'custom',
        resource = Config and Config.CustomTarget
            and (Config.CustomTarget.resource or Config.CustomTarget.resourceName) or nil,
        priority = 400,
        Detect = function()
            local value = configured()
            local resource = value and (value.resource or value.resourceName)
            return Config and Config.TargetBridge == 'custom'
                and value ~= nil and hasMethod(value)
                and resourceStarted(resource)
        end,
        AddEntityInteraction = function(_, id, entity, options)
            local ok, result, handle = callConfigured(
                'AddEntityInteraction', id, entity, options
            )
            local accepted = ok and result ~= false
            local normalizedHandle = handle
                or (result ~= true and result)
                or id
            return accepted, normalizedHandle
        end,
        AddModelInteraction = function(_, id, models, options)
            local ok, result, handle = callConfigured(
                'AddModelInteraction', id, models, options
            )
            local accepted = ok and result ~= false
            local normalizedHandle = handle
                or (result ~= true and result)
                or id
            return accepted, normalizedHandle
        end,
        AddZoneInteraction = function(_, id, zone, options)
            local ok, result, handle = callConfigured(
                'AddZoneInteraction', id, zone, options
            )
            local accepted = ok and result ~= false
            local normalizedHandle = handle
                or (result ~= true and result)
                or id
            return accepted, normalizedHandle
        end,
        RemoveInteraction = function(_, id, handle)
            local ok, result = callConfigured('RemoveInteraction', id, handle)
            return ok and result ~= false
        end,
    })
end
