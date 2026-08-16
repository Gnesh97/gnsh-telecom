TelecomTxAdmin = TelecomTxAdmin or {}

local admins = {}
local registered = false

local function normalizeNetId(value, allowAll)
    local number = tonumber(value)
    if not number
        or number ~= number
        or number == math.huge
        or number == -math.huge
        or number ~= math.floor(number) then
        return nil
    end
    if allowAll and number == -1 then return number end
    if number < 1 then return nil end
    return number
end

local function copyAdmins()
    local copy = {}
    for netId in pairs(admins) do
        copy[netId] = true
    end
    return copy
end

local function invalidateAuth(data)
    local netId = type(data) == 'table' and normalizeNetId(data.netid, true) or nil
    if netId and netId > 0 then
        local updated = copyAdmins()
        updated[netId] = nil
        admins = updated
    else
        admins = {}
    end
    return false, 'invalid_payload'
end

function TelecomTxAdmin.IsAdmin(source)
    local netId = normalizeNetId(source, false)
    return netId ~= nil and admins[netId] == true
end

local function applyAuth(data)
    if type(data) ~= 'table' then return invalidateAuth(data) end

    local netId = normalizeNetId(data.netid, true)
    if not netId or type(data.isAdmin) ~= 'boolean' then
        return invalidateAuth(data)
    end

    if netId == -1 then
        if data.isAdmin then
            admins = {}
            return false, 'invalid_payload'
        end
        admins = {}
        return true
    end

    local updated = copyAdmins()
    if data.isAdmin then
        updated[netId] = true
    else
        updated[netId] = nil
    end
    admins = updated
    return true
end

local function applyAdminsUpdated(data)
    if type(data) ~= 'table' then
        admins = {}
        return false, 'invalid_payload'
    end

    local length = #data
    for key in pairs(data) do
        if type(key) ~= 'number'
            or key < 1
            or key ~= math.floor(key)
            or key > length then
            admins = {}
            return false, 'invalid_payload'
        end
    end

    local updated = {}
    for index = 1, length do
        local value = data[index]
        local netId = normalizeNetId(value, false)
        if not netId then
            admins = {}
            return false, 'invalid_payload'
        end
        updated[netId] = true
    end

    admins = updated
    return true
end

local function clear(source)
    local netId = normalizeNetId(source, false)
    if not netId then return false end

    if not admins[netId] then return true end
    local updated = copyAdmins()
    updated[netId] = nil
    admins = updated
    return true
end

local function register()
    if registered then return true end
    if type(AddEventHandler) ~= 'function' then
        return false, 'event_api_unavailable'
    end

    AddEventHandler('txAdmin:events:adminAuth', function(data)
        applyAuth(data)
    end)

    AddEventHandler('txAdmin:events:adminsUpdated', function(data)
        applyAdminsUpdated(data)
    end)

    AddEventHandler('playerDropped', function()
        clear(source)
    end)

    registered = true
    return true
end

register()
