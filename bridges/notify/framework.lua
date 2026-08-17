local function isServer()
    if type(IsDuplicityVersion) == 'function' then
        local ok, value = pcall(IsDuplicityVersion)
        if ok then return value == true end
    end
    return true
end

local function frameworkName()
    if not FrameworkBridge or type(FrameworkBridge.GetName) ~= 'function' then return nil end
    local ok, name = pcall(FrameworkBridge.GetName)
    return ok and name or nil
end

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function durationFromData(data)
    if type(data) == 'table' and isFiniteNumber(data.duration)
        and data.duration == math.floor(data.duration)
        and data.duration >= 0 and data.duration <= 60000 then
        return data.duration
    end
    return 5000
end

local function frameworkNotify(source, kind, message, data)
    local name = frameworkName()
    if name == 'qbcore' or name == 'qbox' then
        if isServer() then
            if type(TriggerClientEvent) ~= 'function' then
                return false, 'framework_notify_transport_unavailable'
            end
            local ok = pcall(TriggerClientEvent, 'QBCore:Notify', source, message, kind, durationFromData(data))
            if not ok then return false, 'framework_notify_transport_failed' end
            return true
        end
        if type(TriggerEvent) ~= 'function' then return false, 'framework_notify_transport_unavailable' end
        local ok = pcall(TriggerEvent, 'QBCore:Notify', message, kind, durationFromData(data))
        if not ok then return false, 'framework_notify_transport_failed' end
        return true
    end

    if name == 'esx' then
        if isServer() then
            if type(TriggerClientEvent) ~= 'function' then
                return false, 'framework_notify_transport_unavailable'
            end
            local ok = pcall(TriggerClientEvent, 'esx:showNotification', source, message)
            if not ok then return false, 'framework_notify_transport_failed' end
            return true
        end
        if type(TriggerEvent) ~= 'function' then return false, 'framework_notify_transport_unavailable' end
        local ok = pcall(TriggerEvent, 'esx:showNotification', message)
        if not ok then return false, 'framework_notify_transport_failed' end
        return true
    end

    if name == 'custom' and Config and type(Config.CustomFramework) == 'table'
        and type(Config.CustomFramework.Notify) == 'function' then
        local ok, result = pcall(
            Config.CustomFramework.Notify,
            source,
            kind,
            message,
            data
        )
        if not ok then return false, 'custom_framework_notify_failed' end
        return result ~= false
    end

    return false, 'framework_notify_unavailable'
end

if NotifyBridge and type(NotifyBridge.Register) == 'function' then
    NotifyBridge.Register({
        name = 'framework',
        priority = 50,
        Detect = function()
            local name = frameworkName()
            return name == 'qbcore' or name == 'qbox' or name == 'esx' or name == 'custom'
        end,
        Notify = frameworkNotify,
    })
end
