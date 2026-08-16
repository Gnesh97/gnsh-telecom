TelecomPermissions = TelecomPermissions or {}

local function normalizeSource(source)
    local number = tonumber(source)
    if not number or number ~= math.floor(number) or number < 0 then return nil end
    return number
end

function TelecomPermissions.IsConsole(source)
    return normalizeSource(source) == 0
end

function TelecomPermissions.GetAdminAce()
    local debug = Config and Config.Debug
    return debug and debug.adminAce or nil
end

function TelecomPermissions.IsAdmin(source)
    local number = normalizeSource(source)
    if not number then return false end
    if number == 0 then return true end

    local ace = TelecomPermissions.GetAdminAce()
    if type(ace) ~= 'string' or ace == '' then return false end
    if type(IsPlayerAceAllowed) ~= 'function' then return false end

    local ok, allowed = pcall(IsPlayerAceAllowed, tostring(number), ace)
    return ok and allowed == true
end

function TelecomPermissions.RequireAdmin(source)
    if TelecomPermissions.IsAdmin(source) then return true end
    return false, 'not_authorized'
end
