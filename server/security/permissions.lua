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

local function getAdminAces()
    local configured = TelecomPermissions.GetAdminAce()
    local aces = {}
    if type(configured) == 'string' and configured ~= '' then
        aces[#aces + 1] = configured
    end
    if configured ~= 'admin' then
        aces[#aces + 1] = 'admin'
    end
    return aces
end

function TelecomPermissions.IsAdmin(source)
    local number = normalizeSource(source)
    if not number then return false end
    if number == 0 then return true end

    if type(IsPlayerAceAllowed) ~= 'function' then return false end

    for _, ace in ipairs(getAdminAces()) do
        local ok, allowed = pcall(IsPlayerAceAllowed, tostring(number), ace)
        if ok and allowed == true then return true end
    end
    return false
end

function TelecomPermissions.RequireAdmin(source)
    if TelecomPermissions.IsAdmin(source) then return true end
    return false, 'not_authorized'
end
