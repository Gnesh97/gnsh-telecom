local function customConfig()
    local configured = Config and Config.CustomFramework
    return type(configured) == 'table' and configured or nil
end

local function resourceStarted(resourceName)
    if type(resourceName) ~= 'string' or resourceName == ''
        or type(GetResourceState) ~= 'function' then
        return false
    end
    local ok, state = pcall(GetResourceState, resourceName)
    return ok and state == 'started'
end

local function callConfigured(method, ...)
    local configured = customConfig()
    local fn = configured and configured[method]
    if type(fn) ~= 'function' then return false, nil end
    local args = { ... }
    local ok, result = pcall(function() return fn(table.unpack(args)) end)
    return ok, result
end

local function hasConfiguredMethod(configured)
    for _, method in ipairs({
        'GetPlayer',
        'GetStablePlayerId',
        'GetJob',
        'HasJob',
        'IsAdmin',
        'GetCharacterName',
        'AddMoney',
        'RemoveMoney',
    }) do
        if type(configured[method]) == 'function' then return true end
    end
    return false
end

if FrameworkBridge and FrameworkBridge.Register then
    local configured = customConfig()
    FrameworkBridge.Register('custom', {
        resource = configured and (configured.resource or configured.resourceName) or nil,
        priority = 400,
        Detect = function()
            local current = customConfig()
            local configuredProvider = BridgeConfig and BridgeConfig.GetProvider
                and BridgeConfig.GetProvider('framework')
                or (Config and Config.Framework)
            if configuredProvider ~= 'custom' or not current
                or not hasConfiguredMethod(current) then
                return false
            end
            local resource = current.resource or current.resourceName
            return resource == nil or resourceStarted(resource)
        end,
        GetPlayer = function(_, source)
            local ok, player = callConfigured('GetPlayer', source)
            return ok and player or nil
        end,
        GetStablePlayerId = function(_, source)
            local ok, identifier = callConfigured('GetStablePlayerId', source)
            if ok and identifier ~= nil then return identifier end
            local playerOk, player = callConfigured('GetPlayer', source)
            if not playerOk or type(player) ~= 'table' then return nil end
            return player.identifier or player.citizenid or player.id
        end,
        GetJob = function(_, source)
            local ok, job = callConfigured('GetJob', source)
            return ok and job or nil
        end,
        HasJob = function(_, source, jobs)
            local ok, result = callConfigured('HasJob', source, jobs)
            return ok and result or nil
        end,
        IsAdmin = function(_, source)
            local ok, result = callConfigured('IsAdmin', source)
            return ok and result or nil
        end,
        GetCharacterName = function(_, source)
            local ok, name = callConfigured('GetCharacterName', source)
            return ok and name or nil
        end,
        AddMoney = function(_, source, account, amount)
            local ok, result = callConfigured('AddMoney', source, account, amount)
            return ok and result == true
        end,
        RemoveMoney = function(_, source, account, amount)
            local ok, result = callConfigured('RemoveMoney', source, account, amount)
            return ok and result == true
        end,
    })
end
