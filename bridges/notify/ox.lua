local function isServer()
    if type(IsDuplicityVersion) == 'function' then
        local ok, value = pcall(IsDuplicityVersion)
        if ok then return value == true end
    end
    return true
end

local function resourceStarted(name)
    if type(GetResourceState) ~= 'function' then return false end
    local ok, state = pcall(GetResourceState, name)
    return ok and state == 'started'
end

local function boundedString(value, maximum)
    return type(value) == 'string' and value ~= '' and #value <= maximum and value or nil
end

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function oxPayload(kind, message, data)
    local payload = {
        description = message,
        type = kind == 'info' and 'inform' or kind,
    }
    if type(data) ~= 'table' then return payload end

    local title = boundedString(data.title, 128)
    if title then payload.title = title end
    local position = boundedString(data.position, 32)
    if position then payload.position = position end
    local icon = boundedString(data.icon, 64)
    if icon then payload.icon = icon end
    local iconColor = boundedString(data.iconColor, 32)
    if iconColor then payload.iconColor = iconColor end
    if isFiniteNumber(data.duration) and data.duration == math.floor(data.duration)
        and data.duration >= 0 and data.duration <= 60000 then
        payload.duration = data.duration
    end
    if type(data.showDuration) == 'boolean' then payload.showDuration = data.showDuration end
    return payload
end

local function oxNotify(source, kind, message, data)
    local payload = oxPayload(kind, message, data)
    if isServer() then
        if type(TriggerClientEvent) ~= 'function' then
            return false, 'ox_notify_transport_unavailable'
        end
        local ok = pcall(TriggerClientEvent, Constants.SupportEvents.NOTIFY, source, {
            provider = 'ox',
            kind = kind,
            message = message,
            data = data,
        })
        if not ok then return false, 'ox_notify_transport_failed' end
        return true
    end

    if type(lib) ~= 'table' or type(lib.notify) ~= 'function' then
        return false, 'ox_lib_notify_unavailable'
    end
    local ok, result = pcall(lib.notify, payload)
    if not ok then return false, 'ox_lib_notify_failed' end
    return result ~= false
end

local function runOxNotify(kind, message, data)
    if type(lib) ~= 'table' or type(lib.notify) ~= 'function' then
        return false, 'ox_lib_notify_unavailable'
    end
    local ok, result = pcall(lib.notify, oxPayload(kind, message, data))
    if not ok then return false, 'ox_lib_notify_failed' end
    return result ~= false
end

if NotifyBridge and type(NotifyBridge.Register) == 'function' then
    NotifyBridge.Register({
        name = 'ox',
        priority = 100,
        resources = { 'ox_lib' },
        Detect = function() return resourceStarted('ox_lib') end,
        Notify = oxNotify,
    })
end

if not isServer() and type(AddEventHandler) == 'function' then
    if type(RegisterNetEvent) == 'function' then
        pcall(RegisterNetEvent, Constants.SupportEvents.NOTIFY)
    end
    AddEventHandler(Constants.SupportEvents.NOTIFY, function(payload)
        if type(payload) ~= 'table' or payload.provider ~= 'ox'
            or type(payload.message) ~= 'string' then
            return
        end
        local ok = runOxNotify(payload.kind, payload.message, payload.data or {})
        if not ok and NotifyBridge and type(NotifyBridge.NotifyNative) == 'function' then
            NotifyBridge.NotifyNative(nil, payload.kind, payload.message, payload.data or {})
        end
    end)
end
